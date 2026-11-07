import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var catalog: PluginCatalogService
    @EnvironmentObject private var playback: PlaybackService
    @State private var searchText = ""

    private var continueWatching: [TitleItem] {
        playback.continueWatchingTitles()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = catalog.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                    }

                    if !continueWatching.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Seguir viendo")
                                .font(.headline)
                                .padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(continueWatching) { title in
                                        NavigationLink(value: title) {
                                            TitleCard(title: title)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Para probar el reproductor")
                            .font(.headline)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(TitleItem.sampleTitles) { title in
                                    NavigationLink(value: title) {
                                        TitleCard(title: title)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plugins (\(catalog.plugins.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(catalog.plugins.prefix(12)) { plugin in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plugin.displayName).font(.subheadline).bold()
                                Text(plugin.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let repo = plugin.repo {
                                    Text(repo).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                            Divider()
                        }
                    }
                }
                .padding(.vertical)
            }
            .searchable(text: $searchText, prompt: "Buscar títulos y plugins")
            .navigationTitle("Kino")
            .navigationDestination(for: TitleItem.self) { title in
                DetailView(title: title)
            }
        }
    }
}

struct TitleCard: View {
    var title: TitleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 160, height: 100)
                Image(systemName: title.hasStream ? "play.circle.fill" : "film")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            Text(title.title)
                .font(.caption)
                .bold()
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            Text(title.kind.label + (title.hasStream ? " · Reproducible" : " · Solo catálogo"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
