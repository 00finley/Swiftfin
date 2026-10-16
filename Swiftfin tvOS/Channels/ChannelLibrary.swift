//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// The library's shows and the episodes a channel can play, with short-lived caches.
@MainActor
final class ChannelLibrary {

    /// A channel's shows and their playable episodes
    struct Pool {
        var series: [BaseItemDto] = []
        var episodes: [ChannelEpisode] = []
        /// Episode metadata by ID (enough for the Up Next card and to start playback)
        var items: [String: BaseItemDto] = [:]

        var isEmpty: Bool {
            episodes.isEmpty
        }
    }

    static let shared = ChannelLibrary()

    /// Specials (season 0) are often extras, and very short videos are clips: neither is a full episode
    static let minimumRuntime: TimeInterval = 5 * 60

    private let logger = Logger.swiftfin()

    private var seriesCache: (userID: String, date: Date, items: [BaseItemDto])?
    private var seriesTask: Task<[BaseItemDto], Error>?
    private var episodeCache: [String: (date: Date, items: [BaseItemDto])] = [:]
    private var episodeCacheUserID: String?

    private init() {}

    // MARK: - Shows

    /// Every show in the user's libraries, by name
    func allSeries(maxAge: TimeInterval = 5 * 60) async throws -> [BaseItemDto] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        if let seriesCache, seriesCache.userID == session.user.id, Date.now.timeIntervalSince(seriesCache.date) < maxAge {
            return seriesCache.items
        }
        if let seriesTask {
            return try await seriesTask.value
        }

        let task = Task<[BaseItemDto], Error> {
            var parameters = Paths.GetItemsParameters()
            parameters.userID = session.user.id
            parameters.isRecursive = true
            parameters.includeItemTypes = [.series]
            parameters.fields = [.genres]
            parameters.sortBy = [.sortName]
            parameters.enableUserData = false
            parameters.enableImageTypes = [.primary, .backdrop, .thumb, .logo]
            parameters.imageTypeLimit = 1

            return try await session.client.send(Paths.getItems(parameters: parameters)).value.items ?? []
        }
        seriesTask = task
        defer { seriesTask = nil }

        let items = try await task.value
        seriesCache = (session.user.id, .now, items)
        return items
    }

    /// The shows in a channel: the rule's matches plus the user's additions, minus removals
    func series(in channel: ChannelDefinition) async throws -> [BaseItemDto] {
        let store = ChannelStore.shared

        return try await allSeries().filter { series in
            guard let id = series.id else { return false }

            return store.includes(id, matchesRule: channel.pool.matches(series), in: channel)
        }
    }

    // MARK: - Episodes

    /// The channel's shows and every full episode of them that has a media file
    func pool(for channel: ChannelDefinition) async throws -> Pool {
        let series = try await series(in: channel)
        let seriesIDs = series.compactMap(\.id)

        let episodesBySeries = try await withThrowingTaskGroup(of: (String, [BaseItemDto]).self) { group in
            for id in seriesIDs {
                group.addTask { @MainActor in
                    try await (id, self.episodes(seriesID: id))
                }
            }

            var result: [String: [BaseItemDto]] = [:]
            for try await (id, items) in group {
                result[id] = items
            }
            return result
        }

        var pool = Pool(series: series)

        // Shows in name order, so the pool is the same for the same library (the shuffle is random anyway)
        for id in seriesIDs {
            for item in episodesBySeries[id] ?? [] {
                guard let episodeID = item.id else { continue }

                pool.episodes.append(ChannelEpisode(id: episodeID, seriesID: id))
                pool.items[episodeID] = item
            }
        }

        return pool
    }

    private func episodes(seriesID: String, maxAge: TimeInterval = 10 * 60) async throws -> [BaseItemDto] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        if episodeCacheUserID != session.user.id {
            episodeCache = [:]
            episodeCacheUserID = session.user.id
        }
        if let cached = episodeCache[seriesID], Date.now.timeIntervalSince(cached.date) < maxAge {
            return cached.items
        }

        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = session.user.id
        parameters.isMissing = false
        parameters.enableUserData = false
        parameters.enableImages = true
        parameters.enableImageTypes = [.primary, .thumb]
        parameters.imageTypeLimit = 1

        let items = try await session.client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).value.items ?? []
        let playable = items.filter(Self.isFullEpisode)

        episodeCache[seriesID] = (.now, playable)
        return playable
    }

    /// An episode with a media file (the request leaves out missing episodes; this drops virtual
    /// placeholders), not a special, and not a clip
    static func isFullEpisode(_ item: BaseItemDto) -> Bool {
        guard item.type == .episode,
              item.locationType != .virtual,
              (item.parentIndexNumber ?? 1) >= 1
        else { return false }

        if let ticks = item.runTimeTicks, ticks > 0 {
            return Double(ticks) / 10_000_000 >= minimumRuntime
        }
        return true
    }

    func invalidate() {
        seriesCache = nil
        episodeCache = [:]
    }
}
