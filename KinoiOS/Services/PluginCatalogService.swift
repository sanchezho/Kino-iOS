import Foundation

/// Loads the bundled plugin catalog seed (`plugin-catalog-seed.json`) and
/// exposes it to the UI. No network calls: the seed is the file recovered
/// from the Kino 0.9.83 APK, kept intact in the app bundle.
final class PluginCatalogService: ObservableObject {
    @Published private(set) var plugins: [Plugin] = []
    @Published private(set) var loadError: String?

    init() {
        load()
    }

    func load() {
        guard let url = Bundle.main.url(forResource: "plugin-catalog-seed", withExtension: "json") else {
            loadError = "plugin-catalog-seed.json no está en el bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(PluginCatalog.self, from: data)
            plugins = catalog.plugins
            loadError = nil
        } catch {
            loadError = "No se pudo decodificar el catálogo de plugins: \(error.localizedDescription)"
        }
    }

    var categories: [String] {
        Array(Set(plugins.flatMap { $0.categories ?? [] })).sorted()
    }

    func plugins(inCategory category: String) -> [Plugin] {
        plugins.filter { $0.categories?.contains(category) ?? false }
    }

    func searchPlugins(_ query: String) -> [Plugin] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return plugins }
        let needle = trimmed.lowercased()
        return plugins.filter { plugin in
            plugin.displayName.lowercased().contains(needle)
                || plugin.description.lowercased().contains(needle)
                || (plugin.tags?.joined(separator: " ").lowercased().contains(needle) ?? false)
                || (plugin.repo?.lowercased().contains(needle) ?? false)
        }
    }

    func plugin(withId id: String) -> Plugin? {
        plugins.first { $0.id == id }
    }
}
