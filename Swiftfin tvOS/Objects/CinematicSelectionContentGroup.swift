//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

struct CinematicSelectionContentGroup: ContentGroup {

    let id = "cinematic-selection"
    let viewModel: CinematicSelectionContentGroupViewModel

    var _shouldBeResolved: Bool {
        viewModel.hasContent
    }

    init(
        upNextLibrary: UpNextLibrary,
        recentlyAddedLibrary: RecentlyAddedLibrary
    ) {
        self.viewModel = CinematicSelectionContentGroupViewModel(
            upNextLibrary: upNextLibrary,
            recentlyAddedLibrary: recentlyAddedLibrary
        )
    }

    func body(with viewModel: CinematicSelectionContentGroupViewModel) -> some View {
        SelectionView(viewModel: viewModel)
    }

    private struct SelectionView: View {

        @Environment(\.frameForParentView)
        private var frameForParentView

        @ObservedObject
        var viewModel: CinematicSelectionContentGroupViewModel

        @Router
        private var router

        @StateObject
        private var preview = HomePreviewController()

        @FocusState
        private var isHeroFocused

        private func heroOptions(showsUpNext: Bool) -> ContentGroupParentOption {
            var options: ContentGroupParentOption = .ignoreSafeAreaTop
            if isHeroFocused {
                options.insert(.pinsToTop)
            }
            if showsUpNext, preview.isImmersive {
                options.insert(.immersiveHero)
            }
            return options
        }

        private var parentFrame: CGRect {
            frameForParentView[.scrollView, default: .zero].frame
        }

        private func itemSelectorImageSource(for item: BaseItemDto) -> ImageSource? {
            if item.type == .episode {
                item.imageSource(
                    .logo,
                    itemID: item.parentLogoItemID,
                    tag: item.parentLogoImageTag,
                    environment: ImageSourceOptions(
                        maxWidth: CinematicSelectionLayout.logoMaxWidth,
                        maxHeight: CinematicSelectionLayout.logoMaxHeight
                    )
                )
            } else {
                item.imageSource(
                    .logo,
                    itemID: item.id,
                    environment: ImageSourceOptions(
                        maxWidth: CinematicSelectionLayout.logoMaxWidth,
                        maxHeight: CinematicSelectionLayout.logoMaxHeight
                    )
                )
            }
        }

        /// "TV Show · Drama", like the Apple TV app's hero; the rating is shown as a badge.
        /// Episodes often have no genres of their own, so the series fills them in.
        private func heroMetadata(for item: BaseItemDto) -> String? {
            let parts: [String?] = if item.type == .episode {
                [L10n.tvShow]
            } else {
                [item.type?.displayTitle, item.genres?.first, item.productionYear.map(String.init)]
            }
            return Self.joined(parts)
        }

        /// "S4, E2 · Redcoats · 32m left" for episodes; time left or runtime otherwise.
        private func heroStatus(for item: BaseItemDto) -> String? {
            let remaining = item.hasPlaybackProgress ? item.progressLabel.map(L10n.timeRemaining) : nil
            let parts: [String?] = if item.type == .episode {
                [item.heroSeasonEpisodeLabel, item.displayTitle, remaining]
            } else {
                [remaining ?? item.runTimeLabel]
            }
            return Self.joined(parts)
        }

        /// Card caption: "S4, E2 · 32m" plus a progress bar, inside the artwork.
        private func cardCaption(for item: BaseItemDto) -> CinematicCardCaption {
            let progress = item.hasPlaybackProgress ? item.userData?.playedPercentage.map { $0 / 100 } : nil
            let time = item.hasPlaybackProgress ? item.progressLabel : item.runTimeLabel
            let text: String? = if item.type == .episode {
                Self.joined([item.heroSeasonEpisodeLabel, time])
            } else {
                Self.joined([item.displayTitle, time])
            }
            return CinematicCardCaption(text: text, progress: progress)
        }

        private static func joined(_ parts: [String?]) -> String? {
            let joined = parts.compactMap(\.self).filter(\.isNotEmpty).joined(separator: " · ")
            return joined.isEmpty ? nil : joined
        }

        /// Selecting the card while its preview is playing continues into full playback from the
        /// preview's position; otherwise it opens the item.
        private func select(_ item: ItemEntry) {
            let snapshot = item.snapshot

            if let ticks = preview.currentTicks(for: snapshot.id),
               let provider = snapshot.getPlaybackItemProvider(userSession: nil)?.modifyingItem({ value in
                   var data = value.userData ?? UserItemDataDto(key: value.id ?? "")
                   data.playbackPositionTicks = ticks
                   value.userData = data
               })
            {
                preview.focusChanged(to: nil)
                router.route(
                    to: .videoPlayer(
                        provider: provider,
                        queue: snapshot.type == .episode ? EpisodeMediaPlayerQueue(episode: snapshot) : nil
                    )
                )
            } else {
                router.route(to: .item(item: snapshot))
            }
        }

