import SwiftUI

/// "Ver más" target for an Internet Archive Home row.
struct BrowseTarget: Hashable {
    var rowId: String
    var title: String
}

/// Paginated poster grid for one Internet Archive Home row
/// (the plugin's `browse`: 50 titles per page).
struct BrowseView: View {
    var target: BrowseTarget
    @EnvironmentObject private var archive: ArchiveService
    @State private var items: [ArchiveItem] = []
    @State private var nextPage: Int? = 1
    @State private var isLoading = false
    @State private var error: String?

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
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

            if let error {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Reintentar") {
                        Task { await load(page: nextPage ?? 1) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }

            if isLoading {
                ProgressView()
                    .padding()
            } else if nextPage != nil {
                Button("Cargar más") {
                    Task { await load(page: nextPage ?? 1) }
                }
                .buttonStyle(.bordered)
                .padding(.bottom)
            }
        }
        .navigationTitle(target.title)
        .navigationDestination(for: ArchiveItem.self) { item in
            ArchiveDetailView(item: item)
        }
        .task {
            if items.isEmpty { await load(page: 1) }
        }
    }

    private func load(page: Int) async {
        isLoading = true
        error = nil
        do {
            let (pageItems, next) = try await archive.browse(rowId: target.rowId, page: page)
            items.append(contentsOf: pageItems)
            nextPage = next
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
