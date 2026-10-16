//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Minimal Jellyfin client for the Top Shelf: the extension only needs three list endpoints,
/// so it avoids linking the full app stack.
struct TopShelfClient {

    struct Item: Decodable, Hashable {

        struct UserData: Decodable, Hashable {
            let PlayedPercentage: Double?
            let PlaybackPositionTicks: Int?
            let Played: Bool?
            let LastPlayedDate: String?
        }

        let Id: String
        let Name: String?
        let `Type`: String?
        let SeriesName: String?
        let SeriesId: String?
        let ParentIndexNumber: Int?
        let IndexNumber: Int?
        let RunTimeTicks: Int?
        let DateCreated: String?
        let ImageTags: [String: String]?
        let BackdropImageTags: [String]?
        let ParentThumbItemId: String?
        let ParentThumbImageTag: String?
        let ParentBackdropItemId: String?
        let ParentBackdropImageTags: [String]?
        let UserData: UserData?

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.Id == rhs.Id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(Id)
        }
    }

    // MARK: Item state

    /// Watch progress for the Top Shelf's progress bar (0...1), when the item has been started.
    static func progress(of item: Item) -> Double? {
        if let percentage = item.UserData?.PlayedPercentage, percentage > 0, percentage < 100 {
            return percentage / 100
        }
        if let position = item.UserData?.PlaybackPositionTicks, position > 0,
           let runtime = item.RunTimeTicks, runtime > 0, position < runtime
        {
            return Double(position) / Double(runtime)
        }
        return nil
    }

    /// An episode added in the last `days` days that hasn't been started.
    static func isNew(_ item: Item, days: Int = 7, now: Date = .now) -> Bool {
        guard item.Type == "Episode", item.UserData?.Played != true,
              (item.UserData?.PlaybackPositionTicks ?? 0) == 0,
              let created = item.DateCreated.flatMap(parseDate)
        else { return false }

        return now.timeIntervalSince(created) <= Double(days) * 24 * 60 * 60
    }

    /// Jellyfin dates carry up to 7 fractional digits, which ISO8601DateFormatter rejects: parse the
    /// seconds-precision prefix (they're UTC).
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: String(string.prefix(19)) + "Z")
    }

    private struct ItemsResponse: Decodable {
        let Items: [Item]
    }

    let session: TopShelfCredentials.Session

    private static let fields = "EnableImageTypes=Primary,Thumb,Backdrop&ImageTypeLimit=1&Fields=ParentId,DateCreated"

    func resumeItems(limit: Int) async throws -> [Item] {
        try await items(at: "UserItems/Resume?userId=\(session.userID)&MediaTypes=Video&Limit=\(limit)&\(Self.fields)")
    }

    func nextUpItems(limit: Int) async throws -> [Item] {
        try await items(at: "Shows/NextUp?userId=\(session.userID)&Limit=\(limit)&EnableResumable=false&\(Self.fields)")
    }

    func latestItems(limit: Int) async throws -> [Item] {
        let data = try await get("Items/Latest?userId=\(session.userID)&Limit=\(limit)&\(Self.fields)")
        return try JSONDecoder().decode([Item].self, from: data)
    }

    // MARK: Images

    /// A 16:9 image: the series thumb (usually with the logo), then the episode still, then a backdrop.
    func landscapeImageURL(for item: Item, maxWidth: Int) -> URL? {
        if let id = item.ParentThumbItemId, let tag = item.ParentThumbImageTag {
            return imageURL(itemID: id, type: "Thumb", tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.ImageTags?["Thumb"] {
            return imageURL(itemID: item.Id, type: "Thumb", tag: tag, maxWidth: maxWidth)
        }
        if item.Type == "Episode", let tag = item.ImageTags?["Primary"] {
            return imageURL(itemID: item.Id, type: "Primary", tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.BackdropImageTags?.first {
            return imageURL(itemID: item.Id, type: "Backdrop/0", tag: tag, maxWidth: maxWidth)
        }
        if let id = item.ParentBackdropItemId, let tag = item.ParentBackdropImageTags?.first {
            return imageURL(itemID: id, type: "Backdrop/0", tag: tag, maxWidth: maxWidth)
        }
        return nil
    }

    private func imageURL(itemID: String, type: String, tag: String, maxWidth: Int) -> URL? {
        URL(string: "\(baseURL)/Items/\(itemID)/Images/\(type)?tag=\(tag)&maxWidth=\(maxWidth)&quality=90")
    }

    // MARK: Requests

    private var baseURL: String {
        var base = session.serverURL.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    private func items(at path: String) async throws -> [Item] {
        let data = try await get(path)
        return try JSONDecoder().decode(ItemsResponse.self, from: data).Items
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "MediaBrowser Client=\"Glassfin Top Shelf\", Device=\"Apple TV\", DeviceId=\"glassfin-topshelf\", Version=\"1.0\", Token=\"\(session.accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: ["status": (response as? HTTPURLResponse)?.statusCode ?? -1])
        }

        return data
    }
}
