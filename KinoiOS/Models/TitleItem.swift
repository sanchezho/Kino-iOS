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
/// clearly labelled Apple sample HLS test streams below. Phase 2 titles
/// come from Internet Archive (`ArchiveItem.asTitleItem`) once their
/// stream URL has been resolved.
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
    /// Apple sample HLS stream, used only to test AVPlayer.
    /// This is not an Internet Archive file and not a Kino title.
    /// The HEVC example URL used in Phase 1 is dead (it 302-redirects to
    /// developer.apple.com/videos/); this classic BipBop URL was verified
    /// 2026-11-07 to answer 200 with application/x-mpegURL.
    static let sampleHLS = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8"
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
        )
    ]
}
