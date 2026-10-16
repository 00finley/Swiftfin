//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI
import SwiftUI

struct CinematicSelectionContentGroup: ContentGroup {

    let id = "cinematic-selection"
    let viewModel: CinematicSelectionContentGroupViewModel

    var _shouldBeResolved: Bool {
        viewModel.hasContent
    }

    init(
        resumeLibrary: ResumeItemsLibrary,
        recentlyAddedLibrary: RecentlyAddedLibrary
    ) {
        self.viewModel = CinematicSelectionContentGroupViewModel(
            resumeLibrary: resumeLibrary,
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

        /// "S2:E1 · Ooze · 20m" for episodes, "2025 · Animation · 1h 52m" otherwise.
        private func heroSubtitle(for item: BaseItemDto) -> String? {
            let parts: [String?] = if item.type == .episode {
                [item.seasonEpisodeLabel, item.displayTitle, item.progressLabel ?? item.runTimeLabel]
            } else {
                [item.productionYear.map(String.init), item.genres?.first, item.runTimeLabel]
            }
            let joined = parts.compactMap(\.self).filter(\.isNotEmpty).joined(separator: " · ")
            return joined.isEmpty ? nil : joined
        }

        var body: some View {
            let items = viewModel.hasResumeItems ? viewModel.resumeViewModel.elements.elements : viewModel.recentlyAddedViewModel.elements
                .elements

            CinematicItemSelector(
                items: items
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
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: CinematicSelectionLayout.overviewMaxWidth, alignment: .leading)
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
        viewModel.hasResumeItems && viewModel.recentlyAddedViewModel.elements.isNotEmpty
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
            async let resume: Void = viewModel.resumeViewModel.background.refresh()
            async let recentlyAdded: Void = viewModel.recentlyAddedViewModel.background.refresh()
            _ = await (resume, recentlyAdded)
        }
    }

    let recentlyAddedGroup: PosterGroup<RecentlyAddedLibrary>
    let resumeViewModel: PagingLibraryViewModel<ResumeItemsLibrary>

    var recentlyAddedViewModel: PagingLibraryViewModel<RecentlyAddedLibrary> {
        recentlyAddedGroup.viewModel
    }

    var background: Background {
        get { Background(viewModel: self) }
        set {}
    }

    var hasResumeItems: Bool {
        resumeViewModel.elements.isNotEmpty
    }

    var hasContent: Bool {
        hasResumeItems || recentlyAddedViewModel.elements.isNotEmpty
    }

    init(
        resumeLibrary: ResumeItemsLibrary,
        recentlyAddedLibrary: RecentlyAddedLibrary
    ) {
        self.resumeViewModel = PagingLibraryViewModel(library: resumeLibrary, pageSize: 20)
        self.recentlyAddedGroup = PosterGroup(library: recentlyAddedLibrary)

        super.init()

        resumeViewModel.objectWillChange
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
        async let resume: Void = resumeViewModel.refresh()
        async let recentlyAdded: Void = recentlyAddedViewModel.refresh()

        _ = await (resume, recentlyAdded)
    }
}

private enum CinematicSelectionLayout {

    static let logoMaxHeight: CGFloat = 170
    static let logoMaxWidth: CGFloat = 620
    static let overviewMaxWidth: CGFloat = 1000
}
