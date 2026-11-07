// KinoiOS-Bridging-Header.h — Phase 4 step 1.
//
// Exposes the vendored LibTorrent-Swift wrapper (Thirdparty/LibTorrent-Swift)
// to Swift. The wrapper's headers are found via the recursive header search
// path $(PROJECT_DIR)/Thirdparty/LibTorrent-Swift/** set on the app target.
// See Thirdparty/LibTorrent-Swift/PATCHES.md for the two import patches
// applied to the vendored copies.
#import "LibTorrent.h"

// Phase 4 step 3: vendored GCDWebServer (Thirdparty/GCDWebServer, found via
// the recursive header search path) — loopback range server for playback.
#import "GCDWebServer.h"