        /// Lower-left details, spaced from Apple TV app measurements (see CinematicHeroLayout):
        /// a 150pt logo box, metadata, a two-line summary, a status line and the button row.
        @ViewBuilder
        private func heroDetails(for item: ItemEntry) -> some View {
            let snapshot = item.snapshot

            VStack(alignment: .leading, spacing: 0) {
                ImageView(itemSelectorImageSource(for: snapshot))
                    .placeholder { _ in
                        EmptyView()
                    }
                    .failure {
                        Text(item.displayTitle)
                            .font(.title2.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        maxWidth: CinematicSelectionLayout.logoMaxWidth,
                        maxHeight: CinematicSelectionLayout.logoMaxHeight,
                        alignment: .bottomLeading
                    )
                    .frame(height: CinematicSelectionLayout.logoMaxHeight, alignment: .bottomLeading)
                    .padding(.bottom, 21)

                HeroMetadataLine(item: snapshot, baseText: heroMetadata(for: snapshot))
                    .frame(height: 36, alignment: .leading)
                    .padding(.bottom, 23)

                Text(snapshot.overview ?? "")
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: CinematicSelectionLayout.overviewMaxWidth, alignment: .leading)
                    .frame(height: 64, alignment: .topLeading)
                    .padding(.bottom, 12)

                Text(heroStatus(for: snapshot) ?? "")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(height: 36, alignment: .leading)
                    .padding(.bottom, 30)

                if snapshot.isHeroPlayable {
                    HStack(spacing: 20) {
                        HeroPlayButton(item: snapshot)

                        HeroFavoriteButton(item: item)

                        HeroCircleButton(systemImage: "info", label: L10n.moreInformation) {
                            router.route(to: .item(item: snapshot))
                        }
                    }
                    .frame(height: CinematicSelectionLayout.buttonHeight)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .padding(.leading, CinematicHeroLayout.leadingMargin)
        }

        var body: some View {
            let showsUpNext = viewModel.hasUpNext
            let items = showsUpNext ? viewModel.upNextViewModel.elements.elements : viewModel.recentlyAddedViewModel.elements
                .elements

            CinematicItemSelector(
                items: items,
                title: showsUpNext ? viewModel.upNextViewModel.library.parent.displayTitle : L10n.recentlyAdded.localizedCapitalized,
                preview: showsUpNext ? preview : nil,
                previewItem: { $0.snapshot },
                caption: { cardCaption(for: $0.snapshot) }
            ) { item in
                if showsUpNext {
                    select(item)
                } else {
                    router.route(to: .item(item: item.snapshot))
                }
            } topContent: { item in
                heroDetails(for: item)
            }
            .focused($isHeroFocused)
            .preference(
                key: ContentGroupCustomizationKey.self,
                value: heroOptions(showsUpNext: showsUpNext)
            )
        }
    }
}

struct CinematicRecentlyAddedContentGroup: ContentGroup {

    let id = "cinematic-recently-added"
    let viewModel: CinematicSelectionContentGroupViewModel

    var _shouldBeResolved: Bool {
        viewModel.hasUpNext && viewModel.recentlyAddedViewModel.elements.isNotEmpty
    }

    func body(with viewModel: CinematicSelectionContentGroupViewModel) -> some View {
        PosterHStackLibrarySection(
            viewModel: viewModel.recentlyAddedViewModel,
            group: viewModel.recentlyAddedGroup
        )
    }
}

final class CinematicSelectionContentGroupViewModel: ViewModel, WithRefresh {

    struct Background: WithRefresh {

        let viewModel: CinematicSelectionContentGroupViewModel

        func refresh() {
            Task { await refresh() }
        }

        func refresh() async {
            async let upNext: Void = viewModel.upNextViewModel.background.refresh()
            async let recentlyAdded: Void = viewModel.recentlyAddedViewModel.background.refresh()
            _ = await (upNext, recentlyAdded)
        }
    }

    let recentlyAddedGroup: PosterGroup<RecentlyAddedLibrary>
    let upNextViewModel: PagingLibraryViewModel<UpNextLibrary>

    var recentlyAddedViewModel: PagingLibraryViewModel<RecentlyAddedLibrary> {
        recentlyAddedGroup.viewModel
    }

    var background: Background {
        get { Background(viewModel: self) }
        set {}
    }

    var hasUpNext: Bool {
        upNextViewModel.elements.isNotEmpty
    }

    var hasContent: Bool {
        hasUpNext || recentlyAddedViewModel.elements.isNotEmpty
    }

