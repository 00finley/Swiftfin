//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

// MARK: - Shelf

/// A Home row: a `.title3` header and a horizontal row of cards, inset 60 pt like the library rows.
struct HomeShelf<Content: View>: View {

    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .edgePadding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                    content
                }
                .edgePadding(.horizontal)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.vertical, -20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Card

/// 16:9 card sized like Home's landscape library cards (5 across), with the title and a subtitle
/// below the art and an optional glass badge in its top-leading corner.
struct HomeRowCard<Artwork: View>: View {

    /// (1920 − 2 × 60 inset − 4 × 40 spacing) / 5, the width of Home's landscape poster cards
    static var width: CGFloat {
        328
    }

    let title: String
    let subtitle: String?
    var badge: String?
    var badgeSystemImage: String?
    var accessibilityLabel: String?
    let action: () -> Void
    @ViewBuilder
    let artwork: () -> Artwork

    private var width: CGFloat {
        Self.width
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.08)

                artwork()
                    .frame(width: width, height: width * 9 / 16)
                    .clipped()

                if let badge {
                    HomeCardBadge(text: badge, systemImage: badgeSystemImage)
                        .padding(14)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(.rect(cornerRadius: 12))
            .hoverEffect(.highlight)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)

                Text(subtitle ?? " ")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.roundedRectangle)
        .foregroundStyle(.primary, .secondary)
        .frame(width: width, alignment: .leading)
        .accessibilityLabel(accessibilityLabel ?? [title, subtitle].compactMap(\.self).joined(separator: ", "))
    }
}

