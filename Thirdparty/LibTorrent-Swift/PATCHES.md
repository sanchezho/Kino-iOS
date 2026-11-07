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

4. 2026-11-07 (CI run #23 link errors: 121 undefined symbols) `make.sh`:
   added `-Dencryption=OFF -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE
   -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=TRUE` to the cmake configure call.
   Reason: the CI runner's CMake auto-detected OpenSSL, so the built
   `libtorrent-rasterbar.a` referenced ~90 OpenSSL C symbols (`_SSL_*`,
   `_BIO_*`, `_BN_*`, `_ASN1_*`, ...) that the iOS app cannot link — iOS
   ships no OpenSSL library to link against. With these flags libtorrent
   builds with its built-in RC4/SHA1, no SSL support and no MSE/DH peer
   encryption (`TORRENT_DISABLE_ENCRYPTION`, `pe_crypto.cpp` excluded).
   Functional consequence: HTTPS trackers and MSE-only peers won't work;
   plain HTTP/UDP trackers, DHT and normal peers are unaffected (the app
   already sets `validateHttpsTrackers = false`). If HTTPS trackers or MSE
   are ever needed, the alternative is vendoring an OpenSSL build for iOS
   and linking it — a separate project, not a flag.
   (Companion app-side fix, same run: `TORRENT_ABI_VERSION=4` +
   `TORRENT_HAVE_MMAP=0` added to the app target's
   `GCC_PREPROCESSOR_DEFINITIONS` — see the pbxproj. Upstream's own
   `LibTorrent.xcodeproj` defines exactly those. Without the ABI define the
   app compiled the headers at the default ABI 2 while the library was
   built at ABI 100 by `make.sh`'s `-Ddeprecated-functions=OFF`, so the
   2.0/2.1 APIs — `add_torrent_params`, `session_params`,
   `torrent_status`, `torrent_info::layout()`, `file_storage`,
   `parse_magnet_uri`, `write_resume_data`, ... — were mangled under
   different inline namespaces (`v2`/`v2_1`) on each side and failed to
   link. Verified against the headers at the pinned libtorrent SHA.)

No other changes. If the wrapper is ever re-vendored from a newer commit,
re-apply these three patches and update the commit SHA above.
