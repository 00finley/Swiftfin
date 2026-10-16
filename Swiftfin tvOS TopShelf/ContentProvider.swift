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

        let (loaded, keychainStatus) = TopShelfCredentials.loadWithStatus()
        guard let session = loaded else {
            log.append("no credentials in shared keychain (OSStatus \(keychainStatus))")
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

        // One entry per show: the most recently started episode, else that show's Next Up episode
        let inProgress = (resume ?? []).sorted { ($0.UserData?.LastPlayedDate ?? "") > ($1.UserData?.LastPlayedDate ?? "") }
        var seen = Set<String>()
        var seenSeries = Set<String>()
        let upNext = (inProgress + (nextUp ?? []))
            .filter { item in
                guard seen.insert(item.Id).inserted else { return false }
                guard let series = item.SeriesId else { return true }

                return seenSeries.insert(series).inserted
            }
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

        // The system draws a progress bar under started items
        if let progress = TopShelfClient.progress(of: item) {
            shelfItem.playbackProgress = progress
        }

        // Same format as DeepLink: <scheme>://<serverID>/<userID>/item/<itemID>
        if let url = URL(string: "glassfin://\(session.serverID)/\(session.userID)/item/\(item.Id)") {
            shelfItem.displayAction = TVTopShelfAction(url: url)
        }

        return shelfItem
    }

    /// "Haunted Hotel · S2, E2" for episodes (the Apple TV app's locator), the item name otherwise.
    /// Episodes added in the last 7 days that haven't been started lead with "New": sectioned Top
    /// Shelf items have no badge, so the indicator is part of the title shown under the focused item.
    private func title(for item: TopShelfClient.Item) -> String {
        let base: String = if item.Type == "Episode", let series = item.SeriesName {
            if let season = item.ParentIndexNumber, let episode = item.IndexNumber {
                "\(series) · S\(season), E\(episode)"
            } else {
                series
            }
        } else {
            item.Name ?? ""
        }

        guard TopShelfClient.isNew(item) else { return base }

        return String(format: NSLocalizedString("New · %@", comment: "Top Shelf title of an episode added in the last 7 days"), base)
    }
}

private extension Collection {

    var isNotEmpty: Bool {
        !isEmpty
    }
}