/// Small glass capsule on a card ("New", "Today").
struct HomeCardBadge: View {

    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .fill(Color.black.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

/// Landscape art for a library item: its Thumb (usually titled), else a Backdrop, else Primary.
struct HomeLibraryArtwork: View {

    let itemID: String
    var imageTags: [String: String]?
    var hasBackdrop = true
    var maxWidth: CGFloat = HomeRowCard<EmptyView>.width

    var body: some View {
        ImageView(HomeImages.landscapeURLs(itemID: itemID, imageTags: imageTags, hasBackdrop: hasBackdrop, maxWidth: maxWidth))
            .placeholder { _ in Color.clear }
            .failure { Color.clear }
            .aspectRatio(contentMode: .fill)
    }
}

/// Art for a TMDB title that isn't in the library, the same titled art Discover uses.
struct HomeTMDBArtwork: View {

    let kind: DiscoverTitle.Kind
    let tmdbID: Int
    var fallbackName: String?

    @State
    private var title: DiscoverTitle?

    var body: some View {
        Group {
            if let title {
                DiscoverCardArtwork(title: title, width: HomeRowCard<EmptyView>.width)
            } else {
                ZStack(alignment: .bottomLeading) {
                    Color.white.opacity(0.08)

                    if let fallbackName {
                        Text(fallbackName)
                            .font(.headline)
                            .lineLimit(2)
                            .padding(18)
                    }
                }
            }
        }
        .task(id: tmdbID) {
            guard title == nil, TMDBClient.isAvailable else { return }

            title = try? await TMDBClient.shared.details(kind: kind, id: tmdbID).title
        }
    }
}

enum HomeImages {

    /// Image URLs for a library item, best first; `ImageView` falls through them.
    static func landscapeURLs(itemID: String, imageTags: [String: String]?, hasBackdrop: Bool, maxWidth: CGFloat) -> [URL?] {
        var types: [ImageType] = []
        if imageTags?["Thumb"] != nil {
            types.append(.thumb)
        }
        if hasBackdrop {
            types.append(.backdrop)
        }
        types.append(.primary)

        return types.map { url(itemID: itemID, type: $0, maxWidth: maxWidth, tag: $0 == .thumb ? imageTags?["Thumb"] : nil) }
    }

    static func url(itemID: String, type: ImageType, maxWidth: CGFloat, tag: String? = nil) -> URL? {
        guard let client = Container.shared.currentUserSession()?.client else { return nil }

        let scale = UITraitCollection.current.displayScale
        let parameters = Paths.GetItemImageParameters(
            maxWidth: Int(maxWidth * max(1, scale)),
            quality: 90,
            tag: tag,
            format: type == .logo ? .png : nil
        )
        return client.url(with: Paths.getItemImage(itemID: itemID, imageType: type.rawValue, parameters: parameters))
    }
}

// MARK: - Formatting

enum HomeRowFormat {

    /// "S4, E7", or "S5, E1–E2" for several episodes on the same day.
    static func episodeLabel(season: Int?, episodes: [Int]) -> String? {
        guard let season, let first = episodes.min() else { return nil }

        let last = episodes.max() ?? first
        return last == first ? "S\(season), E\(first)" : "S\(season), E\(first)–E\(last)"
    }

    /// "Today", "Tomorrow", a weekday within the next week ("Friday"), else "Oct 24".
    static func relativeDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: start, to: day).day ?? 0

        switch offset {
        case 0: return L10n.today
        case 1: return L10n.tomorrow
        case 2 ..< 7: return date.formatted(.dateTime.weekday(.wide))
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

// MARK: - Library index

/// The user's movies and shows keyed by TMDB and TVDB id, for matching Seerr and Sonarr titles to
/// library items. Loaded once and shared by the Home rows for a few minutes.
@MainActor
final class HomeLibraryIndex {

    struct Snapshot {
        var items: [BaseItemDto] = []
        var byKey: [String: BaseItemDto] = [:]
        var seriesByTVDB: [Int: BaseItemDto] = [:]

        /// `"tv-1396"` / `"movie-550"`, Discover's key format
        func item(kind: DiscoverTitle.Kind, tmdbID: Int?) -> BaseItemDto? {
            guard let tmdbID else { return nil }

            return byKey["\(kind.rawValue)-\(tmdbID)"]
        }
    }

    static let shared = HomeLibraryIndex()

    private var snapshot: Snapshot?
    private var loadedAt: Date?
    private var userID: String?
    private var task: Task<Snapshot, Error>?

    /// The index, reloaded when older than `maxAge` or after switching users.
    func load(maxAge: TimeInterval = 5 * 60) async throws -> Snapshot {
        guard let session = Container.shared.currentUserSession() else { return Snapshot() }

        if userID == session.user.id, let snapshot, let loadedAt, Date.now.timeIntervalSince(loadedAt) < maxAge {
            return snapshot
        }
        if userID == session.user.id, let task {
            return try await task.value
        }

        userID = session.user.id
        let task = Task<Snapshot, Error> {
            var parameters = Paths.GetItemsParameters()
            parameters.userID = session.user.id
            parameters.isRecursive = true
            parameters.includeItemTypes = [.series, .movie]
            parameters.fields = [.providerIDs, .genres, .overview]
            parameters.enableUserData = true
            parameters.enableImageTypes = [.primary, .backdrop, .thumb, .logo]
            parameters.imageTypeLimit = 1

            let items = try await session.client.send(Paths.getItems(parameters: parameters)).value.items ?? []

            var snapshot = Snapshot(items: items)
            for item in items {
                let kind: DiscoverTitle.Kind = item.type == .movie ? .movie : .tv
                if let tmdb = item.providerIDs?["Tmdb"].flatMap(Int.init) {
                    snapshot.byKey["\(kind.rawValue)-\(tmdb)"] = item
                }
                if kind == .tv, let tvdb = item.providerIDs?["Tvdb"].flatMap(Int.init) {
                    snapshot.seriesByTVDB[tvdb] = item
                }
            }
            return snapshot
        }
        self.task = task
        defer { self.task = nil }

        let result = try await task.value
        snapshot = result
        loadedAt = .now
        return result
    }

    func invalidate() {
        loadedAt = nil
    }
}

/// Waits for `operation` up to `seconds`, so Home's first paint can include a row that answers
/// quickly without ever waiting long on a slow service. The work keeps running past the timeout.
@MainActor
func homeAwait(upTo seconds: Double, _ task: Task<Void, Never>) async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await task.value }
        group.addTask { try? await Task.sleep(for: .seconds(seconds)) }
        await group.next()
        group.cancelAll()
    }
}

// MARK: - Glass button

/// tvOS 26 glass button: Liquid Glass with a white label, solid white with a dark label when
/// focused (the Apple TV app's hero buttons).
struct HomeGlassButtonStyle<S: Shape>: ButtonStyle {

    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        HomeGlassButtonBody(configuration: configuration, shape: shape)
    }
}

extension ButtonStyle where Self == HomeGlassButtonStyle<Capsule> {

    static var homeGlass: HomeGlassButtonStyle<Capsule> {
        HomeGlassButtonStyle(shape: Capsule())
    }
}

private struct HomeGlassButtonBody<S: Shape>: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration
    let shape: S

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background {
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: shape)
                        .opacity(isFocused ? 0 : 1)
                    shape.fill(Color.white)
                        .opacity(isFocused ? 1 : 0)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 1.04 : (isFocused ? 1.1 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
