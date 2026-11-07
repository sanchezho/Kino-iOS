//
//  Session.swift
//  LibTorrent
//
//  Created by Daniil Vinogradov on 03/07/2024.
//

import Foundation

@objc public extension StorageModel {
    @discardableResult
    func resolveSequrityScopes() -> Bool {
        do {
            var isStale = false

            url = try URL(resolvingBookmarkData: pathBookmark, bookmarkDataIsStale: &isStale)
            resolved = true

            allowed = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            print("Path - \(url) | write permissions - \(allowed)")

            // No idea what stale really is and what to do with it
            if isStale {
                let newBookmark = try url.bookmarkData(options: [.minimalBookmark])
                pathBookmark = newBookmark
            }

            return allowed
        } catch {
            allowed = false
            resolved = false
            print(error)
            return false
        }
    }
}

extension StorageModel: Identifiable {
    public var id: UUID { uuid }
}
