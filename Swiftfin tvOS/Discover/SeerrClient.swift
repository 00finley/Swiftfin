//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

/// Where a title stands in Seerr (`mediaInfo.status`, plus pending requests).
enum SeerrStatus: Equatable {

    case notRequested
    case requested
    case processing
    case partiallyAvailable
    case available

    var badgeTitle: String? {
        switch self {
        case .notRequested: nil
        case .requested: L10n.seerrRequested
        case .processing: L10n.seerrDownloading
        case .partiallyAvailable: L10n.seerrPartiallyAvailable
        case .available: L10n.seerrAvailable
        }
    }

    var systemImage: String {
        switch self {
        case .notRequested: "plus"
        case .requested: "clock"
        case .processing: "arrow.down.circle"
        case .partiallyAvailable: "circle.lefthalf.filled"
        case .available: "checkmark"
        }
    }
}

enum SeerrError: LocalizedError {

    case notConfigured
    case unreachable
    case unauthorized
    case alreadyRequested
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured, .unreachable: L10n.seerrErrorUnreachable
        case .unauthorized: L10n.seerrErrorUnauthorized
        case .alreadyRequested: L10n.seerrErrorAlreadyRequested
        case .server: L10n.seerrErrorGeneric
        }
    }
}

/// Minimal Seerr (Overseerr/Jellyseerr-compatible v1 API) client for Discover requests.
///
/// Configuration comes from the private xcconfig (`SEERR_URL`, `SEERR_API_KEY`, compiled into Info.plist)
/// so nothing has to be typed on the TV; Settings → Discover → Requests can override both.
actor SeerrClient {

    static let shared = SeerrClient()

    struct Configuration: Equatable {
        let baseURL: URL
        let apiKey: String
    }

    nonisolated static var configuration: Configuration? {
        let url = nonEmpty(Defaults[.Discover.seerrURL]) ?? infoValue("SeerrURL")
        let key = nonEmpty(Defaults[.Discover.seerrAPIKey]) ?? infoValue("SeerrAPIKey")

        guard var url, let key else { return nil }

        // xcconfig treats "//" as a comment, so the build setting is usually written without a scheme
        if url.contains("://") == false {
            url = "http://" + url
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        guard let baseURL = URL(string: url), baseURL.scheme?.hasPrefix("http") == true else { return nil }

        return Configuration(baseURL: baseURL, apiKey: key)
    }

    nonisolated static var isConfigured: Bool {
        configuration != nil
    }

    private nonisolated static func infoValue(_ key: String) -> String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false,
              value.contains("$(") == false
        else { return nil }

        return value
    }

    private let cacheTTL: TimeInterval = 5 * 60
    private var cache: [String: (date: Date, status: SeerrStatus)] = [:]
    private var inFlight: [String: Task<SeerrStatus, Error>] = [:]

    // MARK: - API

    /// `GET /api/v1/status`, used by Settings to test the connection.
    func ping() async throws {
        _ = try await send("GET", path: "status")
    }

    func status(for title: DiscoverTitle, refresh: Bool = false) async throws -> SeerrStatus {
        if !refresh, let cached = cache[title.id], Date.now.timeIntervalSince(cached.date) < cacheTTL {
            return cached.status
        }
        if let task = inFlight[title.id] {
            return try await task.value
        }

        let task = Task<SeerrStatus, Error> {
            let data = try await send("GET", path: "\(title.kind == .movie ? "movie" : "tv")/\(title.tmdbID)")
            let details = try JSONDecoder().decode(MediaDetails.self, from: data)
            return Self.status(from: details.mediaInfo)
        }
        inFlight[title.id] = task
        defer { inFlight[title.id] = nil }

        let status = try await task.value
        cache[title.id] = (.now, status)
        return status
    }

    /// `POST /api/v1/request`; shows request every season.
    @discardableResult
    func request(_ title: DiscoverTitle) async throws -> SeerrStatus {
        var body: [String: Any] = [
            "mediaType": title.kind == .movie ? "movie" : "tv",
            "mediaId": title.tmdbID,
        ]
        if title.kind == .tv {
            body["seasons"] = "all"
        }

        do {
            let data = try await send("POST", path: "request", body: body)
            let request = try? JSONDecoder().decode(MediaRequest.self, from: data)
            // 2 = approved (auto-approved for admins), so it's on its way rather than waiting
            let status: SeerrStatus = request?.status == 2 ? .processing : .requested
            cache[title.id] = (.now, status)
            return status
        } catch SeerrError.alreadyRequested {
            let status = try await self.status(for: title, refresh: true)
            return status == .notRequested ? .requested : status
        }
    }

    func clearCache() {
        cache = [:]
        requesterIDs = [:]
    }

    // MARK: - Requests

    /// One of the user's requests whose media has arrived (Home's Ready to Watch).
    struct AvailableRequest: Identifiable, Hashable {
        let id: Int
        let kind: DiscoverTitle.Kind
        let tmdbID: Int
        let isPartial: Bool
        /// When the media became available (`media.mediaAddedAt`, else the request's last update)
        let availableAt: Date?
        /// Seerr's own link to the Jellyfin item, when it has one
        let jellyfinMediaID: String?

        var key: String {
            "\(kind.rawValue)-\(tmdbID)"
        }
    }

    /// Seerr user ids keyed by Jellyfin user id.
    private var requesterIDs: [String: Int] = [:]

    /// The Seerr user linked to this Jellyfin user (`jellyfinUserId`), else the API key's own user.
    private func requesterID(jellyfinUserID: String) async throws -> Int? {
        let wanted = Self.normalizedJellyfinID(jellyfinUserID)
        if let id = requesterIDs[wanted] {
            return id
        }

        let users = try? await JSONDecoder().decode(
            UserPage.self,
            from: send("GET", path: "user", query: ["take": "200"])
        )
        var id = users?.results.first { $0.jellyfinUserId.map(Self.normalizedJellyfinID) == wanted }?.id
        if id == nil {
            id = try? await JSONDecoder().decode(SeerrUser.self, from: send("GET", path: "auth/me")).id
        }
        if let id {
            requesterIDs[wanted] = id
        }
        return id
    }

    /// `GET /api/v1/request`: this user's requests that are available or partially available, newest first.
    func availableRequests(jellyfinUserID: String) async throws -> [AvailableRequest] {
        let requester = try await requesterID(jellyfinUserID: jellyfinUserID)

        var query = ["take": "100", "skip": "0", "sort": "modified", "filter": "all"]
        if let requester {
            query["requestedBy"] = String(requester)
        }
        let data = try await send("GET", path: "request", query: query)
        let page = try JSONDecoder().decode(RequestPage.self, from: data)

        var seen = Set<String>()
        return page.results
            .filter { request in
                // Older servers ignore `requestedBy`; check it here too
                guard let requester, let by = request.requestedBy?.id else { return true }

                return by == requester
            }
            .compactMap { request -> AvailableRequest? in
                guard let media = request.media, let tmdbID = media.tmdbId,
                      media.status == 4 || media.status == 5
                else { return nil }

                let kind: DiscoverTitle.Kind = (request.type ?? media.mediaType) == "movie" ? .movie : .tv
                let availableAt = Self.date(media.mediaAddedAt) ?? Self.date(request.updatedAt) ?? Self.date(request.createdAt)
                return AvailableRequest(
                    id: request.id,
                    kind: kind,
                    tmdbID: tmdbID,
                    isPartial: media.status == 4,
                    availableAt: availableAt,
                    jellyfinMediaID: media.jellyfinMediaId
                )
            }
            .sorted { ($0.availableAt ?? .distantPast) > ($1.availableAt ?? .distantPast) }
            .filter { seen.insert($0.key).inserted }
    }

    private static func normalizedJellyfinID(_ id: String) -> String {
        id.replacing("-", with: "").lowercased()
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - Transport

    private func send(_ method: String, path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data {
        guard let configuration = Self.configuration else { throw SeerrError.notConfigured }

        var url = configuration.baseURL.appendingPathComponent("api/v1/\(path)")
        if query.isNotEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components.url ?? url
        }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SeerrError.unreachable
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200 ..< 300:
            return data
        case 401, 403:
            throw SeerrError.unauthorized
        case 409:
            throw SeerrError.alreadyRequested
        case let code:
            throw SeerrError.server(code)
        }
    }

    // MARK: - Models

    private struct MediaDetails: Decodable {
        let mediaInfo: MediaInfo?
    }

    private struct MediaInfo: Decodable {
        /// 1 unknown, 2 pending, 3 processing, 4 partially available, 5 available, 6 deleted
        let status: Int?
        let requests: [MediaRequest]?
    }

    private struct MediaRequest: Decodable {
        /// 1 pending approval, 2 approved, 3 declined
        let status: Int?
    }

    private struct SeerrUser: Decodable {
        let id: Int
        let jellyfinUserId: String?
    }

    private struct UserPage: Decodable {
        let results: [SeerrUser]
    }

    private struct RequestPage: Decodable {
        let results: [UserMediaRequest]
    }

    /// A row of `GET /api/v1/request`.
    private struct UserMediaRequest: Decodable {

        struct Media: Decodable {
            let tmdbId: Int?
            let mediaType: String?
            /// 1 unknown, 2 pending, 3 processing, 4 partially available, 5 available
            let status: Int?
            let mediaAddedAt: String?
            let jellyfinMediaId: String?
        }

        struct Requester: Decodable {
            let id: Int?
        }

        let id: Int
        let type: String?
        let createdAt: String?
        let updatedAt: String?
        let media: Media?
        let requestedBy: Requester?
    }

    private static func status(from info: MediaInfo?) -> SeerrStatus {
        switch info?.status {
        case 2: return .requested
        case 3: return .processing
        case 4: return .partiallyAvailable
        case 5: return .available
        default:
            // Unknown/deleted media can still carry an open request
            let open = info?.requests?.contains { $0.status == 1 || $0.status == 2 } ?? false
            return open ? .requested : .notRequested
        }
    }
}

