//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import Get
import JellyfinAPI

/// The Playback Reporting plugin's activity log (`/user_usage_stats/...`), for exact minutes.
///
/// Every endpoint of the plugin requires an administrator, so this answers nil for other users,
/// when the plugin isn't installed, or on any error; the recap then estimates from Jellyfin's user data.
enum PlaybackReporting {

    struct Row: Hashable {
        let date: Date
        let itemID: String
        let itemType: String
        let itemName: String
        let seconds: Double
    }

    private struct CustomQuery: Encodable {
        let CustomQueryString: String
        let ReplaceUserId: Bool
    }

    private struct CustomQueryResult: Decodable {
        // Sic: the plugin spells it "colums"
        let colums: [String]?
        let results: [[String]]?
        let message: String?
    }

    /// The year's movie and episode plays for one user, oldest first.
    static func plays(year: Int, userID: String, client: JellyfinClient) async -> [Row]? {
        // The id is pasted into SQL: keep only hex digits (the plugin stores ids without dashes)
        let id = userID.lowercased().filter(\.isHexDigit)
        guard id.count == 32 else { return nil }

        let sql = """
        SELECT DateCreated, ItemId, ItemType, ItemName, PlayDuration FROM PlaybackActivity \
        WHERE UserId = '\(id)' AND ItemType IN ('Movie', 'Episode') \
        AND DateCreated >= '\(year)-01-01 00:00:00' AND DateCreated < '\(year + 1)-01-01 00:00:00' \
        ORDER BY DateCreated
        """

        let request = Request<CustomQueryResult>(
            path: "/user_usage_stats/submit_custom_query",
            method: .post,
            body: CustomQuery(CustomQueryString: sql, ReplaceUserId: false)
        )

        guard let result = try? await client.send(request).value,
              result.message?.isEmpty ?? true,
              let columns = result.colums
        else { return nil }

        func index(_ name: String) -> Int? {
            columns.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let dateIndex = index("DateCreated"), let itemIndex = index("ItemId"), let typeIndex = index("ItemType"),
              let nameIndex = index("ItemName"), let durationIndex = index("PlayDuration")
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Server local time with no offset; assume the TV is in the same time zone
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return (result.results ?? []).compactMap { row -> Row? in
            let width = [dateIndex, itemIndex, typeIndex, nameIndex, durationIndex].max() ?? 0
            guard row.count > width, let date = formatter.date(from: String(row[dateIndex].prefix(19))) else { return nil }

            return Row(
                date: date,
                itemID: row[itemIndex],
                itemType: row[typeIndex],
                itemName: row[nameIndex],
                seconds: Double(row[durationIndex]) ?? 0
            )
        }
    }
}

/// Loads a user's year: Playback Reporting's exact plays when the plugin answers, otherwise
/// Jellyfin's user data (play count, played, last played date) with minutes estimated from runtimes.
@MainActor
enum YearInGlassfinLoader {

    /// Each item's lifetime play count stands in for plays this year, capped so a much-rewatched
    /// episode doesn't dominate the estimate.
    static let maxEstimatedPlays = 3

    static func load(year: Int) async throws -> YearStats {
        guard let session = Container.shared.currentUserSession() else { throw UserSessionError.missingCurrentSession }

        let client = session.client
        let library = await (try? HomeLibraryIndex.shared.load()) ?? HomeLibraryIndex.Snapshot()
        let seriesGenres: [String: [String]] = Dictionary(
            library.items.filter { $0.type == .series }.compactMap { item in item.id.map { ($0, item.genres ?? []) } },
            uniquingKeysWith: { first, _ in first }
        )

        let favorites = await YearStats.favorites(year: year, library: library)

        if let rows = await PlaybackReporting.plays(year: year, userID: session.user.id, client: client), rows.isNotEmpty {
            let plays = await exactPlays(rows, client: client, userID: session.user.id, seriesGenres: seriesGenres)
            return YearStats.build(year: year, plays: plays, isEstimated: false, favorites: favorites)
        }

        let plays = try await estimatedPlays(year: year, client: client, userID: session.user.id, seriesGenres: seriesGenres)
        return YearStats.build(year: year, plays: plays, isEstimated: true, favorites: favorites)
    }

    // MARK: - Jellyfin user data

