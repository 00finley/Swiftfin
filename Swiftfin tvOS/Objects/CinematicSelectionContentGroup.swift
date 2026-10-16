//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
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

        /// "S2:E1 · Ooze" for episodes, "2025 · Animation · 1h 52m" otherwise.
        private func heroSubtitle(for item: BaseItemDto) -> String? {
            let parts: [String?] = if item.type == .episode {
                [item.seasonEpisodeLabel, item.displayTitle]
            } else {
                [item.productionYear.map(String.init), item.genres?.first, item.runTimeLabel]
            }
            let joined = parts.compactMap(\.self).filter(\.isNotEmpty).joined(separator: " · ")
            return joined.isEmpty ? nil : joined
        }

        var body: some View {
            let showsUpNext = viewModel.hasUpNext
            let items = showsUpNext ? viewModel.upNextViewModel.elements.elements : viewModel.recentlyAddedViewModel.elements
                .elements

            CinematicItemSelector(
                items: items,
                title: showsUpNext ? viewModel.upNextViewModel.library.parent.displayTitle : L10n.recentlyAdded.localizedCapitalized
            ) { item in
                router.route(to: .item(item: item.snapshot))
            } topContent: { item in
                VStack(alignment: .leading, spacing: 16) {
                    ImageView(itemSelectorImageSource(for: item.snapshot))
                        .placeholder { _ in
                            EmptyView()
                        }
                        .failure {
                            Text(item.displayTitle)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(height: CinematicSelectionLayout.logoMaxHeight, alignment: .bottomLeading)
                        .frame(maxWidth: CinematicSelectionLayout.logoMaxWidth, alignment: .leading)

                    if let subtitle = heroSubtitle(for: item.snapshot) {
                        Text(subtitle)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    if let overview = item.snapshot.overview, overview.isNotEmpty {
                        Text(overview)
                            .font(.callout)
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: CinematicSelectionLayout.overviewMaxWidth, alignment: .leading)
                    }

                    if item.snapshot.isHeroPlayable {
                        HeroPlayButton(item: item.snapshot)
                            .padding(.top, 8)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 12)
                .edgePadding(.leading)
            }
            .preference(
                key: ContentGroupCustomizationKey.self,
                value: .ignoreSafeAreaTop
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
}

/// White Resume/Play capsule for the hero, matching the item page's PlayButton.
private struct HeroPlayButton: View {

    @Default(.accentColor)
    private var accentColor

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
            HStack(spacing: 16) {
                Image(systemName: "play.fill")

                VStack(spacing: 2) {
                    Text(item.playActionTitle)

                    if let subtitle = item.playActionSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .opacity(0.7)
                    }
                }
            }
            .font(.callout)
            .fontWeight(.semibold)
            .frame(width: CinematicSelectionLayout.playButtonWidth, height: 75)
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
    }
}

private enum CinematicSelectionLayout {

    static let playButtonWidth: CGFloat = 420

    static let logoMaxHeight: CGFloat = 170
    static let logoMaxWidth: CGFloat = 620
    static let overviewMaxWidth: CGFloat = 860
}
