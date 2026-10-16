//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What went wrong talking to glassfin-helper.
enum GlassfinHelperError: LocalizedError {

    case notConfigured
    case unreachable
    /// No answer within the request's timeout (the Mac is up but slow, or the request was lost).
    case timedOut
    case unauthorized
    /// The helper's `{"error": code, "message": sentence}` body, with the HTTP status and
    /// `Retry-After` in seconds when the helper sent one (429 caps, 503 busy).
    case server(status: Int, code: String?, message: String?, retryAfter: TimeInterval? = nil)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .server(_, _, message?, _): message
        default: L10n.glassfinHelperUnavailable
        }
    }
}

/// Client for glassfin-helper, the small service on the Mac that answers for the TV:
/// `GET /calendar` (Sonarr's upcoming episodes) and `POST /ask` (recommendations).
///
/// Configuration comes from the private xcconfig (`GLASSFIN_HELPER_URL` without a scheme, and
/// `GLASSFIN_HELPER_TOKEN`), compiled into Info.plist as `GlassfinHelperURL` / `GlassfinHelperToken`.
/// Every request sends `Authorization: Bearer <token>`.
actor GlassfinHelperClient {

    static let shared = GlassfinHelperClient()

    struct Configuration: Equatable {
        let baseURL: URL
        let token: String
    }

    nonisolated static var configuration: Configuration? {
        guard var url = infoValue("GlassfinHelperURL"), let token = infoValue("GlassfinHelperToken") else { return nil }

        // xcconfig treats "//" as a comment, so the build setting is written without a scheme
        if url.contains("://") == false {
            url = "http://" + url
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        guard let baseURL = URL(string: url), baseURL.scheme?.hasPrefix("http") == true else { return nil }

        return Configuration(baseURL: baseURL, token: token)
    }

    nonisolated static var isConfigured: Bool {
        configuration != nil
    }

    private nonisolated static func infoValue(_ key: String) -> String? {
        guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false,
            value.contains("$(") == false
        else { return nil }

        return value
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    // MARK: - Requests

    /// `GET <path>` decoded as `Response`.
    func get<Response: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        timeout: TimeInterval = 8,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await send("GET", path: path, query: query, body: nil, timeout: timeout)
        return try decode(data)
    }

    /// `POST <path>` with a JSON body, decoded as `Response`. `/ask` runs Claude on the Mac, so give it ~150 s.
    func post<Response: Decodable>(
        _ path: String,
        body: some Encodable,
        timeout: TimeInterval = 150,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let encoded = try JSONEncoder().encode(body)
        let data = try await send("POST", path: path, query: [:], body: encoded, timeout: timeout)
        return try decode(data)
    }

    // MARK: - Transport

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GlassfinHelperError.invalidResponse
        }
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
    }

    private func send(_ method: String, path: String, query: [String: String], body: Data?, timeout: TimeInterval) async throws -> Data {
        guard let configuration = Self.configuration else { throw GlassfinHelperError.notConfigured }

        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )
        if query.isNotEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw GlassfinHelperError.notConfigured }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw GlassfinHelperError.timedOut
        } catch {
            throw GlassfinHelperError.unreachable
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        switch status {
        case 200 ..< 300:
            return data
        case 401:
            throw GlassfinHelperError.unauthorized
        default:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let retryAfter = (http?.value(forHTTPHeaderField: "Retry-After"))
                .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            throw GlassfinHelperError.server(status: status, code: body?.error, message: body?.message, retryAfter: retryAfter)
        }
    }
}

// MARK: - Calendar

/// One upcoming episode from Sonarr's calendar (`GET /calendar`).
struct HelperCalendarEpisode: Decodable, Hashable {

    let series: String?
    let seriesTmdbId: Int?
    let seriesTvdbId: Int?
    let season: Int?
    let episode: Int?
    let title: String?
    let airDateUtc: String?
    let hasFile: Bool?
    let overview: String?
    let network: String?

    var airDate: Date? {
        guard let airDateUtc else { return nil }

        return Self.parse(airDateUtc)
    }

    private static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

extension GlassfinHelperClient {

    private struct CalendarResponse: Decodable {

        let episodes: [HelperCalendarEpisode]

        private enum CodingKeys: String, CodingKey {
            case episodes
            case items
        }

        // `{start, end, days, count, episodes: [...]}`; also accept `items` or a bare list
        init(from decoder: Decoder) throws {
            if let list = try? decoder.singleValueContainer().decode([HelperCalendarEpisode].self) {
                episodes = list
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            episodes = try container.decodeIfPresent([HelperCalendarEpisode].self, forKey: .episodes)
                ?? container.decode([HelperCalendarEpisode].self, forKey: .items)
        }
    }

    /// Sonarr's episodes airing from local midnight today through `days` days, sorted by air date.
    func calendar(days: Int = 7) async throws -> [HelperCalendarEpisode] {
        let response: CalendarResponse = try await get("calendar", query: ["days": String(days)])
        return response.episodes
    }
}
