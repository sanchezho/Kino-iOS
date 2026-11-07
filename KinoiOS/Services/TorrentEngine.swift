import Foundation

/// UI-facing state of one torrent being prepared for playback.
enum TorrentPlayState: Equatable {
    case fetchingMetadata(fileName: String?)
    /// `progress` is 0–1 of the WANTED file (not the whole torrent).
    case downloading(progress: Double, rate: UInt64, downloaded: UInt64, total: UInt64, fileName: String)
    /// Start threshold reached and the file is AVPlayer-playable; playback
    /// goes through the local HTTP server (`startServer(for:)`).
    case readyToPlay(fileName: String, downloaded: UInt64, total: UInt64)
    case unsupportedFormat(fileName: String, format: String)
    case failed(message: String)
    case finished(fileName: String)
}

/// Phase 4 step 2 — libtorrent session, magnet add, file selection and
/// progress. Step 3 added the local HTTP server (`startServer(for:)`) so a
/// ready file actually plays through AVPlayer.
///
/// Threading: libtorrent delegate callbacks may arrive on background
/// threads. Every one of them hops to the main queue before touching any
/// state, so all stored properties (and `@Published`) are only accessed on
/// the main thread. Public methods must be called from the main thread
/// (SwiftUI actions do).
final class TorrentEngine: NSObject, ObservableObject, SessionDelegate {
    static let shared = TorrentEngine()

    /// libtorrent version string from the linked C++ library, e.g. "2.1.2.0".
    /// Pure read — safe to call at launch; creates no session, no network.
    static var libtorrentVersion: String {
        Version.libtorrentVersion
    }

    /// Torrent state keyed by lowercased infoHash.
    @Published private(set) var states: [String: TorrentPlayState] = [:]

    private(set) var session: Session?

    /// Documents/torrents — libtorrent's save_path; set by `ensureSession()`.
    private(set) var downloadsDirectory: URL?
    private let httpServer = TorrentHTTPServer()
    /// Lowercased infoHash of the torrent the HTTP server is serving, if any.
    private(set) var servingInfoHash: String?

    private var handles: [String: TorrentHandle] = [:]
    private var pendingFileIdx: [String: Int] = [:]
    private var selectedFile: [String: Int] = [:]
    private var lastPublish: [String: Date] = [:]

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv"]
    private static let playableExtensions: Set<String> = ["mp4", "m4v", "mov"]
    private static let publishInterval: TimeInterval = 0.25

    private override init() {
        super.init()
    }

    // MARK: - Session

    /// Creates the app's single libtorrent session on first use. Downloads in
    /// Documents/torrents, state in Application Support/kino-torrents.
    @discardableResult
    func ensureSession() -> Session {
        if let session { return session }
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let downloadPath = documents.appendingPathComponent("torrents")
        downloadsDirectory = downloadPath
        let statePath = support.appendingPathComponent("kino-torrents")
        try? fileManager.createDirectory(at: downloadPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: statePath, withIntermediateDirectories: true)

        let settings = Session.Settings()
        settings.agentName = "KinoiOS/0.4.0"
        settings.peerFingerprint = "-KI0000-"
        settings.maxActiveTorrents = 3
        settings.maxDownloadingTorrents = 3
        settings.maxUploadingTorrents = 2
        settings.maxDownloadSpeed = 0
        settings.maxUploadSpeed = 0
        settings.isDhtEnabled = true
        settings.isLsdEnabled = true
        settings.isUtpEnabled = true
        settings.isUpnpEnabled = true
        settings.isNatEnabled = true
        settings.encryptionPolicy = .enabled
        settings.validateHttpsTrackers = false
        settings.port = 6881
        // REQUIRED (crash 2026-11-07): SessionSettings.settingsPack passes
        // these straight to libtorrent's set_str(), which strlen()s the C
        // string — a nil one segfaults (EXC_BAD_ACCESS) inside the Session
        // constructor, before any torrent work. listenInterfaces is also
        // the only place the listen port is honoured (settingsPack ignores
        // `port`); outgoingInterfaces "" means "any interface", libtorrent's
        // default.
        settings.listenInterfaces = "0.0.0.0:6881,[::]:6881"
        settings.outgoingInterfaces = ""

        let created = Session(
            downloadPath,
            torrentsPath: statePath,
            fastResumePath: statePath,
            settings: settings,
            storages: [:]
        )
        created.add(self)
        session = created
        return created
    }

    // MARK: - Public API

