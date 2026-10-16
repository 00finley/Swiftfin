//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Continue Watching and Next Up merged into one row with a single episode per series:
/// the most recently started episode, otherwise the series' Next Up episode. Ordered by
/// most recent activity. Movies pass through unchanged.
struct UpNextLibrary: BaseItemKindLibrary {

    typealias Environment = NextUpLibrary.Environment

    let libraryItemTypes: [BaseItemKind] = [.episode, .movie, .video]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.nextUp, id: "up-next")

    func shouldRefreshForUserDataChange(environment: Environment) -> Bool {
        true
    }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [ItemPatch] {
        // Merged once from both sources, so there is only a single page
        guard pageState.pageOffset == 0 else { return [] }

        var resumeParameters = Paths.GetResumeItemsParameters()
        resumeParameters.enableUserData = true
        resumeParameters.fields = PosterSubtitleField.itemFields + [.overview]
        resumeParameters.limit = 50
        resumeParameters.mediaTypes = [.video]
        resumeParameters.userID = pageState.userSession.user.id

        var nextUpParameters = Paths.GetNextUpParameters()
        nextUpParameters.enableRewatching = environment.enableRewatching
        nextUpParameters.enableUserData = true
        nextUpParameters.fields = PosterSubtitleField.itemFields + [.overview]
        nextUpParameters.limit = pageState.pageSize

        if environment.maxNextUp > 0 {
            nextUpParameters.nextUpDateCutoff = Date.now.addingTimeInterval(-environment.maxNextUp)
        }

        let client = pageState.userSession.client
        async let resumeResponse = client.send(Paths.getResumeItems(parameters: resumeParameters))
        async let nextUpResponse = client.send(Paths.getNextUp(parameters: nextUpParameters))

        let resume = try await resumeResponse.patches()
        let nextUp = try await nextUpResponse.patches()

        return Self.merge(resume: resume, nextUp: nextUp, limit: pageState.pageSize)
    }

    /// One entry per series (movies keyed by their own ID): in-progress items win, newest first,
    /// then Next Up episodes for series without one, in the server's order.
    static func merge(resume: [ItemPatch], nextUp: [ItemPatch], limit: Int) -> [ItemPatch] {
        var seenKeys = Set<String>()
        var dated: [(date: Date, patch: ItemPatch)] = []
        var undated: [ItemPatch] = []

        func groupKey(_ item: BaseItemDto) -> String? {
            item.type == .episode ? (item.seriesID ?? item.id) : item.id
        }

        let newestFirst = resume.sorted {
            ($0.value.userData?.lastPlayedDate ?? .distantPast) > ($1.value.userData?.lastPlayedDate ?? .distantPast)
        }

        for patch in newestFirst + nextUp {
            guard let key = groupKey(patch.value), seenKeys.insert(key).inserted else { continue }

            if let date = patch.value.userData?.lastPlayedDate {
                dated.append((date, patch))
            } else {
                undated.append(patch)
            }
        }

        let ordered = dated.sorted { $0.date > $1.date }.map(\.patch) + undated
        return Array(ordered.prefix(limit))
    }

    func includes(_ element: ItemEntry, environment: Environment) -> Bool {
        element.item.confirmedUserData?.isPlayed != true
    }
}
