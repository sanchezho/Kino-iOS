import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var playback: PlaybackService

    var body: some View {
        NavigationStack {
            List {
                Section("Seguir viendo") {
                    let watching = playback.continueWatchingTitles()
                    if watching.isEmpty {
                        Text("Todavía no hay nada en curso. Reproduce el stream de prueba desde Inicio.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(watching) { title in
                        NavigationLink(value: title) {
                            LibraryRow(title: title, subtitle: "Posición guardada: \(formatted(playback.position(for: title)))")
                        }
                    }
                }
                Section("Guardados") {
                    let saved = playback.savedTitles()
                    if saved.isEmpty {
                        Text("Nada guardado todavía.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(saved) { title in
                        NavigationLink(value: title) {
                            LibraryRow(title: title, subtitle: title.kind.label)
                        }
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .navigationDestination(for: TitleItem.self) { title in
                DetailView(title: title)
            }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct LibraryRow: View {
    var title: TitleItem
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.title).bold()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
