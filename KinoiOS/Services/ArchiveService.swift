import Foundation

/// Native Swift implementation of the original Kino Internet Archive
/// plugin (`kinotvapp/kino-plugin-archive`, id `archive-org`, v1.4.2).
/// Same queries, same poster pattern, same stream-resolution rules
/// (format rank, video originals, subtitles, episode numbering).
/// Simplified vs the plugin, documented in the repo README:
/// no user-configured source addresses, no `kino.rank` similarity
/// ranking (results stay in archive.org's downloads order), no
/// multi-video item cards on Home/search (series use `episodes`).
///
/// All network goes through URLSession; archive.org needs no API key.
final class ArchiveService: ObservableObject {
    static let base = "https://archive.org"
    private static let fields = ["identifier", "title", "year", "description"]
    private static let validID = "^[A-Za-z0-9._-]{1,100}$"
    private static let playableExtensions = ["mp4", "m4v", "webm"]
    /// Preferred playable files, best first (archive.org `format`, lowercased).
    private static let formatRank = ["h.264", "h.264 hd", "mpeg4", "512kb mpeg4"]
    private static let homeRowSize = 30
    private static let pageSize = 50

    enum ArchiveError: LocalizedError {
        case badResponse(String)
        case noPlayableVideo

        var errorDescription: String? {
            switch self {
            case .badResponse(let message): return message
            case .noPlayableVideo: return "Este título no tiene video reproducible en archive.org."
            }
        }
    }

    // MARK: - Home

    /// The three Home rows, fetched in parallel. A row that fails comes
    /// back with its `error` set instead of blanking the whole Home.
    func homeRows() async -> [ArchiveRow] {
        let defs = ArchiveRowDef.all
        let rows = await withTaskGroup(of: ArchiveRow.self) { group in
            for def in defs {
                group.addTask { await self.fetchRow(def) }
            }
            var collected: [ArchiveRow] = []
            for await row in group { collected.append(row) }
            return collected
        }
        return defs.compactMap { def in rows.first { $0.id == def.id } }
    }

    func fetchRow(_ def: ArchiveRowDef) async -> ArchiveRow {
        do {
            let items = try await docs(query: def.query, rows: Self.homeRowSize, page: 1)
                .map { Self.toItem($0, kind: def.kind) }
            return ArchiveRow(id: def.id, title: def.title, items: items, error: nil)
        } catch {
            return ArchiveRow(id: def.id, title: def.title, items: [], error: error.localizedDescription)
        }
    }

    /// "Ver más" on a Home row: the same query, 50 rows per page.
    /// Returns the page and the next page number, or nil when done.
    func browse(rowId: String, page: Int) async throws -> ([ArchiveItem], nextPage: Int?) {
        guard let def = ArchiveRowDef.all.first(where: { $0.id == rowId }) else {
            throw ArchiveError.badResponse("Esa fila ya no existe.")
        }
        guard page >= 1, page <= 100 else {
            throw ArchiveError.badResponse("Página inválida.")
        }
        let found = try await docs(query: def.query, rows: Self.pageSize, page: page)
        return (found.map { Self.toItem($0, kind: def.kind) },
                found.count == Self.pageSize ? page + 1 : nil)
    }

    // MARK: - Search

