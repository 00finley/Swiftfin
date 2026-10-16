//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

enum CategoriesLayout {

    /// Apple TV app horizontal margin
    static let margin: CGFloat = 80
    /// 5-column tvOS grid: 5 × 320 + 4 × 40 = 1760
    static let tileWidth: CGFloat = 320
    /// 4-column tvOS grid: 4 × 410 + 3 × 40 = 1760
    static let resultWidth: CGFloat = 410
    static let gap: CGFloat = 40

    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
}

// MARK: - Chips

/// Liquid Glass chip: glass while unfocused (tinted when selected), solid white with a dark label when focused.
struct GlassChipButtonStyle: ButtonStyle {

    var isSelected = false
    var isCircle = false

    func makeBody(configuration: Configuration) -> some View {
        GlassChipBody(configuration: configuration, isSelected: isSelected, isCircle: isCircle)
    }
}

private struct GlassChipBody: View {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled

    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let isCircle: Bool

    private var glass: Glass {
        isSelected ? .regular.tint(.white.opacity(0.3)) : .regular
    }

    var body: some View {
        configuration.label
            .font(.body)
            .fontWeight(.semibold)
            .lineLimit(1)
            .padding(.horizontal, isCircle ? 0 : 28)
            .padding(.vertical, isCircle ? 0 : 14)
            .frame(width: isCircle ? 72 : nil, height: isCircle ? 72 : nil)
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(isEnabled ? 1 : 0.4))
            .background {
                Capsule()
                    .fill(.white)
                    .opacity(isFocused ? 1 : 0)
            }
            .glassEffect(isFocused ? .identity : glass, in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 1.02 : (isFocused ? 1.08 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 16, y: 8)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Wrapping row layout for chips.
struct ChipFlowLayout: Layout {

    var spacing: CGFloat = 20
    var lineSpacing: CGFloat = 24

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if extra > width, row.indices.isNotEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if row.indices.isNotEmpty {
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Tile

/// A category tile: representative backdrop with the name on a glass band so it stays legible on any art.
struct CategoryTile: View {

    static let size = CGSize(width: CategoriesLayout.tileWidth, height: CategoriesLayout.tileWidth * 9 / 16)

    let category: BrowseCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)

                ImageView(TMDBClient.imageURL(category.backdropPath, size: "w780"))
                    .placeholder { _ in Color.clear }
                    .failure { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.6), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let logoPath = category.logoPath {
                    ImageView(TMDBClient.imageURL(logoPath, size: "w154"))
                        .placeholder { _ in EmptyView() }
                        .failure { EmptyView() }
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                        .padding(.top, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                Text(category.title)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.card)
        .accessibilityLabel(category.title)
    }
}

// MARK: - Results grid

/// 4-across 16:9 grid of TMDB titles with infinite paging, "In Library" badges and the
/// user's Not Interested titles left out.
struct DiscoverTitleGrid: View {

    @ObservedObject
    var pager: DiscoverTitlePager
    @ObservedObject
    var feed: DiscoverViewModel
    var emptyText: String = L10n.categoriesNoMatches

    @Default(.Discover.profile)
    private var profile

    @Router
    private var router

    private var items: [DiscoverItem] {
        pager.titles
            .filter { profile.dismissed.contains($0.id) == false }
            .map { title in
                DiscoverItem(
                    title: title,
                    providers: [],
                    libraryItemID: feed.libraryItemIDs[title.id],
                    reason: [title.kind == .tv ? L10n.tvShow : L10n.movie, title.year].compactMap(\.self).joined(separator: " · ")
                )
            }
    }

    private let columns = Array(
        repeating: GridItem(.fixed(CategoriesLayout.resultWidth), spacing: CategoriesLayout.gap, alignment: .top),
        count: 4
    )

    var body: some View {
        switch pager.phase {
        case .idle:
            EmptyView()

        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 300)

        case .failed:
            message(L10n.discoverLoadFailed)

        case .loaded:
            if items.isEmpty {
                message(emptyText)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                    ForEach(items) { item in
                        DiscoverCard(item: item, viewModel: feed, width: CategoriesLayout.resultWidth) {
                            router.route(to: .discoverTitle(item: item, feed: feed))
                        }
                        .onAppear {
                            pager.loadMoreIfNeeded(after: item.title)
                        }
                    }
                }
                .padding(.horizontal, CategoriesLayout.margin)
                .focusSection()

                if pager.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 240)
            .accessibilityAddTraits(.isStaticText)
    }
}
