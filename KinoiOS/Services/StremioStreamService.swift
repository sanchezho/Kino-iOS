import Foundation

/// One stream from a Stremio streaming add-on (StreamVault's model:
/// `StremioStream` there carries `infoHash`, `fileIdx`, `sources`,
/// `behaviorHints` and an optional direct `url`). Torrentio
/// (`https://torrentio.strem.fun`, the default add-on) returns torrent
/// streams — `infoHash` + tracker/DHT `sources`, no direct `url` in
/// its default configuration — so those streams are listed but cannot
/// be played on iOS: there is no torrent engine in this app. A stream
/// that does carry a direct `url` (rare with Torrentio's defaults)
/// plays through `PlaybackService` like any other title.
///
/// Decoding is deliberately lenient: every field is optional and a
/// wrong-typed value is skipped instead of failing the whole list,
/// so a real Torrentio response can never throw here.
struct StremioStream: Identifiable, Hashable, Decodable {
    var name: String?
    var title: String?
    var url: String?
    var infoHash: String?
    var fileIdx: Int?
    var sources: [String]?
    var behaviorHints: StremioBehaviorHints?
    /// Stable fallback id, only used when a stream carries no
    /// infoHash, no url and no name/title at all.
    private var fallbackID = UUID()

    var id: String {
        if let infoHash, !infoHash.isEmpty { return infoHash }
        if let url, !url.isEmpty { return url }
        let combined = (name ?? "") + (title ?? "")
        return combined.isEmpty ? fallbackID.uuidString : combined
    }

    /// Torrent streams have an infoHash and no direct URL.
    var isTorrent: Bool { infoHash != nil }
    /// Direct streams carry a playable URL.
    var isDirect: Bool { url != nil }

    /// First line of the add-on's name (Torrentio puts the size and
    /// seeders on later lines), falling back to the title.
    var displayName: String {
        let source = name ?? title ?? ""
        let first = source.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return first.isEmpty ? "Fuente sin nombre" : first
    }

    /// The rest of the title (filename / quality / size details),
    /// capped so a row stays readable.
    var detailLine: String {
        let source = title ?? name ?? ""
        let lines = source.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return "" }
        let rest = lines.dropFirst().joined(separator: " · ")
        return String(rest.prefix(200))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = Self.lenient(container, .name)
        title = Self.lenient(container, .title)
        url = Self.lenient(container, .url)
        infoHash = Self.lenient(container, .infoHash)
        fileIdx = Self.lenient(container, .fileIdx)
        sources = Self.lenient(container, .sources)
        behaviorHints = Self.lenient(container, .behaviorHints)
        fallbackID = UUID()
    }

    /// Decodes one field, returning nil for a missing key, a null, or
    /// a wrong-typed value instead of failing the whole stream.
    private static func lenient<T: Decodable>(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> T? {
        (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, url, infoHash, fileIdx, sources, behaviorHints
    }
}

struct StremioBehaviorHints: Hashable, Decodable {
    var filename: String?
    var bingeGroup: String?
}

/// Streaming add-on client (Stremio protocol), modelled on
/// StreamVault's add-on handling: the base URL is user-configurable
/// and defaults to Torrentio. Endpoints used:
/// `{base}/stream/{type}/{imdbId}.json` and `{base}/manifest.json`.
/// No API key needed. Style matches `CinemetaService` (URLSession,
/// lenient decoding).
final class StremioStreamService: ObservableObject {
    static let defaultBaseURL = "https://torrentio.strem.fun"
    private static let baseURLKey = "kino.streamAddonBaseURL"

    /// The add-on base URL, persisted in UserDefaults. Editing it in
    /// Settings updates this live; a pasted `/manifest.json` suffix
    /// and trailing slashes are stripped on the way in.
    @Published var baseURL: String {
        didSet {
            let normalized = Self.normalize(baseURL)
            if normalized != baseURL {
                baseURL = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.baseURLKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey)
        baseURL = Self.normalize(stored ?? Self.defaultBaseURL)
        // didSet does not run inside init, so persist the normalized
        // value explicitly when it differs from what was stored.
        if stored != baseURL {
            UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey)
        }
    }

    func resetToDefault() {
        baseURL = Self.defaultBaseURL
    }

    /// Streams for a title from the configured add-on. A missing
    /// `streams` key means "no sources", not an error.
    func streams(type: String, imdbId: String) async throws -> [StremioStream] {
        guard let url = URL(string: baseURL + "/stream/\(type)/\(imdbId).json") else {
            throw StremioStreamError.badResponse("Dirección del add-on inválida.")
        }
        let data = try await getData(url)
        let decoded = try JSONDecoder().decode(StremioStreamsResponse.self, from: data)
        return decoded.streams ?? []
    }

    /// The add-on's display name from its manifest, or nil if the
    /// manifest cannot be fetched. Never throws.
    func manifestName() async -> String? {
        guard let url = URL(string: baseURL + "/manifest.json") else { return nil }
        guard let data = try? await getData(url) else { return nil }
        return (try? JSONDecoder().decode(StremioManifest.self, from: data))?.name
    }

    // MARK: - Private

    /// Strips a trailing `/manifest.json` and any trailing slashes.
    private static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("/manifest.json") {
            value = String(value.dropLast("/manifest.json".count))
        }
        while value.hasSuffix("/") {
            value = String(value.dropLast())
        }
        return value.isEmpty ? defaultBaseURL : value
    }

    private func getData(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StremioStreamError.badResponse("El add-on respondió \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return data
    }

    enum StremioStreamError: LocalizedError {
        case badResponse(String)

        var errorDescription: String? {
            if case .badResponse(let message) = self { return message }
            return nil
        }
    }
}

// MARK: - Decodable wire models

/// `{"streams": [...]}` — the key may be absent (no sources).
private struct StremioStreamsResponse: Decodable {
    var streams: [StremioStream]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streams = (try? container.decodeIfPresent([StremioStream].self, forKey: .streams)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case streams
    }
}

private struct StremioManifest: Decodable {
    var name: String?
}
