//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension SeriesEpisodeContentGroup {

    struct EpisodeCard: View {

        @Namespace
        private var namespace

        @Router
        private var router

        @SharedBaseItem
        var episode: BaseItemDto

        private var episodeContent: String {
            if episode.isUnaired {
                episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                episode.overview ?? L10n.noOverviewAvailable
            }
        }

        /// "May 24, 2023" under the description
        private var dateLabel: String? {
            guard !episode.isUnaired else { return nil }

            return episode.premiereDate?.formatted(date: .abbreviated, time: .omitted)
        }

        /// "▶ 31m" on the image; in-progress episodes show their progress bar instead
        private var showsRuntimeLabel: Bool {
            (episode.userData?.playbackPositionTicks ?? 0) == 0 && episode.runtime != nil && !episode.isUnaired
        }

        var body: some View {
            EpisodeCardLayout(
                header: episode.displayTitle,
                subHeader: episode.episodeLocator ?? .emptyDash,
                content: episodeContent,
                date: dateLabel,
                rating: episode.officialRating,
                artworkAction: {
                    guard let provider = episode.getPlaybackItemProvider(userSession: nil) else {
                        return
                    }

                    router.route(
                        to: .videoPlayer(
                            provider: provider,
                            queue: EpisodeMediaPlayerQueue(episode: episode)
                        )
                    )
                },
                contentAction: {
                    router.route(to: .item(item: episode), in: namespace)
                },
                contextMenuItem: episode
            ) {
                PosterImage(
                    item: episode,
                    type: .landscape,
                    size: .medium
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    PosterIndicatorsOverlay(
                        item: episode,
                        posterDisplayType: .landscape
                    )
                }
                #if os(tvOS)
                .overlay(alignment: .bottomLeading) {
                    if showsRuntimeLabel, let runtime = episode.runtime {
                        EpisodeRuntimeLabel(runtime: runtime)
                    }
                }
                #endif
                .contentShape(.contextMenuPreview, Rectangle())
                .subtleShadow()
                .matchedTransitionSource(id: "item", in: namespace)
            }
        }
    }

    #if os(tvOS)
    /// "▶ 31m" at the bottom-left of the image, like the Apple TV app
    private struct EpisodeRuntimeLabel: View {

        let runtime: Duration

        var body: some View {
            Label {
                Text(runtime.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
            } icon: {
                Image(systemName: "play.fill")
                    .font(.system(size: 18))
            }
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 6)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
        }
    }
    #endif

    struct EpisodeStateCard: View {

        let title: String
        let subHeader: String
        let content: String
        let systemImage: String?
        let action: () -> Void

        var body: some View {
            EpisodeCardLayout(
                header: title,
                subHeader: subHeader,
                content: content,
                artworkAction: action,
                contentAction: action
            ) {
                Rectangle()
                    .fill(.complexSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if let systemImage {
                            RelativeSystemImageView(systemName: systemImage)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .posterStyle(.landscape)
                    #if os(tvOS)
                    .posterCornerRadius(.landscape)
                    #endif
                    .subtleShadow()
            }
        }
    }

    private struct EpisodeCardLayout<Artwork: View>: View {

        private enum FocusedElement: Hashable {

            case artwork
            case content
        }

        @Environment(\.posterConfiguration)
        private var posterConfiguration

        @Environment(\.viewContext)
        private var viewContext

        @FocusState
        private var focusedElement: FocusedElement?

        @State
        private var artworkSize: CGSize = .zero

        let header: String
        let subHeader: String
        let content: String
        let date: String?
        let rating: String?
        let artworkAction: () -> Void
        let contentAction: () -> Void
        @OptionalSharedBaseItem
        var contextMenuItem: BaseItemDto?
        let artwork: Artwork

        private var contentAccessibilityLabel: String {
            let title = contextMenuItem?.posterAccessibility(configuration: posterConfiguration).label
            return PosterAccessibility.joined([title ?? header, contextMenuItem == nil ? subHeader : nil, content, date, rating])
        }

        init(
            header: String,
            subHeader: String,
            content: String,
            date: String? = nil,
            rating: String? = nil,
            artworkAction: @escaping () -> Void,
            contentAction: @escaping () -> Void,
            contextMenuItem: BaseItemDto? = nil,
            @ViewBuilder artwork: () -> Artwork
        ) {
            self.header = header
            self.subHeader = subHeader
            self.content = content
            self.date = date
            self.rating = rating
            self.artworkAction = artworkAction
            self.contentAction = contentAction
            self.contextMenuItem = contextMenuItem
            self.artwork = artwork()
        }

        @ViewBuilder
        private func contextMenuPreview(for item: BaseItemDto) -> some View {
            VStack(alignment: .leading) {
                PosterImage(
                    item: item,
                    type: .landscape,
                    size: .medium,
                    contentMode: .fit
                )
                .subtleShadow()

                item.posterLabel
                    .allowsHitTesting(false)
            }
            .environment(\.posterDisplayType, .landscape)
            .foregroundStyle(.primary, .secondary)
            .posterAccessibility(for: item)
            .frame(width: artworkSize.width)
            .padding(20)
            .backport
            .glassEffect(in: .rect(cornerRadius: 10))
        }

        @ViewBuilder
        private var artworkButton: some View {
            let button = Button(action: artworkAction) {
                if let contextMenuItem {
                    artwork
                        .posterAccessibility(for: contextMenuItem)
                        .accessibilityHint(L10n.posterAccessibilityPlayHint)
                } else {
                    artwork
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(PosterAccessibility.joined([header, subHeader]))
                }
            }
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.card)
            .focused($focusedElement, equals: .artwork)

            if let contextMenuItem {
                button
                    .trackingSize($artworkSize)
                    .posterContextMenu(for: contextMenuItem) {
                        contextMenuPreview(for: contextMenuItem)
                            .withViewContext(viewContext)
                    }
            } else {
                button
            }
        }

        var body: some View {
            VStack(alignment: .leading) {
                artworkButton
                    .posterAspectRatio(.landscape, contentMode: .fit)

                Button(action: contentAction) {
                    EpisodeMetadataView(
                        header: header,
                        subHeader: subHeader,
                        content: content,
                        date: date,
                        rating: rating
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(contentAccessibilityLabel)
                    .accessibilityHint(contextMenuItem == nil ? "" : L10n.posterAccessibilityDetailsHint)
                }
                .foregroundStyle(.primary, .secondary)
                #if os(tvOS)
                .buttonStyle(
                    EpisodeContentButtonStyle(
                        showsMaterial: focusedElement != nil,
                        isFocused: focusedElement == .content
                    )
                )
                #endif
                .focused($focusedElement, equals: .content)
            }
            .focusSection()
            .defaultFocus(
                $focusedElement,
                .artwork,
                priority: .userInitiated
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private struct EpisodeMetadataView: View {

        let header: String
        let subHeader: String
        let content: String
        var date: String?
        var rating: String?

        var body: some View {
            #if os(tvOS)
            // The Apple TV app's episode lockup: "EPISODE 3" in small caps, the title, a 4-line
            // description and the air date with the rating badge at the bottom
            VStack(alignment: .leading, spacing: 0) {
                Text(subHeader.uppercased())
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                Text(header)
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(content)
                    .font(.system(size: 27))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4, reservesSpace: false)
                    .padding(.top, 4)

                Spacer(minLength: 10)

                if date != nil || rating != nil {
                    HStack(spacing: 12) {
                        if let date {
                            Text(date)
                                .font(.system(size: 27))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if let rating, rating.isNotEmpty {
                            TechBadge(title: rating)
                        }
                    }
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            iOSBody
            #endif
        }

        private var iOSBody: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(subHeader)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(header)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                SeeMoreText(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #if os(tvOS)
    private struct EpisodeContentButtonStyle: ButtonStyle {

        let showsMaterial: Bool
        let isFocused: Bool

        private let cornerRadius: CGFloat = 20

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .frame(height: 300)
                // The glass panel reaches slightly past the image's edges, under the enlarged artwork
                .padding(.horizontal, -12)
                .backport
                .glassEffect(
                    showsMaterial ? .regular.tint(.white.opacity(0.1)) : .identity,
                    in: .rect(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .scaleEffect(isFocused ? 1.05 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .brightness(isFocused ? 0.04 : 0)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .shadow(
                    color: .black.opacity(isFocused ? 0.3 : 0),
                    radius: isFocused ? 18 : 0,
                    y: isFocused ? 10 : 0
                )
                .animation(.easeInOut(duration: 0.2), value: showsMaterial)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    #endif
}
