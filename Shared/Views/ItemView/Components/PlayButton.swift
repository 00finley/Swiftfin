//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import Logging
import SwiftUI

struct PlayButton: View {

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    var provider: ItemContentGroupProvider

    @Router
    private var router

    private var mediaSource: String? {
        guard provider.mediaPlayerItemProvider?.item.mediaSources?.count ?? 0 > 1 else { return nil }

        return provider.mediaPlayerItemProvider?.mediaSource?.displayTitle
    }

    #if os(tvOS)
    /// tvOS-style label, e.g. "Resume S2:E1" or "Play S2:E1", like the Apple TV app.
    private var title: String {
        guard let item = provider.mediaPlayerItemProvider?.item else { return L10n.play }

        let fallback = item.playButtonLabel
        guard [L10n.unaired, L10n.ended, L10n.missing].contains(fallback) == false else { return fallback }

        let isResuming = (item.userData?.playbackPositionTicks ?? 0) > 0
        let verb = isResuming ? L10n.resume : L10n.play

        if item.type == .episode, let locator = item.seasonEpisodeLabel {
            return "\(verb) \(locator)"
        }
        return verb
    }

    /// Time remaining when resuming, shown under the title.
    private var subtitle: String? {
        guard let item = provider.mediaPlayerItemProvider?.item,
              (item.userData?.playbackPositionTicks ?? 0) > 0
        else { return nil }

        return item.progressLabel
    }
    #else
    private var title: String {
        provider.mediaPlayerItemProvider?.item.playButtonLabel ?? L10n.play
    }

    private var subtitle: String? {
        nil
    }
    #endif

    private func play(fromBeginning: Bool = false) {
        let mediaPlayerItemProvider = if fromBeginning {
            provider.mediaPlayerItemProvider?.modifyingItem {
                $0.userData?.playbackPositionTicks = 0
            }
        } else {
            provider.mediaPlayerItemProvider
        }

        guard let mediaPlayerItemProvider else {
            provider.logger.error("Play selected with no playback item provider")
            return
        }

        let queue: (any MediaPlayerQueue)? = mediaPlayerItemProvider.item.type == .episode ?
            EpisodeMediaPlayerQueue(episode: mediaPlayerItemProvider.item) : nil

        router.route(
            to: .videoPlayer(
                provider: mediaPlayerItemProvider,
                queue: queue
            )
        )
    }

    var body: some View {
        Button {
            play()
        } label: {
            HStack {
                Image(systemName: "play.fill")

                VStack(spacing: 2) {
                    Text(title)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .opacity(0.7)
                    }

                    if let mediaSource {
                        Marquee(mediaSource, speed: 40, delay: 3, fade: 5)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .font(.callout)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backport
            .glassEffect(
                .regular.selection(
                    tint: accentColor,
                    foregroundColor: accentColor.overlayColor
                ),
                in: .capsule
            )
        }
        .buttonBorderShape(.capsule)
        .buttonStyle(BasicHoverButtonStyle())
        .contextMenu {
            if provider.mediaPlayerItemProvider?.item.userData?.playbackPositionTicks != 0 {
                Button(L10n.playFromBeginning, systemImage: "gobackward") {
                    play(fromBeginning: true)
                }
            }
        }
        .disabled(provider.mediaPlayerItemProvider == nil)
    }
}
