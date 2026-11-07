import Foundation
import SwiftVLC

/// VLC player wrapper with continue-watching position and saved titles,
/// both persisted in UserDefaults. Phase 4b: a single SwiftVLC `Player`
/// replaces AVPlayer for ALL playback (Archive direct streams, Cinemeta
/// direct streams, torrents through the local HTTP server). VLC plays
/// MP4/MOV as well as MKV/AVI/WMV/FLV, so there is no per-format routing
/// and no unsupported-format dead end.
///
/// The position / saved-titles / known-titles logic is player-agnostic
/// and unchanged from the AVPlayer era: positions are still stored as
/// Double seconds under `kino.position.<title-id>`, so positions saved
/// by 0.4.0 keep working.
///
/// No downloads, no background audio session configuration beyond
/// VLC defaults.
@MainActor
final class PlaybackService: ObservableObject {
    /// The single shared VLC player. `Player()` only builds the libVLC
    /// instance; no media is loaded and no network happens here.
    let vlcPlayer = Player()

    @Published private(set) var currentTitle: TitleItem?
    @Published private(set) var isPlaying = false
    /// Set when the current playback fails (a bad URL throws from
    /// `play(url:)`, a bad stream surfaces as a VLC error event), so the
    /// player shows the error instead of a black screen.
    @Published private(set) var playerError: String?
    /// Live playback position for the control bar (seconds). Updated by a
    /// 0.5 s poll while a title is loaded; 0 duration means unknown/live.
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0

    private let savedKey = "kino.savedTitleIDs"
    private let continueKey = "kino.continueWatchingIDs"
    private let knownTitlesKey = "kino.knownTitles"

    /// Surfaces VLC failures: libVLC reports a bad stream as
    /// `.encounteredError` / state `.error`, not as a throw from play().
    private var errorTask: Task<Void, Never>?
    /// Polls VLC time/duration for the control bar.
    private var timeTask: Task<Void, Never>?
    /// Waits for a seekable duration, then restores a saved position.
    private var restoreTask: Task<Void, Never>?

