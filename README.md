# Kino iOS — Phase 2: catálogos reales

A clean-room iOS rewrite of **Kino TV** (Android), built in SwiftUI.
This is **not** a conversion of the Android APK: an APK cannot be
recompiled into an IPA. The Android app (Kotlin + Jetpack Compose,
FFmpeg, QuickJS plugins) was analysed with REA/Jadx — see the analysis
summary below — and this project re-implements the player for iOS from
scratch, reusing only the plugin protocol data (catalog seed +
bundled `plugin.js`).

- Source app: Kino TV 0.9.83, package `com.arkiv.player.light`,
  APK SHA-256 `ad9e85219f9cb0cc15327ea51bfc5aab81b660147ce687d20a6ecca6d78aefb7`
- Kino site: https://kinotvapp.github.io/en/ — open source, Apache-2.0,
  generic player; it does not host content itself.
- Bundle ID: `com.sanchezho.KinoiOS`
- Target: iOS 17.0, Swift 5.9+, Xcode 15+ (assumption — the Xcode version
  on the owner's Mac was not confirmed when this scaffold was written;
  the GitHub Actions workflow selects Xcode 16 on `macos-15` when
  available and otherwise uses the runner default).
- Version: 0.2.0 (Phase 2)

## What works in Phase 1

- SwiftUI app with four tabs: Home, Search, Library, Settings.
- Home: continue-watching, test titles, and the plugin list from the
  bundled catalog seed (43 plugins in the seed file).
- Search across the Phase 1 titles and the plugin catalog.
- Detail view with Play (only for titles with a stream) and Save.
- Player: AVPlayer (`VideoPlayer` from AVKit) with continue-watching
  position saved in UserDefaults.
- Library: continue-watching positions and saved titles.
- Settings: version, bundle ID, plugin runtime status, full plugin list.
- Plugin catalog: `plugin-catalog-seed.json` bundled and decoded locally,
  no network calls to load it.
- Plugin runtime: JavaScriptCore loads the bundled `plugin.js`, exposes
  a `kino` host object (`log` is real; `fetch` is a Phase 1 stub that
  logs and returns null), and calls the only exported function,
  `storeSync`, with an empty argument. Status and diagnostics are shown
  in Settings. The full plugin API (search, catalog fetching, playback
  resolution, storage, screens) is **not** implemented yet.

## What works in Phase 2

Phase 2 implements the original Kino catalogs **natively in Swift**
(no JavaScript runs): the Internet Archive plugin
(`kinotvapp/kino-plugin-archive`, id `archive-org`, v1.4.2) and the
Cinemeta Stremio catalog addon from the bundled seed. No API keys.

