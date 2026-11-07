import SwiftUI

/// Detail for an Internet Archive title: poster, year, overview, and
/// a Reproducir button that first resolves the stream (the plugin's
/// `resolve`) and only then opens the player. Series show their
/// episodes, each with its own play button.
struct ArchiveDetailView: View {
    var item: ArchiveItem
    @EnvironmentObject private var archive: ArchiveService
    @EnvironmentObject private var playback: PlaybackService
    @State private var episodes: [ArchiveEpisode]?
    @State private var episodesError: String?
    @State private var resolving = false
    @State private var resolveError: String?
    @State private var resolvedURL: URL?
    @State private var showingPlayer = false

    private var titleForLibrary: TitleItem {
        TitleItem(
            id: "archive:\(item.id)",
            title: item.title,
            kind: item.kind,
            posterURL: item.posterURL,
            synopsis: item.overview ?? "",
            year: item.year,
            pluginId: "internet-archive",
            streamURL: resolvedURL
        )
    }

    private var savedPosition: Double {
        playback.position(for: titleForLibrary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: item.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.2))
                        Image(systemName: "film")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 320)
                .clipped()
                .cornerRadius(12)

                Text(item.title)
                    .font(.title2)
                    .bold()
                HStack(spacing: 8) {
                    Text(item.kind.label)
                    if let year = item.year {
                        Text(String(year))
                    }
                    Text("· Internet Archive")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                }

                if item.kind == .movie {
                    playButton(
                        label: "Reproducir",
                        action: { await play(ref: item.ref, episode: nil) }
                    )
                    if savedPosition > 1 {
                        Text("Seguir viendo desde \(formatted(savedPosition))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if item.kind == .series {
                    if let episodesError {
                        Text(episodesError)
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else if let episodes {
                        if episodes.isEmpty {
                            Text("Este título no tiene episodios con video en archive.org.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Episodios (\(episodes.count))")
                                .font(.headline)
                            ForEach(episodes) { episode in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("T\(episode.season) E\(episode.number) — \(episode.title)")
                                            .font(.subheadline)
                                            .bold()
                                    }
                                    Spacer()
                                    Button {
                                        Task { await play(ref: episode.ref, episode: episode) }
                                    } label: {
                                        Label("Ver", systemImage: "play.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(resolving)
                                }
                                Divider()
                            }
                        }
                    } else {
                        ProgressView("Buscando episodios…")
                    }
                }

                if let resolveError {
                    Text(resolveError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Button {
                    playback.toggleSaved(titleForLibrary)
                } label: {
                    Label(
                        playback.isSaved(titleForLibrary) ? "Quitar de mi biblioteca" : "Guardar en mi biblioteca",
                        systemImage: playback.isSaved(titleForLibrary) ? "bookmark.fill" : "bookmark"
                    )
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlayer) {
            PlayerView()
        }
        .task {
            guard item.kind == .series, episodes == nil else { return }
            do {
                let result = try await archive.episodes(identifier: item.id)
                episodes = result.episodes
            } catch {
                episodesError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func playButton(label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if resolving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label(label, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(resolving)
    }

    private func play(ref: String, episode: ArchiveEpisode?) async {
        if let url = resolvedURL, episode == nil {
            playback.playArchive(item, streamURL: url)
            showingPlayer = true
            return
        }
        resolving = true
        resolveError = nil
        defer { resolving = false }
        do {
            let resolved = try await archive.resolve(ref: ref)
            if episode == nil {
                resolvedURL = resolved.url
            }
            playback.playArchive(item, streamURL: resolved.url, episode: episode)
            showingPlayer = true
        } catch {
            resolveError = error.localizedDescription
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Detail for a Cinemeta title: poster, year, rating, genres, cast and
/// description. Cinemeta is a catalog — it has no video streams, so
/// there is no play button here. Instead the detail searches Internet
/// Archive for the same title (see `searchArchive`): when the title
/// is in the public-domain archive, its matches are listed below with
/// a play link; new commercial releases are not in the archive and
/// cannot be played from these catalogs.
struct CinemetaDetailView: View {
    var item: CinemetaItem
    @EnvironmentObject private var cinemeta: CinemetaService
    @EnvironmentObject private var archive: ArchiveService
    @EnvironmentObject private var streams: StremioStreamService
    @EnvironmentObject private var playback: PlaybackService
    @State private var detail: CinemetaItem?
    @State private var detailError: String?
    @State private var archiveMatches: [ArchiveItem]?
    @State private var archiveSearchError: String?
    @State private var isSearchingArchive = false
    @State private var streamList: [StremioStream]?
    @State private var streamsError: String?
    @State private var isLoadingStreams = false
    @State private var addonName: String?
    @State private var showingPlayer = false

    private var shown: CinemetaItem { detail ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: shown.backgroundURL ?? shown.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.2))
                        Image(systemName: "film")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
                .clipped()
                .cornerRadius(12)

                Text(shown.title)
                    .font(.title2)
                    .bold()
                HStack(spacing: 8) {
                    Text(shown.kind.label)
                    if let year = shown.year {
                        Text(String(year))
                    }
                    if let rating = shown.rating {
                        Text("★ \(rating)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !shown.genres.isEmpty {
                    Text(shown.genres.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let overview = shown.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                }
                if !shown.cast.isEmpty {
                    Text("Reparto: \(shown.cast.prefix(6).joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let detailError {
                    Text(detailError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                // Puente a Internet Archive: el mismo título, si está
                // en el archivo público, se puede reproducir desde aquí.
                if isSearchingArchive && archiveMatches == nil {
                    ProgressView("Buscando en Internet Archive…")
                        .font(.callout)
                } else if let matches = archiveMatches, !matches.isEmpty {
                    Text("Disponible en Internet Archive")
                        .font(.headline)
                    ForEach(matches) { match in
                        NavigationLink(value: match) {
                            HStack(alignment: .top, spacing: 12) {
                                AsyncImage(url: match.posterURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.2))
                                }
                                .frame(width: 60, height: 90)
                                .clipped()
                                .cornerRadius(6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.title)
                                        .font(.subheadline)
                                        .bold()
                                    if let year = match.year {
                                        Text(String(year))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Label("Ver", systemImage: "play.fill")
                                        .font(.caption)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                } else if let archiveSearchError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(archiveSearchError)
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Button("Reintentar") { Task { await searchArchive() } }
                            .buttonStyle(.bordered)
                    }
                } else if archiveMatches != nil {
                    Label("Este título no está en Internet Archive. El archivo solo tiene películas de dominio público; los estrenos como este no se pueden reproducir desde estos catálogos.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Fuentes del add-on de streams (Stremio/Torrentio):
                // la lista real de fuentes de este título. Los streams
                // con URL directa se reproducen; los torrents se listan
                // pero no se pueden reproducir en iOS (sin motor torrent).
                if isLoadingStreams && streamList == nil {
                    ProgressView("Buscando fuentes…")
                        .font(.callout)
                } else if let streamList, !streamList.isEmpty {
                    Text("Fuentes (streams)")
                        .font(.headline)
                    if let addonName {
                        Text("Add-on: \(addonName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(streamList) { stream in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stream.displayName)
                                    .font(.subheadline)
                                    .bold()
                                if !stream.detailLine.isEmpty {
                                    Text(stream.detailLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if stream.isTorrent {
                                    Text("Torrent — sin motor en iOS")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if stream.isDirect {
                                Button {
                                    playStream(stream)
                                } label: {
                                    Label("Ver", systemImage: "play.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        Divider()
                    }
                } else if let streamsError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(streamsError)
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Button("Reintentar") { Task { await loadStreams() } }
                            .buttonStyle(.bordered)
                    }
                } else if streamList != nil {
                    Text("Sin fuentes de este add-on para este título.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlayer) {
            PlayerView()
        }
        .task {
            guard detail == nil else { return }
            do {
                detail = try await cinemeta.metaDetail(type: item.type, imdbId: item.id)
            } catch {
                detailError = error.localizedDescription
            }
            await searchArchive()
            await loadStreams()
        }
    }

    /// Searches Internet Archive for this title. A match opens the
    /// Archive detail, which resolves the stream and plays it.
    private func searchArchive() async {
        isSearchingArchive = true
        archiveSearchError = nil
        defer { isSearchingArchive = false }
        do {
            archiveMatches = try await archive.search(query: item.title)
        } catch {
            archiveSearchError = error.localizedDescription
        }
    }

    /// Lists this title's streams from the configured Stremio add-on.
    /// Series are queried with the series imdb id only; an empty
    /// result is expected there — episode ids are never invented.
    private func loadStreams() async {
        isLoadingStreams = true
        streamsError = nil
        defer { isLoadingStreams = false }
        addonName = await streams.manifestName()
        do {
            streamList = try await streams.streams(type: item.type, imdbId: item.id)
        } catch {
            streamsError = error.localizedDescription
        }
    }

    /// Plays a direct-URL stream through the shared player.
    private func playStream(_ stream: StremioStream) {
        guard let urlString = stream.url, let url = URL(string: urlString) else { return }
        let title = TitleItem(
            id: "stremio:\(stream.id)",
            title: shown.title,
            kind: shown.kind,
            posterURL: shown.posterURL,
            synopsis: shown.overview ?? "",
            year: shown.year,
            pluginId: "stremio",
            streamURL: url
        )
        playback.play(title)
        showingPlayer = true
    }
}
