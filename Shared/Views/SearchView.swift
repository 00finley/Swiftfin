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

    /// TMDB titles to request, below the library results (Settings → Discover)
    @StateObject
    private var requestable = SearchDiscoverViewModel()
    @StateObject
    private var discoverFeed = DiscoverViewModel.shared

    /// Ask Glassfin (glassfin-helper) under the search field; hidden when the helper isn't configured
    @Default(.Discover.askEnabled)
    private var askEnabled
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
                if AskGlassfin.isAvailable(enabled: askEnabled) {
                    AskSearchAction(query: searchQuery) {
                        let question = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        router.route(to: .askGlassfin(query: question.isEmpty ? nil : question))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .edgePadding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, showsFilters ? 0 : 30)
                    .focusSection()
                }

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
                                #if os(tvOS)
                                if !requestable.hasItems(libraryItemIDs: discoverFeed.libraryItemIDs) {
                                    Text(L10n.noResults)
                                }
                                #else
                                Text(L10n.noResults)
                                #endif
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

                #if os(tvOS)
                if viewModel.canSearch, viewModel.state != .searching {
                    SearchDiscoverSection(viewModel: requestable, feed: discoverFeed)
                }
                #endif
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
            #if os(tvOS)
            requestable.search(searchQuery)
            #endif
        }
        .searchable(
            text: $searchQuery,
            prompt: L10n.search
        )
        .environmentObject(focusCoordinator)
        #if os(tvOS)
        .modifier(SearchSafeAreaModifier())
        .onReceive(viewModel.filterViewModel.$currentFilters) { filters in
            // The filter stores the query trimmed; writing that back would eat the space just typed
            // ("something like" → "somethinglike"), so only sync real changes (e.g. Reset)
            let query = filters.query ?? ""
            if query != searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                searchQuery = query
            }
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
