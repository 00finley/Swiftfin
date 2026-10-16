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

// TODO: when used for single seasons, have title as just "Episodes" or
//       have functionality in PosterGroup

struct SeriesEpisodeContentGroup: ContentGroup, Identifiable {

    let id: String
    @OptionalSharedBaseItem
    var playButtonItem: BaseItemDto?
    let viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    init(
        parent: BaseItemDto,
        playButtonItem: BaseItemDto? = nil
    ) {
        self.id = "\(parent.id ?? "parent")-episode-selector"
        self.playButtonItem = playButtonItem
        self.viewModel = .init(library: SeasonViewModelLibrary(parent: parent), pageSize: 100)
    }

    func body(with viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>) -> Body {
        Body(
            viewModel: viewModel,
            playButtonItem: playButtonItem
        )
    }

    struct Body: View {

        @ObservedObject
        var viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        @OptionalSharedBaseItem
        var playButtonItem: BaseItemDto?

        @State
        private var selection: PagingLibraryViewModel<EpisodeLibrary>.ID?

        private var selectedSeasonViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            viewModel.elements.first { $0.id == selection }
        }

        /// The last season that finished loading. When the item changes on the server (an import, a
        /// watched state), the page rebuilds this group with fresh season view models that start out
        /// empty; showing placeholders then removed the focused card and focus jumped back to the
        /// top of the page. Until the new season has content, keep showing this one.
        @State
        private var lastLoadedSeason: PagingLibraryViewModel<EpisodeLibrary>?

        private var displayedSeasonViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            if let selectedSeasonViewModel, selectedSeasonViewModel.state == .content {
                return selectedSeasonViewModel
            }
            if let lastLoadedSeason, lastLoadedSeason.id == selection {
                return lastLoadedSeason
            }
            return selectedSeasonViewModel
        }

        private func rememberLoadedSeason() {
            if let selectedSeasonViewModel, selectedSeasonViewModel.state == .content,
               lastLoadedSeason !== selectedSeasonViewModel
            {
                lastLoadedSeason = selectedSeasonViewModel
            }
        }

        private var seasonSelectorView: some View {
            SeasonSelector(
                seasons: Array(viewModel.elements),
                selection: $selection,
                preferredSelection: selection ?? preferredSeasonSelection()
            )
        }

        private func preferredSeasonSelection() -> PagingLibraryViewModel<EpisodeLibrary>.ID? {
            if let playButtonSeasonID = playButtonItem?.seasonID,
               viewModel.elements.contains(where: { $0.id == playButtonSeasonID })
            {
                return playButtonSeasonID
            }

            return viewModel.elements.first?.id
        }

        private func selectPreferredSeasonIfNeeded() {
            if selection == nil || !viewModel.elements.contains(where: { $0.id == selection }) {
                selection = preferredSeasonSelection()
            }
        }

        private func refreshSelectedSeasonIfNeeded() {
            guard let selectedSeasonViewModel, selectedSeasonViewModel.state == .initial else { return }

            selectedSeasonViewModel.refresh()
        }

        @ViewBuilder
        var body: some View {
            Group {
                if let displayedSeasonViewModel {
                    SeasonEpisodesView(
                        seasonViewModel: displayedSeasonViewModel,
                        playButtonItem: playButtonItem
                    ) {
                        seasonSelectorView
                    }
                } else {
                    LoadingEpisodesView {
                        seasonSelectorView
                    }
                }
            }
            .onFirstAppear {
                selectPreferredSeasonIfNeeded()
                refreshSelectedSeasonIfNeeded()
            }
            .onChange(of: viewModel.elements.map(ObjectIdentifier.init)) {
                selectPreferredSeasonIfNeeded()
                refreshSelectedSeasonIfNeeded()
            }
            .onChange(of: selection) {
                refreshSelectedSeasonIfNeeded()
            }
            // Swap to a rebuilt season once it has loaded (nothing else observes it while hidden)
            .onReceive(
                (selectedSeasonViewModel?.objectWillChange.eraseToAnyPublisher() ?? Combine.Empty<Void, Never>().eraseToAnyPublisher())
                    .receive(on: RunLoop.main)
            ) { _ in
                rememberLoadedSeason()
            }
            .onAppear(perform: rememberLoadedSeason)
        }
    }
}