    /// Search both collections (films, then TV) with the cleaned title.
    /// An item in both collections is listed once, as a movie.
    /// Throws only when every request fails.
    func search(query: String) async throws -> [ArchiveItem] {
        let cleaned = Self.cleanTitle(query)
        guard !cleaned.isEmpty else { return [] }
        let titleQuery = "title:(\(cleaned))"
        let groups: [(query: String, kind: TitleKind)] = [
            (ArchiveRowDef.films.query, .movie),
            (ArchiveRowDef.tv.query, .series),
        ]
        var found: [ArchiveItem] = []
        var seen = Set<String>()
        var failures = 0
        await withTaskGroup(of: (TitleKind, Result<[ArchiveDoc], Error>).self) { group in
            for (whereQuery, kind) in groups {
                group.addTask {
                    do {
                        let docs = try await self.docs(query: "\(titleQuery) AND \(whereQuery)", rows: 25, page: 1)
                        return (kind, .success(docs))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }
            for await (kind, result) in group {
                switch result {
                case .failure:
                    failures += 1
                case .success(let docs):
                    for doc in docs where !seen.contains(doc.identifier) {
                        seen.insert(doc.identifier)
                        found.append(Self.toItem(doc, kind: kind))
                    }
                }
            }
        }
        if failures == groups.count {
            throw ArchiveError.badResponse("archive.org no respondió a la búsqueda.")
        }
        return found
    }

    // MARK: - Resolve / episodes

    /// The plugin's `resolve`: metadata → video originals → best playable
    /// file by format rank → direct download URL (+ subtitles, duration).
    func resolve(ref: String) async throws -> ArchiveResolved {
        let (identifier, wanted) = Self.splitRef(ref)
        let meta = try await metadata(identifier)
        let originals = Self.videoOriginals(meta.files)
        let original: ArchiveFile?
        if let wanted {
            original = originals.first { $0.name == wanted }
        } else {
            original = originals.first
        }
        guard let original else { throw ArchiveError.noPlayableVideo }
        guard let file = Self.bestPlayable(meta.files, original: original) else {
            throw ArchiveError.noPlayableVideo
        }
        let seconds = file.length ?? original.length
        return ArchiveResolved(
            url: Self.downloadURL(identifier: identifier, name: file.name),
            mime: file.name.lowercased().hasSuffix(".webm") ? "video/webm" : "video/mp4",
            subtitles: Self.subtitlesFor(identifier: identifier, files: meta.files, original: original),
            durationSeconds: seconds.map { $0 > 0 ? $0 : nil } ?? nil
        )
    }

    /// The plugin's `episodes`: every video original of a series item,
    /// naturally ordered, numbered from SxxExx when all files match.
    func episodes(identifier: String) async throws -> (title: String, poster: URL?, episodes: [ArchiveEpisode]) {
        let meta = try await metadata(identifier)
        let originals = Self.videoOriginals(meta.files)
        let numbers = Self.numbering(originals)
        let title = Self.firstString(meta.metadata["title"]) ?? identifier
        let episodes = originals.enumerated().map { index, file in
            ArchiveEpisode(
                id: "\(identifier)|\(file.name)",
                identifier: identifier,
                filename: file.name,
                season: numbers[index].season,
                number: numbers[index].number,
                title: Self.episodeTitle(file)
            )
        }
        return (title, Self.posterURL(identifier), episodes)
    }

    // MARK: - Raw API

    private func getData(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArchiveError.badResponse("archive.org respondió \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return data
    }

    private func advancedURL(query: String, rows: Int, page: Int, sort: String = "downloads desc") -> URL? {
        var components = URLComponents(string: Self.base + "/advancedsearch.php")
        var items: [URLQueryItem] = [URLQueryItem(name: "q", value: query)]
        for field in Self.fields {
            items.append(URLQueryItem(name: "fl[]", value: field))
        }
        items.append(URLQueryItem(name: "sort[]", value: sort))
        items.append(URLQueryItem(name: "rows", value: String(rows)))
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "output", value: "json"))
        components?.queryItems = items
        return components?.url
    }

    private func docs(query: String, rows: Int, page: Int, sort: String = "downloads desc") async throws -> [ArchiveDoc] {
        guard let url = advancedURL(query: query, rows: rows, page: page, sort: sort) else {
            throw ArchiveError.badResponse("No se pudo armar la búsqueda.")
        }
        let data = try await getData(url)
        let decoded = try JSONDecoder().decode(AdvancedSearchResponse.self, from: data)
        // A query archive.org can't parse still answers 200, with
        // {"error": ...} instead of "response".
        guard let response = decoded.response else {
            throw ArchiveError.badResponse("archive.org no entendió la búsqueda.")
        }
        return response.docs.filter { $0.isValid }
    }

    private func metadata(_ identifier: String) async throws -> ArchiveMetadata {
        guard let encoded = Self.encodeURIComponent(identifier),
              let url = URL(string: Self.base + "/metadata/" + encoded) else {
            throw ArchiveError.badResponse("Identificador inválido.")
        }
        let data = try await getData(url)
        let decoded = try JSONDecoder().decode(ArchiveMetadata.self, from: data)
        guard !decoded.files.isEmpty else {
            throw ArchiveError.badResponse("archive.org no tiene ese título.")
        }
        return decoded
    }

    // MARK: - Mapping (mirrors the plugin's toItem / videoOriginals / rank)

    private static func toItem(_ doc: ArchiveDoc, kind: TitleKind) -> ArchiveItem {
        let description = doc.description?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ArchiveItem(
            id: doc.identifier,
            title: doc.title ?? doc.identifier,
            kind: kind,
            year: doc.year.flatMap { Int($0) },
            posterURL: posterURL(doc.identifier),
            overview: description.map { String($0.prefix(400)) }
        )
    }

    private static func posterURL(_ identifier: String) -> URL? {
        guard let encoded = encodeURIComponent(identifier) else { return nil }
        return URL(string: base + "/services/img/" + encoded)
    }

    private static func splitRef(_ ref: String) -> (identifier: String, wanted: String?) {
        if let cut = ref.firstIndex(of: "|") {
            return (String(ref[..<cut]), String(ref[ref.index(after: cut)...]))
        }
        return (ref, nil)
    }

    /// A video is an original file something playable exists for: itself
    /// (mp4/m4v/webm) or a derivative made from it (its `original` field).
    /// The extension of the original tells nothing: real items hold .avi,
    /// .mpg, .mkv and .divx originals next to their derived mp4.
    private static func videoOriginals(_ files: [ArchiveFile]) -> [ArchiveFile] {
        var playable = Set<String>()
        for file in files where isPlayable(file.name) {
            let from = file.source == "original" ? file.name : file.original
            if let from { playable.insert(from) }
        }
        return files
            .filter { $0.source == "original" && playable.contains($0.name) }
            .sorted { naturalCompare($0.name, $1.name) == .orderedAscending }
    }

    private static func isPlayable(_ name: String) -> Bool {
        let lower = name.lowercased()
        return playableExtensions.contains { lower.hasSuffix("." + $0) }
    }

    private static func rank(_ file: ArchiveFile) -> Int {
        let index = formatRank.firstIndex(of: (file.format ?? "").lowercased())
        return index ?? formatRank.count
    }

    private static func bestPlayable(_ files: [ArchiveFile], original: ArchiveFile) -> ArchiveFile? {
        files
            .filter { ($0.name == original.name || $0.original == original.name) && isPlayable($0.name) }
            .sorted { rank($0) < rank($1) }
            .first
    }

    private static func downloadURL(identifier: String, name: String) -> URL {
        let encodedName = name.split(separator: "/").map { encodeURIComponent(String($0)) ?? String($0) }.joined(separator: "/")
        return URL(string: base + "/download/" + (encodeURIComponent(identifier) ?? identifier) + "/" + encodedName)!
    }

    private static func subtitlesFor(identifier: String, files: [ArchiveFile], original: ArchiveFile) -> [ArchiveSubtitle] {
        let stem = original.name.replacingOccurrences(of: "\\.[^./]+$", with: "", options: .regularExpression)
        let prefix = stem + "."
        return files
            .filter {
                let lower = $0.name.lowercased()
                return (lower.hasSuffix(".vtt") || lower.hasSuffix(".srt")) && $0.name.hasPrefix(prefix)
            }
            .map { file in
                let lang = file.name.range(of: "[._](es|spa|spanish)[._]", options: .regularExpression) != nil ? "es" : "en"
                return ArchiveSubtitle(
                    lang: lang,
                    url: downloadURL(identifier: identifier, name: file.name),
                    format: file.name.lowercased().hasSuffix(".srt") ? "srt" : "vtt"
                )
            }
    }

    private static func numbering(_ originals: [ArchiveFile]) -> [(season: Int, number: Int)] {
        let found = originals.map { file in
            file.name.range(of: #"S(\d{1,3})E(\d{1,4})"#, options: [.regularExpression, .caseInsensitive])
                .flatMap { range -> (Int, Int)? in
                    let text = String(file.name[range])
                    let digits = text.dropFirst().split(separator: "E", maxSplits: 1)
                    guard digits.count == 2,
                          let season = Int(digits[0]),
                          let number = Int(digits[1].trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) else { return nil }
                    return (season, number)
                }
        }
        if found.allSatisfy({ $0 != nil }) {
            return found.map { $0! }
        }
        return originals.enumerated().map { (season: 1, number: $0.offset + 1) }
    }

    private static func episodeTitle(_ file: ArchiveFile) -> String {
        if let title = file.title, !title.isEmpty { return title }
        let name = file.name.split(separator: "/").last.map(String.init) ?? file.name
        let stem = name.replacingOccurrences(of: "\\.[^./]+$", with: "", options: .regularExpression)
        if let range = stem.range(of: #"S\d{1,3}E\d{1,4}\s*-\s*(.+)$"#, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(stem[range])
            if let dash = matched.range(of: "-") {
                return String(matched[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return stem
    }

    /// Letters, digits and apostrophes inside words only: any other
    /// character can be query syntax to advancedsearch. The words
    /// and/or/not are dropped (a dangling one is an error too).
    private static func cleanTitle(_ raw: String) -> String {
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "' "))
        let kept = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let words = String(kept).split(separator: " ").map(String.init)
        let banned = ["and", "or", "not"]
        return words.filter { !banned.contains($0.lowercased()) }.joined(separator: " ")
    }

    /// "Season 2" after "Season 10" is wrong; compare digit runs as numbers.
    static func naturalCompare(_ a: String, _ b: String) -> ComparisonResult {
        let tokensA = naturalTokens(a)
        let tokensB = naturalTokens(b)
        for (x, y) in zip(tokensA, tokensB) {
            if x == y { continue }
            if let nx = Int(x), let ny = Int(y) {
                return nx < ny ? .orderedAscending : .orderedDescending
            }
            return x < y ? .orderedAscending : .orderedDescending
        }
        if tokensA.count == tokensB.count { return .orderedSame }
        return tokensA.count < tokensB.count ? .orderedAscending : .orderedDescending
    }

    private static func naturalTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsDigit: Bool?
        for ch in text {
            let isDigit = ch.isNumber
            if currentIsDigit == nil || currentIsDigit == isDigit {
                current.append(ch)
            } else {
                tokens.append(current)
                current = String(ch)
            }
            currentIsDigit = isDigit
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// `encodeURIComponent` equivalent: alphanumerics plus `-_.!~*'()`.
    private static func encodeURIComponent(_ value: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

// MARK: - Decodable wire models (lenient: one bad doc never fails the list)

private struct AdvancedSearchResponse: Decodable {
    var response: AdvancedSearchResult?
}

private struct AdvancedSearchResult: Decodable {
    var docs: [ArchiveDoc]
}

/// A doc whose fields may be a single value or an array, a string or a
/// number — archive.org is loose about all of them.
struct ArchiveDoc: Decodable {
    var identifier: String
    var title: String?
    var year: String?
    var description: String?

    var isValid: Bool {
        !identifier.isEmpty
            && identifier.range(of: ArchiveService.validIDPattern, options: .regularExpression) != nil
    }

    enum CodingKeys: String, CodingKey {
        case identifier, title, year, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = (try? container.decode(String.self, forKey: .identifier)) ?? ""
        title = ArchiveService.firstString(try? container.decode(ArchiveDocValue.self, forKey: .title))
        year = ArchiveService.firstString(try? container.decode(ArchiveDocValue.self, forKey: .year))
        description = ArchiveService.firstString(try? container.decode(ArchiveDocValue.self, forKey: .description))
    }
}

/// A JSON value that may be a string, a number, or an array of either.
struct ArchiveDocValue: Decodable {
    var strings: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            strings = [single]
        } else if let number = try? container.decode(Double.self) {
            strings = [number.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(number)) : String(number)]
        } else if let array = try? container.decode([String].self) {
            strings = array
        } else if let numbers = try? container.decode([Double].self) {
            strings = numbers.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) }
        } else {
            strings = []
        }
    }
}

struct ArchiveMetadata: Decodable {
    var metadata: [String: ArchiveDocValue]
    var files: [ArchiveFile]

    enum CodingKeys: String, CodingKey {
        case metadata, files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = (try? container.decode([String: ArchiveDocValue].self, forKey: .metadata)) ?? [:]
        files = (try? container.decode([ArchiveFile].self, forKey: .files)) ?? []
    }
}

struct ArchiveFile: Decodable {
    var name: String
    var format: String?
    var source: String?
    var original: String?
    var title: String?
    var length: Double?

    enum CodingKeys: String, CodingKey {
        case name, format, source, original, title, length
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        format = try? container.decode(String.self, forKey: .format)
        source = try? container.decode(String.self, forKey: .source)
        original = try? container.decode(String.self, forKey: .original)
        title = try? container.decode(String.self, forKey: .title)
        if let asString = try? container.decode(String.self, forKey: .length) {
            length = Double(asString)
        } else {
            length = try? container.decode(Double.self, forKey: .length)
        }
    }
}

extension ArchiveService {
    static var validIDPattern: String { validID }

    static func firstString(_ value: ArchiveDocValue?) -> String? {
        value?.strings.first
    }

    static func firstString(_ dict: [String: ArchiveDocValue], _ key: String) -> String? {
        dict[key]?.strings.first
    }
}
