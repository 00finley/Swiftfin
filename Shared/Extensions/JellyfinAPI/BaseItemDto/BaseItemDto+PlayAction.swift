//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

extension BaseItemDto {

    var hasPlaybackProgress: Bool {
        (userData?.playbackPositionTicks ?? 0) > 0
    }

    /// "Resume S2:E1" or "Play S2:E1", like the Apple TV app. Unaired, ended and
    /// missing items keep their existing label.
    var playActionTitle: String {
        let fallback = playButtonLabel
        guard [L10n.unaired, L10n.ended, L10n.missing].contains(fallback) == false else { return fallback }

        let verb = hasPlaybackProgress ? L10n.resume : L10n.play

        if type == .episode, let locator = seasonEpisodeLabel {
            return "\(verb) \(locator)"
        }
        return verb
    }

    /// Time remaining when resuming, shown under the title.
    var playActionSubtitle: String? {
        hasPlaybackProgress ? progressLabel : nil
    }
}
