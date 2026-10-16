//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension NavigationRoute {

    static func featuredCollection(_ collection: FeaturedCollection) -> NavigationRoute {
        NavigationRoute(id: "featuredCollection-\(collection.id)") {
            FeaturedCollectionView(collection: collection)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Dates

extension FeaturedOccurrence {

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "MMMd"
        return formatter
    }()

    /// "Oct 21" or "Oct 1 – 31"
    var dateText: String {
        if isSingleDay {
            return Self.dayFormatter.string(from: event.lowerBound.date())
        }
        return Self.intervalFormatter.string(from: event.lowerBound.date(), to: event.upperBound.date())
    }

    /// For something featuring today: "Today", "Tomorrow", "Oct 21", "Through Oct 31" or "Starts Nov 1".
    func statusText(on day: CalendarDay) -> String {
        if isSingleDay {
            switch day.days(until: event.lowerBound) {
            case 0: return L10n.collectionsToday
            case 1: return L10n.collectionsTomorrow
            default: return dateText
            }
        }
        if day < event.lowerBound {
            return L10n.collectionsStarts(Self.dayFormatter.string(from: event.lowerBound.date()))
        }
        return L10n.collectionsThrough(Self.dayFormatter.string(from: event.upperBound.date()))
    }
}

// MARK: - Art

/// A collection's backdrop, cropped to fill, with a soft placeholder.
private struct FeaturedArt: View {

    let path: String?
    let size: CGSize
    var imageSize = "w1280"

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)

            ImageView(TMDBClient.imageURL(path, size: imageSize))
                .placeholder { _ in Color.clear }
                .failure { Color.clear }
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Small glass capsule ("Today", "Through Oct 31").
private struct FeaturedBadge: View {

    let text: String
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.black.opacity(0.2)), in: .capsule)
    }
}

// MARK: - Categories: hero and Featured Now

/// The top of Categories: today's featured collection as a wide hero, then a Featured Now row
/// of everything active. Shows nothing when collections are off or nothing is featuring.
struct FeaturedCollectionsSection: View {

    @ObservedObject
    var model: FeaturedCollectionsModel

    @Router
    private var router

    var body: some View {
        let active = model.active

        if let hero = active.first {
            VStack(alignment: .leading, spacing: 64) {
                FeaturedHeroBanner(occurrence: hero, model: model) {
                    router.route(to: .featuredCollection(hero.collection))
                }
                .padding(.horizontal, CategoriesLayout.margin)
                .focusSection()

                VStack(alignment: .leading, spacing: 30) {
                    Text(L10n.categoriesFeaturedNow)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, CategoriesLayout.margin)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: CategoriesLayout.gap) {
                            ForEach(active) { occurrence in
                                FeaturedCollectionCard(occurrence: occurrence, model: model) {
                                    router.route(to: .featuredCollection(occurrence.collection))
                                }
                            }
                        }
                        .padding(.horizontal, CategoriesLayout.margin)
                        .padding(.vertical, 30)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .padding(.vertical, -30)
                }
                .focusSection()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.categoriesFeaturedNow)
            }
        }
    }
}

/// Wide hero: the collection's textless art with Glassfin's title treatment on a glass band.
struct FeaturedHeroBanner: View {

    static let size = CGSize(width: 1760, height: 560)
    private static let cornerRadius: CGFloat = 24

    let occurrence: FeaturedOccurrence
    @ObservedObject
    var model: FeaturedCollectionsModel
    let action: () -> Void

    private var collection: FeaturedCollection {
        occurrence.collection
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                FeaturedArt(path: model.backdropPath(for: collection), size: Self.size)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.3),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                FeaturedBadge(text: "\(L10n.collectionsFeatured) · \(occurrence.statusText(on: model.today))", systemImage: "sparkles")
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(collection.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(collection.tagline)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.black.opacity(0.3)), in: .rect)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(DiscoverLiftButtonStyle(cornerRadius: Self.cornerRadius))
        .accessibilityLabel(collection.title)
        .accessibilityValue("\(collection.tagline), \(occurrence.statusText(on: model.today))")
    }
}

