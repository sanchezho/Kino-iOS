import SwiftUI

struct DetailView: View {
    var title: TitleItem
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var catalog: PluginCatalogService
    @State private var showingPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(height: 220)
                    Image(systemName: "film")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                }
                Text(title.title)
                    .font(.title2)
                    .bold()
                HStack(spacing: 8) {
                    Text(title.kind.label)
                    if let year = title.year {
                        Text(String(year))
                    }
                    if let plugin = catalog.plugin(withId: title.pluginId) {
                        Text("· \(plugin.displayName)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(title.synopsis)
                    .font(.body)
                if title.hasStream {
                    Button {
                        playback.play(title)
                        showingPlayer = true
                    } label: {
                        Label("Reproducir", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if savedPosition > 1 {
                        Text("Seguir viendo desde \(formatted(savedPosition))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Sin stream en Fase 1 — solo catálogo", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button {
                    playback.toggleSaved(title)
                } label: {
                    Label(
                        playback.isSaved(title) ? "Quitar de mi biblioteca" : "Guardar en mi biblioteca",
                        systemImage: playback.isSaved(title) ? "bookmark.fill" : "bookmark"
                    )
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(title.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlayer) {
            PlayerView()
        }
    }

    private var savedPosition: Double {
        playback.position(for: title)
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
