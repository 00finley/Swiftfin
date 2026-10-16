//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

struct ContentGroupView<Provider: ContentGroupProvider>: View {

    private enum Focus: String {

        case content = "contentGroup-content"
    }

    @Environment(\.tabSafeAreaInsets)
    private var tabSafeAreaInsets

    @Router
    private var router

    @State
    private var contentGroupOptions: ContentGroupParentOption = .init()

    /// Scrolls to the true top edge (ScrollViewReader anchors at the safe area instead)
    @State
    private var scrollPosition = ScrollPosition(edge: .top)

    @StateObject
    private var focusCoordinator = FocusCoordinator(waitingFor: Focus.content.rawValue, focusPlaceholder: true)
    @StateObject
    private var viewModel: ContentGroupViewModel<Provider>

    @TabItemSelected
    private var tabItemSelected

    init(provider: Provider) {
        _viewModel = StateObject(wrappedValue: ContentGroupViewModel(provider: provider))
    }

    #if os(tvOS)
    private enum HeroScrollPin {
        case top
        case row
    }

    /// Where the hero holds the page while it has focus; nil when focus is elsewhere.
    private var heroScrollPin: HeroScrollPin? {
        if contentGroupOptions.contains(.pinsToTop) {
            .top
        } else if contentGroupOptions.contains(.pinsHeroRow) {
            .row
        } else {
            nil
        }
    }
    #endif

    @ViewBuilder
    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    ContentGroupVStack(
                        groups: viewModel.groups,
                        isHeroImmersive: contentGroupOptions.contains(.immersiveHero)
                    )
                    .edgePadding(contentGroupOptions.contains(.ignoreSafeAreaTop) ? .bottom : .vertical)
                    .padding(.top, contentGroupOptions.contains(.ignoreSafeAreaTop) ? 0 : tabSafeAreaInsets.top)
                    .onPreferenceChange(ContentGroupCustomizationKey.self) { value in
                        contentGroupOptions = value
                    }
                }
            }
            #if os(tvOS)
            .scrollPosition($scrollPosition)
                .onChange(of: heroScrollPin) { _, pin in
                    // Hero buttons: the true top. Hero row: the row fully on screen with the next
                    // group's title peeking below (see CinematicHeroLayout.rowFocusedScrollOffset).
                    switch pin {
                    case .top:
                        withAnimation(CinematicHeroLayout.scrollAnimation) {
                            scrollPosition.scrollTo(edge: .top)
                        }

                    case .row:
                        withAnimation(CinematicHeroLayout.scrollAnimation) {
                            scrollPosition.scrollTo(y: CinematicHeroLayout.rowFocusedScrollOffset)
                        }

                    case nil: ()
                    }
                }
                .onChange(of: focusCoordinator.focusedIDs) { oldValue, newValue in
                    // While the hero is pinned, scrolling is disabled, so focus moving down to a later
                    // group doesn't scroll it into view by itself. Scroll to the group's anchor, one
                    // group spacing above it, so its header stays inside the top safe area. (The
                    // hero's preference still says pinned at this point; it updates a pass later.)
                    guard let firstID = viewModel.groups.first?.id,
                          oldValue.contains(firstID),
                          let target = viewModel.groups.dropFirst().first(where: { newValue.contains($0.id) })
                    else { return }

                    withAnimation(CinematicHeroLayout.scrollAnimation) {
                        proxy.scrollTo(ContentGroupVStack.scrollAnchorID(for: target.id), anchor: .top)
                    }
                }
            #endif
                .trackingFrame(for: .scrollView)
            #if os(tvOS)
            .coordinatedFocus(Focus.content.rawValue)
            .ignoresSafeArea(.container, edges: [.horizontal, .top])
            #else
            .ignoresSafeArea(
                edges: contentGroupOptions.contains(.ignoreSafeAreaTop) ? [.horizontal, .top] : .horizontal
            )
            #endif
            .scrollIndicators(.hidden)
            #if os(tvOS)
            .scrollDisabled(heroScrollPin != nil)
            // Groups that draw under the top edge start at the true top, not below the safe area
            .contentMargins(.top, contentGroupOptions.contains(.ignoreSafeAreaTop) ? 0 : nil, for: .scrollContent)
            #endif
            .refreshable {
                await viewModel.background.refresh()
            }
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .content:
                if viewModel.groups.isEmpty {
                    ContentUnavailableView(
                        L10n.noResults.localizedCapitalized,
                        systemImage: "rectangle.on.rectangle.slash"
                    )
                    .focusable()
                    #if os(tvOS)
                    .coordinatedFocus(.fallback)
                    #endif
                } else {
                    contentView
                }

            case .error:
                viewModel.error.map(ErrorView.init)
                    #if os(tvOS)
                        .coordinatedFocus(.fallback)
                    #endif

            case .initial, .refreshing:
                ProgressView()
                    #if os(tvOS)
                        .coordinatedFocus(.placeholder)
                    #endif
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.background.states)
        .navigationTitle(viewModel.provider.displayTitle)
        #if os(iOS)
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #elseif os(tvOS)
        .toolbar(router.isRootOfPath ? .hidden : .automatic, for: .navigationBar)
        #endif
        .onFirstAppear {
            viewModel.refresh()
        }
        .refreshable {
            viewModel.refresh()
        }
        .sinceLastDisappear { interval in
            viewModel.refreshIfNeeded(sinceLastDisappear: interval)
        }
        .onSceneWillEnterForeground {
            viewModel.refreshIfPendingChanges()
        }
        .topBarTrailing {
            if #unavailable(iOS 26.0) {
                if viewModel.background.is(.refreshing) {
                    ProgressView()
                }
            }
        }
        .environmentObject(focusCoordinator)
    }
}
