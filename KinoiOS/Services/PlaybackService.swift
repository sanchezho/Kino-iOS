import AVKit
import Combine
import Foundation

/// AVPlayer wrapper with continue-watching position and saved titles,
/// both persisted in UserDefaults. Phase 2: titles played from Internet
/// Archive are remembered in full (so Library can show them later),
/// not only the Phase 1 sample titles.
///
/// No downloads, no background audio session configuration beyond
/// AVPlayer defaults.
final class PlaybackService: ObservableObject {
    @Published private(set) var player = AVPlayer()
    @Published private(set) var currentTitle: TitleItem?
    @Published private(set) var isPlaying = false
    /// Set when the current player item fails (e.g. a dead stream URL),
    /// so the player shows the error instead of a black screen.
    @Published private(set) var playerError: String?

    private let savedKey = "kino.savedTitleIDs"
    private let continueKey = "kino.continueWatchingIDs"
    private let knownTitlesKey = "kino.knownTitles"

    private var statusObservation: AnyCancellable?

    private func positionKey(for id: String) -> String {
        "kino.position.\(id)"
    }

    func play(_ title: TitleItem) {
        guard let url = title.streamURL else { return }
        savePosition()
        remember(title)
        currentTitle = title
        playerError = nil
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.publisher(for: \.status, options: [.initial, .new])
            .sink { [weak self] status in
                if status == .failed {
                    self?.playerError = item.error?.localizedDescription
                        ?? "No se pudo reproducir el video."
                }
            }
        let saved = position(for: title)
        if saved > 1 {
            player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        markContinueWatching(title)
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
        player.pause()
        isPlaying = false
    }

    func resume() {
        guard currentTitle != nil else { return }
        player.play()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func savePosition() {
        guard let title = currentTitle else { return }
        let seconds = player.currentTime().seconds
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
