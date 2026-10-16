//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

/// The taste context sent with each question: titles the user loved, liked and disliked (in-app
/// ratings and the build's seed list, newest first), what they watched lately in Jellyfin, and
/// their streaming services. Lists are capped so the prompt stays small, and their order is stable
/// so the helper's answer cache (keyed partly on taste) still hits for repeated questions.
@MainActor
enum AskTaste {

    static let lovedLimit = 25
    static let likedLimit = 25
    static let dislikedLimit = 15
    static let recentLimit = 10

    static func build(client: JellyfinClient?, userID: String?) async -> AskRequest.Taste {
        async let recent = recentlyWatched(client: client, userID: userID)
        var taste = await rated()
        taste.recentlyWatched = await recent
        return taste
    }

    static var services: [String] {
        let selected = Set(Defaults[.Discover.providers])
        return DiscoverProvider.supported.filter { selected.contains($0.id) }.map(\.name)
    }

    // MARK: - Ratings

    /// Loved / liked / disliked names. In-app ratings first (newest first), then the seed list in its order.
    static func rated(profile: DiscoverProfile = Defaults[.Discover.profile]) async -> AskRequest.Taste {
        let all = profile.ratedTitles()

        // In-app ratings by date, then seeds in their configured order
        let inApp = profile.ratings
            .sorted { $0.value.date == $1.value.date ? $0.key < $1.key : $0.value.date > $1.value.date }
            .map(\.key)
        let seeds = DiscoverSeedTitle.configured.map(\.key).filter { profile.ratings[$0] == nil }
        let ordered = (inApp + seeds).compactMap { all[$0] }

        let limits: [DiscoverRatingLevel: Int] = [.loved: lovedLimit, .liked: likedLimit, .disliked: dislikedLimit]
        var chosen: [DiscoverRatingLevel: [DiscoverRatedTitle]] = [:]
        for entry in ordered {
            guard let limit = limits[entry.level], chosen[entry.level, default: []].count < limit else { continue }

            chosen[entry.level, default: []].append(entry)
        }

        // Seeds carry only TMDB ids: their names come from the title info cache (Discover fills it), else TMDB
        let picked = chosen.values.flatMap(\.self)
        let missing = picked.filter { $0.title == nil && DiscoverTitleInfoStore.shared.cached($0.key) == nil }.map(\.key)
        if missing.isNotEmpty, TMDBClient.isAvailable {
            _ = await withTimeout(seconds: 6) {
                await DiscoverTitleInfoStore.shared.infos(for: missing)
            }
        }

        func names(_ level: DiscoverRatingLevel) -> [String] {
            var seen = Set<String>()
            return (chosen[level] ?? []).compactMap { entry in
                let name = entry.title?.title ?? DiscoverTitleInfoStore.shared.cached(entry.key)?.title.title
                guard let name, name.isNotEmpty, seen.insert(name.lowercased()).inserted else { return nil }

                return name
            }
        }

        return AskRequest.Taste(loved: names(.loved), liked: names(.liked), disliked: names(.disliked))
    }

    /// A loved title's name for the "Something like a show I love" chip (rotates daily).
    static func lovedTitleName(profile: DiscoverProfile = Defaults[.Discover.profile]) -> String? {
        let loved = profile.ratedTitles()
            .values
            .filter { $0.level == .loved }
            .sorted { $0.key < $1.key }
            .compactMap { entry -> String? in
                entry.title?.title ?? DiscoverTitleInfoStore.shared.cached(entry.key)?.title.title
            }
        guard loved.isNotEmpty else { return nil }

        let day = Int(Date.now.timeIntervalSince1970 / 86400)
        return loved[day % loved.count]
    }

    // MARK: - History

    /// Series and movies from Continue Watching, then the most recently played, without repeats.
    static func recentlyWatched(client: JellyfinClient?, userID: String?) async -> [String] {
        guard let client, let userID else { return [] }

        var resumeParameters = Paths.GetResumeItemsParameters()
        resumeParameters.userID = userID
        resumeParameters.limit = 12
        resumeParameters.mediaTypes = [.video]
        resumeParameters.enableUserData = true
        resumeParameters.enableImages = false

        var playedParameters = Paths.GetItemsParameters()
        playedParameters.userID = userID
        playedParameters.isRecursive = true
        playedParameters.includeItemTypes = [.episode, .movie]
        playedParameters.sortBy = [.datePlayed]
        playedParameters.sortOrder = [.descending]
        playedParameters.enableUserData = true
        playedParameters.enableImages = false
        playedParameters.limit = 80

        let resumeQuery = resumeParameters
        let playedQuery = playedParameters
        async let resumeRequest = client.send(Paths.getResumeItems(parameters: resumeQuery))
        async let playedRequest = client.send(Paths.getItems(parameters: playedQuery))

        let resume = await (try? resumeRequest.value.items) ?? []
        let played = await ((try? playedRequest.value.items) ?? []).filter { item in
            item.userData?.lastPlayedDate != nil || item.userData?.isPlayed == true
        }

        var seen = Set<String>()
        var names: [String] = []
        for item in resume + played {
            let name = item.type == .episode ? (item.seriesName ?? item.name) : item.name
            guard let name, name.isNotEmpty, seen.insert(name.lowercased()).inserted else { continue }

            names.append(name)
            if names.count == recentLimit {
                break
            }
        }
        return names
    }
}

/// Runs `operation`, giving up (nil) after `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