    private static func estimatedPlays(
        year: Int,
        client: JellyfinClient,
        userID: String,
        seriesGenres: [String: [String]]
    ) async throws -> [YearPlay] {
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return [] }

        var plays: [YearPlay] = []
        var startIndex = 0
        let pageSize = 500

        // Newest played first; stop at the first item last played before the year
        pages: while true {
            var parameters = Paths.GetItemsParameters()
            parameters.userID = userID
            parameters.isRecursive = true
            parameters.includeItemTypes = [.episode, .movie]
            parameters.sortBy = [.datePlayed]
            parameters.sortOrder = [.descending]
            parameters.enableUserData = true
            parameters.fields = [.genres]
            parameters.enableImages = false
            parameters.startIndex = startIndex
            parameters.limit = pageSize

            let items = try await client.send(Paths.getItems(parameters: parameters)).value.items ?? []

            for item in items {
                guard let id = item.id, let data = item.userData, let lastPlayed = data.lastPlayedDate else { break pages }
                guard lastPlayed < end else { continue }
                guard lastPlayed >= start else { break pages }

                let runtime = Double(item.runTimeTicks ?? 0) / 10_000_000
                let position = Double(data.playbackPositionTicks ?? 0) / 10_000_000
                let count = max(1, data.playCount ?? 1)
                let seconds = data.isPlayed == true
                    ? runtime * Double(min(count, maxEstimatedPlays))
                    : min(position, runtime > 0 ? runtime : position)

                let isEpisode = item.type == .episode
                plays.append(YearPlay(
                    itemID: id,
                    isEpisode: isEpisode,
                    name: item.displayTitle,
                    seriesID: isEpisode ? item.seriesID : nil,
                    seriesName: isEpisode ? item.seriesName : nil,
                    season: item.parentIndexNumber,
                    episode: item.indexNumber,
                    date: lastPlayed,
                    seconds: seconds,
                    plays: count,
                    genres: genres(for: item, seriesGenres: seriesGenres)
                ))
            }

            guard items.count == pageSize else { break }

            startIndex += pageSize
        }
        return plays
    }

    // MARK: - Playback Reporting

    private static func exactPlays(
        _ rows: [PlaybackReporting.Row],
        client: JellyfinClient,
        userID: String,
        seriesGenres: [String: [String]]
    ) async -> [YearPlay] {
        // Look the items up for their show, numbers and genres (removed items fall back to the logged name)
        let ids = Array(Set(rows.map(\.itemID)))
        var items: [String: BaseItemDto] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 150).map({ Array(ids[$0 ..< min($0 + 150, ids.count)]) }) {
            var parameters = Paths.GetItemsParameters()
            parameters.userID = userID
            parameters.ids = chunk
            parameters.fields = [.genres]
            parameters.enableImages = false
            for item in await (try? client.send(Paths.getItems(parameters: parameters)).value.items) ?? [] {
                if let id = item.id {
                    items[id.lowercased().filter(\.isHexDigit)] = item
                }
            }
        }

        return rows.map { row in
            let item = items[row.itemID.lowercased().filter(\.isHexDigit)]
            let isEpisode = row.itemType == "Episode"
            // "Series - s01e02 - Title"
            let parts = row.itemName.components(separatedBy: " - ")
            let loggedSeries = isEpisode && parts.count >= 3 ? parts[0] : nil
            let loggedName = isEpisode && parts.count >= 3 ? parts.dropFirst(2).joined(separator: " - ") : row.itemName

            return YearPlay(
                itemID: item?.id ?? row.itemID,
                isEpisode: isEpisode,
                name: item?.displayTitle ?? loggedName,
                seriesID: isEpisode ? (item?.seriesID ?? loggedSeries.map { "name:\($0)" }) : nil,
                seriesName: isEpisode ? (item?.seriesName ?? loggedSeries) : nil,
                season: item?.parentIndexNumber,
                episode: item?.indexNumber,
                date: row.date,
                seconds: row.seconds,
                genres: item.map { genres(for: $0, seriesGenres: seriesGenres) } ?? []
            )
        }
    }

    private static func genres(for item: BaseItemDto, seriesGenres: [String: [String]]) -> [String] {
        if item.type == .episode, let seriesID = item.seriesID, let genres = seriesGenres[seriesID], genres.isNotEmpty {
            return Array(genres.prefix(3))
        }
        return Array((item.genres ?? []).prefix(3))
    }
}