/// Seerr statuses for Discover cards: loaded lazily as cards appear, shared across screens.
@MainActor
final class SeerrStatusStore: ObservableObject {

    static let shared = SeerrStatusStore()

    @Published
    private(set) var statuses: [String: SeerrStatus] = [:]

    private var requested: Set<String> = []

    func status(for title: DiscoverTitle) -> SeerrStatus? {
        statuses[title.id]
    }

    /// Fetches once per title per session; failures stay silent (cards just show no badge).
    func prefetch(_ title: DiscoverTitle) {
        guard SeerrClient.isConfigured, requested.insert(title.id).inserted else { return }

        Task {
            if let status = try? await SeerrClient.shared.status(for: title) {
                statuses[title.id] = status
            }
        }
    }

    func refresh(_ title: DiscoverTitle) async throws -> SeerrStatus {
        let status = try await SeerrClient.shared.status(for: title, refresh: true)
        statuses[title.id] = status
        return status
    }

    func request(_ title: DiscoverTitle) async throws -> SeerrStatus {
        let status = try await SeerrClient.shared.request(title)
        statuses[title.id] = status
        return status
    }

    func reset() {
        statuses = [:]
        requested = []
        Task { await SeerrClient.shared.clearCache() }
    }

    /// Plugs Seerr into the Discover request hook.
    static func installRequestHandler() {
        guard SeerrClient.isConfigured else {
            DiscoverRequests.handler = nil
            return
        }

        DiscoverRequests.handler = { title in
            _ = try await SeerrStatusStore.shared.request(title)
        }
    }
}
