import Foundation

/// Phase 4 step 1 — link-only stub (no UI, no behavior change yet).
///
/// Constructs a libtorrent `Session` so the next CI run proves the vendored
/// LibTorrent-Swift wrapper compiles and `libtorrent-rasterbar.a` links.
/// No torrent is added, no UI is wired — that comes in steps 2–3
/// (TorrentEngine session/magnet/progress, then the local HTTP server +
/// AVPlayer wiring). See `~/workspace/kino-diagnosis/PHASE4-TORRENT-PLAN.md`.
final class TorrentEngine {
    static let shared = TorrentEngine()

    /// libtorrent version string from the linked C++ library, e.g. "2.1.2.0".
    /// Pure read — safe to call at launch; creates no session, no network.
    static var libtorrentVersion: String {
        Version.libtorrentVersion
    }

    private(set) var session: Session?

    private init() {}

    /// Creates the app's single libtorrent session on first use. Paths mirror
    /// iTorrent: downloads in Documents/torrents, state in Application
    /// Support/kino-torrents (fast-resume + .torrent files, restored on next
    /// launch). Not called yet — step 2 wires it to the stream detail.
    func ensureSession() -> Session {
        if let session { return session }
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloadPath = documents.appendingPathComponent("torrents")
        let statePath = support.appendingPathComponent("kino-torrents")
        try? fileManager.createDirectory(at: downloadPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: statePath, withIntermediateDirectories: true)
        let settings = Session.Settings()
        settings.agentName = "KinoiOS/0.3.0"
        settings.peerFingerprint = "-KI0000-"
        let created = Session(
            downloadPath: downloadPath,
            torrentsPath: statePath,
            fastResumePath: statePath,
            settings: settings,
            storages: [:]
        )
        session = created
        return created
    }
}
