import Foundation

/// Phase 4 step 3 — loopback-only HTTP server that serves ONE file with
/// range-request support, so AVPlayer can play a torrent file while it is
/// still downloading.
///
/// GCDWebServerFileResponse stats the file on every request, so a file that
/// keeps growing on disk is served with its current size each time; nothing
/// here caches the size.
final class TorrentHTTPServer {
    private var server: GCDWebServer?
    private(set) var streamURL: URL?

    var isRunning: Bool { server?.isRunning ?? false }

    /// Starts the server on 127.0.0.1 with an ephemeral port and returns
    /// `http://127.0.0.1:<port>/stream`, or nil if the file does not exist or
    /// the server fails to start. Any previous instance is stopped first.
    func start(fileURL: URL) -> URL? {
        stop()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let server = GCDWebServer()
        server.addGETHandler(
            forPath: "/stream",
            filePath: fileURL.path,
            isAttachment: false,
            cacheAge: 0,
            allowRangeRequests: true
        )

        let options: [String: Any] = [
            GCDWebServerOption_Port: 0,
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_AutomaticallySuspendInBackground: false,
        ]
        do {
            try server.start(options: options)
        } catch {
            return nil
        }

        let port = Int(server.port)
        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/stream") else {
            server.stop()
            return nil
        }
        self.server = server
        self.streamURL = url
        return url
    }

    func stop() {
        if let server, server.isRunning { server.stop() }
        server = nil
        streamURL = nil
    }

    deinit { stop() }
}
