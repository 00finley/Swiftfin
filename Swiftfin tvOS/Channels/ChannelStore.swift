//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import Logging

/// The user's state for each channel: settings, show edits, shuffle history and what played last.
///
/// Kept per server user (in that user's defaults suite) and per channel. It never touches the
/// server: channel viewing stays out of the user's watch history unless "Count as Watched" is on.
@MainActor
final class ChannelStore: ObservableObject {

    struct NowPlaying: Codable, Hashable {
        let seriesID: String
        let seriesName: String
        let episodeID: String
        let date: Date
    }

    struct State: Codable, Hashable {
        var settings: ChannelSettings?
        /// Shows the user turned on that the rule doesn't match
        var addedSeriesIDs: Set<String> = []
        /// Shows the rule matches that the user turned off
        var removedSeriesIDs: Set<String> = []
        var history = ChannelShuffleHistory()
        /// The last episode the channel played, for the card's "Now: Bob's Burgers"
        var nowPlaying: NowPlaying?
    }

    static let shared = ChannelStore()

    /// Bumped on every change, so views showing channel state refresh
    @Published
    private(set) var revision = 0

    private var states: [String: State] = [:]

    private let logger = Logger.swiftfin()

    private init() {}

    private var userID: String? {
        Container.shared.currentUserSession()?.user.id
    }

    private func storageKey(for channel: ChannelDefinition) -> String {
        "glassfin.channel.\(channel.id)"
    }

    private func cacheKey(for channel: ChannelDefinition, userID: String) -> String {
        "\(userID)|\(channel.id)"
    }

    func state(for channel: ChannelDefinition) -> State {
        guard let userID else { return State() }

        let key = cacheKey(for: channel, userID: userID)
        if let state = states[key] {
            return state
        }

        let state = UserDefaults.userSuite(id: userID)
            .data(forKey: storageKey(for: channel))
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()

        states[key] = state
        return state
    }

    func update(_ channel: ChannelDefinition, _ change: (inout State) -> Void) {
        guard let userID else { return }

        var state = state(for: channel)
        change(&state)
        states[cacheKey(for: channel, userID: userID)] = state
        revision += 1

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.userSuite(id: userID).set(data, forKey: storageKey(for: channel))
        } catch {
            logger.error("Couldn't save channel state", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    // MARK: - Settings

    func settings(for channel: ChannelDefinition) -> ChannelSettings {
        state(for: channel).settings ?? channel.defaults
    }

    func setCountsAsWatched(_ isOn: Bool, for channel: ChannelDefinition) {
        update(channel) { state in
            var settings = state.settings ?? channel.defaults
            settings.countsAsWatched = isOn
            state.settings = settings
        }
    }

    // MARK: - Shows

    /// Whether a show is in the channel: the rule's choice unless the user changed it
    func includes(_ seriesID: String, matchesRule: Bool, in channel: ChannelDefinition) -> Bool {
        let state = state(for: channel)

        if matchesRule {
            return !state.removedSeriesIDs.contains(seriesID)
        }
        return state.addedSeriesIDs.contains(seriesID)
    }

    func setIncluded(_ isIncluded: Bool, seriesID: String, matchesRule: Bool, in channel: ChannelDefinition) {
        update(channel) { state in
            if matchesRule {
                if isIncluded {
                    state.removedSeriesIDs.remove(seriesID)
                } else {
                    state.removedSeriesIDs.insert(seriesID)
                }
            } else {
                if isIncluded {
                    state.addedSeriesIDs.insert(seriesID)
                } else {
                    state.addedSeriesIDs.remove(seriesID)
                }
            }
        }
    }

    func resetShows(for channel: ChannelDefinition) {
        update(channel) { state in
            state.addedSeriesIDs = []
            state.removedSeriesIDs = []
        }
    }

    // MARK: - Playback

    func recordPlayed(_ episode: ChannelEpisode, seriesName: String, pool: [ChannelEpisode], in channel: ChannelDefinition) {
        update(channel) { state in
            ChannelShuffler.record(episode, pool: pool, in: &state.history)
            state.nowPlaying = NowPlaying(seriesID: episode.seriesID, seriesName: seriesName, episodeID: episode.id, date: .now)
        }
    }

    #if DEBUG
    /// UI tests start from a fresh history with `-GlassfinResetChannels`
    func resetAllIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-GlassfinResetChannels"), let userID else { return }

        for channel in ChannelCatalog.channels {
            UserDefaults.userSuite(id: userID).removeObject(forKey: storageKey(for: channel))
            states[cacheKey(for: channel, userID: userID)] = nil
        }
    }
    #endif
}
