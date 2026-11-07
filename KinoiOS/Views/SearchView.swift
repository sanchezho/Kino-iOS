import SwiftUI

/// Search across Internet Archive (films + classic TV), debounced.
/// Results are poster cards, like Home. An empty query shows the
/// BipBop test stream and a hint instead of an empty list.
struct SearchView: View {
    @EnvironmentObject private var archive: ArchiveService
    @State private var query = ""
    @State private var results: [ArchiveItem] = []
    @State private var isSearching = false
    @State private var searchError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12),
    ]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if trimmedQuery.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Busca películas de dominio público y televisión clásica en Internet Archive.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Para probar el reproductor")
                            .font(.headline)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(TitleItem.sampleTitles) { title in
                                NavigationLink(value: title) {
                                    PosterCard(
                                        posterURL: title.posterURL,
                                        title: title.title,
                                        subtitle: "Stream de prueba"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                } else {
                    if isSearching && results.isEmpty {
                        ProgressView("Buscando…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    if let searchError {
                        VStack(spacing: 8) {
                            Text(searchError)
                                .font(.callout)
                                .foregroundStyle(.orange)
                            Button("Reintentar") {
                                Task { await performSearch() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                    if !isSearching, results.isEmpty, searchError == nil {
                        Text("Sin resultados para “\(trimmedQuery)”.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(results) { item in
                            NavigationLink(value: item) {
                                PosterCard(
                                    posterURL: item.posterURL,
                                    title: item.title,
                                    subtitle: item.year.map(String.init)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .searchable(text: $query, prompt: "Buscar en Kino")
            .navigationTitle("Buscar")
            .navigationDestination(for: TitleItem.self) { title in
                DetailView(title: title)
            }
            .navigationDestination(for: ArchiveItem.self) { item in
                ArchiveDetailView(item: item)
            }
            .task(id: query) {
                // Debounce: wait 400 ms after the last keystroke.
                do {
                    try await Task.sleep(nanoseconds: 400_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await performSearch()
            }
        }
    }

    private func performSearch() async {
        let text = trimmedQuery
        guard !text.isEmpty else {
            results = []
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        searchError = nil
        do {
            results = try await archive.search(query: text)
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }
}
