//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

/// A movie or show from TMDB, as shown in Discover.
struct DiscoverTitle: Hashable, Codable, Identifiable {

    enum Kind: String, Codable, Hashable {
        case movie
        case tv
    }

    let kind: Kind
    let tmdbID: Int
    let title: String
    let overview: String?
    let backdropPath: String?
    let posterPath: String?
    /// `release_date` for movies, `first_air_date` for shows (yyyy-MM-dd)
    let date: String?
    let genreIDs: [Int]
    let popularity: Double
    let voteAverage: Double
    let voteCount: Int

    var id: String {
        "\(kind.rawValue)-\(tmdbID)"
    }

    var year: String? {
        guard let date, date.count >= 4 else { return nil }

        return String(date.prefix(4))
    }

    var releaseDate: Date? {
        guard let date else { return nil }

        return DiscoverTitle.dateFormatter.date(from: date)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

/// A streaming service a title is available on.
struct DiscoverProvider: Hashable, Codable, Identifiable {

    let id: Int
    let name: String
    let logoPath: String?

    /// The services offered in Settings, in display order.
    static let supported: [DiscoverProvider] = [
        .init(id: 8, name: "Netflix", logoPath: nil),
        .init(id: 15, name: "Hulu", logoPath: nil),
        .init(id: 337, name: "Disney+", logoPath: nil),
        .init(id: 1899, name: "HBO Max", logoPath: nil),
        .init(id: 9, name: "Prime Video", logoPath: nil),
        .init(id: 350, name: "Apple TV+", logoPath: nil),
    ]

    /// TV networks matching the supported services, used to find upcoming shows
    /// that have no streaming availability yet.
    static let networksByProvider: [Int: Int] = [
        8: 213, // Netflix
        15: 453, // Hulu
        337: 2739, // Disney+
        1899: 49, // HBO
        9: 1024, // Amazon
        350: 2552, // Apple TV+
    ]
}

/// One horizontal row in Discover.
struct DiscoverRow: Identifiable, Hashable {

    enum Kind: Hashable {
        case topPicks
        case becauseYouWatched(String)
        /// "Because You Loved X" / "Because You Liked X", from ratings and the seed list
        case becauseYouRated(String)
        case newOnServices
        case trending
        case comingSoon
        case moreLikeThis
    }

    let kind: Kind
    let title: String
    let items: [DiscoverItem]

    var id: String {
        switch kind {
        case .topPicks: "top-picks"
        case let .becauseYouWatched(seed): "because-\(seed)"
        case let .becauseYouRated(seed): "rated-\(seed)"
        case .newOnServices: "new"
        case .trending: "trending"
        case .comingSoon: "coming-soon"
        case .moreLikeThis: "more-like-this"
        }
    }
}

/// A title plus everything Discover knows about it for display.
struct DiscoverItem: Identifiable, Hashable {

    let title: DiscoverTitle
    var providers: [DiscoverProvider]
    /// Jellyfin item id when the title is already in the library.
    var libraryItemID: String?
    /// Short, human explanation of why this was suggested.
    var reason: String?

    var id: String {
        title.id
    }

    var isInLibrary: Bool {
        libraryItemID != nil
    }
}

/// How the user feels about a title.
enum DiscoverRatingLevel: Int, Codable, CaseIterable, Hashable {

    case disliked = -1
    case neutral = 0
    case liked = 1
    case loved = 2

    /// Love It first, like the choices on screen.
    static let displayOrder: [DiscoverRatingLevel] = [.loved, .liked, .neutral, .disliked]

    var title: String {
        switch self {
        case .loved: L10n.discoverRatingLoved
        case .liked: L10n.discoverRatingLiked
        case .neutral: L10n.discoverRatingNeutral
        case .disliked: L10n.discoverRatingDisliked
        }
    }

    var systemImage: String {
        switch self {
        case .loved: "heart"
        case .liked: "hand.thumbsup"
        case .neutral: "minus"
        case .disliked: "hand.thumbsdown"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .loved: "heart.fill"
        case .liked: "hand.thumbsup.fill"
        case .neutral: "minus"
        case .disliked: "hand.thumbsdown.fill"
        }
    }

    /// Weight as a recommendation seed (finished, favorited history is about 1.0-1.5).
    var seedWeight: Double {
        switch self {
        case .loved: 1.4
        case .liked: 0.8
        case .neutral, .disliked: 0
        }
    }

    /// Weight for genre and keyword affinity; negative leans away.
    var tasteWeight: Double {
        switch self {
        case .loved: 1.4
        case .liked: 0.8
        case .neutral: 0
        case .disliked: -0.8
        }
    }

    /// Seed list weights: 2 loved, 1 liked, 0 neutral, -1 disliked.
    init(seedWeight weight: Double) {
        switch weight {
        case 1.5...: self = .loved
        case 0.5 ..< 1.5: self = .liked
        case ...(-0.5): self = .disliked
        default: self = .neutral
        }
    }
}

/// One rating the user made in the app.
struct DiscoverRating: Codable, Hashable {

    var level: DiscoverRatingLevel
    /// Snapshot for Settings and taste; nil for titles hidden before ratings existed.
    var title: DiscoverTitle?
    var date: Date
}

/// A title from the build's `DISCOVER_SEED_TITLES` list: a starting rating that in-app ratings override.
///
/// Format: comma-separated `tv:<tmdbId>` or `movie:<tmdbId>`, optionally weighted `tv:1399*2`
/// (2 loved, 1 liked (default), 0 neutral, -1 disliked). No `//`: xcconfig treats it as a comment.
struct DiscoverSeedTitle: Hashable {

    let kind: DiscoverTitle.Kind
    let tmdbID: Int
    let level: DiscoverRatingLevel

    var key: String {
        "\(kind.rawValue)-\(tmdbID)"
    }

    /// Later entries for the same title win; malformed entries are skipped.
    static func parse(_ text: String) -> [DiscoverSeedTitle] {
        var order: [String] = []
        var seeds: [String: DiscoverSeedTitle] = [:]

        for token in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline }) {
            let entry = token.filter { !$0.isWhitespace }.lowercased()
            let parts = entry.split(separator: "*", maxSplits: 1).map(String.init)
            let head = parts.first?.split(separator: ":", maxSplits: 1).map(String.init) ?? []

            guard head.count == 2,
                  let kind = DiscoverTitle.Kind(rawValue: head[0] == "movies" ? "movie" : head[0]),
                  let id = Int(head[1]), id > 0
            else { continue }

            var level = DiscoverRatingLevel.liked
            if parts.count == 2 {
                guard let weight = Double(parts[1]) else { continue }

                level = DiscoverRatingLevel(seedWeight: weight)
            }

            let seed = DiscoverSeedTitle(kind: kind, tmdbID: id, level: level)
            if seeds[seed.key] == nil {
                order.append(seed.key)
            }
            seeds[seed.key] = seed
        }
        return order.compactMap { seeds[$0] }
    }

