//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

/// Top Shelf for the home screen: "Up Next" (in-progress items, then next episodes) and "Recently Added".
/// Returns `nil` without a shared session, so the static Top Shelf image is shown instead.
final class ContentProvider: TVTopShelfContentProvider {

    private let upNextLimit = 10
    private let latestLimit = 10

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        var log = ["\(Date.now.formatted(date: .abbreviated, time: .standard))"]
        defer { TopShelfCredentials.saveDiagnostics(log.joined(separator: " | ")) }

        guard let session = TopShelfCredentials.load() else {
            log.append("no credentials in shared keychain")
            return nil
        }

        log.append("server \(session.serverURL.absoluteString)")

        let client = TopShelfClient(session: session)

        async let resumeResult = Self.capture { try await client.resumeItems(limit: self.upNextLimit) }
        async let nextUpResult = Self.capture { try await client.nextUpItems(limit: self.upNextLimit) }
        async let latestResult = Self.capture { try await client.latestItems(limit: self.latestLimit) }

        let (resume, resumeNote) = await resumeResult
        let (nextUp, nextUpNote) = await nextUpResult
        let (latest, latestNote) = await latestResult
        log.append("resume \(resumeNote), nextUp \(nextUpNote), latest \(latestNote)")

        var seen = Set<String>()
        let upNext = await ((resume ?? []) + (nextUp ?? []))
            .filter { seen.insert($0.Id).inserted }
            .prefix(upNextLimit)

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if upNext.isNotEmpty {
            let collection = TVTopShelfItemCollection(items: upNext.map { makeItem($0, client: client, session: session) })
            collection.title = NSLocalizedString("Up Next", comment: "Top Shelf section title")
            sections.append(collection)
        }

        // Skip shows that already appear in Up Next as an episode
        let upNextSeries = Set(upNext.compactMap(\.SeriesId))
        let recent = await (latest ?? []).filter { seen.contains($0.Id) == false && upNextSeries.contains($0.Id) == false }
        if recent.isNotEmpty {
            let collection = TVTopShelfItemCollection(items: recent.map { makeItem($0, client: client, session: session) })
            collection.title = NSLocalizedString("Recently Added", comment: "Top Shelf section title")
            sections.append(collection)
        }

        guard sections.isNotEmpty else {
            log.append("no sections")
            return nil
        }

        log.append("returned \(sections.count) section(s)")
        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func capture(_ work: () async throws -> [TopShelfClient.Item]) async -> ([TopShelfClient.Item]?, String) {
        do {
            let items = try await work()
            return (items, "\(items.count)")
        } catch {
            return (nil, "error: \(error)")
        }
    }

    private func makeItem(
        _ item: TopShelfClient.Item,
        client: TopShelfClient,
        session: TopShelfCredentials.Session
    ) -> TVTopShelfSectionedItem {
        let shelfItem = TVTopShelfSectionedItem(identifier: item.Id)
        shelfItem.title = title(for: item)
        shelfItem.imageShape = .hdtv

        if let url = client.landscapeImageURL(for: item, maxWidth: 800) {
            shelfItem.setImageURL(url, for: .screenScale1x)
        }
        if let url = client.landscapeImageURL(for: item, maxWidth: 1600) {
            shelfItem.setImageURL(url, for: .screenScale2x)
        }

        if let percentage = item.UserData?.PlayedPercentage, percentage > 0, percentage < 100 {
            shelfItem.playbackProgress = percentage / 100
        }

        // Same format as DeepLink: <scheme>://<serverID>/<userID>/item/<itemID>
        if let url = URL(string: "glassfin://\(session.serverID)/\(session.userID)/item/\(item.Id)") {
            shelfItem.displayAction = TVTopShelfAction(url: url)
        }

        return shelfItem
    }

    /// "Haunted Hotel · S2:E2" for episodes, the item name otherwise.
    private func title(for item: TopShelfClient.Item) -> String {
        if item.Type == "Episode", let series = item.SeriesName {
            if let season = item.ParentIndexNumber, let episode = item.IndexNumber {
                return "\(series) · S\(season):E\(episode)"
            }
            return series
        }
        return item.Name ?? ""
    }
}

private extension Collection {

    var isNotEmpty: Bool {
        !isEmpty
    }
}
