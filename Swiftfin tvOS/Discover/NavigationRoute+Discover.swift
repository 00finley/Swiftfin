//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationRoute {

    @MainActor
    static func discoverTitle(item: DiscoverItem, feed: DiscoverViewModel) -> NavigationRoute {
        NavigationRoute(id: "discover-\(item.id)") {
            DiscoverTitleView(item: item, feed: feed)
        }
    }

    static var discoverSettings: NavigationRoute {
        NavigationRoute(id: "discoverSettings") {
            DiscoverSettingsView()
        }
    }
}

extension TabItem {

    static var discover: TabItem {
        TabItem(
            id: "discover",
            title: L10n.discover,
            systemImage: "sparkles.tv"
        ) {
            DiscoverView()
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}