    func addStream(_ stream: StremioStream, title: String) {
        guard let rawHash = stream.infoHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHash.isEmpty else { return }
        let hash = rawHash.lowercased()

        if let existing = states[hash] {
            // Only a failed torrent may be re-added (Reintentar).
            guard case .failed = existing else { return }
            if servingInfoHash == hash { stopServer() }
            if let old = handles[hash] {
                ensureSession().removeTorrent(old, deleteFiles: false)
            }
            clearEntries(for: hash)
        }

        guard let url = Self.magnetURL(infoHash: hash, title: title, sources: stream.sources),
              let magnet = MagnetURI(with: url) else {
            states[hash] = .failed(message: "Enlace magnético inválido.")
            return
        }

        if let fileIdx = stream.fileIdx, fileIdx >= 0 {
            pendingFileIdx[hash] = fileIdx
        }
        states[hash] = .fetchingMetadata(fileName: stream.behaviorHints?.filename ?? title)

        if let handle = ensureSession().addTorrent(magnet) {
            handles[hash] = handle
        } else {
            pendingFileIdx[hash] = nil
            states[hash] = .failed(message: "No se pudo añadir el torrent.")
        }
    }

    func remove(infoHash: String, deleteFiles: Bool) {
        let hash = infoHash.lowercased()
        // Stop the server first so a player never hits a vanishing file.
        if hash == servingInfoHash { stopServer() }
        if let handle = handles[hash] {
            session?.removeTorrent(handle, deleteFiles: deleteFiles)
        }
        clearEntries(for: hash)
    }

    /// Removes every torrent and its downloaded files, and stops the server.
    func removeAllDownloads() {
        let hashes = Set(handles.keys).union(states.keys)
        for hash in hashes {
            remove(infoHash: hash, deleteFiles: true)
        }
        stopServer()
        states.removeAll()
    }

