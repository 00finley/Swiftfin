//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// The Apple TV app's tech line under the summary:
/// "2025 · 1 Season · ★ 8.1  [TV-14] [4K] [Dolby Vision] [Dolby Atmos] [5.1] [CC]".
///
/// Year, runtime / seasons and ratings are white text; the rest are outlined monochrome badges,
/// derived from the media streams of the item (or of the series' next-up episode).
struct ItemTechLine: View {

    let item: BaseItemDto
    let mediaSource: MediaSourceInfo?
    var attributes: [ItemViewAttribute] = ItemViewAttribute.allCases

    var body: some View {
        let texts = Self.texts(for: item, attributes: attributes)
        let badges = Self.badges(for: item, mediaSource: mediaSource, attributes: attributes)

        if texts.isNotEmpty || badges.isNotEmpty {
            HStack(spacing: 14) {
                if texts.isNotEmpty {
                    Text(texts.joined(separator: " · "))
                        .foregroundStyle(.white)
                }

                ForEach(badges, id: \.self) { badge in
                    TechBadge(title: badge)
                }
            }
            .font(.system(size: 27, weight: .medium))
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Content

    static func texts(for item: BaseItemDto, attributes: [ItemViewAttribute]) -> [String] {
        var texts: [String] = []

        if let year = item.premiereDateYear {
            texts.append(year)
        }

        if item.type == .series {
            if let seasons = item.childCount, seasons > 0 {
                texts.append(seasons == 1 ? L10n.discoverOneSeason : L10n.discoverSeasons(seasons))
            }
        } else if let runtime = item.runtime {
            // "31m" / "1h 2m", like the Apple TV app
            texts.append(runtime.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
        }

        if attributes.contains(.ratingCommunity), let rating = item.communityRating, rating > 0 {
            texts.append(String(format: "★ %.1f", rating))
        }

        if attributes.contains(.ratingCritics), let rating = item.criticRating, rating > 0 {
            texts.append(String(format: "%.0f%%", rating))
        }

        return texts
    }

    static func badges(for item: BaseItemDto, mediaSource: MediaSourceInfo?, attributes: [ItemViewAttribute]) -> [String] {
        var badges: [String] = []

        if attributes.contains(.ratingOfficial), let rating = item.officialRating, rating.isNotEmpty {
            badges.append(rating)
        }

        guard let streams = mediaSource?.mediaStreams ?? item.mediaSources?.first?.mediaStreams else {
            return badges
        }

        if attributes.contains(.videoQuality) {
            if streams.has4KVideo {
                badges.append("4K")
            } else if streams.hasHDVideo {
                badges.append("HD")
            }

            if streams.hasDolbyVision {
                badges.append("Dolby Vision")
            } else if streams.hasHDRVideo {
                badges.append("HDR")
            }
        }

        if attributes.contains(.audioChannels) {
            let audio = streams.filter { $0.type == .audio }

            if audio.contains(where: \.isDolbyAtmos) {
                badges.append("Dolby Atmos")
            }

            if streams.has71AudioChannelLayout {
                badges.append("7.1")
            } else if streams.has51AudioChannelLayout {
                badges.append("5.1")
            }
        }

        if attributes.contains(.subtitles) {
            let subtitles = streams.filter { $0.type == .subtitle }

            if subtitles.isNotEmpty {
                badges.append("CC")
            }

            if subtitles.contains(where: { $0.isHearingImpaired == true }) {
                badges.append("SDH")
            }

            if streams.contains(where: \.isAudioDescription) {
                badges.append("AD")
            }
        }

        return badges
    }
}

/// An outlined, monochrome badge ("TV-14", "4K", "CC").
struct TechBadge: View {

    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
            }
            .fixedSize()
    }
}

extension MediaStream {

    var isDolbyAtmos: Bool {
        [profile, displayTitle, title]
            .compactMap(\.self)
            .contains { $0.localizedCaseInsensitiveContains("atmos") }
    }

    /// An audio description track (narration for blind and low-vision viewers)
    var isAudioDescription: Bool {
        guard type == .audio else { return false }

        return [displayTitle, title]
            .compactMap(\.self)
            .contains { $0.localizedCaseInsensitiveContains("audio description") || $0.localizedCaseInsensitiveContains("descriptive") }
    }
}