    /// From the Info.plist key `DiscoverSeedTitles` (build setting `DISCOVER_SEED_TITLES`).
    static let configured: [DiscoverSeedTitle] = {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "DiscoverSeedTitles") as? String,
              text.contains("$(") == false
        else { return [] }

        return parse(text)
    }()

    static let configuredByKey: [String: DiscoverSeedTitle] = Dictionary(
        configured.map { ($0.key, $0) },
        uniquingKeysWith: { _, last in last }
    )
}

/// A rated title from either the seed list or the app.
struct DiscoverRatedTitle: Identifiable, Hashable {

    let key: String
    let level: DiscoverRatingLevel
    let title: DiscoverTitle?
    /// From the seed list and not re-rated in the app
    let isSeed: Bool

    var id: String {
        key
    }

    var kind: DiscoverTitle.Kind? {
        DiscoverTitle.Kind(rawValue: String(key.prefix { $0 != "-" }))
    }

    var tmdbID: Int? {
        Int(key.split(separator: "-").last ?? "")
    }
}

/// What Discover has learned from the user's choices, stored per user on device.
struct DiscoverProfile: Codable, Hashable, Defaults.Serializable {

    /// Ratings keyed by TMDB key ("tv-1396"). They override the seed list; It's OK is kept only
    /// when it overrides a seeded rating.
    var ratings: [String: DiscoverRating] = [:]
    /// Genre adjustments from feedback before ratings existed (positive = more, negative = less).
    var genreFeedback: [Int: Double] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case ratings
        case genreFeedback
        // Before ratings
        case liked
        case dismissed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ratings = (try? container.decodeIfPresent([String: DiscoverRating].self, forKey: .ratings)) ?? [:]
        genreFeedback = (try? container.decodeIfPresent([Int: Double].self, forKey: .genreFeedback)) ?? [:]

