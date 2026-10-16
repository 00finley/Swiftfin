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

        @ObservedObject
        private var colorStore = ArtworkColorStore.shared

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

        /// The artwork-tinted wash behind the sections below the hero, like the Apple TV app's
        /// episode screens: the blurred art under a gradient of its dominant color, darkened so
        /// white text keeps its contrast (see `ArtworkColorStore`).
        @ViewBuilder
        private var colorWash: some View {
            let base = Color(red: 0.07, green: 0.07, blue: 0.08)
            let wash = colorStore.color(for: backgroundImageItem.id) ?? base

            LinearGradient(
                stops: [
                    .init(color: wash.opacity(0.62), location: 0),
                    .init(color: wash.opacity(0.72), location: 0.5),
                    .init(color: base.opacity(0.9), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .animation(.easeInOut(duration: 0.4), value: wash)
        }

        @ViewBuilder
        private var background: some View {
            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(backgroundImageSources)
                    .image { (image: UIImage) in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                colorStore.resolve(backgroundImageItem.id, from: image)
                            }
                    }
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
            #if os(tvOS)
            .overlay {
                colorWash
                    .opacity(isHeaderFocused ? 0 : 1)
            }
            #endif
            .animation(.linear(duration: 0.2), value: isHeaderFocused)
        }

        #if os(tvOS)
        /// Like the Apple TV app, the episodes section takes the whole screen when focus moves into
        /// it (the hero scrolls away), and moving back up brings the full hero back.
        private func scrollToFocusedSection(from oldValue: Set<String>, to newValue: Set<String>, proxy: ScrollViewProxy) {
            guard isEnhanced, let headerID = groups.first?.id else { return }

            if newValue.contains(headerID), !oldValue.contains(headerID) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(ContentGroupVStack.scrollAnchorID(for: headerID), anchor: .top)
                }
                return
            }

            guard let target = groups.dropFirst().first(where: { newValue.contains($0.id) && !oldValue.contains($0.id) }),
                  target.id.hasSuffix("-episode-selector") || oldValue.contains(headerID)
            else { return }

            // After the focus engine's own scroll-into-view for the newly focused card
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(ContentGroupVStack.scrollAnchorID(for: target.id), anchor: .top)
                }
            }
        }
        #endif

        var body: some View {
            ZStack {
                #if os(tvOS)
                if isEnhanced {
                    background
                        .ignoresSafeArea()
                }
                #endif

                ScrollViewReader { proxy in
                    ScrollView {
                        ContentGroupVStack(groups: groups)
                            .edgePadding(.bottom)
                            .padding(.top, isEnhanced ? 0 : tabSafeAreaInsets.top)
                    }
                    #if os(tvOS)
                    .onChange(of: focusCoordinator.focusedIDs) { oldValue, newValue in
                            scrollToFocusedSection(from: oldValue, to: newValue, proxy: proxy)
                        }
                    #endif
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
