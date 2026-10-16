//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Builds the Discover feed and scores recommendations on device.
///
/// Scoring is deliberately simple and explainable:
/// - **Seeds** come from Jellyfin watch history (finished and favorited titles weigh most,
///   partially watched less, long-abandoned least) plus titles rated Love It or Like It (in the app
///   or in the build's seed list). Rated seeds rotate daily, favoring Love It.
/// - **Candidates** are TMDB recommendations and similar titles for the strongest seeds,
///   plus what's new and trending on the user's services.
/// - **Score** = seed matches (weighted) + genre affinity + recency + popularity (log) +
///   rating confidence + a bonus when it streams on the user's services.
/// - Watched, finished-in-library, rated and Not for Me titles are excluded.
struct DiscoverEngine {

    struct Feed {
        var hero: DiscoverItem?
        var rows: [DiscoverRow]
        /// Jellyfin item ids keyed by TMDB key ("tv-1396"), for "In Library" badges elsewhere.
        var libraryItemIDs: [String: String] = [:]
        var taste = DiscoverTaste()
    }

    /// A title the user has engaged with, used to find similar titles.
    struct Seed {

        enum Source {
            case history
            case liked
            case loved
        }

        let kind: DiscoverTitle.Kind
        let tmdbID: Int
        var name: String
        let weight: Double
        let lastActivity: Date?
        var source: Source = .history

        /// "Because You Watched X" for history, "Because You Loved X" / "Because You Liked X" for ratings.
        var label: String {
            switch source {
            case .history: L10n.discoverBecauseYouWatched(name)
            case .liked: L10n.discoverBecauseYouLiked(name)
            case .loved: L10n.discoverBecauseYouLoved(name)
            }
        }

        var key: String {
            "\(kind.rawValue)-\(tmdbID)"
        }

        var isRated: Bool {
            source != .history
        }
    }

    /// Library state for matching TMDB titles to Jellyfin items.
    struct Library {
        var itemIDsByKey: [String: String] = [:]
        var finishedKeys: Set<String> = []
        var seeds: [Seed] = []
    }

    /// Seeds, their TMDB details and the taste built from them; shared by the feed and Categories.
    struct Context {
        var library = Library()
        /// Strongest first
        var seedDetails: [(Seed, TMDBDetails)] = []
        var taste = DiscoverTaste()
        /// Titles never recommended: hidden, finished, rated and the seeds themselves
        var excluded: Set<String> = []
    }

    let client: JellyfinClient
    let userID: String
    let providers: [Int]
    let region: String
    let profile: DiscoverProfile

    private let tmdb = TMDBClient.shared
    private let historySeedsForCandidates = 4
    private let ratedSeedsForCandidates = 4
    private let historySeedsForTaste = 20
    private let rowLength = 20

    // MARK: - Context

    func prepareContext() async -> Context {
        // If the Jellyfin server is unreachable (e.g. mid-migration), still use ratings without history
        let library = await (try? loadLibrary()) ?? Library()
        let rated = profile.ratedTitles()

        // A rated title counts as rated, not as history
        let history = library.seeds
            .filter { rated[$0.key] == nil }
            .sorted { $0.weight > $1.weight }
        let ratedSeeds = rated.values.compactMap { entry -> Seed? in
            guard entry.level == .loved || entry.level == .liked, let kind = entry.kind, let id = entry.tmdbID else { return nil }

            return Seed(
                kind: kind,
                tmdbID: id,
                name: entry.title?.title ?? "",
                weight: entry.level.seedWeight,
                lastActivity: nil,
                source: entry.level == .loved ? .loved : .liked
            )
        }

        // Up to 4 of each; when one side is short, the other fills in
        let total = historySeedsForCandidates + ratedSeedsForCandidates
        let rotated = Self.dailyRotation(ratedSeeds)
        let historyCount = min(history.count, max(historySeedsForCandidates, total - rotated.count))
        let chosen = Array(history.prefix(historyCount)) + Array(rotated.prefix(total - historyCount))

        async let infosRequest = DiscoverTitleInfoStore.shared.infos(
            for: history.prefix(historySeedsForTaste).map(\.key) + rated.values.filter { $0.level != .neutral }.map(\.key)
        )

        let seedDetails = await withTaskGroup(of: (Seed, TMDBDetails?).self) { group in
            for seed in chosen {
                group.addTask { await (seed, try? tmdb.details(kind: seed.kind, id: seed.tmdbID)) }
            }
            var results: [(Seed, TMDBDetails)] = []
            for await (seed, details) in group {
                guard let details else { continue }

                var named = seed
                if named.name.isEmpty {
                    named.name = details.title.title
                }
                results.append((named, details))
            }
            return results.sorted { $0.0.weight > $1.0.weight }
        }
        let infos = await infosRequest

        var taste = DiscoverTaste()
        var sources: [DiscoverTaste.Source] = history.prefix(historySeedsForTaste).compactMap { seed in
            infos[seed.key].map { .init(genres: $0.title.genreIDs, keywords: $0.keywords, weight: seed.weight) }
        }
        for entry in rated.values where entry.level != .neutral {
            let genres = infos[entry.key]?.title.genreIDs ?? entry.title?.genreIDs ?? []
            sources.append(.init(genres: genres, keywords: infos[entry.key]?.keywords ?? [], weight: entry.level.tasteWeight))
        }
        taste.learn(from: sources, genreFeedback: profile.genreFeedback)

        for (seed, details) in seedDetails {
            for (title, strength) in details.recommendations.map({ ($0, 1.0) }) + details.similar.map({ ($0, 0.6) }) {
                taste.related[title.id, default: 0] += seed.weight * strength / 1.5
            }
        }
        taste.related = taste.related.mapValues { min(1, $0) }
        taste.libraryKeys = Set(library.itemIDsByKey.keys)
        taste.hiddenKeys = profile.hiddenKeys
        taste.watchedKeys = library.finishedKeys.union(rated.values.filter { $0.level != .disliked }.map(\.key))

        let excluded = taste.hiddenKeys
            .union(library.finishedKeys)
            .union(rated.keys)
            .union(seedDetails.map(\.0.key))

        return Context(library: library, seedDetails: seedDetails, taste: taste, excluded: excluded)
    }

