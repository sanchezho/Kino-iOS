import SwiftUI
import SwiftVLC

/// VLC player view. Playback starts in `PlaybackService.play(_:)`; this view
/// only presents the player and saves the position when it disappears.
/// Phase 4b: a single SwiftVLC `VideoView` replaces AVPlayer's
/// `VideoPlayer` for all playback — MP4/MOV as well as MKV/AVI/WMV/FLV.
struct PlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    /// Scrub state: while the user drags, the slider shows this value
    /// instead of the polled position, and the seek fires on release.
    @State private var scrubValue: Double = 0
    @State private var scrubbing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoView(playback.vlcPlayer)
                    .onAppear {
                        playback.resume()
                    }
                    .onDisappear {
                        playback.pause()
                    }
                // Minimal transport controls: VideoView is a bare drawable
                // surface, so pause/resume, time and scrubbing live here.
                HStack(spacing: 12) {
                    Button {
                        if playback.isPlaying {
                            playback.pause()
                        } else {
                            playback.resume()
                        }
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .disabled(playback.currentTitle == nil)
                    Text(Self.formatTime(scrubbing ? scrubValue : playback.currentTimeSeconds))
                        .font(.caption.monospacedDigit())
                    Slider(
                        value: Binding(
                            get: { scrubbing ? scrubValue : playback.currentTimeSeconds },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...max(playback.durationSeconds, 1),
                        onEditingChanged: { editing in
                            if editing {
                                scrubValue = playback.currentTimeSeconds
                            }
                            scrubbing = editing
                            if !editing {
                                playback.seek(to: scrubValue)
                            }
                        }
                    )
                    .disabled(playback.durationSeconds <= 0)
                    Text(Self.formatTime(playback.durationSeconds))
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal)
                .padding(.top, 8)
                if let error = playback.playerError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding()
                }
                if let title = playback.currentTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.title).bold()
                        Text("VLC")
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

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
