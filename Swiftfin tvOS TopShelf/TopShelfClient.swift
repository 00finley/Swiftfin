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
        }

        let Id: String
        let Name: String?
        let `Type`: String?
        let SeriesName: String?
        let SeriesId: String?
        let ParentIndexNumber: Int?
        let IndexNumber: Int?
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

    private struct ItemsResponse: Decodable {
        let Items: [Item]
    }

    let session: TopShelfCredentials.Session

    private static let fields = "EnableImageTypes=Primary,Thumb,Backdrop&ImageTypeLimit=1&Fields=ParentId"

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
            throw URLError(.badServerResponse)
        }

        return data
    }
}
