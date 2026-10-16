//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A channel plays random full episodes back to back, like a TV channel, from a pool of the
/// library's shows. It's a name, a rule for which shows it draws from, and default settings.
///
/// Adding a channel is a data change: add a `ChannelDefinition` to `ChannelCatalog.channels`.
/// The user can still add or remove shows (Edit Shows) and change its settings, per user.
struct ChannelDefinition: Identifiable, Hashable {

    /// Stable: the user's show edits, shuffle history and settings are stored under it
    let id: String
    let name: String
    let systemImage: String
    let pool: ShowPoolRule
    /// One line for the card, e.g. "Random episodes, back to back"
    var tagline: String = L10n.channelsTagline
    var defaults: ChannelSettings = .init()
}

/// Settings the user can change per channel
struct ChannelSettings: Codable, Hashable {

    /// Channel viewing writes playback progress and played state like normal playback,
    /// so it moves Next Up and Resume. Off by default.
    var countsAsWatched = false
}

enum ChannelCatalog {

    /// The channels on Home, in order
    static var channels: [ChannelDefinition] {
        var channels = [adultAnimation]

        #if DEBUG
        // UI tests: the test server has a single animated show, so a mixed channel checks
        // the shuffle across shows. Debug builds only, with `-GlassfinTestChannel`.
        if ProcessInfo.processInfo.arguments.contains("-GlassfinTestChannel") {
            channels.append(testMix)
        }
        #endif

        return channels
    }

    static func channel(id: String) -> ChannelDefinition? {
        channels.first { $0.id == id }
    }

    /// Animated shows for grown-ups: American Dad!, Bob's Burgers, Rick and Morty, Solar Opposites, ...
    static let adultAnimation = ChannelDefinition(
        id: "adult-animation",
        name: L10n.channelsAdultAnimation,
        systemImage: "sparkles.tv",
        pool: .adultAnimation
    )

    // More channels are a data change, e.g.:
    //
    // static let comfortComedies = ChannelDefinition(
    //     id: "comfort-comedies",
    //     name: "Comfort Comedies",
    //     systemImage: "sofa.fill",
    //     pool: ShowPoolRule(anyGenres: ["Comedy"], excludedGenres: ["Animation", "Kids"])
    // )
    //
    // static let bakeOffAllDay = ChannelDefinition(
    //     id: "bake-off-all-day",
    //     name: "Bake Off All Day",
    //     systemImage: "birthday.cake.fill",
    //     pool: ShowPoolRule(seriesNames: ["The Great British Bake Off"])
    // )

    #if DEBUG
    static let testMix = ChannelDefinition(
        id: "test-mix",
        name: "Test Mix",
        systemImage: "testtube.2",
        pool: ShowPoolRule(includesAllShows: true)
    )
    #endif
}
