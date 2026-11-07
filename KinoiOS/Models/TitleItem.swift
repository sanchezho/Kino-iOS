import Foundation

enum TitleKind: String, Codable, CaseIterable {
    case movie = "movie"
    case series = "series"
    case live = "live"

    var label: String {
        switch self {
        case .movie: return "Película"
        case .series: return "Serie"
        case .live: return "En vivo"
        }
    }
}

/// A watchable title. In Phase 1 the only titles with a real stream are the
/// clearly labelled Apple sample HLS test streams below. Every other title
/// is catalog-only (`streamURL == nil`) until a plugin implements playback.
struct TitleItem: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var kind: TitleKind
    var posterURL: URL?
    var synopsis: String
    var year: Int?
    var pluginId: String
    var streamURL: URL?

    var hasStream: Bool { streamURL != nil }
}

extension TitleItem {
    /// Apple sample HLS stream, used only to test AVPlayer in Phase 1.
    /// This is not an Internet Archive file and not a Kino title.
    static let sampleHLS = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_hevc/master.m3u8"
    )!

    static let sampleTitles: [TitleItem] = [
        TitleItem(
            id: "test-bipbop",
            title: "Test stream — BipBop (muestra de Apple)",
            kind: .movie,
            posterURL: nil,
            synopsis: "Stream HLS de prueba de Apple, solo para verificar que AVPlayer reproduce en esta app. No es un título de Kino ni un archivo de Internet Archive.",
            year: nil,
            pluginId: "internet-archive",
            streamURL: sampleHLS
        ),
        TitleItem(
            id: "catalog-internet-archive",
            title: "Internet Archive — películas de dominio público",
            kind: .movie,
            posterURL: nil,
            synopsis: "Catálogo del plugin internet-archive (kinotvapp/kino-plugin-archive): películas de dominio público y televisión clásica de archive.org. En Fase 1 es solo catálogo: todavía no reproduce.",
            year: nil,
            pluginId: "internet-archive",
            streamURL: nil
        ),
        TitleItem(
            id: "catalog-tmdb",
            title: "TMDB — catálogo de películas y series",
            kind: .series,
            posterURL: nil,
            synopsis: "Catálogo del plugin tmdb (kinotvapp/kino-plugin-tmdb): información de películas y series de TMDB. En Fase 1 es solo catálogo: todavía no reproduce.",
            year: nil,
            pluginId: "tmdb",
            streamURL: nil
        )
    ]
}
