//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Categories tab: title search plus grouped category tiles (genres, moods, formats, eras, acclaimed,
/// languages, services, family). Picking a tile opens results that can be narrowed with more categories.
struct CategoriesView: View {

    @StateObject
    private var search = CategorySearchViewModel()
    @StateObject
    private var feed = DiscoverViewModel.shared

    @Default(.Discover.providers)
    private var providers
    @Default(.Discover.region)
    private var region

    @State
    private var logos: [Int: String] = [:]

    @Router
    private var router

    private var groups: [(group: BrowseCategory.Group, categories: [BrowseCategory])] {
        BrowseCategory.grouped(providers: providers, logos: logos)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 64) {
                header
                    .focusSection()

                if search.isActive {
                    DiscoverTitleGrid(pager: search.pager, feed: feed, emptyText: L10n.categoriesNoSearchResults)
                } else {
                    ForEach(groups, id: \.group) { entry in
                        groupSection(entry.group, categories: entry.categories)
                    }
                }

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, CategoriesLayout.margin)
            }
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(CategoriesLayout.background.ignoresSafeArea())
        .onAppear {
            SeerrStatusStore.installRequestHandler()
            feed.ensureLibrary()
        }
        .task(id: region) {
            if let logos = try? await TMDBClient.shared.providerLogos(region: region) {
                self.logos = logos
            }
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            GlassSearchField(text: $search.text, prompt: L10n.categoriesSearchPrompt)

            Button {
                router.route(to: .discoverSettings)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(GlassChipButtonStyle(isCircle: true))
            .accessibilityLabel(L10n.settings)
        }
        .padding(.horizontal, CategoriesLayout.margin)
    }

    private func groupSection(_ group: BrowseCategory.Group, categories: [BrowseCategory]) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(group.title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityAddTraits(.isHeader)

            // Not lazy: tiles below the fold must exist for focus to move into them
            VStack(alignment: .leading, spacing: 48) {
                ForEach(Array(stride(from: 0, to: categories.count, by: 5)), id: \.self) { start in
                    HStack(spacing: CategoriesLayout.gap) {
                        ForEach(categories[start ..< min(start + 5, categories.count)]) { category in
                            CategoryTile(category: category) {
                                router.route(to: .categoryResults(category))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, CategoriesLayout.margin)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.title)
    }
}

// MARK: - Results

/// Results for one or more categories, with glass filter chips that combine
/// (e.g. Korean + Thriller + 2010s, TV only, Top Rated).
struct CategoryResultsView: View {

    @StateObject
    private var viewModel: CategoryResultsViewModel
    @StateObject
    private var feed = DiscoverViewModel.shared

    @Router
    private var router

    init(category: BrowseCategory) {
        _viewModel = StateObject(wrappedValue: CategoryResultsViewModel(query: BrowseQuery(categories: [category])))
    }

    private var title: String {
        let names = viewModel.query.categories.map(\.title)
        return names.isEmpty ? L10n.categoriesEverything : names.joined(separator: " · ")
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, CategoriesLayout.margin)
                    .accessibilityAddTraits(.isHeader)

                filterBar

                DiscoverTitleGrid(pager: viewModel.pager, feed: feed)

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, CategoriesLayout.margin)
            }
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(CategoriesLayout.background.ignoresSafeArea())
        .onAppear {
            SeerrStatusStore.installRequestHandler()
            feed.ensureLibrary()
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChipFlowLayout(spacing: 20, lineSpacing: 24) {
                ForEach(viewModel.query.categories) { category in
                    Button {
                        viewModel.query.remove(category)
                    } label: {
                        Label(category.title, systemImage: "xmark")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(GlassChipButtonStyle(isSelected: true))
                    .accessibilityLabel(category.title)
                    .accessibilityHint(L10n.categoriesRemoveHint)
                }

                Button {
                    router.route(to: .categoryPicker(viewModel))
                } label: {
                    Label(L10n.categoriesAddCategory, systemImage: "plus")
                }
                .buttonStyle(GlassChipButtonStyle())
            }
            .focusSection()

            HStack(spacing: 16) {
                mediaChip(.both, L10n.categoriesMoviesAndTV)
                mediaChip(.movies, L10n.movies)
                mediaChip(.tv, L10n.categoriesTV)

                Spacer()
                    .frame(width: 24)

                Button {
                    viewModel.query.onMyServices.toggle()
                } label: {
                    Label(L10n.categoriesOnMyServices, systemImage: viewModel.query.onMyServices ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(GlassChipButtonStyle(isSelected: viewModel.query.onMyServices))
                .accessibilityAddTraits(viewModel.query.onMyServices ? .isSelected : [])

                Spacer()
                    .frame(width: 24)

                sortChip(.popular, L10n.categoriesPopular)
                sortChip(.topRated, L10n.categoriesTopRated)
                sortChip(.newest, L10n.categoriesNewest)
            }
            .focusSection()
        }
        .padding(.horizontal, CategoriesLayout.margin)
    }

    private func mediaChip(_ media: BrowseQuery.Media, _ title: String) -> some View {
        let isSelected = viewModel.query.media == media
        // A TV-only category (e.g. Limited Series) can't show movies
        let isPossible = media.kinds.contains { kind in viewModel.query.categories.allSatisfy { $0.clause(for: kind) != nil } }

        return Button(title) {
            viewModel.query.media = media
        }
        .buttonStyle(GlassChipButtonStyle(isSelected: isSelected))
        .disabled(!isPossible)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sortChip(_ sort: BrowseQuery.Sort, _ title: String) -> some View {
        let isSelected = viewModel.query.sort == sort

        return Button(title) {
            viewModel.query.sort = sort
        }
        .buttonStyle(GlassChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TrailingIconLabelStyle: LabelStyle {

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.title
            configuration.icon
                .font(.caption)
        }
    }
}

// MARK: - Picker

/// Adds a category on top of the current ones; picking a selected one removes it.
struct CategoryPickerView: View {

    @ObservedObject
    var viewModel: CategoryResultsViewModel

    @Default(.Discover.providers)
    private var providers

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 48) {
                Text(L10n.categoriesAddCategory)
                    .font(.title2)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                ForEach(BrowseCategory.grouped(providers: providers, logos: [:]), id: \.group) { entry in
                    VStack(alignment: .leading, spacing: 24) {
                        Text(entry.group.title)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.75))
                            .accessibilityAddTraits(.isHeader)

                        ChipFlowLayout(spacing: 20, lineSpacing: 24) {
                            ForEach(entry.categories) { category in
                                let isSelected = viewModel.query.categories.contains { $0.id == category.id }

                                Button {
                                    viewModel.toggle(category)
                                    dismiss()
                                } label: {
                                    if isSelected {
                                        Label(category.title, systemImage: "checkmark")
                                    } else {
                                        Text(category.title)
                                    }
                                }
                                .buttonStyle(GlassChipButtonStyle(isSelected: isSelected))
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    .focusSection()
                }
            }
            .padding(.horizontal, CategoriesLayout.margin)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(CategoriesLayout.background.ignoresSafeArea())
    }
}
