//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

extension VideoPlayer {

    /// Where the player goes when the sleep timer stops playback: the show (or movie) page,
    /// like exiting playback in the Apple TV app.
    @MainActor
    enum ExitNavigation {

        /// The page to open after the player dismisses, or nil when the player was presented over it already.
        static func showPageRoute(for item: BaseItemDto) -> NavigationRoute? {
            let pageID: String? = item.type == .episode ? item.seriesID : item.id
            guard let pageID else { return nil }

            let pageRouteIDs = Set([pageID, item.seasonID, item.id].compactMap(\.self).map { "item-\($0)" })

            if let behind = routeIDBehindPlayer(), pageRouteIDs.contains(behind) {
                return nil
            }

            return .item(id: pageID)
        }

        /// Opens the show page once the player has dismissed.
        static func openShowPage(_ route: NavigationRoute) {
            Task { @MainActor in
                // Wait for the full screen cover's dismissal so the page lands on the screen behind it
                try? await Task.sleep(for: .milliseconds(900))
                FactoryKit.Container.shared.userSessionManager().routePublisher.send(route)
            }
        }

        /// The route ID of the screen the player is presented over (nil for a tab's root or when unknown).
        private static func routeIDBehindPlayer() -> String? {
            guard let tabCoordinator = TabCoordinator.current,
                  let tab = tabCoordinator.tabs.first(where: { $0.item.id == tabCoordinator.selectedTabID })
            else { return nil }

            var coordinator = tab.coordinator
            var behind: String? = coordinator.path.last?.id

            while let presented = coordinator.presentedFullScreen ?? coordinator.presentedSheet {
                if presented.route.id == "videoPlayer" {
                    return behind
                }

                coordinator = presented.coordinator
                behind = coordinator.path.last?.id ?? presented.route.id
            }

            return nil
        }
    }
}
