import SwiftUI

/// Home with real posters, Phase 2: the three Internet Archive rows
/// (films, classic TV, cartoons) and the Cinemeta catalog sections.
/// Each row loads independently — one failing row shows its own error
/// and retry button instead of blanking the whole Home.
struct HomeView: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var archive: ArchiveService
    @EnvironmentObject private var cinemeta: CinemetaService
    @State private var archiveRows: [ArchiveRow] = []
    @State private var cinemetaSections: [CinemetaSection] = []
    @State private var isLoading = true

    private var continueWatching: [TitleItem] {
        playback.continueWatchingTitles()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !continueWatching.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Seguir viendo")
                                .font(.headline)
                                .padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(continueWatching) { title in
                                        NavigationLink(value: title) {
                                            PosterCard(
                                                posterURL: title.posterURL,
                                                title: title.title,
                                                subtitle: title.kind.label
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    if isLoading && archiveRows.isEmpty && cinemetaSections.isEmpty {
                        ProgressView("Cargando catálogos…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }

                    ForEach(archiveRows) { row in
                        ArchiveRowSection(
                            row: row,
                            onRetry: { Task { await reloadRow(row) } }
                        )
                    }

                    ForEach(cinemetaSections) { section in
                        CinemetaSectionView(
                            section: section,
                            onRetry: { Task { await reloadSection(section) } }
                        )
                    }

                    if !isLoading && archiveRows.isEmpty && cinemetaSections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No se pudieron cargar los catálogos.")
                                .font(.headline)
                            Text("Revisa tu conexión a internet e inténtalo de nuevo.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Reintentar") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Para probar el reproductor")
                            .font(.headline)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
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
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Kino")
            .navigationDestination(for: TitleItem.self) { title in
                DetailView(title: title)
            }
            .navigationDestination(for: ArchiveItem.self) { item in
                ArchiveDetailView(item: item)
            }
            .navigationDestination(for: CinemetaItem.self) { item in
                CinemetaDetailView(item: item)
            }
            .navigationDestination(for: BrowseTarget.self) { target in
                BrowseView(target: target)
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        async let rows = archive.homeRows()
        async let sections = cinemeta.sections()
        archiveRows = await rows
        cinemetaSections = await sections
        isLoading = false
    }

    private func reloadRow(_ row: ArchiveRow) async {
        guard let def = ArchiveRowDef.all.first(where: { $0.id == row.id }) else { return }
        let fresh = await archive.fetchRow(def)
        if let index = archiveRows.firstIndex(where: { $0.id == row.id }) {
            archiveRows[index] = fresh
        }
    }

    private func reloadSection(_ section: CinemetaSection) async {
        let fresh = await cinemeta.reloadSection(section)
        if let index = cinemetaSections.firstIndex(where: { $0.id == section.id }) {
            cinemetaSections[index] = fresh
        }
    }
}

private struct ArchiveRowSection: View {
    var row: ArchiveRow
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.title)
                    .font(.headline)
                Spacer()
                if !row.items.isEmpty {
                    NavigationLink(value: BrowseTarget(rowId: row.id, title: row.title)) {
                        Text("Ver más")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)

            if let error = row.error, row.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Reintentar") { onRetry() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row.items) { item in
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
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct CinemetaSectionView: View {
    var section: CinemetaSection
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .padding(.horizontal)

            if let error = section.error, section.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Reintentar") { onRetry() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(section.items) { item in
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
                    .padding(.horizontal)
                }
            }
        }
    }
}

/// A poster card used by Home, Browse and Search: the poster image
/// (or a placeholder while it loads), the title and one subtitle line.
struct PosterCard: View {
    var posterURL: URL?
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.2))
                    ProgressView()
                }
            }
            .frame(width: 120, height: 180)
            .clipped()
            .cornerRadius(8)
            Text(title)
                .font(.caption)
                .bold()
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
            }
        }
    }
}
