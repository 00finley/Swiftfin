//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct SearchView: View {

    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters

    @FocusState
    private var isSearchFocused: Bool

    #if os(tvOS)
    @FocusState
    private var focusedFilter: FilterTrack.FocusTarget?
    #endif

    @State
    private var searchQuery = ""

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel = SearchViewModel()

    @Router
    private var router

    @TabItemSelected
    private var tabItemSelected

    @ViewBuilder
    private var suggestionsView: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.suggestions)
                .font(.title3)
                .fontWeight(.semibold)
                .edgePadding(.horizontal)

            PosterHStack(
                elements: viewModel.suggestions,
                displayType: .portrait,
                size: .small
            ) { item, _ in
                router.route(to: .item(item: item))
            }
            .frame(height: 420)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        VStack(spacing: 20) {
            ForEach(viewModel.suggestions) { item in
                Button(item.displayTitle) {
                    searchQuery = item.displayTitle
                }
            }
        }
        #endif
    }

    #if os(tvOS)
    private var showsFilters: Bool {
        enabledDrawerFilters.isNotEmpty && (viewModel.canSearch || viewModel.filterViewModel.hasActiveFilters)
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(tvOS)
                if showsFilters {
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            FilterTrack(viewModel: viewModel.filterViewModel, types: enabledDrawerFilters, focus: $focusedFilter)
                        }
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                    .frame(height: 64)
                    .coordinatedFocusScope(
                        $focusedFilter,
                        values: enabledDrawerFilters.map(FilterTrack.FocusTarget.filter) +
                            (viewModel.filterViewModel.hasActiveFilters ? [.reset] : [])
                    )
                    .edgePadding(.horizontal)
                    .padding(.vertical, EdgeInsets.itemSpacing)
                }
                #endif

                ZStack {
                    switch viewModel.state {
                    case .error:
                        viewModel.error.map(ErrorView.init)

                    case .initial:
                        if viewModel.canSearch {
                            if viewModel.isEmpty {
                                Text(L10n.noResults)
                            } else {
                                ContentGroupVStack(
                                    groups: viewModel.itemContentGroupViewModel.groups
                                )
                            }
                        } else {
                            suggestionsView
                        }

                    case .searching:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .focusSection()
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .scrollIndicators(.hidden)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .ignoresSafeArea(.keyboard)
        .navigationTitle(L10n.search)
        .toolbarTitleDisplayMode(.inline)
        .searchFocused($isSearchFocused)
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
        .onFirstAppear {
            viewModel.getSuggestions()
        }
        .onChange(of: searchQuery) {
            viewModel.search(query: searchQuery)
        }
        .searchable(
            text: $searchQuery,
            prompt: L10n.search
        )
        .environmentObject(focusCoordinator)
        #if os(tvOS)
        .modifier(SearchSafeAreaModifier())
        .onReceive(viewModel.filterViewModel.$currentFilters) { filters in
            searchQuery = filters.query ?? ""
        }
        #endif
        #if os(iOS)
        .navigationBarFilterDrawer(
            viewModel: viewModel.filterViewModel,
            types: enabledDrawerFilters
        )
        #endif
    }
}
