# GCDWebServer — provenance

Source: https://github.com/XITRIX/GCDWebServer (fork of swisspol/GCDWebServer),
branch `master`, commit `993173736fa84a4174d2e3bc13cc746576025841`
(2024-05-02). Vendored 2026-11-07 for Kino-iOS Phase 4 step 3.

Vendored files (28, 260,394 bytes): the full `GCDWebServer/Core`,
`GCDWebServer/Requests` and `GCDWebServer/Responses` folders — the file
serving code the local HTTP range server needs. No changes were made to
these files. The fork is restructured into `Core|Requests|Responses`
(unlike upstream's flat layout); the XITRIX fork is used because iTorrent
uses it and the plan verified its byte-range support
(`GCDWebServerFileResponse` + `addGETHandlerForPath:… allowRangeRequests:`).

Used only to serve the single active torrent file on 127.0.0.1 at path
`/stream` (see `KinoiOS/Services/TorrentHTTPServer.swift`). No directory
listing, no upload, no WebDAV.
