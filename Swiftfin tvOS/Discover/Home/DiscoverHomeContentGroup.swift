//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import SwiftUI

/// The Discover feed as Home rows, below the library rows, like the Apple TV app mixes
/// your own Up Next with editorial rows.
///
/// Loading never holds up Home: `refresh()` returns at once and the feed builds in the
/// background. The group only resolves (appears) once there are rows, so when TMDB is
/// unreachable or not configured nothing shows.
struct DiscoverHomeContentGroup: ContentGroup {

    let id = "discover-home"
    let viewModel = DiscoverHomeViewModel()

    var _shouldBeResolved: Bool {
        viewModel.isVisible
    }

    func body(with viewModel: DiscoverHomeViewModel) -> some View {
        DiscoverHomeSection(viewModel: viewModel, feed: viewModel.feed)
    }
}

final class DiscoverHomeViewModel: ViewModel, WithRefresh {

    let feed = DiscoverViewModel.shared

    @Published
    private(set) var isEnabled = Defaults[.Discover.showOnHome]
    @Published
    private(set) var genreNames: [Int: String] = [:]

    var isVisible: Bool {
        isEnabled && (feed.hero != nil || feed.rows.isNotEmpty)
    }

    private var startTask: Task<Void, Never>?

    override init() {
        super.init()

        feed.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Defaults.publisher(.Discover.showOnHome, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.isEnabled = change.newValue
                if change.newValue {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        start()
    }

    /// Never waits on TMDB, so Home's own loading isn't delayed.
    func refresh() async {
        start()
    }

    private func start() {
        guard isEnabled, TMDBClient.isAvailable, startTask == nil else { return }

        startTask = Task { [weak self] in
            // Give the library rows a head start; Discover is extra
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }

            self.feed.refreshIfNeeded()
            if self.genreNames.isEmpty, let names = try? await TMDBClient.shared.genres() {
                self.genreNames = names
            }
            self.startTask = nil
        }
    }
}

// MARK: - Section

/// Home's Discover rows, built from the shared feed:
/// a tall feature row, Because You Watched / Loved / Liked, New on Your Services, Top 10 and Coming Soon.
struct DiscoverHomeSection: View {

    private enum Style {
        case feature
        case top10
        case standard
    }

    private struct Shelf: Identifiable {
        let id: String
        let title: String
        let style: Style
        let items: [DiscoverItem]
    }

    @ObservedObject
    var viewModel: DiscoverHomeViewModel
    @ObservedObject
    var feed: DiscoverViewModel

    @Router
    private var router

    /// Apple TV app order: editorial feature row first, then personal and Top 10 rows mixed.
    private var shelves: [Shelf] {
        var shelves: [Shelf] = []
        let rows = feed.rows

        let topPicks = rows.first { $0.kind == .topPicks }
        let featured = ([feed.hero].compactMap(\.self) + (topPicks?.items ?? [])).prefix(12)
        if featured.isNotEmpty {
            shelves.append(Shelf(id: "featured", title: L10n.discoverTopPicks, style: .feature, items: Array(featured)))
        }

        // Because You Watched / Loved / Liked, in the feed's alternating order
        let because = rows.filter {
            switch $0.kind {
            case .becauseYouWatched, .becauseYouRated: true
            default: false
            }
        }
        func standard(_ row: DiscoverRow?) {
            guard let row, row.items.isNotEmpty else { return }

            shelves.append(Shelf(id: row.id, title: row.title, style: .standard, items: row.items))
        }

        standard(because.first)
        standard(rows.first { $0.kind == .newOnServices })

        if let trending = rows.first(where: { $0.kind == .trending }), trending.items.count >= 5 {
            shelves.append(Shelf(id: "top10", title: L10n.discoverTop10, style: .top10, items: Array(trending.items.prefix(10))))
        }

        because.dropFirst().forEach { standard($0) }
        standard(rows.first { $0.kind == .comingSoon })

        return shelves
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 60) {
            ForEach(Array(shelves.enumerated()), id: \.element.id) { index, shelf in
                shelfView(shelf)

                // The featured collection's row ("Halloween Picks") follows the feature row
                if index == 0 {
                    FeaturedCollectionHomeRow(feed: feed)
                }
            }

            Text(L10n.discoverAttribution)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: 1100, alignment: .leading)
                .edgePadding(.horizontal)
        }
        .onAppear {
            SeerrStatusStore.installRequestHandler()
            FeaturedCollectionsModel.shared.prepare()
        }
    }

    private func open(_ item: DiscoverItem) {
        router.route(to: .discoverTitle(item: item, feed: feed))
    }

    @ViewBuilder
    private func shelfView(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(shelf.title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .edgePadding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                    ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                        switch shelf.style {
                        case .feature:
                            DiscoverFeatureCard(item: item, genreNames: viewModel.genreNames, feed: feed) {
                                open(item)
                            }

                        case .top10:
                            DiscoverTop10Card(item: item, rank: index + 1, feed: feed) {
                                open(item)
                            }

                        case .standard:
                            DiscoverCard(item: item, viewModel: feed, width: 320) {
                                open(item)
                            }
                        }
                    }
                }
                .edgePadding(.horizontal)
                .padding(.vertical, shelf.style == .standard ? 20 : 36)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.vertical, shelf.style == .standard ? -20 : -36)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shelf.title)
    }
}
