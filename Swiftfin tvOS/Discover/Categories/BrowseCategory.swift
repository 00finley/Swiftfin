//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What one category asks of TMDB's `/discover` endpoint for one media type.
///
/// Within a category, lists are alternatives (any genre, any keyword). Combining categories
/// narrows the results: see `BrowseQuery`.
struct BrowseClause: Hashable {

    var genres: [Int] = []
    var keywords: [Int] = []
    var withoutGenres: [Int] = []
    var withoutKeywords: [Int] = []
    /// ISO 639-1 original languages
    var languages: [String] = []
    /// ISO 3166-1 origin countries
    var countries: [String] = []
    var providers: [Int] = []
    var years: ClosedRange<Int>?
    var minRuntime: Int?
    var maxRuntime: Int?
    var minRating: Double?
    var minVotes: Int?
    var maxVotes: Int?
    /// US certification ceiling (movies), e.g. "PG"
    var certification: String?
}

/// A browsable category: a genre, mood, format, era, language, service...
struct BrowseCategory: Identifiable, Hashable {

    enum Group: String, CaseIterable, Identifiable {
        case genres
        case moods
        case formats
        case eras
        case acclaimed
        case languages
        case services
        case family

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .genres: L10n.categoriesGenres
            case .moods: L10n.categoriesMoods
            case .formats: L10n.categoriesFormats
            case .eras: L10n.categoriesEras
            case .acclaimed: L10n.categoriesAcclaimed
            case .languages: L10n.categoriesLanguages
            case .services: L10n.categoriesServices
            case .family: L10n.categoriesFamily
            }
        }

        /// Groups where a title can only match one category (a decade, a language), so adding
        /// one replaces the other instead of narrowing to nothing.
        var isExclusive: Bool {
            switch self {
            case .eras, .acclaimed, .languages: true
            default: false
            }
        }
    }

    let id: String
    let title: String
    let group: Group
    let backdropPath: String?
    /// nil when the category doesn't apply to movies (e.g. Limited Series)
    let movie: BrowseClause?
    /// nil when the category doesn't apply to shows (e.g. Movies Under 100 Min)
    let tv: BrowseClause?
    /// Service logo for service tiles
    var logoPath: String?

    func clause(for kind: DiscoverTitle.Kind) -> BrowseClause? {
        kind == .movie ? movie : tv
    }

    /// A tile per streaming service, built from the user's services.
    static func service(_ provider: DiscoverProvider, logoPath: String?) -> BrowseCategory {
        BrowseCategory(
            id: "service-\(provider.id)",
            title: provider.name,
            group: .services,
            backdropPath: serviceBackdrops[provider.id],
            movie: .init(providers: [provider.id]),
            tv: .init(providers: [provider.id]),
            logoPath: logoPath
        )
    }

    /// A signature original from each service.
    private static let serviceBackdrops: [Int: String] = [
        8: "/9P4IIMYY3HifqeruZq0ZZ9g7YUi.jpg", // Stranger Things
        15: "/aJtG4txtmiRHwAAqENQHZvBs6kY.jpg", // The Bear
        337: "/9zcbqSxdsRMZWHYtyCd1nXPr2xq.jpg", // The Mandalorian
        1899: "/577eXC8wFQT0eUrJcgznSiFPRmk.jpg", // House of the Dragon
        9: "/pF0qkRsrHkdYadPWY9AMeFZfcwk.jpg", // Reacher
        350: "/ixgFmf1X59PUZam2qbAfskx2gQr.jpg", // Severance
    ]
}

/// The combination the user is browsing: categories plus the filter chips.
struct BrowseQuery: Hashable {

    enum Media: String, CaseIterable, Hashable {
        case both
        case movies
        case tv

        var kinds: [DiscoverTitle.Kind] {
            switch self {
            case .both: [.tv, .movie]
            case .movies: [.movie]
            case .tv: [.tv]
            }
        }
    }

    enum Sort: String, CaseIterable, Hashable {
        case popular
        case topRated
        case newest
    }

    var categories: [BrowseCategory]
    var media: Media = .both
    var onMyServices = true
    var sort: Sort = .popular

    /// Adds a category; one from an exclusive group (an era, a language) replaces its sibling.
    mutating func add(_ category: BrowseCategory) {
        guard categories.contains(where: { $0.id == category.id }) == false else { return }

        if category.group.isExclusive {
            categories.removeAll { $0.group == category.group }
        }
        categories.append(category)
    }

    mutating func remove(_ category: BrowseCategory) {
        categories.removeAll { $0.id == category.id }
    }

    /// Media types the categories allow, intersected with the Movies / TV chip.
    var kinds: [DiscoverTitle.Kind] {
        media.kinds.filter { kind in categories.allSatisfy { $0.clause(for: kind) != nil } }
    }

