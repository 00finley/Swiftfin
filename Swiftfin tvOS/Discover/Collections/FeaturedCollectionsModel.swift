//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation

/// What's featuring today, plus each active collection's top For You picks and art,
/// shared by the Categories hero, the Featured Now row and the Home row.
@MainActor
final class FeaturedCollectionsModel: ObservableObject {

    static let shared = FeaturedCollectionsModel()

    @Published
    private(set) var today = FeaturedSchedule.today
    /// For You picks (default shelf, pins first) by collection id; Not for Me titles are left out when shown.
    @Published
    private(set) var picks: [String: [DiscoverTitle]] = [:]
    /// Textless art from each collection's top pick, by collection id
    @Published
    private(set) var art: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]
    private var pickedDay: CalendarDay?
    private let artCache = DiscoverKeyedCache<String>(fileName: "DiscoverFeaturedArt.json", maxEntries: 400)
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Ratings change the For You order; services change nothing here (collections search everything)
        Defaults.publisher(.Discover.profile, options: [])
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
        Defaults.publisher(keys: .Discover.seasonalCollections, .Discover.funDays, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isEnabled: Bool {
        Defaults[.Discover.seasonalCollections] && TMDBClient.isAvailable
    }

    var collections: [FeaturedCollection] {
        FeaturedSchedule.collections(includeFun: Defaults[.Discover.funDays])
    }

    /// Featuring today, best first (the first is the hero).
    var active: [FeaturedOccurrence] {
        isEnabled ? FeaturedSchedule.active(on: today, in: collections) : []
    }

    /// Every collection for the Celebrate group, featuring now first, then by date.
    var celebrate: [FeaturedOccurrence] {
        isEnabled ? FeaturedSchedule.upcoming(from: today, in: collections) : []
    }

    /// Picks without the user's Not for Me titles.
    func visiblePicks(for collection: FeaturedCollection) -> [DiscoverTitle] {
        let hidden = Defaults[.Discover.profile].hiddenKeys
        return (picks[collection.id] ?? []).filter { !hidden.contains($0.id) }
    }

    /// The collection's own art when its picks have loaded, else the built-in backdrop.
    func backdropPath(for collection: FeaturedCollection) -> String? {
        art[collection.id] ?? collection.backdropPath
    }

    /// Rechecks the date (the app can stay open past midnight) and loads picks for what's featuring.
    func prepare() {
        let day = FeaturedSchedule.today
        if day != today {
            today = day
        }
        if pickedDay != day {
            pickedDay = day
            tasks.values.forEach { $0.cancel() }
            tasks = [:]
        }
        for occurrence in active.prefix(6) {
            load(occurrence.collection)
        }
    }

    private func reset() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        picks = [:]
        pickedDay = nil
        prepare()
    }

    private func load(_ collection: FeaturedCollection) {
        guard tasks[collection.id] == nil, picks[collection.id] == nil, let shelf = collection.shelves.first else { return }

        tasks[collection.id] = Task { [weak self] in
            // The same paging, pins and For You ranking as the collection page
            let pager = DiscoverTitlePager()
            CategoryResultsViewModel.load(pager, query: collection.query(for: shelf), pinnedKeys: collection.pins(for: shelf))
            for await phase in pager.$phase.values where phase != .loading {
                break
            }
            guard let self, !Task.isCancelled else { return }

            let titles = pager.titles
            self.picks[collection.id] = titles
            await self.loadArt(collection, titles: titles)
        }
    }

    /// Textless (no-language) backdrop of the top pick, the way TMDB serves key art without a title.
    private func loadArt(_ collection: FeaturedCollection, titles: [DiscoverTitle]) async {
        let hidden = Defaults[.Discover.profile].hiddenKeys
        guard let top = titles.first(where: { !hidden.contains($0.id) }) else { return }

        let key = "\(collection.id)|\(top.id)"
        if let cached = artCache.value(for: key) {
            art[collection.id] = cached
            return
        }

        var path = top.backdropPath
        if let images = try? await TMDBClient.shared.images(kind: top.kind, id: top.tmdbID) {
            let textless = (images.backdrops ?? [])
                .filter { $0.iso_639_1 == nil && ($0.width ?? 1920) >= 1280 }
                .min(by: TMDBImages.Image.isBetter)
            path = textless?.file_path ?? path
        }
        guard !Task.isCancelled, let path else { return }

        artCache.set(path, for: key, ttl: 14 * 86400)
        art[collection.id] = path
    }
}
