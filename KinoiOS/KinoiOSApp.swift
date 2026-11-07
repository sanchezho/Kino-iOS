import SwiftUI

/// Kino iOS — Phase 1 scaffold.
///
/// Clean-room iOS rewrite of Kino TV (Android, Kotlin + Jetpack Compose).
/// An APK cannot be converted to an IPA; this is a new SwiftUI app that
/// reuses only the plugin protocol data (catalog seed + bundled plugin.js)
/// recovered from the Kino 0.9.83 APK. See README.md and
/// KinoiOS/Resources/README-PROVENANCE.md.
@main
struct KinoiOSApp: App {
    @StateObject private var catalog = PluginCatalogService()
    @StateObject private var pluginRuntime = PluginRuntime()
    @StateObject private var playback = PlaybackService()

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem { Label("Inicio", systemImage: "house") }
                SearchView()
                    .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
                LibraryView()
                    .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
                SettingsView()
                    .tabItem { Label("Ajustes", systemImage: "gear") }
            }
            .environmentObject(catalog)
            .environmentObject(pluginRuntime)
            .environmentObject(playback)
        }
    }
}
