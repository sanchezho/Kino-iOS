import SwiftUI
import SwiftVLC

/// Fullscreen VLC player view. Phase 4b: a single SwiftVLC `VideoView`
/// replaces AVPlayer's `VideoPlayer` for all playback — MP4/MOV as well
/// as MKV/AVI/WMV/FLV.
///
/// The player takes the whole screen (presented with `fullScreenCover`,
/// video ignores the safe area). Controls are overlaid on the video:
/// top bar (Cerrar + title) and bottom bar (pause/resume, time,
/// scrubber). They auto-hide 3 s after playback starts or after any
/// interaction while playing, and reappear when the user taps the video.
/// While paused the controls stay visible. `VideoView` itself is a bare
/// drawable surface with no controls of its own.
struct PlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    /// Scrub state: while the user drags, the slider shows this value
    /// instead of the polled position, and the seek fires on release.
    @State private var scrubValue: Double = 0
    @State private var scrubbing = false
    /// Overlay controls visibility; auto-hidden while playing.
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoView(playback.vlcPlayer)
                .ignoresSafeArea()
                .onTapGesture {
                    controlsVisible.toggle()
                    if controlsVisible {
                        scheduleHideControls()
                    } else {
                        hideTask?.cancel()
                    }
                }
                .onAppear {
                    playback.resume()
                }
                .onDisappear {
                    playback.pause()
                }
            // Overlay controls (safe-area aware: the top bar sits below
            // the status bar / Dynamic Island, the bottom bar above the
            // home indicator; only the video ignores the safe area).
            VStack {
                HStack {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                    Text(playback.currentTitle?.title ?? "Reproductor")
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                    Spacer()
                    // Balances the Cerrar button so the title stays centered.
                    Text("Cerrar")
                        .hidden()
                }
                Spacer()
                if let error = playback.playerError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .shadow(radius: 4)
                        .padding(.bottom, 8)
                }
                HStack(spacing: 12) {
                    Button {
                        if playback.isPlaying {
                            playback.pause()
                        } else {
                            playback.resume()
                        }
                        scheduleHideControls()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .disabled(playback.currentTitle == nil)
                    Text(Self.formatTime(scrubbing ? scrubValue : playback.currentTimeSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
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
                            scheduleHideControls()
                        }
                    )
                    .disabled(playback.durationSeconds <= 0)
                    Text(Self.formatTime(playback.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
            }
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        }
        .onAppear {
            scheduleHideControls()
        }
        .onChange(of: playback.isPlaying) { _, playing in
            if playing {
                scheduleHideControls()
            } else {
                hideTask?.cancel()
                controlsVisible = true
            }
        }
    }

    /// Hides the overlay 3 s from now, only while playing. Any call
    /// restarts the timer (button taps, scrubbing, tapping the video).
    private func scheduleHideControls() {
        hideTask?.cancel()
        guard playback.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                controlsVisible = false
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