    /// `/discover` parameters for one media type, or nil when the combination can't match anything
    /// for it (e.g. Korean + British, or a TV-only format with Movies).
    ///
    /// TMDB can't nest AND and OR in one parameter, so a category's alternatives are kept only when
    /// it's the sole category using that parameter; otherwise each contributes its main value and
    /// they must all match (Thriller + Heists = thriller AND heist).
    func parameters(
        for kind: DiscoverTitle.Kind,
        myProviders: [Int],
        region: String,
        today: Date = .now
    ) -> [String: String]? {
        let clauses = categories.compactMap { $0.clause(for: kind) }
        guard clauses.count == categories.count, media.kinds.contains(kind) else { return nil }

        var query: [String: String] = [:]

        func combine(_ lists: [[Int]]) -> String? {
            let lists = lists.filter(\.isNotEmpty)
            if lists.count == 1 {
                return lists[0].map(String.init).joined(separator: "|")
            }
            return lists.isEmpty ? nil : lists.compactMap(\.first).map(String.init).joined(separator: ",")
        }

        /// Values every contributing category accepts; nil when they share none.
        func intersect(_ lists: [[String]]) -> [String]?? {
            let lists = lists.filter(\.isNotEmpty)
            guard var common = lists.first else { return .some(nil) }

            for list in lists.dropFirst() {
                common = common.filter(list.contains)
            }
            return common.isEmpty ? nil : .some(common)
        }

        query["with_genres"] = combine(clauses.map(\.genres))
        query["with_keywords"] = combine(clauses.map(\.keywords))

        let withoutGenres = Set(clauses.flatMap(\.withoutGenres)).sorted()
        if withoutGenres.isNotEmpty {
            query["without_genres"] = withoutGenres.map(String.init).joined(separator: ",")
        }
        let withoutKeywords = Set(clauses.flatMap(\.withoutKeywords)).sorted()
        if withoutKeywords.isNotEmpty {
            query["without_keywords"] = withoutKeywords.map(String.init).joined(separator: ",")
        }

        guard let languages = intersect(clauses.map(\.languages)) else { return nil }

        if let languages {
            query["with_original_language"] = languages.joined(separator: "|")
        }
        guard let countries = intersect(clauses.map(\.countries)) else { return nil }

        if let countries {
            query["with_origin_country"] = countries.joined(separator: "|")
        }

        // Services: a service category picks that service; otherwise the chip limits to the user's own
        let categoryProviders = Set(clauses.flatMap(\.providers))
        let providers = categoryProviders.isNotEmpty ? Array(categoryProviders).sorted() : (onMyServices ? myProviders : [])
        if providers.isNotEmpty {
            query["with_watch_providers"] = providers.map(String.init).joined(separator: "|")
            query["watch_region"] = region
            query["with_watch_monetization_types"] = "flatrate"
        }

        // Dates
        let dateKey = kind == .movie ? "primary_release_date" : "first_air_date"
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: today)
        let lower = clauses.compactMap(\.years?.lowerBound).max()
        var upper = clauses.compactMap(\.years?.upperBound).min()
        if let lower, let upper, lower > upper {
            return nil
        }
        // Newest means released already, not announced for 2029
        if sort == .newest {
            upper = min(upper ?? currentYear, currentYear)
        }
        if let lower {
            query["\(dateKey).gte"] = "\(lower)-01-01"
        }
        if let upper {
            query["\(dateKey).lte"] = upper >= currentYear ? DiscoverTitle.dateFormatter.string(from: today) : "\(upper)-12-31"
        }

        // Runtime
        let minRuntime = clauses.compactMap(\.minRuntime).max()
        let maxRuntime = clauses.compactMap(\.maxRuntime).min()
        if let minRuntime, let maxRuntime, minRuntime > maxRuntime {
            return nil
        }
        if let minRuntime {
            query["with_runtime.gte"] = String(minRuntime)
        }
        if let maxRuntime {
            query["with_runtime.lte"] = String(maxRuntime)
        }

        // Ratings and votes; Top Rated needs a vote floor or it's all one-vote 10s
        let maxVotes = clauses.compactMap(\.maxVotes).min()
        var minVotes = clauses.compactMap(\.minVotes).max()
        if maxVotes == nil {
            switch sort {
            case .topRated: minVotes = max(minVotes ?? 0, kind == .movie ? 300 : 150)
            case .newest: minVotes = max(minVotes ?? 0, 10)
            case .popular: break
            }
        }
        if let minVotes, let maxVotes, minVotes > maxVotes {
            return nil
        }
        if let minVotes {
            query["vote_count.gte"] = String(minVotes)
        }
        if let maxVotes {
            query["vote_count.lte"] = String(maxVotes)
        }
        if let minRating = clauses.compactMap(\.minRating).max() {
            query["vote_average.gte"] = String(minRating)
        }

        if kind == .movie, let certification = clauses.compactMap(\.certification).min(by: Self.isStricter) {
            query["certification_country"] = "US"
            query["certification.lte"] = certification
        }

        query["sort_by"] = switch sort {
        case .popular: "popularity.desc"
        case .topRated: "vote_average.desc"
        case .newest: "\(dateKey).desc"
        }

        return query
    }

    private static let certificationOrder = ["G", "PG", "PG-13", "R", "NC-17"]

    private static func isStricter(_ lhs: String, _ rhs: String) -> Bool {
        (certificationOrder.firstIndex(of: lhs) ?? 99) < (certificationOrder.firstIndex(of: rhs) ?? 99)
    }
}
