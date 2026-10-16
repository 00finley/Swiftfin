//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Which library shows a channel draws from by default. The user's Edit Shows changes
/// (added / removed shows) apply on top of it.
///
/// A show matches when it's named in `seriesNames`, or when the genre rule is on
/// (`anyGenres` isn't empty, or `includesAllShows`) and the show has one of `anyGenres`,
/// none of `excludedGenres`, and an official rating outside `excludedRatings`.
/// Genres and ratings compare case-insensitively.
struct ShowPoolRule: Hashable {

    /// The show has at least one of these genres
    var anyGenres: Set<String> = []
    /// The show has none of these genres
    var excludedGenres: Set<String> = []
    /// Official ratings that keep a show out, e.g. "TV-Y". A show without a rating isn't excluded.
    var excludedRatings: Set<String> = []
    /// Shows that are always in, by name
    var seriesNames: Set<String> = []
    /// Every show passes the genre part of the rule (exclusions still apply)
    var includesAllShows = false

    /// Adult Animation: Animation, and not a kids or family show.
    ///
    /// Kids' ratings (TV-Y, TV-Y7, TV-G, G) are out, but TV-PG isn't: Bob's Burgers is TV-PG on
    /// TMDB, and a rating-only rule (TV-14 / TV-MA) would drop it. The genre exclusions keep
    /// TV-PG family cartoons out instead, since TMDB tags those Kids or Family.
    static let adultAnimation = ShowPoolRule(
        anyGenres: ["Animation"],
        excludedGenres: ["Kids", "Children", "Children's", "Family"],
        excludedRatings: ["TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "G"]
    )

    func matches(_ series: BaseItemDto) -> Bool {
        if let name = series.name, seriesNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return true
        }

        guard includesAllShows || anyGenres.isNotEmpty else { return false }

        let genres = Set((series.genres ?? []).map { $0.lowercased() })

        if !includesAllShows, genres.isDisjoint(with: anyGenres.map { $0.lowercased() }) {
            return false
        }

        if !genres.isDisjoint(with: excludedGenres.map { $0.lowercased() }) {
            return false
        }

        if let rating = series.officialRating.map(Self.normalizedRating),
           excludedRatings.map(Self.normalizedRating).contains(rating)
        {
            return false
        }

        return true
    }

    /// "tv-y7 fv" and "US-TV-Y7-FV" both become "TV-Y7-FV"
    static func normalizedRating(_ rating: String) -> String {
        var value = rating
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacing(" ", with: "-")
            .replacing("_", with: "-")

        if value.hasPrefix("US-") {
            value.removeFirst(3)
        }

        return value
    }
}
