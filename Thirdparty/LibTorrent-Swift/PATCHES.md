# Patches applied to vendored LibTorrent-Swift (direct-link, not framework)

Source: XITRIX/LibTorrent-Swift @ commit
`82735476b1f7666058447a6d9a39b100e98c1208` (main, 2026-11-06).
Vendored 2026-11-07 into `Thirdparty/LibTorrent-Swift/`: `make.sh` + all 45
files under `LibTorrent/` (122,224 bytes total, all UTF-8). NOT vendored:
`Thirdparty/libtorrent` (cloned in CI at pinned SHA
`6da363d2994f17c0b3c0450d124cf73a31a73847`, libtorrent 2.1.2.0) and
`LibTorrent.xcodeproj` (only needed for the framework route).

Upstream ships the wrapper as a **framework**, so its headers use
framework-style imports (`#import <LibTorrent/X.h>`) and `Session.mm`
imports the framework's Swift-generated header. Kino-iOS links the wrapper
**directly into the app target** (plan §4.1), so two mechanical patches
were applied to the vendored copies (upstream files untouched):

1. All 27 occurrences of `#import <LibTorrent/X.h>` in 8 headers
   (`LibTorrent.h`, `Session.h`, `FileEntry.h`, `Downloadable.h`,
   `TorrentFile.h`, `MagnetURI.h`, `TorrentHandle.h`,
   `TorrentHandleSnapshot.h`) changed to `#import "X.h"`. They resolve via
   the recursive header search path
   `$(PROJECT_DIR)/Thirdparty/LibTorrent-Swift/**` set on the app target.
2. `LibTorrent/Core/Session/Session.mm:9`:
   `#import "LibTorrent/LibTorrent-Swift.h"` →
   `#import "KinoiOS-Swift.h"`. Session.mm uses `resolveSequrityScopes`,
   a Swift extension on StorageModel defined in the wrapper's
   `Session.swift`; in the app target those Swift files compile into the
   `KinoiOS` module, so the generated header is `KinoiOS-Swift.h`.

3. 2026-11-07 (CI run #18 compile errors) `LibTorrent/Core/Session/Session.swift`:
   removed the entire `extension StorageModel: Codable { ... }` block
   (`init(uuid:name:pathBookmark:)` convenience init, `required convenience
   init(from:)`, `encode(to:)`, private `CodingKeys`). Reason: Swift forbids
   `required` initializers in an extension, and a non-final ObjC class
   (`StorageModel : NSObject`) cannot satisfy `Decodable.init(from:)` from an
   extension (2 compile errors). Repo-wide grep found no use of StorageModel
   Codable, JSONEncoder/Decoder with it, or the removed convenience init (the
   app passes `storages: [:]`). `@objc public extension StorageModel`
   (`resolveSequrityScopes`, used by Session.mm) and
   `extension StorageModel: Identifiable` are untouched.

No other changes. If the wrapper is ever re-vendored from a newer commit,
re-apply these three patches and update the commit SHA above.
