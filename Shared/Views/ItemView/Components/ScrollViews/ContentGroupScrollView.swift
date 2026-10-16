//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: tvOS black background if not enhanced?

extension ItemView {

    struct ContentGroupScrollView: View {

        @Environment(\.tabSafeAreaInsets)
        private var tabSafeAreaInsets

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        @ObservedObject
        var provider: ItemContentGroupProvider

        let groups: [any ContentGroup]
        let isEnhanced: Bool

        private var isHeaderFocused: Bool {
            focusCoordinator.lastFocusedIDs.contains(Component.header)
        }

        private var backgroundImageItem: BaseItemDto {
            if provider.item.type == .person || provider.item.type == .musicArtist,
               let randomItem = provider.randomBackdropItem
            {
                randomItem
            } else {
                provider.item
            }
        }

        private var backgroundImageSources: [ImageSource] {
            let sources = backgroundImageItem.imageSources(
                for: .landscape,
                environment: .init(maxWidth: 1920)
            )

            // Episodes: prefer the episode still, then fall back to the series backdrop
            guard backgroundImageItem.type == .episode else { return sources }

            let parentSources = backgroundImageItem.imageSources(
                for: .landscape,
                environment: .init(maxWidth: 1920, useParent: true)
            )
            return Array((sources + parentSources).uniqued())
        }

        @ViewBuilder
        private var background: some View {
            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(backgroundImageSources)
                    .failure {
                        Color.black
                    }
                    .aspectRatio(contentMode: .fill)
            }
            .accessibilityHidden(true)
            .overlay {
                // Episode stills are often bright and busy: darken behind the bottom-leading text block
                if [.episode, .series, .season, .movie].contains(backgroundImageItem.type) {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.7), location: 0),
                            .init(color: .black.opacity(0.35), location: 0.45),
                            .init(color: .clear, location: 0.8),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                }
            }
            .overlay {
                Rectangle()
                    .fill(Material.regular)
                    .mask(gradient: .linear) {
                        if isHeaderFocused {
                            (location: 0.3, opacity: 0)
                        } else {
                            (location: 0, opacity: 1)
                        }

                        (location: 1, opacity: 1)
                    }
            }
            .animation(.linear(duration: 0.2), value: isHeaderFocused)
        }

        var body: some View {
            ZStack {
                #if os(tvOS)
                if isEnhanced {
                    background
                        .ignoresSafeArea()
                }
                #endif

                ScrollView {
                    ContentGroupVStack(groups: groups)
                        .edgePadding(.bottom)
                        .padding(.top, isEnhanced ? 0 : tabSafeAreaInsets.top)
                }
                .trackingFrame(for: .scrollView)
                #if os(tvOS)
                .ignoresSafeArea(.container, edges: isEnhanced ? .all : [.horizontal, .top])
                #else
                .ignoresSafeArea(edges: isEnhanced ? .all : .horizontal)
                #endif
                .scrollIndicators(.hidden)
            }
        }
    }
}
