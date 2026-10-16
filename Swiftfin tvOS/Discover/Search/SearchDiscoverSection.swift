//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// TMDB rows below the library results on the Search tab: "Available to Request" (or "More to Watch"
/// without Seerr) and "More with <person>". Cards open the Discover title page, which has Request.
/// Shows nothing until there are results, so a missing or failing TMDB leaves Search unchanged.
struct SearchDiscoverSection: View {

    @ObservedObject
    var viewModel: SearchDiscoverViewModel
    @ObservedObject
    var feed: DiscoverViewModel

    @Router
    private var router

    var body: some View {
        let items = viewModel.items(libraryItemIDs: feed.libraryItemIDs)

        if items.titles.isNotEmpty || items.personTitles.isNotEmpty {
            VStack(alignment: .leading, spacing: 60) {
                if items.titles.isNotEmpty {
                    row(
                        id: "titles",
                        title: SeerrClient.isConfigured ? L10n.searchAvailableToRequest : L10n.searchMoreToWatch,
                        items: items.titles
                    )
                }

                if let person = viewModel.results?.person, items.personTitles.isNotEmpty {
                    row(id: "person-\(person.id)", title: L10n.searchMoreWith(person.name), items: items.personTitles)
                }

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: 1100, alignment: .leading)
                    .edgePadding(.horizontal)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    private func row(id: String, title: String, items: [DiscoverItem]) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .edgePadding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                    ForEach(items) { item in
                        DiscoverCard(item: item, viewModel: feed, width: 320) {
                            router.route(to: .discoverTitle(item: item, feed: feed))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("search.tmdb.\(item.id)")
                    }
                }
                .edgePadding(.horizontal)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.vertical, -20)
        }
        .id(id)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
