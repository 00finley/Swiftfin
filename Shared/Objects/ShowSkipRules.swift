//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI

/// Skip or watch a show's intro or credits.
enum ShowSkipChoice: String, CaseIterable, Codable, Hashable, Displayable {

    case skip
    case watch

    var displayTitle: String {
        switch self {
        case .skip:
            L10n.skip
        case .watch:
            L10n.watch
        }
    }
}

/// A per-series exception to the global skip segment settings, stored per user in Defaults.
///
/// A stored rule means the user has decided about this show, so a pre-seeded exception for it no
/// longer applies (a rule with neither part set keeps the show on the global defaults).
struct ShowSkipRule: Storable, Hashable {

    /// The series name, for Settings > Show Exceptions
    var seriesName: String
    /// nil follows the global setting
    var intro: ShowSkipChoice?
    /// nil follows the global setting
    var credits: ShowSkipChoice?

    var isDefault: Bool {
        intro == nil && credits == nil
    }
}

/// A show's resolved intro and credits choices.
struct ResolvedShowSkipRule: Equatable {

    enum Source: Equatable {
        /// No exception: the global skip settings
        case global
        /// One of Glassfin's pre-seeded exceptions
        case seeded
        /// The user's own choice
        case custom
    }

    var intro: ShowSkipChoice
    var credits: ShowSkipChoice
    var source: Source

    var isException: Bool {
        intro != ShowSkipRules.defaultChoice(for: .intro) || credits != ShowSkipRules.defaultChoice(for: .outro)
    }
}

/// Per-show intro / credits rules on top of the global skip segment settings.
///
/// - Intro "Watch": no auto skip and no skip button; the player shows a "Watching intro" chip.
/// - Credits "Watch": no credits skip and no countdown at the credits; the next episode
///   countdown and autoplay wait for the real end of the file.
/// - Recaps always skip in episodes (unless recaps are disabled globally).
@MainActor
enum ShowSkipRules {

    /// Exceptions that ship with Glassfin, matched by the series' TMDB, TVDB or IMDb id so they
    /// work on any server. They apply until the user changes that show.
    struct Seed: Hashable {

        let name: String
        let tmdb: String
        let tvdb: String
        let imdb: String
        let intro: ShowSkipChoice?
        let credits: ShowSkipChoice?

        func matches(_ providerIDs: [String: String]) -> Bool {
            let ids = Dictionary(providerIDs.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            return ids["tmdb"] == tmdb || ids["tvdb"] == tvdb || ids["imdb"] == imdb
        }
    }

    /// IDs verified against TMDB (with its TVDB and IMDb external ids) on 2026-10-16.
    static let seeds: [Seed] = [
        Seed(name: "Bob's Burgers", tmdb: "32726", tvdb: "194031", imdb: "tt1561755", intro: .watch, credits: .watch),
        Seed(name: "American Dad!", tmdb: "1433", tvdb: "73141", imdb: "tt0397306", intro: .watch, credits: nil),
        Seed(name: "Community", tmdb: "18347", tvdb: "94571", imdb: "tt1439629", intro: nil, credits: .watch),
        Seed(name: "Arrested Development", tmdb: "4589", tvdb: "72173", imdb: "tt0367279", intro: nil, credits: .watch),
        Seed(name: "Rick and Morty", tmdb: "60625", tvdb: "275274", imdb: "tt2861424", intro: nil, credits: .watch),
        Seed(name: "X-Men '97", tmdb: "138502", tvdb: "412432", imdb: "tt16026746", intro: nil, credits: .watch),
        Seed(name: "Agatha All Along", tmdb: "138501", tvdb: "412429", imdb: "tt15571732", intro: nil, credits: .watch),
        Seed(name: "The Simpsons", tmdb: "456", tvdb: "71663", imdb: "tt0096697", intro: .watch, credits: nil),
    ]

    /// Series provider ids fetched for episodes (whose own item doesn't carry the series' ids)
    private static var providerIDCache: [String: [String: String]] = [:]

    // MARK: - Defaults

    /// Skip unless that segment type is disabled in the global settings.
    nonisolated static func defaultChoice(for type: MediaSegmentType) -> ShowSkipChoice {
        type.behavior == .off ? .watch : .skip
    }

    static var rules: [String: ShowSkipRule] {
        get { Defaults[.VideoPlayer.MediaSegments.showRules] }
        set { Defaults[.VideoPlayer.MediaSegments.showRules] = newValue }
    }

    static func seed(for providerIDs: [String: String]?) -> Seed? {
        guard let providerIDs, providerIDs.isNotEmpty else { return nil }

        return seeds.first { $0.matches(providerIDs) }
    }

    // MARK: - Resolving

