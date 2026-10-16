//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    struct RegularEnhancedHeaderContentGroup: ContentGroup {

        let id: String = ItemView.Component.header
        let provider: ItemContentGroupProvider

        func body(with viewModel: Empty) -> Body {
            Body(provider: provider)
        }

        struct Body: View {

            @ObservedObject
            var provider: ItemContentGroupProvider

            @StoredValue(.User.itemViewAttributes)
            private var attributes

            private let headerAspectRatio = 2.0

            #if !os(tvOS)
            private var headerImageItem: BaseItemDto {
                if provider.item.type == .person || provider.item.type == .musicArtist,
                   let randomItem = provider.randomBackdropItem
                {
                    randomItem
                } else {
                    provider.item
                }
            }
            #endif

            private var logoHeight: CGFloat {
                UIDevice.isTV ? 190 : 70
            }

            @ViewBuilder
            private var logo: some View {
                ImageView(
                    provider.item.imageSource(
                        .logo,
                        itemID: provider.item.id,
                        environment: ImageSourceOptions(maxHeight: logoHeight)
                    )
                )
                .image { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: logoHeight)
                }
                .placeholder { _ in
                    EmptyView()
                }
                .failure {
                    Text(provider.item.displayTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(provider.item.displayTitle)
                .accessibilityRemoveTraits(.isImage)
            }

            @ViewBuilder
            private var overlay: some View {
                HStack(alignment: .bottom, spacing: EdgeInsets.edgePadding) {
                    VStack(alignment: .center, spacing: UIDevice.isTV ? 30 : 5) {
                        VStack(alignment: .leading) {
                            if let parentID = provider.item.parentRootID, let parentTitle = provider.item.parentTitle {
                                ParentButton(title: parentTitle, id: parentID)
                            }

                            logo
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ItemView.ActionBar(provider: provider)
                    }
                    .frame(width: UIDevice.isTV ? 560 : 300)

                    VStack(alignment: .leading, spacing: 10) {
                        ItemView.Description(item: provider.item)

                        HStack(alignment: .top) {
                            ItemView.AttributesHStack(
                                attributes: attributes,
                                item: provider.item,
                                selectedMediaSource: provider.mediaPlayerItemProvider?.mediaSource,
                                alignment: .leading
                            )

                            MetadataHStack(item: provider.item)
                        }
                        #if os(tvOS)
                        .font(.callout)
                        #endif
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                #if os(tvOS)
                .focusSection()
                #else
                    .edgePadding(.bottom)
                    .background(
                        alignment: .bottom,
                        extendedBy: .init(horizontal: EdgeInsets.edgePadding)
                    ) {
                        Rectangle()
                            .fill(Material.ultraThin)
                            .mask(gradient: .eased(.easeOut)) {
                                (location: 0, opacity: 0)
                                (location: 1, opacity: 1)
                            }
                    }
                #endif
            }

            #if os(tvOS)
            /// Cinematic episode layout: title block, description and a single button row, bottom-leading.
            @ViewBuilder
            private var episodeOverlay: some View {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let parentID = provider.item.parentRootID, let parentTitle = provider.item.parentTitle {
                            ParentButton(title: parentTitle, id: parentID)
                        }

                        Text(provider.item.displayTitle)
                            .font(.system(size: 72, weight: .bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        DotHStack {
                            if let seasonEpisodeLabel = provider.item.seasonEpisodeLabel {
                                Text(seasonEpisodeLabel)
                            }

                            if let runtime = provider.item.runtime {
                                Text(runtime, format: .hourMinuteAbbreviated)
                            }

                            if let premiereYear = provider.item.premiereDateYear {
                                Text(premiereYear)
                            }

                            if let officialRating = provider.item.officialRating {
                                Text(officialRating)
                            }
                        }
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    }

                    if let overview = provider.item.overview, overview.isNotEmpty {
                        Text(overview)
                            .font(.callout)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 1000, alignment: .leading)
                    }

                    HStack(alignment: .center, spacing: 40) {
                        ItemView.ActionBar(
                            provider: provider,
                            alignment: .leading,
                            axis: .horizontal
                        )

                        ItemView.AttributesHStack(
                            attributes: attributes,
                            item: provider.item,
                            selectedMediaSource: provider.mediaPlayerItemProvider?.mediaSource,
                            alignment: .leading
                        )
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            }
            #endif

            #if !os(tvOS)
            private func resolveColor(from image: UIImage, binding: Binding<Color>) {
                Task.detached(priority: .utility) {
                    guard let color = image.interestingColor() else { return }

                    await MainActor.run {
                        binding.wrappedValue = color
                    }
                }
            }
            #endif

            var body: some View {
                #if os(tvOS)
                CinematicContentGroupContainer {
                    Group {
                        if provider.item.type == .episode {
                            episodeOverlay
                        } else {
                            overlay
                        }
                    }
                    .edgePadding(.horizontal)
                    .frame(maxWidth: .infinity)
                    .colorScheme(.dark)
                }
                #else
                AlternateLayoutView(alignment: .bottom) {
                    Color.clear
                        .aspectRatio(headerAspectRatio, contentMode: .fit)
                } content: {
                    overlay
                        .edgePadding(.horizontal)
                        .frame(maxWidth: .infinity)
                        .colorScheme(.dark)
                }
                .backgroundParallaxHeader(multiplier: 0.3) {
                    StateAdapter(initialValue: Color.secondarySystemFill) { resolvedColor in
                        AlternateLayoutView {
                            Color.clear
                        } content: {
                            ImageView(headerImageItem.imageSources(for: .landscape, environment: .init(maxWidth: 1920)))
                                .image { (image: UIImage) in
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(1.77, contentMode: .fill)
                                        .onAppear {
                                            resolveColor(from: image, binding: resolvedColor)
                                        }
                                }
                        }
                        .aspectRatio(headerAspectRatio, contentMode: .fit)
                        .bottomEdgeGradient(bottomColor: resolvedColor.wrappedValue)
                        .accessibilityHidden(true)
                    }
                }
                #endif
            }
        }
    }
}