        // More Like This becomes Like It; Not Interested becomes Not for Me
        if let liked = try? container.decodeIfPresent([String: DiscoverTitle].self, forKey: .liked) {
            for (key, title) in liked where ratings[key] == nil {
                ratings[key] = DiscoverRating(level: .liked, title: title, date: .now)
            }
        }
        if let dismissed = try? container.decodeIfPresent(Set<String>.self, forKey: .dismissed) {
            for key in dismissed where ratings[key] == nil {
                ratings[key] = DiscoverRating(level: .disliked, title: nil, date: .now)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ratings, forKey: .ratings)
        try container.encode(genreFeedback, forKey: .genreFeedback)
    }

    // MARK: Ratings

    /// The seed list with in-app ratings on top, including It's OK entries.
    func ratedTitles(seeds: [DiscoverSeedTitle] = DiscoverSeedTitle.configured) -> [String: DiscoverRatedTitle] {
        var result: [String: DiscoverRatedTitle] = [:]
        for seed in seeds {
            result[seed.key] = DiscoverRatedTitle(key: seed.key, level: seed.level, title: nil, isSeed: true)
        }
        for (key, rating) in ratings {
            result[key] = DiscoverRatedTitle(key: key, level: rating.level, title: rating.title, isSeed: false)
        }
        return result
    }

    func level(for key: String) -> DiscoverRatingLevel {
        ratings[key]?.level ?? DiscoverSeedTitle.configuredByKey[key]?.level ?? .neutral
    }

    /// Not for Me titles, hidden from feeds and categories.
    var hiddenKeys: Set<String> {
        var keys = Set(DiscoverSeedTitle.configured.filter { $0.level == .disliked }.map(\.key))
        for (key, rating) in ratings {
            if rating.level == .disliked {
                keys.insert(key)
            } else {
                keys.remove(key)
            }
        }
        return keys
    }

    /// Sets a rating. Picking the seeded level (or It's OK with no seed) removes the in-app rating.
    mutating func rate(_ key: String, _ level: DiscoverRatingLevel, title: DiscoverTitle?) {
        let seeded = DiscoverSeedTitle.configuredByKey[key]?.level ?? .neutral
        if level == seeded {
            ratings[key] = nil
        } else {
            ratings[key] = DiscoverRating(level: level, title: title ?? ratings[key]?.title, date: .now)
        }
    }
}

extension Defaults.Keys {

    enum Discover {

        static var providers: Key<[Int]> {
            Key("discoverProviders", default: DiscoverProvider.supported.map(\.id), suite: .currentUserSuite)
        }

        static var region: Key<String> {
            Key("discoverRegion", default: "US", suite: .currentUserSuite)
        }

        /// Discover rows (Top Picks, Because You Watched, Top 10...) below the library rows on Home.
        static var showOnHome: Key<Bool> {
            Key("discoverShowOnHome", default: true, suite: .currentUserSuite)
        }

        static var profile: Key<DiscoverProfile> {
            Key("discoverProfile", default: .init(), suite: .currentUserSuite)
        }

        /// Overrides for the build-time `SEERR_URL` / `SEERR_API_KEY`; empty means use the build values.
        static var seerrURL: Key<String> {
            Key("discoverSeerrURL", default: "", suite: .currentUserSuite)
        }

        static var seerrAPIKey: Key<String> {
            Key("discoverSeerrAPIKey", default: "", suite: .currentUserSuite)
        }
    }
}