    /// Rated seeds in a different order each day, Love It more often than Like It
    /// (weighted random order with a stable per-day hash).
    static func dailyRotation(_ seeds: [Seed], day: Int = Int(Date.now.timeIntervalSince1970 / 86400)) -> [Seed] {
        seeds
            .map { seed -> (Seed, Double) in
                var hash: UInt64 = 0xCBF2_9CE4_8422_2325
                for byte in "\(day)-\(seed.key)".utf8 {
                    hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
                }
                let unit = (Double(hash % 1_000_000) + 0.5) / 1_000_000
                return (seed, pow(unit, 1 / max(0.1, seed.weight)))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Feed

    func buildFeed() async throws -> Feed {
        async let trendingFirst = tmdb.trending(page: 1)
        async let trendingSecond = tmdb.trending(page: 2)
        async let newRequest = tmdb.newOnServices(providers: providers, region: region)
        async let comingRequest = tmdb.comingSoon(providers: providers, region: region)
        async let genresRequest = tmdb.genres()

        let context = await prepareContext()
        let library = context.library
        let seedDetails = context.seedDetails
        let taste = context.taste
        let excluded = context.excluded

        // Two pages: the Top 10 needs ten titles even when few trending titles are on the user's services
        let trending = await ((try? trendingFirst) ?? []) + ((try? trendingSecond) ?? [])
        let newTitles = await (try? newRequest) ?? []
        let coming = await (try? comingRequest) ?? []
        let genreNames = await (try? genresRequest) ?? [:]

        // Candidate pool with seed matches
        var candidates: [String: DiscoverTitle] = [:]
        var seedMatches: [String: (score: Double, seedLabel: String, bestWeight: Double)] = [:]

        for (seed, details) in seedDetails {
            for (title, strength) in details.recommendations.map({ ($0, 1.0) }) + details.similar.map({ ($0, 0.6) }) {
                candidates[title.id] = candidates[title.id] ?? title
                let contribution = seed.weight * strength
                let current = seedMatches[title.id]
                seedMatches[title.id] = (
                    (current?.score ?? 0) + contribution,
                    contribution > (current?.bestWeight ?? 0) ? seed.label : (current?.seedLabel ?? seed.label),
                    max(current?.bestWeight ?? 0, contribution)
                )
            }
        }
        for title in newTitles + trending {
            candidates[title.id] = candidates[title.id] ?? title
        }

        let newKeys = Set(newTitles.map(\.id))

        func score(_ title: DiscoverTitle) -> Double {
            let match = seedMatches[title.id]?.score ?? 0
            let genre = taste.genreScore(title)
            let age = title.releaseDate.map { max(0, Date.now.timeIntervalSince($0) / 86400) } ?? 3650
            let recency = exp(-age / 365)
            let popularity = min(1, log10(1 + title.popularity) / 3)
            let quality = title.voteAverage / 10 * min(1, Double(title.voteCount) / 200)
            let onServices = newKeys.contains(title.id) ? 0.5 : 0
            return 2.0 * match + 1.0 * genre + 0.5 * recency + 0.4 * popularity + 0.6 * quality + onServices
        }

        func reason(for title: DiscoverTitle) -> String? {
            if let seedLabel = seedMatches[title.id]?.seedLabel {
                return seedLabel
            }
            if newKeys.contains(title.id) {
                return L10n.discoverNewOnYourServices
            }
            if let top = title.genreIDs.max(by: { (taste.genre[$0] ?? 0) < (taste.genre[$1] ?? 0) }), let name = genreNames[top] {
                return name
            }
            return nil
        }

        let ranked = candidates.values
            .filter { excluded.contains($0.id) == false && $0.backdropPath != nil }
            .sorted { score($0) > score($1) }

        // Top picks: personalized, preferring titles that stream on the user's services
        let topCandidates = Array(ranked.prefix(rowLength * 2))
        let topProviders = await providers(for: topCandidates)
        let available = topCandidates.filter { title in
            newKeys.contains(title.id) || topProviders[title.id]?.contains(where: { providers.contains($0.id) }) == true
        }
        let topPicks = Array((available.count >= 8 ? available : topCandidates).prefix(rowLength))

        // Trending: the user's services when at least ten trending titles stream there (so the
        // Top 10 stays full), otherwise TMDB's own order
        var seenTrending = Set<String>()
        let trendingCandidates = Array(trending
            .filter { excluded.contains($0.id) == false && $0.backdropPath != nil && seenTrending.insert($0.id).inserted }
            .prefix(rowLength * 2))
        let trendingProviders = await providers(for: trendingCandidates)
        let trendingOnServices = trendingCandidates
            .filter { trendingProviders[$0.id]?.contains(where: { providers.contains($0.id) }) == true }
        let trendingRow = Array((trendingOnServices.count >= 10 ? trendingOnServices : trendingCandidates).prefix(rowLength))

        let allProviders = topProviders.merging(trendingProviders) { first, _ in first }

        func item(_ title: DiscoverTitle, withReason: Bool = true) -> DiscoverItem {
            DiscoverItem(
                title: title,
                providers: (allProviders[title.id] ?? []).filter { providers.contains($0.id) },
                libraryItemID: library.itemIDsByKey[title.id],
                reason: withReason ? reason(for: title) : nil
            )
        }

        func unique(_ titles: [DiscoverTitle]) -> [DiscoverTitle] {
            var seen = Set<String>()
            return titles.filter { excluded.contains($0.id) == false && $0.backdropPath != nil && seen.insert($0.id).inserted }
        }

        var rows: [DiscoverRow] = []

        let topItems = topPicks.map { item($0) }
        if topItems.count > 1 {
            rows.append(DiscoverRow(kind: .topPicks, title: L10n.discoverTopPicks, items: Array(topItems.dropFirst())))
        }

        // Because You Watched / Loved / Liked rows, alternating; skip titles already in Top Picks
        // when the row stays full enough
        let topPickKeys = Set(topItems.map(\.id))
        func seedRow(_ seed: Seed, _ details: TMDBDetails) -> DiscoverRow? {
            let all = unique(details.recommendations + details.similar)
            let fresh = all.filter { topPickKeys.contains($0.id) == false }
            let titles = (fresh.count >= 6 ? fresh : all).prefix(rowLength)
            guard titles.count >= 4 else { return nil }

            return DiscoverRow(
                kind: seed.isRated ? .becauseYouRated(seed.key) : .becauseYouWatched(seed.key),
                title: seed.label,
                items: titles.map { item($0, withReason: false) }
            )
        }
        let historyRows = seedDetails.filter { !$0.0.isRated }.compactMap(seedRow)
        let ratedRows = seedDetails.filter(\.0.isRated).compactMap(seedRow)
        let ratedRowCount = min(2, ratedRows.count)
        let historyRowCount = min(historyRows.count, 4 - ratedRowCount, 3)
        for index in 0 ..< max(historyRowCount, ratedRowCount) {
            if index < historyRowCount {
                rows.append(historyRows[index])
            }
            if index < ratedRowCount {
                rows.append(ratedRows[index])
            }
        }

        let newItems = unique(newTitles).prefix(rowLength).map { item($0, withReason: false) }
        if newItems.isNotEmpty {
            rows.append(DiscoverRow(kind: .newOnServices, title: L10n.discoverNewOnYourServices, items: Array(newItems)))
        }

        let trendingItems = unique(trendingRow).map { item($0, withReason: false) }
        if trendingItems.isNotEmpty {
            rows.append(DiscoverRow(kind: .trending, title: L10n.discoverTrendingNow, items: trendingItems))
        }

        let comingItems = unique(coming).prefix(rowLength).map { item($0, withReason: false) }
        if comingItems.isNotEmpty {
            rows.append(DiscoverRow(kind: .comingSoon, title: L10n.discoverComingSoon, items: Array(comingItems)))
        }

        return Feed(
            hero: topItems.first ?? trendingItems.first,
            rows: rows,
            libraryItemIDs: library.itemIDsByKey,
            taste: taste
        )
    }

    // MARK: - Library

    /// Library items keyed by TMDB id, plus watch-history seeds.
    func loadLibrary() async throws -> Library {
        var itemsParameters = Paths.GetItemsParameters()
        itemsParameters.userID = userID
        itemsParameters.isRecursive = true
        itemsParameters.includeItemTypes = [.series, .movie]
        itemsParameters.fields = [.providerIDs]
        itemsParameters.enableUserData = true

        var episodesParameters = Paths.GetItemsParameters()
        episodesParameters.userID = userID
        episodesParameters.isRecursive = true
        episodesParameters.includeItemTypes = [.episode]
        episodesParameters.sortBy = [.datePlayed]
        episodesParameters.sortOrder = [.descending]
        episodesParameters.enableUserData = true
        episodesParameters.limit = 300

        async let itemsResponse = client.send(Paths.getItems(parameters: itemsParameters))
        async let episodesResponse = client.send(Paths.getItems(parameters: episodesParameters))

        let items = try await itemsResponse.value.items ?? []
        let episodes = await (try? episodesResponse.value.items) ?? []

        // Per-series activity from episode history
        var lastActivity: [String: Date] = [:]
        var startedEpisodes: [String: Int] = [:]
        for episode in episodes {
            guard let seriesID = episode.seriesID, let data = episode.userData else { continue }

            let started = data.isPlayed == true || (data.playbackPositionTicks ?? 0) > 0
            guard started else { continue }

            startedEpisodes[seriesID, default: 0] += 1
            if let date = data.lastPlayedDate, date > (lastActivity[seriesID] ?? .distantPast) {
                lastActivity[seriesID] = date
            }
        }

        var library = Library()

        for item in items {
            guard let id = item.id, let tmdb = item.providerIDs?["Tmdb"].flatMap(Int.init) else { continue }

            let kind: DiscoverTitle.Kind = item.type == .movie ? .movie : .tv
            let key = "\(kind.rawValue)-\(tmdb)"
            library.itemIDsByKey[key] = id

            let data = item.userData
            let favorite = data?.isFavorite == true ? 0.5 : 0
            var weight: Double
            var activity: Date?

            if kind == .movie {
                activity = data?.lastPlayedDate
                if data?.isPlayed == true {
                    weight = 1.0
                    library.finishedKeys.insert(key)
                } else if (data?.playbackPositionTicks ?? 0) > 0 {
                    weight = isAbandoned(activity) ? 0.15 : 0.6
                } else {
                    weight = 0
                }
            } else {
                activity = lastActivity[id]
                let completion = (data?.playedPercentage ?? 0) / 100
                if data?.isPlayed == true || completion >= 0.99 {
                    weight = 1.0
                    library.finishedKeys.insert(key)
                } else if (startedEpisodes[id] ?? 0) > 0 || completion > 0 {
                    weight = completion < 0.25 && isAbandoned(activity) ? 0.15 : 0.4 + 0.6 * min(1, completion * 2)
                } else {
                    weight = 0
                }
            }

            weight += weight > 0 || favorite > 0 ? favorite : 0
            guard weight > 0 else { continue }

            library.seeds.append(Seed(
                kind: kind,
                tmdbID: tmdb,
                name: item.displayTitle,
                weight: weight * recencyMultiplier(activity),
                lastActivity: activity
            ))
        }

        return library
    }

    // MARK: - Helpers

    private func providers(for titles: [DiscoverTitle]) async -> [String: [DiscoverProvider]] {
        await withTaskGroup(of: (String, [DiscoverProvider]).self) { group in
            for title in titles {
                group.addTask { await (title.id, (try? tmdb.providers(for: title, region: region)) ?? []) }
            }
            var results: [String: [DiscoverProvider]] = [:]
            for await (id, providers) in group {
                results[id] = providers
            }
            return results
        }
    }

    private func isAbandoned(_ lastActivity: Date?) -> Bool {
        guard let lastActivity else { return false }

        return Date.now.timeIntervalSince(lastActivity) > 45 * 86400
    }

    private func recencyMultiplier(_ lastActivity: Date?) -> Double {
        guard let lastActivity else { return 1.0 }

        let days = Date.now.timeIntervalSince(lastActivity) / 86400
        if days <= 14 {
            return 1.3
        }
        if days <= 60 {
            return 1.0
        }
        return 0.7
    }
}