- Home: titles **with posters** (`AsyncImage`). The three Internet
  Archive rows from the plugin — Películas de dominio público
  (`collection:(feature_films)`), Televisión clásica
  (`collection:(classic_tv)`), Animación clásica
  (`collection:(animationandcartoons)`), 30 items each, most downloaded
  first — plus four Cinemeta sections (Películas/Series populares y
  nuevas). Each row loads independently; a failed row shows its own
  error and a retry button. "Ver más" opens a paginated poster grid
  (50 per page, the plugin's `browse`).
- Search: debounced search of both Archive collections (25 rows each,
  deduplicated by identifier), results as a poster grid.
- Detail (Internet Archive): poster, year, overview, Save, and a
  Reproducir button that first resolves the stream and only then opens
  the player. Series list their episodes (natural order, SxxExx
  numbering when all files match) with per-episode play buttons.
- Player: AVPlayer over the resolved archive.org MP4/WebM URL, with a
  visible error state when the player item fails (Phase 1 showed a
  black screen). Continue-watching and saved titles now cover Archive
  titles too (they are remembered in full in UserDefaults).
- The BipBop test stream URL was fixed: the HEVC example URL used in
  Phase 1 is dead (302 to developer.apple.com/videos/); Phase 2 uses
  the classic BipBop URL, verified 200 with `application/x-mpegURL`.

### What mirrors the original plugin exactly

- Home row queries, 30 items, `downloads desc` order; browse 50/page
  with the page number as cursor.
- Item mapping: id = identifier, title/year = first value, poster =
  `https://archive.org/services/img/<identifier>`, overview =
  description with HTML stripped, max 400 chars.
- Search query cleaning (letters/digits/apostrophes/spaces only,
  dropping `and`/`or`/`not`) and searching both collections.
- Resolve: metadata → video originals (an original with a playable
  derivative) → best playable file by format rank
  (`h.264`, `h.264 hd`, `mpeg4`, `512kb mpeg4`) → direct download URL
  with each path segment URL-encoded; subtitles (.vtt/.srt next to the
  original, `es` when the name says so) and duration from the file.
- Episodes: natural sort (digit runs as numbers), SxxExx numbering.
- Cinemeta: manifest first, then `catalog/{type}/{id}.json`
  (URLSession follows the 307 redirect to
  `cinemeta-catalogs.strem.io`); posters/backgrounds used as-is.

### What was simplified vs the original plugin

- No user-configured source addresses (`url1…url6` / `cat1…cat6`):
  Home shows the plugin's three built-in rows only.
- No `kino.rank` similarity ranking on search: results stay in
  archive.org's downloads order.
- No multi-video item cards on Home/search (an item with several
  videos is one card; series use the episodes list).
- No TMDB (needs an API key) and no subtitles shown in the player
  yet (they are resolved and listed in the code path, not rendered).
- No Cinemeta search (Cinemeta has no reliable search endpoint);
  Archive search covers search.
- Cinemeta titles have no play button: Cinemeta is a catalog, it
  carries no video streams.

## What does NOT work yet

- Full plugin API: plugin search, fetching catalogs from GitHub,
  resolving a title to a playable stream, subtitles.
- Downloads, offline playback.
- Chromecast / AirPlay sender, DLNA, EPG / live TV guide.
- Accounts, sync, social features, recommendations, Kinobot.
- TMDB (needs an API key) and the other seed plugins are still
  catalog-only: Phase 2 playback is Internet Archive only.

## Open in Xcode on a Mac

1. Clone this repo.
2. Open `KinoiOS.xcodeproj` in Xcode 15 or newer.
3. Select an iPhone simulator and press Run. No signing team is needed
   to run on the simulator.
4. To run on a physical iPhone, select your Apple Developer team in
   the target's Signing & Capabilities (the project ships with no team).

## Build the unsigned IPA with GitHub Actions (primary route)

The owner explicitly chose GitHub Actions as the build route; the local
Mac compile is only a fallback.

Every push to `main` and every manual run (`workflow_dispatch`) triggers
`.github/workflows/ios.yml` on a `macos-15` runner:

1. Checks out the repo and selects Xcode 16 when
   `/Applications/Xcode_16.app` exists, otherwise the runner default.
2. Builds unsigned:
   `xcodebuild build -project KinoiOS.xcodeproj -scheme KinoiOS -configuration Release -sdk iphoneos -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
   (`archive` was tried in runs #1–#3 and failed the same way; `build`
   is what produces the app.)
3. Packages the `.app` from
   `build/DerivedData/Build/Products/Release-iphoneos/KinoiOS.app`
   into an unsigned IPA by zipping it as `Payload/KinoiOS.app` →
   `KinoiOS-unsigned.ipa`.
4. Uploads `KinoiOS-unsigned.ipa` as the Actions artifact
   `KinoiOS-unsigned-ipa`.

Download the artifact from the Actions run, then sign it in Signulous
and install it on the iPhone. Signulous re-signs the IPA; it does not
convert an APK, and this repo contains no APK.

## Project layout

```
KinoiOS.xcodeproj/            Xcode project (hand-written, no signing team)
KinoiOS/
  KinoiOSApp.swift            App entry, TabView
  Models/Plugin.swift         Plugin + PluginCatalog decoding
  Models/TitleItem.swift      Title model + BipBop sample stream
  Models/ArchiveItem.swift    Internet Archive item / row / episode models
  Services/PluginCatalogService.swift   Loads bundled catalog seed
  Services/PluginRuntime.swift        JavaScriptCore plugin runtime
  Services/PlaybackService.swift      AVPlayer + positions + saved
  Services/ArchiveService.swift       Internet Archive plugin, native
  Services/CinemetaService.swift      Cinemeta catalog (Stremio addon)
  Views/                      Home, Search, Detail, Player, Library, Settings
  Views/BrowseView.swift      Paginated poster grid ("Ver más")
  Views/ArchiveDetailView.swift  Detail for Archive + Cinemeta titles
  Resources/
    plugin-catalog-seed.json  From the Kino 0.9.83 APK, intact
    plugin.js                 Bundled Kino plugin (storeSync), intact
    kino-plugin.json          Bundled plugin manifest (v1.0.5, apiVersion 15)
    README-PROVENANCE.md      Where the bundled files came from
  Assets.xcassets/            App icon set (empty in Phase 1)
.github/workflows/ios.yml     macOS Actions build → unsigned IPA artifact
```

## Provenance

The bundled `plugin-catalog-seed.json`, `plugin.js` and
`kino-plugin.json` were extracted from the Kino TV 0.9.83 APK
(`archive.org/download/kino-app/kino.apk`) and are reproduced intact;
see `KinoiOS/Resources/README-PROVENANCE.md`. Kino is Apache-2.0.
No Android code, DEX, or binary from the APK is in this repo.
