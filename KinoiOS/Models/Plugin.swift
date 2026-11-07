import Foundation

/// One entry of the bundled plugin catalog seed
/// (`plugin-catalog-seed.json`, schema 1, taken from the Kino 0.9.83 APK).
///
/// Fields are all optional except `id` and `description`, because the seed
/// mixes two shapes: Kino plugins (with `repo`/`name`) and Stremio addons
/// (with only a `stremio` manifest URL and no `name`/`repo`).
struct Plugin: Identifiable, Decodable, Hashable {
    var id: String
    var repo: String?
    var name: String?
    var description: String
    var tags: [String]?
    var categories: [String]?
    var needsSetup: Bool?
    var stremio: String?
    var requires: [String]?
    var authorKey: String?

    var displayName: String { name ?? id }
}

/// Top level of `plugin-catalog-seed.json`.
struct PluginCatalog: Decodable {
    var schema: Int
    var plugins: [Plugin]
}
