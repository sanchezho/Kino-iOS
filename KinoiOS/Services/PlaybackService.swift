import AVKit
import Combine
import Foundation

/// AVPlayer wrapper with continue-watching position and saved titles,
/// both persisted in UserDefaults. Phase 1 only: no downloads, no
/// background audio session configuration beyond AVPlayer defaults.
final class PlaybackService: ObservableObject {
    @Published private(set) var player = AVPlayer()
    @Published private(set) var currentTitle: TitleItem?
    @Published private(set) var isPlaying = false

    private let savedKey = "kino.savedTitleIDs"
    private let continueKey = "kino.continueWatchingIDs"

    private func positionKey(for id: String) -> String {
        "kino.position.\(id)"
    }

    func play(_ title: TitleItem) {
        guard let url = title.streamURL else { return }
        savePosition()
        currentTitle = title
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        let saved = position(for: title)
        if saved > 1 {
            player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        markContinueWatching(title)
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
        return ids.compactMap { id in TitleItem.sampleTitles.first { $0.id == id } }
    }

    // MARK: - Saved titles

    var savedIDs: [String] {
        UserDefaults.standard.stringArray(forKey: savedKey) ?? []
    }

    func isSaved(_ title: TitleItem) -> Bool {
        savedIDs.contains(title.id)
    }

    func toggleSaved(_ title: TitleItem) {
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
        savedIDs.compactMap { id in TitleItem.sampleTitles.first { $0.id == id } }
    }
}