/// Featured Now card: 560-wide 16:9 art with the title and dates on a glass band (3 across).
struct FeaturedCollectionCard: View {

    static let size = CGSize(width: 560, height: 315)
    private static let cornerRadius: CGFloat = 20

    let occurrence: FeaturedOccurrence
    @ObservedObject
    var model: FeaturedCollectionsModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                FeaturedArt(path: model.backdropPath(for: occurrence.collection), size: Self.size, imageSize: "w780")

                VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.collection.title)
                        .font(.callout)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(occurrence.statusText(on: model.today))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(DiscoverLiftButtonStyle(cornerRadius: Self.cornerRadius))
        .accessibilityLabel(occurrence.collection.title)
        .accessibilityValue(occurrence.statusText(on: model.today))
    }
}

// MARK: - Categories: Celebrate

/// Every collection, year-round: featuring now first, then by date.
struct CelebrateSection: View {

    @ObservedObject
    var model: FeaturedCollectionsModel

    @Router
    private var router

    var body: some View {
        let occurrences = model.celebrate

        if occurrences.isNotEmpty {
            VStack(alignment: .leading, spacing: 30) {
                Text(L10n.categoriesCelebrate)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityAddTraits(.isHeader)

                // Not lazy, like the other groups: focus must reach tiles below the fold
                VStack(alignment: .leading, spacing: 48) {
                    ForEach(Array(stride(from: 0, to: occurrences.count, by: 5)), id: \.self) { start in
                        HStack(spacing: CategoriesLayout.gap) {
                            ForEach(occurrences[start ..< min(start + 5, occurrences.count)]) { occurrence in
                                CelebrateTile(occurrence: occurrence, isActive: occurrence.window.contains(model.today)) {
                                    router.route(to: .featuredCollection(occurrence.collection))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, CategoriesLayout.margin)
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.categoriesCelebrate)
        }
    }
}

/// A category-sized tile with the collection's date in a corner.
struct CelebrateTile: View {

    let occurrence: FeaturedOccurrence
    let isActive: Bool
    let action: () -> Void

    private var caption: String {
        isActive ? L10n.collectionsNow : occurrence.dateText
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                FeaturedArt(path: occurrence.collection.backdropPath, size: CategoryTile.size, imageSize: "w780")

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.35),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Featuring now: solid white with a dark label; otherwise the date on glass
                Text(caption)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isActive ? Color.black : Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background {
                        if isActive {
                            Capsule().fill(.white)
                        }
                    }
                    .glassEffect(isActive ? .identity : .regular.tint(.black.opacity(0.25)), in: .capsule)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Text(occurrence.collection.title)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect)
            }
            .frame(width: CategoryTile.size.width, height: CategoryTile.size.height)
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.card)
        .accessibilityLabel(occurrence.collection.title)
        .accessibilityValue(caption)
    }
}

// MARK: - Collection page

/// One collection: its art and tagline, shelf chips (Spooky Fun / Family & Animated / Scarier),
/// Movies / TV chips, and the For You grid with pins first, "In Library" badges and Request on the title page.
struct FeaturedCollectionView: View {

    let collection: FeaturedCollection

    @StateObject
    private var viewModel: CategoryResultsViewModel
    @StateObject
    private var feed = DiscoverViewModel.shared
    @ObservedObject
    private var model = FeaturedCollectionsModel.shared

    @State
    private var shelf: FeaturedCollection.Shelf

    init(collection: FeaturedCollection) {
        self.collection = collection
        let shelf = collection.shelves[0]
        _shelf = State(initialValue: shelf)
        _viewModel = StateObject(wrappedValue: CategoryResultsViewModel(
            query: collection.query(for: shelf),
            pinnedKeys: collection.pins(for: shelf)
        ))
    }

    private var occurrence: FeaturedOccurrence? {
        collection.nextOccurrence(from: model.today)
    }

    /// Movies and TV the shelf can show at all (Easter is movies only)
    private var shelfKinds: [DiscoverTitle.Kind] {
        collection.query(for: shelf).kinds
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                header

                if collection.shelves.count > 1 || shelfKinds.count > 1 {
                    chips
                }

                DiscoverTitleGrid(pager: viewModel.pager, feed: feed)

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, CategoriesLayout.margin)
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                CategoriesLayout.background

