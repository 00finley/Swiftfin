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
///   partially watched less, long-abandoned least) plus titles marked "More Like This".
/// - **Candidates** are TMDB recommendations and similar titles for the strongest seeds,
///   plus what's new and trending on the user's services.
/// - **Score** = seed matches (weighted) + genre affinity + recency + popularity (log) +
///   rating confidence + a bonus when it streams on the user's services.
/// - Watched, finished-in-library and "Not Interested" titles are excluded.
struct DiscoverEngine {

    struct Feed {
        var hero: DiscoverItem?
        var rows: [DiscoverRow]
    }

    /// A title the user has engaged with, used to find similar titles.
    struct Seed {
        let kind: DiscoverTitle.Kind
        let tmdbID: Int
        let name: String
        let weight: Double
        let lastActivity: Date?
        /// From "More Like This" rather than watch history
        var isLiked = false

        /// "Because You Watched X" for history, "More Like X" for explicit likes.
        var label: String {
            isLiked ? L10n.discoverMoreLike(name) : L10n.discoverBecauseYouWatched(name)
        }

        var key: String {
            "\(kind.rawValue)-\(tmdbID)"
        }
    }

    /// Library state for matching TMDB titles to Jellyfin items.
    struct Library {
        var itemIDsByKey: [String: String] = [:]
        var finishedKeys: Set<String> = []
        var seeds: [Seed] = []
    }

    let client: JellyfinClient
    let userID: String
    let providers: [Int]
    let region: String
    let profile: DiscoverProfile

    private let tmdb = TMDBClient.shared
    private let seedsForCandidates = 5
    private let becauseYouWatchedRows = 3
    private let rowLength = 20

    // MARK: - Feed

    func buildFeed() async throws -> Feed {
        let library = try await loadLibrary()

        async let trendingRequest = tmdb.trending()
        async let newRequest = tmdb.newOnServices(providers: providers, region: region)
        async let comingRequest = tmdb.comingSoon(providers: providers, region: region)
        async let genresRequest = tmdb.genres()

        let seeds = Array(seedList(from: library).prefix(seedsForCandidates))
        let seedDetails = await withTaskGroup(of: (Seed, TMDBDetails?).self) { group in
            for seed in seeds {
                group.addTask { await (seed, try? tmdb.details(kind: seed.kind, id: seed.tmdbID)) }
            }
            var results: [(Seed, TMDBDetails)] = []
            for await (seed, details) in group {
                if let details {
                    results.append((seed, details))
                }
            }
            return results.sorted { $0.0.weight > $1.0.weight }
        }

        let trending = await (try? trendingRequest) ?? []
        let newTitles = await (try? newRequest) ?? []
        let coming = await (try? comingRequest) ?? []
        let genreNames = await (try? genresRequest) ?? [:]

        let affinity = genreAffinity(seedDetails: seedDetails)
        let excluded = profile.dismissed.union(library.finishedKeys).union(seeds.map(\.key))

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
            let genre = title.genreIDs.isEmpty ? 0 : title.genreIDs.map { affinity[$0] ?? 0 }.reduce(0, +) / Double(title.genreIDs.count)
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
            if let top = title.genreIDs.max(by: { (affinity[$0] ?? 0) < (affinity[$1] ?? 0) }), let name = genreNames[top] {
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

        // Trending, filtered to the user's services when enough titles qualify
        let trendingCandidates = Array(trending.filter { excluded.contains($0.id) == false && $0.backdropPath != nil }
            .prefix(rowLength * 2))
        let trendingProviders = await providers(for: trendingCandidates)
        let trendingOnServices = trendingCandidates
            .filter { trendingProviders[$0.id]?.contains(where: { providers.contains($0.id) }) == true }
        let trendingRow = Array((trendingOnServices.count >= 6 ? trendingOnServices : trendingCandidates).prefix(rowLength))

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

        // Skip titles already in Top Picks when the row stays full enough
        let topPickKeys = Set(topItems.map(\.id))
        for (seed, details) in seedDetails.prefix(becauseYouWatchedRows) {
            let all = unique(details.recommendations + details.similar)
            let fresh = all.filter { topPickKeys.contains($0.id) == false }
            let titles = (fresh.count >= 6 ? fresh : all).prefix(rowLength)
            guard titles.count >= 4 else { continue }

            rows.append(DiscoverRow(
                kind: .becauseYouWatched(seed.key),
                title: seed.label,
                items: titles.map { item($0, withReason: false) }
            ))
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

        return Feed(hero: topItems.first ?? trendingItems.first, rows: rows)
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

    /// Library seeds plus "More Like This" titles, strongest first.
    private func seedList(from library: Library) -> [Seed] {
        let liked = profile.liked.values.map {
            Seed(kind: $0.kind, tmdbID: $0.tmdbID, name: $0.title, weight: 0.8, lastActivity: nil, isLiked: true)
        }
        var seen = Set<String>()
        return (library.seeds + liked)
            .sorted { $0.weight > $1.weight }
            .filter { seen.insert($0.key).inserted }
    }

    /// Genre preferences from seed genres (weighted) and explicit feedback, roughly in -1...1.
    private func genreAffinity(seedDetails: [(Seed, TMDBDetails)]) -> [Int: Double] {
        var totals: [Int: Double] = [:]
        let totalWeight = max(1, seedDetails.map(\.0.weight).reduce(0, +))
        for (seed, details) in seedDetails {
            for genre in details.genres {
                totals[genre.id, default: 0] += seed.weight / totalWeight
            }
        }
        for (genre, adjustment) in profile.genreFeedback {
            totals[genre, default: 0] += adjustment
        }
        return totals.mapValues { max(-1, min(1, $0)) }
    }

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
