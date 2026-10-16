//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI

/// What the video player does when playback enters a media segment.
enum MediaSegmentBehavior: String, CaseIterable, Displayable, Hashable, Storable {

    /// Ignore the segment.
    case off
    /// Present a skip button while inside the segment.
    case showButton
    /// Skip the segment as soon as playback naturally enters it.
    case autoSkip

    var displayTitle: String {
        switch self {
        case .off:
            L10n.disabled
        case .showButton:
            L10n.showButton
        case .autoSkip:
            L10n.autoSkip
        }
    }
}

extension MediaSegmentType: Displayable {

    /// Segment types that can be skipped, in settings display order.
    static let skippableCases: [MediaSegmentType] = [.intro, .recap, .preview, .commercial, .outro]

    var displayTitle: String {
        switch self {
        case .intro:
            L10n.intro
        case .recap:
            L10n.recap
        case .preview:
            L10n.preview
        case .commercial:
            L10n.commercials
        case .outro:
            L10n.credits
        case .unknown:
            L10n.unknown
        }
    }

    /// Title for the button that skips this segment.
    var skipButtonTitle: String {
        switch self {
        case .intro:
            L10n.skipIntro
        case .recap:
            L10n.skipRecap
        case .preview:
            L10n.skipPreview
        case .commercial:
            L10n.skipCommercial
        case .outro:
            L10n.skipCredits
        case .unknown:
            L10n.skip
        }
    }

    /// The user's behavior setting for this segment type.
    var behaviorKey: Defaults.Key<MediaSegmentBehavior>? {
        switch self {
        case .intro:
            .VideoPlayer.MediaSegments.intro
        case .recap:
            .VideoPlayer.MediaSegments.recap
        case .preview:
            .VideoPlayer.MediaSegments.preview
        case .commercial:
            .VideoPlayer.MediaSegments.commercial
        case .outro:
            .VideoPlayer.MediaSegments.outro
        case .unknown:
            nil
        }
    }

    var behavior: MediaSegmentBehavior {
        behaviorKey.map { Defaults[$0] } ?? .off
    }
}

extension MediaSegmentDto {

    var startSeconds: Duration? {
        startTicks.map { Duration.ticks($0) }
    }

    var endSeconds: Duration? {
        endTicks.map { Duration.ticks($0) }
    }
}
