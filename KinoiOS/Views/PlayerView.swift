import AVKit
import SwiftUI

/// AVPlayer view. Playback starts in `PlaybackService.play(_:)`; this view
/// only presents the player and saves the position when it disappears.
struct PlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoPlayer(player: playback.player)
                    .onAppear {
                        playback.resume()
                    }
                    .onDisappear {
                        playback.pause()
                    }
                if let error = playback.playerError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding()
                }
                if let title = playback.currentTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.title).bold()
                        Text("AVPlayer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                Spacer()
            }
            .navigationTitle(playback.currentTitle?.title ?? "Reproductor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
