//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

extension BaseItemDto {

    /// "S2, E2", the Apple TV app's episode locator (comma and space), used throughout the player.
    var playerEpisodeLocator: String? {
        guard type == .episode, let seasonNo = parentIndexNumber, let episodeNo = indexNumber else { return nil }

        return L10n.seasonEpisodeShort(String(seasonNo), String(episodeNo))
    }

    /// The player's title block: the show is the big title, with "S3, E11 • Episode Title" above it.
    /// Movies and other videos show only their title.
    var playerTitles: (title: String, subtitle: String?) {
        guard type == .episode, let showTitle = seriesName ?? parentTitle else {
            return (displayTitle, nil)
        }

        let episodeTitle = displayTitle
        let subtitle = [playerEpisodeLocator, episodeTitle.isEmpty ? nil : episodeTitle]
            .compactMap(\.self)
            .joined(separator: " • ")

        return (showTitle, subtitle.isEmpty ? nil : subtitle)
    }
}
