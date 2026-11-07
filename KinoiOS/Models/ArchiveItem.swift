import Foundation

/// Models for the Internet Archive catalog, mirroring the original Kino
/// plugin `kinotvapp/kino-plugin-archive` (id `archive-org`, v1.4.2,
/// apiVersion 3) — see `~/workspace/kino-diagnosis/kino-plugin-archive-plugin.js`.
/// The plugin's logic is re-implemented natively here; no JavaScript runs.

/// One archive.org title (a film or a classic-TV item).
struct ArchiveItem: Identifiable, Hashable, Codable {
    /// archive.org identifier, e.g. `min-and-bill_1930`.
    var id: String
    var title: String
    var kind: TitleKind
    /// Release year when archive.org knows it.
    var year: Int?
    /// `https://archive.org/services/img/<identifier>` — the item's poster.
    var posterURL: URL?
    /// Description with HTML tags stripped, max 400 chars.
    var overview: String?

    /// The reference the plugin's `resolve` takes for this item.
    /// For a single-video item it is just the identifier; episode cards
    /// use `<identifier>|<original filename>`.
    var ref: String { id }

    /// Map this item to the app's playable title model once a stream URL
    /// has been resolved.
    func asTitleItem(streamURL: URL) -> TitleItem {
        TitleItem(
            id: "archive:\(id)",
            title: title,
            kind: kind,
            posterURL: posterURL,
            synopsis: overview ?? "",
            year: year,
            pluginId: "internet-archive",
            streamURL: streamURL
        )
    }
}

/// One Home row from the plugin: `films`, `tv` or `cartoons`.
/// `error` is set when that row failed to load; the other rows still show.
struct ArchiveRow: Identifiable, Hashable {
    var id: String
    var title: String
    var items: [ArchiveItem]
    var error: String?
}

/// The three rows the plugin defines on Home, with their exact queries.
struct ArchiveRowDef: Identifiable, Hashable {
    var id: String
    var title: String
    var query: String
    var kind: TitleKind

    static let films = ArchiveRowDef(
        id: "films",
        title: "Películas de dominio público",
        query: "collection:(feature_films) AND mediatype:(movies)",
        kind: .movie
    )
    static let tv = ArchiveRowDef(
        id: "tv",
        title: "Televisión clásica",
        query: "collection:(classic_tv) AND mediatype:(movies)",
        kind: .series
    )
    static let cartoons = ArchiveRowDef(
        id: "cartoons",
        title: "Animación clásica",
        query: "collection:(animationandcartoons) AND mediatype:(movies)",
        kind: .movie
    )

    static let all: [ArchiveRowDef] = [.films, .tv, .cartoons]
}

/// One episode of a series item, from the plugin's `episodes`.
struct ArchiveEpisode: Identifiable, Hashable {
    /// `<identifier>|<original filename>` — the ref `resolve` plays.
    var id: String
    var identifier: String
    var filename: String
    var season: Int
    var number: Int
    var title: String

    var ref: String { id }
}

/// One subtitle file found next to a playable video.
struct ArchiveSubtitle: Hashable {
    var lang: String
    var url: URL
    var format: String
}

/// The result of the plugin's `resolve`: a playable stream URL.
struct ArchiveResolved {
    var url: URL
    var mime: String
    var subtitles: [ArchiveSubtitle]
    var durationSeconds: Double?
}