    init(
        upNextLibrary: UpNextLibrary,
        recentlyAddedLibrary: RecentlyAddedLibrary
    ) {
        self.upNextViewModel = PagingLibraryViewModel(library: upNextLibrary, pageSize: 20)
        self.recentlyAddedGroup = PosterGroup(library: recentlyAddedLibrary)

        super.init()

        upNextViewModel.objectWillChange
            .merge(with: recentlyAddedViewModel.objectWillChange)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        async let upNext: Void = upNextViewModel.refresh()
        async let recentlyAdded: Void = recentlyAddedViewModel.refresh()

        _ = await (upNext, recentlyAdded)
    }
}

private extension BaseItemDto {

    var isHeroPlayable: Bool {
        type == .episode || type == .movie || type == .video
    }

    /// "S4, E2", the Apple TV app's format
    var heroSeasonEpisodeLabel: String? {
        guard let season = parentIndexNumber, let episode = indexNumber else { return nil }

        return "S\(season), E\(episode)"
    }
}

/// Metadata line with the series' genre and rating badge (episodes rarely carry their own).
private struct HeroMetadataLine: View {

    /// Series genre and rating, cached for the session
    @MainActor
    private static var seriesInfo: [String: (genre: String?, rating: String?)] = [:]

    let item: BaseItemDto
    let baseText: String?

    @State
    private var info: (genre: String?, rating: String?)?

    private var genre: String? {
        item.genres?.first ?? info?.genre
    }

    private var rating: String? {
        item.officialRating ?? info?.rating
    }

    var body: some View {
        HStack(spacing: 14) {
            if let text = [baseText, genre].compactMap(\.self).filter(\.isNotEmpty).joined(separator: " · ").nilIfEmpty {
                Text(text)
            }

            if let rating, rating.isNotEmpty {
                Text(rating)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                    }
            }
        }
        .font(.body)
        .foregroundStyle(.white)
        .task(id: item.seriesID) {
            guard item.type == .episode, let seriesID = item.seriesID else { return }

            if let cached = Self.seriesInfo[seriesID] {
                info = cached
                return
            }
            guard let session = Container.shared.currentUserSession(),
                  let series = try? await session.client.send(Paths.getItem(itemID: seriesID, userID: session.user.id)).value
            else { return }

            let value = (genre: series.genres?.first, rating: series.officialRating)
            Self.seriesInfo[seriesID] = value
            info = value
        }
    }
}

private extension String {

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// tvOS 26 hero buttons: dark glass with a white label until focused, then solid white with a
/// dark label, like the Apple TV app.
private struct HeroGlassButtonStyle<S: InsettableShape>: ButtonStyle {

    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        HeroGlassButtonBody(configuration: configuration, shape: shape)
    }
}

private struct HeroGlassButtonBody<S: InsettableShape>: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration
    let shape: S

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.black.opacity(0.35))
                    shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    shape.fill(Color.white)
                        .opacity(isFocused ? 1 : 0)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 1.1 : (isFocused ? 1.15 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Resume/Play capsule for the hero.
private struct HeroPlayButton: View {

    @Router
    private var router

    let item: BaseItemDto

    var body: some View {
        Button {
            guard let provider = item.getPlaybackItemProvider(userSession: nil) else { return }

            router.route(
                to: .videoPlayer(
                    provider: provider,
                    queue: item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil
                )
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")

                Text(item.hasPlaybackProgress ? L10n.resume : L10n.play)
            }
            .font(.body.weight(.semibold))
            .frame(width: CinematicSelectionLayout.playButtonWidth, height: CinematicSelectionLayout.buttonHeight)
        }
        .buttonStyle(HeroGlassButtonStyle(shape: Capsule()))
    }
}

private struct HeroCircleButton: View {

    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: CinematicSelectionLayout.buttonHeight, height: CinematicSelectionLayout.buttonHeight)
        }
        .buttonStyle(HeroGlassButtonStyle(shape: Circle()))
        .accessibilityLabel(label)
    }
}

/// "+" adds the item to favorites; a checkmark shows once it's a favorite.
private struct HeroFavoriteButton: View {

    let item: ItemEntry

    private var isFavorite: Bool {
        item.snapshot.userData?.isFavorite == true
    }

    var body: some View {
        HeroCircleButton(
            systemImage: isFavorite ? "checkmark" : "plus",
            label: isFavorite ? L10n.removeFromFavorites : L10n.addToFavorites
        ) {
            Task { @MainActor in
                guard let session = Container.shared.currentUserSession() else { return }

                do {
                    try await session.setFavorite(item, to: !isFavorite)
                } catch {
                    session.itemActionErrors.send(error)
                }
            }
        }
    }
}

private enum CinematicSelectionLayout {

    // Measured from the Apple TV app at 1920x1080
    static let playButtonWidth: CGFloat = 218
    static let buttonHeight: CGFloat = 66

    static let logoMaxHeight: CGFloat = 150
    static let logoMaxWidth: CGFloat = 520
    static let overviewMaxWidth: CGFloat = 480
}
