//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

/// Keeps the Top Shelf extension's copy of the signed-in session current and asks tvOS to refresh it.
enum TopShelfSessionPublisher {

    static func publish(_ session: UserSession?) {
        print("[TopShelf] last extension run: \(TopShelfCredentials.loadDiagnostics() ?? "none recorded")")

        if let session {
            let saved = TopShelfCredentials.save(
                .init(
                    serverID: session.server.id,
                    serverURL: session.server.effectiveServerURL,
                    userID: session.user.id,
                    accessToken: session.user.accessToken
                )
            )
            print("[TopShelf] published session for \(session.server.effectiveServerURL.absoluteString): \(saved ? "ok" : "FAILED")")
        } else {
            TopShelfCredentials.clear()
        }

        refresh()
    }

    /// Up Next changes as things are watched, so refresh whenever the app leaves the foreground.
    static func refresh() {
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
