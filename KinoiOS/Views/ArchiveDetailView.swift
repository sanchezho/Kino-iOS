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
/// there is no play button here; playback in this phase comes from
/// Internet Archive (see the Buscar tab).
struct CinemetaDetailView: View {
    var item: CinemetaItem
    @EnvironmentObject private var cinemeta: CinemetaService
    @State private var detail: CinemetaItem?
    @State private var detailError: String?

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

                Label("Cinemeta es solo un catálogo: no trae video. Si el título está en Internet Archive, búscalo en la pestaña Buscar.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard detail == nil else { return }
            do {
                detail = try await cinemeta.metaDetail(type: item.type, imdbId: item.id)
            } catch {
                detailError = error.localizedDescription
            }
        }
    }
}
