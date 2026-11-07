import SwiftUI

/// Kino iOS — Phase 3.
///
/// Clean-room iOS rewrite of Kino TV (Android, Kotlin + Jetpack Compose).
/// An APK cannot be converted to an IPA; this is a new SwiftUI app that
/// reuses only the plugin protocol data (catalog seed + bundled plugin.js)
/// recovered from the Kino 0.9.83 APK. See README.md and
/// KinoiOS/Resources/README-PROVENANCE.md.
///
/// Phase 2 implements the original catalogs natively in Swift:
/// Internet Archive (the `archive-org` plugin's queries, resolve and
/// episodes) and Cinemeta (the Stremio catalog addon in the seed).
/// Phase 3 adds Stremio streaming add-ons (default: Torrentio) to the
/// Cinemeta detail: real stream sources are listed, direct-URL streams
/// play, torrent streams are listed but not playable on iOS.
@main
struct KinoiOSApp: App {
    @StateObject private var catalog = PluginCatalogService()
    @StateObject private var pluginRuntime = PluginRuntime()
    @StateObject private var playback = PlaybackService()
    @StateObject private var archive = ArchiveService()
    @StateObject private var cinemeta = CinemetaService()
    @StateObject private var streams = StremioStreamService()

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
            .environmentObject(archive)
            .environmentObject(cinemeta)
            .environmentObject(streams)
        }
    }
}