    init() {
        errorTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.vlcPlayer.events {
                switch event {
                case .encounteredError, .stateChanged(.error):
                    self.playerError = "No se pudo reproducir el video."
                    self.isPlaying = false
                case .endReached:
                    self.isPlaying = false
                default:
                    break
                }
            }
        }
        timeTask = Task { [weak self] in
            while true {
                if Task.isCancelled { return }
                guard let self else { return }
                if self.currentTitle != nil {
                    let current = Double(self.vlcPlayer.currentTime.milliseconds) / 1000.0
                    let total = self.vlcPlayer.duration.map { Double($0.milliseconds) / 1000.0 } ?? 0
                    if abs(current - self.currentTimeSeconds) > 0.25 {
                        self.currentTimeSeconds = current
                    }
                    if total != self.durationSeconds {
                        self.durationSeconds = total
                    }
                } else if self.currentTimeSeconds != 0 || self.durationSeconds != 0 {
                    self.currentTimeSeconds = 0
                    self.durationSeconds = 0
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func positionKey(for id: String) -> String {
        "kino.position.\(id)"
    }

    func play(_ title: TitleItem) {
        guard let url = title.streamURL else { return }
        savePosition()
        restoreTask?.cancel()
        restoreTask = nil
        remember(title)
        currentTitle = title
        playerError = nil
        isPlaying = false
        currentTimeSeconds = 0
        durationSeconds = 0
        do {
            try vlcPlayer.play(url: url)
        } catch {
            playerError = error.localizedDescription
            return
        }
        isPlaying = true
        markContinueWatching(title)
        restoreSavedPosition(for: title)
    }

    /// Restores the saved position once the player knows the duration
    /// and is seekable. `seek(to: Duration)` throws while the duration
    /// is unknown, so this polls the (observable) player state instead
    /// of seeking right after `play(url:)`. Gives up after 30 s (live
    /// streams and unparseable media never report a duration) and on
    /// title change; the position is simply not restored in that case.
    private func restoreSavedPosition(for title: TitleItem) {
        let saved = position(for: title)
        guard saved > 1 else { return }
        let titleID = title.id
        restoreTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if Task.isCancelled { return }
                guard let self else { return }
                guard self.currentTitle?.id == titleID else { return }
                if let duration = self.vlcPlayer.duration, self.vlcPlayer.isSeekable {
                    let total = Double(duration.milliseconds) / 1000.0
                    if total > 0, saved < total {
                        try? self.vlcPlayer.seek(to: Duration.seconds(saved))
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Play an Internet Archive title (or one of its episodes) once its
    /// stream URL has been resolved.
    func playArchive(_ item: ArchiveItem, streamURL: URL, episode: ArchiveEpisode? = nil) {
        let title: TitleItem
        if let episode {
            title = TitleItem(
                id: "archive:\(episode.ref)",
                title: episode.title,
                kind: item.kind,
                posterURL: item.posterURL,
                synopsis: "\(episode.title) — \(item.title)",
                year: item.year,
                pluginId: "internet-archive",
                streamURL: streamURL
            )
        } else {
            title = item.asTitleItem(streamURL: streamURL)
        }
        play(title)
    }

    func pause() {
        savePosition()
        vlcPlayer.pause()
        isPlaying = false
    }

    func resume() {
        guard currentTitle != nil else { return }
        vlcPlayer.resume()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        try? vlcPlayer.seek(to: Duration.seconds(seconds))
    }

    /// Saves the current VLC time as Double seconds, same key and format
    /// as the AVPlayer era, so stored positions survive the switch.
    func savePosition() {
        guard let title = currentTitle else { return }
        let seconds = Double(vlcPlayer.currentTime.milliseconds) / 1000.0
        guard seconds.isFinite, seconds > 0 else { return }
        UserDefaults.standard.set(seconds, forKey: positionKey(for: title.id))
    }

    func position(for title: TitleItem) -> Double {
        UserDefaults.standard.double(forKey: positionKey(for: title.id))
    }

    // MARK: - Continue watching

    private func markContinueWatching(_ title: TitleItem) {
        var ids = UserDefaults.standard.stringArray(forKey: continueKey) ?? []
        ids.removeAll { $0 == title.id }
        ids.insert(title.id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(20)), forKey: continueKey)
    }

    func continueWatchingTitles() -> [TitleItem] {
        let ids = UserDefaults.standard.stringArray(forKey: continueKey) ?? []
        return ids.compactMap { id in title(for: id) }
    }

    // MARK: - Saved titles

    var savedIDs: [String] {
        UserDefaults.standard.stringArray(forKey: savedKey) ?? []
    }

    func isSaved(_ title: TitleItem) -> Bool {
        savedIDs.contains(title.id)
    }

    func toggleSaved(_ title: TitleItem) {
        remember(title)
        var ids = savedIDs
        if ids.contains(title.id) {
            ids.removeAll { $0 == title.id }
        } else {
            ids.append(title.id)
        }
        UserDefaults.standard.set(ids, forKey: savedKey)
        objectWillChange.send()
    }

    func savedTitles() -> [TitleItem] {
        savedIDs.compactMap { id in title(for: id) }
    }

    // MARK: - Known titles (played or saved, so Library can show them)

    private func title(for id: String) -> TitleItem? {
        knownTitles().first { $0.id == id }
            ?? TitleItem.sampleTitles.first { $0.id == id }
    }

    private func remember(_ title: TitleItem) {
        var known = knownTitles()
        if let index = known.firstIndex(where: { $0.id == title.id }) {
            known[index] = title
        } else {
            known.insert(title, at: 0)
        }
        if let data = try? JSONEncoder().encode(Array(known.prefix(100))) {
            UserDefaults.standard.set(data, forKey: knownTitlesKey)
        }
    }

    private func knownTitles() -> [TitleItem] {
        guard let data = UserDefaults.standard.data(forKey: knownTitlesKey),
              let titles = try? JSONDecoder().decode([TitleItem].self, from: data) else {
            return []
        }
        return titles
    }
}
