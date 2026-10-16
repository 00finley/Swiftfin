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

/// What Discover has learned from the user's choices, stored per user on device.
struct DiscoverProfile: Codable, Hashable, Defaults.Serializable {

    /// Titles the user asked for "More Like This" on, used as extra recommendation seeds.
    var liked: [String: DiscoverTitle] = [:]
    /// Titles hidden with "Not Interested".
    var dismissed: Set<String> = []
    /// Genre adjustments from feedback (positive = more, negative = less).
    var genreFeedback: [Int: Double] = [:]
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
