//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// One playable episode in a channel's pool
struct ChannelEpisode: Hashable, Codable {

    let id: String
    let seriesID: String
}

/// What a channel has played in its current cycle, kept per user per channel.
struct ChannelShuffleHistory: Codable, Hashable {

    /// Episodes played since the pool was last exhausted
    var playedEpisodeIDs: Set<String> = []
    /// The show of the last episode, so the next one comes from another show
    var lastSeriesID: String?
}

/// Picks a channel's next episode.
///
/// - No episode repeats until every episode in the pool has played; then a new cycle starts.
/// - The same show doesn't come up twice in a row while another show has episodes left.
/// - Otherwise every remaining episode is equally likely, so shows come up in proportion to the
///   episodes they have left and all of them stay on the channel for the whole cycle.
enum ChannelShuffler {

    /// The next episode, or nil for an empty pool.
    ///
    /// - Parameter excluding: episodes that can't be picked now (the one playing, ones that failed to load)
    static func pick(
        from pool: [ChannelEpisode],
        history: ChannelShuffleHistory,
        excluding: Set<String> = [],
        using generator: inout some RandomNumberGenerator
    ) -> ChannelEpisode? {
        let available = pool.filter { !excluding.contains($0.id) }
        guard available.isNotEmpty else { return nil }

        var remaining = available.filter { !history.playedEpisodeIDs.contains($0.id) }

        // Pool exhausted: a new cycle
        if remaining.isEmpty {
            remaining = available
        }

        let otherShows = remaining.filter { $0.seriesID != history.lastSeriesID }
        let candidates = otherShows.isEmpty ? remaining : otherShows

        return candidates.randomElement(using: &generator)
    }

    static func pick(
        from pool: [ChannelEpisode],
        history: ChannelShuffleHistory,
        excluding: Set<String> = []
    ) -> ChannelEpisode? {
        var generator = SystemRandomNumberGenerator()
        return pick(from: pool, history: history, excluding: excluding, using: &generator)
    }

    /// Records an episode that started playing.
    static func record(_ episode: ChannelEpisode, pool: [ChannelEpisode], in history: inout ChannelShuffleHistory) {
        let poolIDs = Set(pool.map(\.id))

        // Forget episodes no longer in the pool (a show was removed), so they don't hold up a new cycle
        history.playedEpisodeIDs.formIntersection(poolIDs)

        // It played earlier this cycle, so the pool was exhausted and a new cycle started with it
        if history.playedEpisodeIDs.contains(episode.id) || poolIDs.isSubset(of: history.playedEpisodeIDs) {
            history.playedEpisodeIDs = []
        }

        history.playedEpisodeIDs.insert(episode.id)
        history.lastSeriesID = episode.seriesID
    }
}