                ImageView(TMDBClient.imageURL(model.backdropPath(for: collection), size: "w1280"))
                    .placeholder { _ in Color.clear }
                    .failure { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 1920, height: 760)
                    .clipped()
                    .opacity(0.55)
                    .mask {
                        LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            SeerrStatusStore.installRequestHandler()
            feed.ensureLibrary()
            feed.prepareTaste()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let occurrence {
                FeaturedBadge(
                    text: occurrence.window.contains(model.today) ? occurrence.statusText(on: model.today) : occurrence.dateText,
                    systemImage: "calendar"
                )
            }

            Text(collection.title)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Text(collection.tagline)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .frame(maxWidth: 1100, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.5), radius: 10)
        .padding(.horizontal, CategoriesLayout.margin)
        .padding(.top, 220)
    }

    private var chips: some View {
        HStack(spacing: 16) {
            if collection.shelves.count > 1 {
                ForEach(collection.shelves) { option in
                    let isSelected = option.id == shelf.id
                    Button(option.title) {
                        select(option)
                    }
                    .buttonStyle(GlassChipButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                Spacer()
                    .frame(width: 24)
            }

            if shelfKinds.count > 1 {
                mediaChip(.both, L10n.categoriesMoviesAndTV)
                mediaChip(.movies, L10n.movies)
                mediaChip(.tv, L10n.categoriesTV)
            }
        }
        .padding(.horizontal, CategoriesLayout.margin)
        .focusSection()
    }

    private func select(_ option: FeaturedCollection.Shelf) {
        guard option.id != shelf.id else { return }

        shelf = option
        var query = collection.query(for: option, media: viewModel.query.media)
        if query.kinds.isEmpty {
            query.media = .both
        }
        viewModel.pinnedKeys = collection.pins(for: option)
        viewModel.query = query
    }

    private func mediaChip(_ media: BrowseQuery.Media, _ title: String) -> some View {
        let isSelected = viewModel.query.media == media

        return Button(title) {
            viewModel.query.media = media
        }
        .buttonStyle(GlassChipButtonStyle(isSelected: isSelected))
        .disabled(!media.kinds.contains(where: shelfKinds.contains))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Home row

/// "Halloween Picks" among Home's Discover rows: the hero collection's For You picks, then See All.
struct FeaturedCollectionHomeRow: View {

    @ObservedObject
    var feed: DiscoverViewModel
    @ObservedObject
    private var model = FeaturedCollectionsModel.shared

    @Router
    private var router

    var body: some View {
        if let collection = model.active.first?.collection {
            let items = model.visiblePicks(for: collection).prefix(15).map { title in
                DiscoverItem(
                    title: title,
                    providers: [],
                    libraryItemID: feed.libraryItemIDs[title.id],
                    reason: [title.kind == .tv ? L10n.tvShow : L10n.movie, title.year].compactMap(\.self).joined(separator: " · ")
                )
            }

            if items.count >= 4 {
                let title = L10n.collectionsPicks(collection.title)

                VStack(alignment: .leading, spacing: 30) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .edgePadding(.horizontal)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                            ForEach(items) { item in
                                DiscoverCard(item: item, viewModel: feed, width: 320) {
                                    router.route(to: .discoverTitle(item: item, feed: feed))
                                }
                            }

                            seeAll(collection)
                        }
                        .edgePadding(.horizontal)
                        .padding(.vertical, 20)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .padding(.vertical, -20)
                }
                .focusSection()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
            }
        }
    }

    private func seeAll(_ collection: FeaturedCollection) -> some View {
        Button {
            router.route(to: .featuredCollection(collection))
        } label: {
            ZStack {
                FeaturedArt(path: model.backdropPath(for: collection), size: CategoryTile.size, imageSize: "w780")
                    .blur(radius: 18)
                    .overlay(Color.black.opacity(0.35))

                Label(L10n.collectionsSeeAll, systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .frame(width: CategoryTile.size.width, height: CategoryTile.size.height)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.card)
        .accessibilityLabel(L10n.collectionsSeeAll)
        .accessibilityValue(collection.title)
    }
}
