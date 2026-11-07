# Kino iOS — Phase 1 scaffold

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
- Version: 0.1.0 (Phase 1)

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

## What does NOT work yet

- Full plugin API: plugin search, fetching catalogs from GitHub,
  resolving a title to a playable stream, subtitles.
- Downloads, offline playback.
- Chromecast / AirPlay sender, DLNA, EPG / live TV guide.
- Accounts, sync, social features, recommendations, Kinobot.
- Real Internet Archive playback: the only playable stream in Phase 1
  is a clearly labelled Apple sample HLS stream used to test AVPlayer.
  The Internet Archive and TMDB entries are catalog-only for now.

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
2. Archives unsigned:
   `xcodebuild archive -project KinoiOS.xcodeproj -scheme KinoiOS -configuration Release -destination 'generic/platform=iOS' -archivePath build/KinoiOS.xcarchive CODE_SIGNING_ALLOWED=NO`
3. Packages the `.app` into an unsigned IPA by zipping it as
   `Payload/KinoiOS.app` → `KinoiOS-unsigned.ipa`.
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
  Models/TitleItem.swift      Title model + Phase 1 sample titles
  Services/PluginCatalogService.swift   Loads bundled catalog seed
  Services/PluginRuntime.swift        JavaScriptCore plugin runtime
  Services/PlaybackService.swift      AVPlayer + positions + saved
  Views/                      Home, Search, Detail, Player, Library, Settings
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
