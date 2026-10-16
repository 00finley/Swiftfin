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

    static func categoryResults(_ category: BrowseCategory) -> NavigationRoute {
        NavigationRoute(id: "categoryResults-\(category.id)") {
            CategoryResultsView(category: category)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @MainActor
    static func categoryPicker(_ viewModel: CategoryResultsViewModel) -> NavigationRoute {
        NavigationRoute(id: "categoryPicker-\(ObjectIdentifier(viewModel).hashValue)") {
            CategoryPickerView(viewModel: viewModel)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    static var discoverSettings: NavigationRoute {
        NavigationRoute(id: "discoverSettings") {
            DiscoverSettingsView()
        }
    }
}

extension TabItem {

    /// Browse and search TMDB by category; the Discover feed itself lives on Home.
    static var categories: TabItem {
        TabItem(
            id: "categories",
            title: L10n.categories,
            systemImage: "square.grid.2x2"
        ) {
            CategoriesView()
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}