    /// The rule for a series, given its provider ids when known.
    static func resolve(seriesID: String?, providerIDs: [String: String]?) -> ResolvedShowSkipRule {
        let introDefault = defaultChoice(for: .intro)
        let creditsDefault = defaultChoice(for: .outro)

        guard let seriesID else {
            return ResolvedShowSkipRule(intro: introDefault, credits: creditsDefault, source: .global)
        }

        if let rule = rules[seriesID] {
            return ResolvedShowSkipRule(
                intro: rule.intro ?? introDefault,
                credits: rule.credits ?? creditsDefault,
                source: rule.isDefault ? .global : .custom
            )
        }

        if let seed = seed(for: providerIDs ?? providerIDCache[seriesID]) {
            return ResolvedShowSkipRule(
                intro: seed.intro ?? introDefault,
                credits: seed.credits ?? creditsDefault,
                source: .seeded
            )
        }

        return ResolvedShowSkipRule(intro: introDefault, credits: creditsDefault, source: .global)
    }

    /// The rule for the series an item belongs to (the series itself or one of its episodes).
    /// Fetches the series' provider ids for episodes when a seed might apply.
    static func resolve(for item: BaseItemDto) async -> ResolvedShowSkipRule {
        let seriesID = item.type == .series ? item.id : item.seriesID
        guard let seriesID else {
            return resolve(seriesID: nil, providerIDs: nil)
        }

        if item.type == .series, let providerIDs = item.providerIDs {
            providerIDCache[seriesID] = providerIDs
        } else if rules[seriesID] == nil, providerIDCache[seriesID] == nil {
            providerIDCache[seriesID] = await fetchProviderIDs(seriesID: seriesID)
        }

        return resolve(seriesID: seriesID, providerIDs: providerIDCache[seriesID])
    }

    /// The series' provider ids, once `resolve(for:)` has looked them up.
    static func cachedProviderIDs(seriesID: String) -> [String: String]? {
        providerIDCache[seriesID]
    }

    /// nil when the request fails, so a later resolve tries again
    private static func fetchProviderIDs(seriesID: String) async -> [String: String]? {
        guard let session = Container.shared.currentUserSession() else { return nil }

        do {
            let response = try await session.client.send(Paths.getItem(itemID: seriesID, userID: session.user.id))
            return response.value.providerIDs ?? [:]
        } catch {
            return nil
        }
    }

    // MARK: - Changing

    /// Sets one part of a show's rule. Choosing the global default stores no override for that part,
    /// but the stored rule still marks the show as decided, so its seed no longer applies.
    static func set(
        _ choice: ShowSkipChoice,
        for type: MediaSegmentType,
        seriesID: String,
        seriesName: String,
        providerIDs: [String: String]? = nil
    ) {
        let current = resolve(seriesID: seriesID, providerIDs: providerIDs)
        var rule = rules[seriesID] ?? ShowSkipRule(seriesName: seriesName)

        // Adopt the seeded values the user didn't touch, so changing one part keeps the other
        if rules[seriesID] == nil, current.source == .seeded {
            rule.intro = current.intro == defaultChoice(for: .intro) ? nil : current.intro
            rule.credits = current.credits == defaultChoice(for: .outro) ? nil : current.credits
        }

        let stored: ShowSkipChoice? = choice == defaultChoice(for: type) ? nil : choice
        switch type {
        case .intro:
            rule.intro = stored
        case .outro:
            rule.credits = stored
        default:
            return
        }

        rule.seriesName = seriesName
        rules[seriesID] = rule
    }

    /// Back to the global settings. A seeded show keeps an empty rule so its seed stays off.
    static func reset(seriesID: String, providerIDs: [String: String]? = nil) {
        if seed(for: providerIDs ?? providerIDCache[seriesID]) != nil {
            rules[seriesID] = ShowSkipRule(seriesName: rules[seriesID]?.seriesName ?? "")
        } else {
            rules[seriesID] = nil
        }
    }
}

// MARK: - Segment behavior for an item

extension MediaSegmentType {

    /// What the player does in this segment for an item of a series with `rule`.
    ///
    /// `nil` means "watch": no skip, no button (intro and credits only).
    func behavior(with rule: ResolvedShowSkipRule?) -> MediaSegmentBehavior? {
        let global = behavior

        guard let rule else { return global }

        switch self {
        case .intro:
            guard rule.intro == .skip else { return nil }

            return global == .off ? .autoSkip : global

        case .outro:
            guard rule.credits == .skip else { return nil }

            return global == .off ? .showButton : global

        case .recap:
            // Recaps always skip in episodes, unless recaps are disabled
            return global == .off ? .off : .autoSkip

        default:
            return global
        }
    }
}
