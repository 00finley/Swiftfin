//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// What a hero row card shows over the bottom of its artwork.
struct CinematicCardCaption {

    var text: String?
    var progress: Double?
}

/// Apple TV-style Home hero, laid out from measurements of the Apple TV app at 1920x1080:
/// bright full-bleed art of the focused item, its details from ~35% of the screen height, and
/// the row's 16:9 cards cut off by the bottom edge. The next group starts below the fold.
struct CinematicItemSelector<Item: Poster, TopContent: View>: View {

    @Environment(\.frameForParentView)
    private var frameForParentView

    @FocusState
    private var isSectionFocused

    @FocusState
    private var focusedCardID: Item.ID?

    @FocusedValue(\.focusedPoster)
    private var focusedPoster

    @State
    private var selectedPoster: AnyPoster?

    /// The screen's initial focus lands on the first focusable view, which would be the hero's
    /// buttons. Keep the hero out of focus until the row has been focused once, so Home opens on
    /// the first card; pressing up from the row reaches the buttons as usual afterwards.
    @State
    private var isTopContentFocusable = false

    @ObservedObject
    private var preview: HomePreviewController

    private let action: (Item) -> Void
    private let items: [Item]
    private let title: String?
    private let caption: (Item) -> CinematicCardCaption
    private let topContent: (Item) -> TopContent
    private let previewItem: ((Item) -> BaseItemDto?)?

    init(
        items: [Item],
        title: String? = nil,
        preview: HomePreviewController? = nil,
        previewItem: ((Item) -> BaseItemDto?)? = nil,
        caption: @escaping (Item) -> CinematicCardCaption = { CinematicCardCaption(text: $0.displayTitle) },
        action: @escaping (Item) -> Void,
        @ViewBuilder topContent: @escaping (Item) -> TopContent
    ) {
        self.items = items
        self.title = title
        self.preview = preview ?? .disabled
        self.previewItem = preview == nil ? nil : previewItem
        self.caption = caption
        self.action = action
        self.topContent = topContent
    }

    private var parentFrame: CGRect {
        frameForParentView[.scrollView, default: .zero].frame
    }

    private var resolvedSelectedPoster: AnyPoster? {
        selectedPoster ?? items.first.map { AnyPoster($0) }
    }

    private var selectedItem: Item? {
        resolvedSelectedPoster?._poster as? Item
    }

    private var isImmersive: Bool {
        previewItem != nil && preview.isImmersive
    }

    private var isPreviewVisible: Bool {
        guard let itemID = selectedItem.flatMap({ previewItem?($0)?.id }) else { return false }

        return preview.visibleItemID == itemID
    }

    private func updateSelectedPoster() {
        guard isSectionFocused, let focusedPoster else {
            if !isSectionFocused, previewItem != nil {
                preview.focusChanged(to: nil)
            }
            return
        }

        selectedPoster = focusedPoster
        isTopContentFocusable = true

        if let previewItem {
            preview.focusChanged(to: selectedItem.flatMap(previewItem))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Group {
                if let selectedItem {
                    topContent(selectedItem)
                        .id(selectedItem.hashValue)
                        .transition(.opacity)
                        .disabled(!isTopContentFocusable)
                } else {
                    Color.clear
                }
            }
            .frame(height: CinematicHeroLayout.heroHeight, alignment: .topLeading)
            .padding(.top, CinematicHeroLayout.heroTop)

            if let title {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(height: CinematicHeroLayout.rowTitleHeight, alignment: .center)
                    .padding(.leading, CinematicHeroLayout.leadingMargin)
                    .padding(.top, CinematicHeroLayout.heroToRowTitle)
            }

            row
                .padding(.top, CinematicHeroLayout.rowTitleToCards)
        }
        .frame(height: CinematicHeroLayout.containerHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            background
        }
        .overlay(alignment: .top) {
            // Immersive: the video covers the UI instead of hiding it, so the focused card keeps
            // focus (fully transparent views can't hold focus on tvOS)
            if previewItem != nil {
                HomePreviewPlayerView(player: preview.player) { _ in }
                    .ignoresSafeArea()
                    .scaleEffect(preview.videoScale)
                    .frame(height: CinematicHeroLayout.screenHeight)
                    .clipped()
                    .opacity(isImmersive ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background {
            RemoteInputInterceptor(isActive: isImmersive) {
                preview.userDidInteract()
            }
        }
        .onChange(of: focusedPoster) {
            updateSelectedPoster()
        }
        .onChange(of: isSectionFocused) {
            updateSelectedPoster()
        }
        .onDisappear {
            if previewItem != nil {
                preview.focusChanged(to: nil)
            }
        }
        .focusSection()
        .focused($isSectionFocused)
    }

    // MARK: - Row

    private var row: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: CinematicHeroLayout.cardSpacing) {
                ForEach(items, id: \.id) { item in
                    CinematicCard(
                        item: item,
                        caption: caption(item)
                    ) {
                        action(item)
                    }
                    .focused($focusedCardID, equals: item.id)
                }
            }
            .padding(.horizontal, CinematicHeroLayout.leadingMargin)
            .padding(.vertical, 24)
            .withViewContext(.isThumb)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .padding(.vertical, -24)
        .focusSection()
        .defaultFocus($focusedCardID, items.first?.id, priority: .userInitiated)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        FadeContentTransitionView(
            item: resolvedSelectedPoster,
            debounce: 0.5
        ) { item in
            ImageView(item?.imageSources(for: .landscape, environment: .init(viewContext: .isBackdrop)) ?? [])
                .failure {
                    EmptyView()
                }
                .aspectRatio(contentMode: .fill)
        }
        .overlay {
            // The still stays fully visible until the preview is actually rendering frames
            if previewItem != nil {
                HomePreviewPlayerView(player: preview.player) { isReady in
                    preview.layerReadyForDisplayChanged(isReady)
                }
                .ignoresSafeArea()
                .scaleEffect(preview.videoScale)
                .opacity(isPreviewVisible ? 1 : 0)
            }
        }
        .overlay {
            // Full-brightness art, darkened only toward the left (text) and bottom (row)
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.45),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.6),
                        .init(color: .black.opacity(0.85), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(isImmersive ? 0 : 1)
        }
        .frame(height: CinematicHeroLayout.screenHeight)
        .clipped()
    }
}

