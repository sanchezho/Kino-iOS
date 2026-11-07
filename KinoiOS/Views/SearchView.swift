import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: PluginCatalogService
    @State private var query = ""

    private var matchingTitles: [TitleItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return TitleItem.sampleTitles }
        let needle = trimmed.lowercased()
        return TitleItem.sampleTitles.filter {
            $0.title.lowercased().contains(needle)
                || $0.synopsis.lowercased().contains(needle)
        }
    }

    private var matchingPlugins: [Plugin] {
        catalog.searchPlugins(query)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Títulos") {
                    if matchingTitles.isEmpty {
                        Text("Sin resultados en los títulos de Fase 1.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matchingTitles) { title in
                        NavigationLink(value: title) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title.title).bold()
                                Text(title.synopsis)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                Section("Plugins") {
                    if matchingPlugins.isEmpty {
                        Text("Sin plugins que coincidan.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matchingPlugins) { plugin in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.displayName).bold()
                            Text(plugin.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Buscar en Kino")
            .navigationTitle("Buscar")
            .navigationDestination(for: TitleItem.self) { title in
                DetailView(title: title)
            }
        }
    }
}
