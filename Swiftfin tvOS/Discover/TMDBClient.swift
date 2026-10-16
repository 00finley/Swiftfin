//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CryptoKit
import Foundation

/// Minimal TMDB v3 client for Discover: bearer auth, 24h memory + disk cache, limited concurrency.
actor TMDBClient {

    static let shared = TMDBClient()

    /// The personal API Read Access Token, compiled in from the private xcconfig (`TMDB_READ_TOKEN`).
    nonisolated static var token: String? {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "TMDBReadAccessToken") as? String,
              token.isEmpty == false,
              token.contains("$(") == false
        else { return nil }

        return token
    }

    nonisolated static var isAvailable: Bool {
        token != nil
    }

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let cacheTTL: TimeInterval = 24 * 60 * 60
    private let maxConcurrentRequests = 6

    private var memoryCache: [String: (date: Date, data: Data)] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private lazy var diskCacheURL: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiscoverTMDB", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: - Endpoints

    func trending() async throws -> [DiscoverTitle] {
        try await list("trending/all/week", kind: nil)
    }

    /// Recently released or currently airing titles on the given services.
    func newOnServices(providers: [Int], region: String) async throws -> [DiscoverTitle] {
        guard providers.isNotEmpty else { return [] }

        let today = Date.now
        let services = providers.map(String.init).joined(separator: "|")

        async let shows = list("discover/tv", kind: .tv, query: [
            "with_watch_providers": services,
            "watch_region": region,
            "with_watch_monetization_types": "flatrate",
            "air_date.gte": Self.day(today.addingTimeInterval(-30 * 86400)),
            "air_date.lte": Self.day(today),
            "sort_by": "popularity.desc",
        ])
        async let movies = list("discover/movie", kind: .movie, query: [
            "with_watch_providers": services,
            "watch_region": region,
            "with_watch_monetization_types": "flatrate",
            "primary_release_date.gte": Self.day(today.addingTimeInterval(-150 * 86400)),
            "primary_release_date.lte": Self.day(today),
            "sort_by": "popularity.desc",
        ])

        return try await Self.interleave(shows, movies)
    }

    /// Upcoming shows from the services' networks and upcoming digital movie releases.
    func comingSoon(providers: [Int], region: String) async throws -> [DiscoverTitle] {
        let today = Date.now
        let networks = providers.compactMap { DiscoverProvider.networksByProvider[$0] }.map(String.init).joined(separator: "|")

        async let shows = networks.isEmpty ? [] : list("discover/tv", kind: .tv, query: [
            "with_networks": networks,
            "first_air_date.gte": Self.day(today.addingTimeInterval(86400)),
            "first_air_date.lte": Self.day(today.addingTimeInterval(120 * 86400)),
            "sort_by": "popularity.desc",
        ])
        async let movies = list("discover/movie", kind: .movie, query: [
            "region": region,
            "with_release_type": "4",
            "release_date.gte": Self.day(today.addingTimeInterval(86400)),
            "release_date.lte": Self.day(today.addingTimeInterval(90 * 86400)),
            "sort_by": "popularity.desc",
        ])

        return try await Self.interleave(shows, movies)
    }

    /// Streaming services (flat-rate) for a title in a region.
    func providers(for title: DiscoverTitle, region: String) async throws -> [DiscoverProvider] {
        let data = try await get("\(title.kind.rawValue)/\(title.tmdbID)/watch/providers")
        let response = try JSONDecoder().decode(ProvidersResponse.self, from: data)
        return (response.results[region]?.flatrate ?? []).map(\.provider)
    }

    /// Full details with images, keywords, recommendations, similar titles and providers in one request.
    func details(kind: DiscoverTitle.Kind, id: Int) async throws -> TMDBDetails {
        let ratings = kind == .tv ? "content_ratings" : "release_dates"
        let data = try await get("\(kind.rawValue)/\(id)", query: [
            "append_to_response": "images,keywords,recommendations,similar,watch/providers,\(ratings)",
            "include_image_language": "en,null",
        ])
        return try TMDBDetails(data: data, kind: kind)
    }

    func genres() async throws -> [Int: String] {
        async let tv = get("genre/tv/list")
        async let movie = get("genre/movie/list")
        let lists = try await [tv, movie].map { try JSONDecoder().decode(GenreList.self, from: $0).genres }
        return Dictionary(lists.flatMap(\.self).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// One page of `/discover/movie` or `/discover/tv` results.
    func discover(kind: DiscoverTitle.Kind, query: [String: String], page: Int) async throws -> TMDBPage {
        var query = query
        query["page"] = String(page)
        query["include_adult"] = "false"
        return try await self.page("discover/\(kind.rawValue)", kind: kind, query: query)
    }

    /// Movies and shows matching a title search (people are skipped).
    func search(_ text: String, page: Int) async throws -> TMDBPage {
        try await self.page("search/multi", kind: nil, query: [
            "query": text,
            "page": String(page),
            "include_adult": "false",
        ])
    }

    /// Logo artwork for streaming services in a region, keyed by provider id.
    func providerLogos(region: String) async throws -> [Int: String] {
        async let tv = get("watch/providers/tv", query: ["watch_region": region])
        async let movie = get("watch/providers/movie", query: ["watch_region": region])
        var logos: [Int: String] = [:]
        for data in try await [tv, movie] {
            for provider in try JSONDecoder().decode(ProviderList.self, from: data).results {
                if let path = provider.logo_path {
                    logos[provider.provider_id] = logos[provider.provider_id] ?? path
                }
            }
        }
        return logos
    }

    func clearCache() {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: diskCacheURL)
    }

    // MARK: - Images

    nonisolated static func imageURL(_ path: String?, size: String) -> URL? {
        guard let path, path.isNotEmpty else { return nil }

        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // MARK: - Requests

    private func list(_ path: String, kind: DiscoverTitle.Kind?, query: [String: String] = [:]) async throws -> [DiscoverTitle] {
        let data = try await get(path, query: query)
        return try JSONDecoder().decode(ListResponse.self, from: data).results.compactMap { $0.title(defaultKind: kind) }
    }

    private func page(_ path: String, kind: DiscoverTitle.Kind?, query: [String: String]) async throws -> TMDBPage {
        let data = try await get(path, query: query)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        return TMDBPage(
            titles: response.results.compactMap { $0.title(defaultKind: kind) },
            page: response.page ?? 1,
            totalPages: min(response.total_pages ?? 1, 500)
        )
    }

    private func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = (query.merging(["language": "en-US"]) { current, _ in current })
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let url = components.url!
        let key = url.absoluteString

        if let cached = memoryCache[key], Date.now.timeIntervalSince(cached.date) < cacheTTL {
            return cached.data
        }
        if let disk = diskCached(key) {
            memoryCache[key] = disk
            return disk.data
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { try await self.fetch(url) }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let data = try await task.value
        memoryCache[key] = (.now, data)
        try? data.write(to: diskCacheFile(key))
        return data
    }

    private func fetch(_ url: URL) async throws -> Data {
        guard let token = Self.token else { throw URLError(.userAuthenticationRequired) }

        await acquire()
        defer { release() }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func acquire() async {
        if activeRequests < maxConcurrentRequests {
            activeRequests += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isNotEmpty {
            waiters.removeFirst().resume()
        } else {
            activeRequests -= 1
        }
    }

    private func diskCacheFile(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskCacheURL.appendingPathComponent(hash + ".json")
    }

    private func diskCached(_ key: String) -> (date: Date, data: Data)? {
        let file = diskCacheFile(key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) < cacheTTL,
              let data = try? Data(contentsOf: file)
        else { return nil }

        return (modified, data)
    }

    private static func day(_ date: Date) -> String {
        DiscoverTitle.dateFormatter.string(from: date)
    }

    private static func interleave(_ first: [DiscoverTitle], _ second: [DiscoverTitle]) -> [DiscoverTitle] {
        var result: [DiscoverTitle] = []
        for index in 0 ..< max(first.count, second.count) {
            if index < first.count {
                result.append(first[index])
            }
            if index < second.count {
                result.append(second[index])
            }
        }
        return result
    }
}

// MARK: - Response types

private struct ListResponse: Decodable {
    let results: [RawTitle]
    let page: Int?
    let total_pages: Int?
}

/// One page of list results; TMDB caps paging at 500 pages.
struct TMDBPage {
    let titles: [DiscoverTitle]
    let page: Int
    let totalPages: Int

    var hasMore: Bool {
        page < totalPages
    }
}

private struct ProviderList: Decodable {
    let results: [RawProvider]
}

struct RawTitle: Decodable {

    let id: Int
    let media_type: String?
    let title: String?
    let name: String?
    let overview: String?
    let backdrop_path: String?
    let poster_path: String?
    let release_date: String?
    let first_air_date: String?
    let genre_ids: [Int]?
    let popularity: Double?
    let vote_average: Double?
    let vote_count: Int?

    func title(defaultKind: DiscoverTitle.Kind?) -> DiscoverTitle? {
        let kind: DiscoverTitle.Kind
        switch media_type {
        case "movie": kind = .movie

        case "tv": kind = .tv

        case nil:
            guard let defaultKind else { return nil }

            kind = defaultKind

        default:
            return nil
        }

        guard let name = title ?? name, name.isNotEmpty else { return nil }

        return DiscoverTitle(
            kind: kind,
            tmdbID: id,
            title: name,
            overview: overview,
            backdropPath: backdrop_path,
            posterPath: poster_path,
            date: (release_date ?? first_air_date).flatMap { $0.isEmpty ? nil : $0 },
            genreIDs: genre_ids ?? [],
            popularity: popularity ?? 0,
            voteAverage: vote_average ?? 0,
            voteCount: vote_count ?? 0
        )
    }
}

private struct ProvidersResponse: Decodable {

    struct Region: Decodable {
        let flatrate: [RawProvider]?
    }

    let results: [String: Region]
}

private struct RawProvider: Decodable {

    let provider_id: Int
    let provider_name: String
    let logo_path: String?

    var provider: DiscoverProvider {
        DiscoverProvider(id: provider_id, name: provider_name, logoPath: logo_path)
    }
}

private struct GenreList: Decodable {

    struct Genre: Decodable {
        let id: Int
        let name: String
    }

    let genres: [Genre]
}

/// Details for one title, decoded from a single appended request.
struct TMDBDetails {

    let title: DiscoverTitle
    let genres: [(id: Int, name: String)]
    let keywords: [Int]
    let logoPath: String?
    /// Key art without a title treatment (language-neutral poster), for tall feature cards.
    let textlessPosterPath: String?
    let recommendations: [DiscoverTitle]
    let similar: [DiscoverTitle]
    let providersByRegion: [String: [DiscoverProvider]]
    let certificationsByRegion: [String: String]
    let runtimeMinutes: Int?
    let seasons: Int?

    init(data: Data, kind: DiscoverTitle.Kind) throws {
        let raw = try JSONDecoder().decode(RawDetails.self, from: data)

        title = DiscoverTitle(
            kind: kind,
            tmdbID: raw.id,
            title: raw.title ?? raw.name ?? "",
            overview: raw.overview,
            backdropPath: raw.backdrop_path,
            posterPath: raw.poster_path,
            date: (raw.release_date ?? raw.first_air_date).flatMap { $0.isEmpty ? nil : $0 },
            genreIDs: raw.genres?.map(\.id) ?? [],
            popularity: raw.popularity ?? 0,
            voteAverage: raw.vote_average ?? 0,
            voteCount: raw.vote_count ?? 0
        )
        genres = raw.genres?.map { ($0.id, $0.name) } ?? []
        keywords = (raw.keywords?.keywords ?? raw.keywords?.results ?? []).map(\.id)
        logoPath = raw.images?.logos?.first(where: { $0.iso_639_1 == "en" })?.file_path ?? raw.images?.logos?.first?.file_path
        textlessPosterPath = raw.images?.posters?.first(where: { $0.iso_639_1 == nil })?.file_path
        recommendations = raw.recommendations?.results.compactMap { $0.title(defaultKind: kind) } ?? []
        similar = raw.similar?.results.compactMap { $0.title(defaultKind: kind) } ?? []
        providersByRegion = (raw.watchProviders?.results ?? [:]).mapValues { ($0.flatrate ?? []).map(\.provider) }

        var certifications: [String: String] = [:]
        for rating in raw.content_ratings?.results ?? [] where rating.rating.isNotEmpty {
            certifications[rating.iso_3166_1] = rating.rating
        }
        for release in raw.release_dates?.results ?? [] {
            if let certification = release.release_dates.map(\.certification).first(where: \.isNotEmpty) {
                certifications[release.iso_3166_1] = certification
            }
        }
        certificationsByRegion = certifications
        runtimeMinutes = raw.runtime ?? raw.episode_run_time?.first
        seasons = raw.number_of_seasons
    }
}

private struct RawDetails: Decodable {

    struct Named: Decodable {
        let id: Int
        let name: String
    }

    struct Keywords: Decodable {
        let keywords: [Named]?
        let results: [Named]?
    }

    struct Images: Decodable {
        struct Image: Decodable {
            let file_path: String
            let iso_639_1: String?
        }

        let logos: [Image]?
        let posters: [Image]?
    }

    struct Page: Decodable {
        let results: [RawTitle]
    }

    struct ContentRatings: Decodable {
        struct Rating: Decodable {
            let iso_3166_1: String
            let rating: String
        }

        let results: [Rating]
    }

    struct ReleaseDates: Decodable {
        struct Country: Decodable {
            struct Release: Decodable {
                let certification: String
            }

            let iso_3166_1: String
            let release_dates: [Release]
        }

        let results: [Country]
    }

    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let backdrop_path: String?
    let poster_path: String?
    let release_date: String?
    let first_air_date: String?
    let genres: [Named]?
    let popularity: Double?
    let vote_average: Double?
    let vote_count: Int?
    let runtime: Int?
    let episode_run_time: [Int]?
    let number_of_seasons: Int?
    let images: Images?
    let keywords: Keywords?
    let recommendations: Page?
    let similar: Page?
    let watchProviders: ProvidersResponse?
    let content_ratings: ContentRatings?
    let release_dates: ReleaseDates?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case backdrop_path
        case poster_path
        case release_date
        case first_air_date
        case genres
        case popularity
        case vote_average
        case vote_count
        case runtime
        case episode_run_time
        case number_of_seasons
        case images
        case keywords
        case recommendations
        case similar
        case content_ratings
        case release_dates
        case watchProviders = "watch/providers"
    }
}