extension CinematicItemSelector where TopContent == EmptyView {

    init(
        items: [Item],
        action: @escaping (Item) -> Void = { _ in }
    ) {
        self.init(
            items: items,
            action: action
        ) { _ in
            EmptyView()
        }
    }
}

// MARK: - Card

/// 16:9 card with its caption and progress inside the artwork, like the Apple TV app's rows.
private struct CinematicCard<Item: Poster>: View {

    @Environment(\.self)
    private var environmentValues

    let item: Item
    let caption: CinematicCardCaption
    let action: () -> Void

    private var poster: AnyPoster {
        AnyPoster(item)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Same settings as other posters: show art (with its logo) for episodes by default
                ImageView(poster.imageSources(for: .landscape, environment: poster.resolveEnvironment(environmentValues)))
                    .failure {
                        Color.white.opacity(0.08)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: CinematicHeroLayout.cardWidth, height: CinematicHeroLayout.cardHeight)

                if caption.text != nil || caption.progress != nil {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        if let progress = caption.progress {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.caption2.weight(.bold))

                                ProgressView(value: min(max(progress, 0), 1))
                                    .progressViewStyle(CinematicCardProgressStyle())
                            }
                        }

                        if let text = caption.text {
                            Text(text)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
            }
            .frame(width: CinematicHeroLayout.cardWidth, height: CinematicHeroLayout.cardHeight)
            .clipShape(.rect(cornerRadius: CinematicHeroLayout.cardCornerRadius))
        }
        .buttonStyle(.card)
        .focusedValue(\.focusedPoster, AnyPoster(item))
        .accessibilityLabel(item.displayTitle)
    }
}

private struct CinematicCardProgressStyle: ProgressViewStyle {

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))

                Capsule()
                    .fill(Color.white)
                    .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Layout

/// Points measured from the Apple TV app's Home on a 1920x1080 screen.
enum CinematicHeroLayout {

    /// tvOS is always 1920x1080 points; the scroll view's own frame is shorter (safe area)
    static let screenHeight: CGFloat = 1080

    static let leadingMargin: CGFloat = 80

    /// Logo box top; a 150pt box bottom-aligned so a typical 110pt wordmark starts at ~380
    static let heroTop: CGFloat = 340
    /// Logo box (150) + metadata (Body), summary (2 lines of Caption 1), status (Body) and the
    /// 66pt button row centered at ~745
    static let heroHeight: CGFloat = 438

    /// Row title (Headline, 46pt line) centered at ~899, cards at 932
    static let heroToRowTitle: CGFloat = 98
    static let rowTitleHeight: CGFloat = 46
    /// The card button style adds ~19pt above the artwork, so this lands the cards at ~932
    static let rowTitleToCards: CGFloat = -9

    static let cardWidth: CGFloat = 320
    static let cardHeight: CGFloat = 180
    static let cardSpacing: CGFloat = 40
    static let cardCornerRadius: CGFloat = 16

    /// Cards start at 932 and run past the bottom edge (only their top ~148pt is on screen)
    static let containerHeight: CGFloat = 1150
}