    /// Total size in bytes of regular files under the downloads directory.
    func downloadsSize() -> UInt64 {
        guard let directory = downloadsDirectory ?? Self.defaultDownloadsDirectory(),
              FileManager.default.fileExists(atPath: directory.path),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [],
                errorHandler: { _, _ in true }
              ) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    private static func defaultDownloadsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("torrents")
    }

    private static let seedKey = "kino.seedAfterFinish"

    /// When false (default) a torrent is paused once it finishes; when true it
    /// keeps seeding. Changing it applies to already-finished torrents too.
    var seedAfterFinish: Bool {
        get { UserDefaults.standard.bool(forKey: Self.seedKey) }
        set {
            guard newValue != seedAfterFinish else { return }
            UserDefaults.standard.set(newValue, forKey: Self.seedKey)
            for (hash, state) in states {
                guard case .finished = state, let handle = handles[hash] else { continue }
                if newValue { handle.resume() } else { handle.pause() }
            }
            objectWillChange.send()
        }
    }

    /// Starts the loopback HTTP server for the selected file of `infoHash`
    /// and returns its stream URL. FileEntry.path is relative to save_path
    /// (including the torrent folder for multi-file torrents), so the on-disk
    /// file is downloadsDirectory + file.path. Returns nil if no file is
    /// selected, the file is not on disk yet, or the server fails to start.
    /// The torrent keeps running; stopServer() only frees the port.
    func startServer(for infoHash: String) -> URL? {
        let hash = infoHash.lowercased()
        guard let handle = handles[hash],
              let index = selectedFile[hash],
              let directory = downloadsDirectory else { return nil }
        let files = handle.snapshot.files
        guard index >= 0, index < files.count else { return nil }
        let fileURL = directory.appendingPathComponent(files[index].path)
        let url = httpServer.start(fileURL: fileURL)
        servingInfoHash = url != nil ? hash : nil
        return url
    }

    func stopServer() {
        httpServer.stop()
        servingInfoHash = nil
    }

    func pauseAll() {
        guard let session else { return }
        for handle in session.torrents { handle.pause() }
    }

    func resumeAll() {
        guard let session else { return }
        for handle in session.torrents { handle.resume() }
    }

    // MARK: - SessionDelegate (any thread → main)

    func torrentManager(_ manager: Session, didAddTorrent torrent: TorrentHandle) {
        DispatchQueue.main.async { [self] in
            let hash = Self.hex(torrent.infoHashes.best)
            if handles[hash] == nil, !hash.isEmpty, states[hash] != nil {
                handles[hash] = torrent
            }
        }
    }

    func torrentManager(_ manager: Session, didRemoveTorrentWithHash hashes: TorrentHashes) {
        DispatchQueue.main.async { [self] in
            let hash = Self.hex(hashes.best)
            // Entries are normally cleared by remove(); this covers removals
            // that did not come through this class.
            if handles[hash] != nil, states[hash] != nil {
                clearEntries(for: hash)
            }
        }
    }

    func torrentManager(_ manager: Session, didReceiveUpdateForTorrent torrent: TorrentHandle) {
        DispatchQueue.main.async { [self] in
            handleUpdate(torrent)
        }
    }

    func torrentManager(_ manager: Session, didErrorOccur error: Error) {
        // The error carries no torrent identity; ignore rather than guess.
        // Storage problems surface through the .storageError torrent state.
    }

    // MARK: - Update handling (main thread)

    private func key(for torrent: TorrentHandle) -> String? {
        if let match = handles.first(where: { $0.value === torrent }) {
            return match.key
        }
        let hash = Self.hex(torrent.infoHashes.best)
        return states[hash] != nil ? hash : nil
    }

    private func handleUpdate(_ torrent: TorrentHandle) {
        guard let hash = key(for: torrent), let current = states[hash] else { return }
        // Terminal states: nothing more to publish.
        switch current {
        case .finished, .failed: return
        default: break
        }

        torrent.updateSnapshot()
        let snapshot = torrent.snapshot
        guard snapshot.isValid else { return }

        var newState: TorrentPlayState
        var shouldPause = false

        if snapshot.state == .storageError {
            newState = .failed(message: "Error de almacenamiento al descargar.")
        } else if !snapshot.hasMetadata {
            let name = snapshot.name.isEmpty ? nil : snapshot.name
            if case .fetchingMetadata(let existing) = current {
                newState = .fetchingMetadata(fileName: name ?? existing)
            } else {
                newState = .fetchingMetadata(fileName: name)
            }
        } else {
            let files = snapshot.files
            if selectedFile[hash] == nil {
                guard let index = Self.chooseFile(files: files, preferred: pendingFileIdx[hash]) else {
                    publish(hash, .failed(message: "El torrent no contiene archivos."), force: true)
                    return
                }
                selectedFile[hash] = index
                pendingFileIdx[hash] = nil
                torrent.setAllFilesPriority(.dontDownload)
                torrent.setFilePriority(.topPriority, at: index)
                torrent.setSequentialDownload(true)
                torrent.setFirstLastPriorityDownload(true)
            }
            guard let index = selectedFile[hash], index >= 0, index < files.count else { return }
            let file = files[index]
            let fileName = (file.name as NSString).lastPathComponent
            let ext = (file.path as NSString).pathExtension.lowercased()
            let size = file.size
            let downloaded = min(file.downloaded, size)
            let threshold = min(UInt64(5 * 1024 * 1024), size * 2 / 100)

            if snapshot.isFinished || (size > 0 && downloaded >= size) {
                newState = .finished(fileName: fileName)
                shouldPause = !seedAfterFinish
            } else if downloaded >= threshold {
                if Self.playableExtensions.contains(ext) {
                    newState = .readyToPlay(fileName: fileName, downloaded: downloaded, total: size)
                } else {
                    let format = ext.isEmpty ? "desconocido" : ext.uppercased()
                    newState = .unsupportedFormat(fileName: fileName, format: format)
                }
            } else {
                let progress = size > 0 ? Double(downloaded) / Double(size) : 0
                newState = .downloading(
                    progress: progress,
                    rate: snapshot.downloadRate,
                    downloaded: downloaded,
                    total: size,
                    fileName: fileName
                )
            }
        }

        let terminal: Bool
        switch newState {
        case .finished, .failed: terminal = true
        default: terminal = false
        }
        publish(hash, newState, force: terminal)
        if shouldPause { torrent.pause() }
    }

    /// Publishes `state`, throttled to ~0.25 s per hash unless `force`.
    private func publish(_ hash: String, _ state: TorrentPlayState, force: Bool) {
        let now = Date()
        if !force, let last = lastPublish[hash], now.timeIntervalSince(last) < Self.publishInterval {
            return
        }
        lastPublish[hash] = now
        if states[hash] != state {
            states[hash] = state
        }
    }

    private func clearEntries(for hash: String) {
        handles[hash] = nil
        pendingFileIdx[hash] = nil
        selectedFile[hash] = nil
        lastPublish[hash] = nil
        states[hash] = nil
    }

    // MARK: - Helpers

    private static func chooseFile(files: [FileEntry], preferred: Int?) -> Int? {
        guard !files.isEmpty else { return nil }
        if let preferred, preferred >= 0, preferred < files.count {
            return preferred
        }
        var bestVideo: (index: Int, size: UInt64)?
        var bestAny: (index: Int, size: UInt64)?
        for (offset, file) in files.enumerated() {
            if bestAny == nil || file.size > bestAny!.size {
                bestAny = (offset, file.size)
            }
            let ext = (file.path as NSString).pathExtension.lowercased()
            if videoExtensions.contains(ext), bestVideo == nil || file.size > bestVideo!.size {
                bestVideo = (offset, file.size)
            }
        }
        return bestVideo?.index ?? bestAny?.index
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func magnetURL(infoHash: String, title: String, sources: [String]?) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func enc(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        var string = "magnet:?xt=urn:btih:\(infoHash)&dn=\(enc(title))"
        for source in sources ?? [] {
            var tracker = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if tracker.hasPrefix("dht:") { continue }
            if tracker.hasPrefix("tracker:") { tracker.removeFirst("tracker:".count) }
            if tracker.isEmpty { continue }
            string += "&tr=\(enc(tracker))"
        }
        return URL(string: string)
    }
}
