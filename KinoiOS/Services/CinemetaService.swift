import Foundation

/// Cinemeta catalog (Stremio addon `cinemeta` in the bundled seed:
/// `https://v3-cinemeta.strem.io/manifest.json`), the same catalog the
/// original Kino app lists. Catalog only: Cinemeta serves posters,
/// titles and metadata — it has no video streams, so playback for these
/// titles comes from Internet Archive (see `ArchiveService`).
///
/// The manifest host 307-redirects to `cinemeta-catalogs.strem.io`;
/// URLSession follows redirects automatically, so the base URL is used
/// as-is. No search endpoint exists, so Phase 2 has no Cinemeta search.
/// No API key needed.
final class CinemetaService: ObservableObject {
    static let base = "https://v3-cinemeta.strem.io"

    /// The four catalogs shown on Home (from the live manifest).
    private static let wantedCatalogs: [(type: String, id: String, title: String)] = [
        ("movie", "top", "Películas populares"),
        ("series", "top", "Series populares"),
        ("movie", "year", "Películas nuevas"),
        ("series", "year", "Series nuevas"),
    ]

    /// One Home section, or its error if that catalog failed.
    func sections() async -> [CinemetaSection] {
        // Fetch the manifest first (it lists the catalogs); fall back to
        // the known catalog ids if the manifest itself fails.
        let catalogs = (try? await manifest()) ?? Self.wantedCatalogs.map { CinemetaCatalogRef(type: $0.type, id: $0.id) }
        let wanted = Self.wantedCatalogs.compactMap { want in
            catalogs.first { $0.type == want.type && $0.id == want.id }.map { (want.title, $0) }
        }
        let sections = await withTaskGroup(of: CinemetaSection.self) { group in
            for (title, ref) in wanted {
                group.addTask { await self.fetchSection(title: title, ref: ref) }
            }
            var collected: [CinemetaSection] = []
            for await section in group { collected.append(section) }
            return collected
        }
        return Self.wantedCatalogs.compactMap { want in sections.first { $0.id == "\(want.type)/\(want.id)" } }
    }

    private func fetchSection(title: String, ref: CinemetaCatalogRef) async -> CinemetaSection {
        let id = "\(ref.type)/\(ref.id)"
        do {
            let items = try await catalog(type: ref.type, id: ref.id)
            return CinemetaSection(id: id, title: title, items: items, error: nil)
        } catch {
            return CinemetaSection(id: id, title: title, items: [], error: error.localizedDescription)
        }
    }

    /// Reload one section (its id is `<type>/<catalog>`).
    func reloadSection(_ section: CinemetaSection) async -> CinemetaSection {
        let parts = section.id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return section }
        return await fetchSection(title: section.title, ref: CinemetaCatalogRef(type: parts[0], id: parts[1]))
    }

    /// Full metadata for a title (cast, director, rating, runtime).
    func metaDetail(type: String, imdbId: String) async throws -> CinemetaItem {
        guard let url = URL(string: Self.base + "/meta/\(type)/\(imdbId).json") else {
            throw CinemetaError.badResponse("Identificador inválido.")
        }
        let data = try await getData(url)
        let decoded = try JSONDecoder().decode(CinemetaMetaResponse.self, from: data)
        return CinemetaItem(meta: decoded.meta)
    }

    // MARK: - Raw API

    private func manifest() async throws -> [CinemetaCatalogRef] {
        guard let url = URL(string: Self.base + "/manifest.json") else {
            throw CinemetaError.badResponse("No se pudo armar la petición.")
        }
        let data = try await getData(url)
        let decoded = try JSONDecoder().decode(CinemetaManifest.self, from: data)
        return decoded.catalogs
    }

    private func catalog(type: String, id: String) async throws -> [CinemetaItem] {
        guard let url = URL(string: Self.base + "/catalog/\(type)/\(id).json") else {
            throw CinemetaError.badResponse("Catálogo inválido.")
        }
        let data = try await getData(url)
        let decoded = try JSONDecoder().decode(CinemetaCatalogResponse.self, from: data)
        return decoded.metas.map(CinemetaItem.init)
    }

    private func getData(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CinemetaError.badResponse("Cinemeta respondió \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return data
    }

    enum CinemetaError: LocalizedError {
        case badResponse(String)

        var errorDescription: String? {
            if case .badResponse(let message) = self { return message }
            return nil
        }
    }
}

/// One Cinemeta title (movie or series), from a catalog or meta detail.
struct CinemetaItem: Identifiable, Hashable {
    var id: String
    var type: String
    var title: String
    var year: Int?
    var posterURL: URL?
    var backgroundURL: URL?
    var overview: String?
    var genres: [String]
    var rating: String?
    var runtime: String?
    var cast: [String]

    var kind: TitleKind { type == "series" ? .series : .movie }

    init(meta: CinemetaMeta) {
        id = meta.imdb_id ?? meta.id
        type = meta.type
        title = meta.name
        year = CinemetaItem.parseYear(meta.year)
        posterURL = URL(string: meta.poster ?? "")
        backgroundURL = URL(string: meta.background ?? "")
        overview = meta.description
        genres = meta.genres ?? meta.genre ?? []
        rating = meta.imdbRating
        runtime = meta.runtime
        cast = meta.cast ?? []
    }

    private static func parseYear(_ value: CinemetaYear?) -> Int? {
        switch value {
        case .int(let n): return n
        case .string(let s): return Int(s)
        case .none: return nil
        }
    }
}

/// One Home section from a Cinemeta catalog.
struct CinemetaSection: Identifiable, Hashable {
    var id: String
    var title: String
    var items: [CinemetaItem]
    var error: String?
}

// MARK: - Decodable wire models

struct CinemetaCatalogRef: Decodable {
    var type: String
    var id: String
}

struct CinemetaManifest: Decodable {
    var catalogs: [CinemetaCatalogRef]
}

struct CinemetaCatalogResponse: Decodable {
    var metas: [CinemetaMeta]
}

struct CinemetaMetaResponse: Decodable {
    var meta: CinemetaMeta
}

/// `year` arrives as an int or a string, depending on the endpoint.
enum CinemetaYear: Decodable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int.self) {
            self = .int(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.typeMismatch(CinemetaYear.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "year no es número ni texto"))
        }
    }
}

struct CinemetaMeta: Decodable {
    var id: String
    var imdb_id: String?
    var type: String
    var name: String
    var year: CinemetaYear?
    var poster: String?
    var background: String?
    var description: String?
    var genres: [String]?
    var genre: [String]?
    var imdbRating: String?
    var runtime: String?
    var cast: [String]?
    var director: [String]?
}
