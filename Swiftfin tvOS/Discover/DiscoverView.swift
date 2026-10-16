//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// One combined, personalized feed across the user's streaming services.
struct DiscoverView: View {

    @StateObject
    private var viewModel = DiscoverViewModel()

    @Router
    private var router

    @FocusState
    private var focusedItemID: String?

    private var focusedItem: DiscoverItem? {
        guard let focusedItemID else { return viewModel.hero }

        return viewModel.rows.lazy.flatMap(\.items).first { $0.id == focusedItemID } ?? viewModel.hero
    }

    var body: some View {
        ZStack {
            DiscoverBackground(item: focusedItem, isHeroVisible: focusedItemID == nil)

            switch viewModel.state {
            case .loading:
                ProgressView()

            case .error:
                DiscoverMessage(text: L10n.discoverLoadFailed) {
                    viewModel.refresh(force: true)
                }

            case .loaded:
                if viewModel.rows.isEmpty, viewModel.hero == nil {
                    DiscoverMessage(text: L10n.discoverNothingYet, retry: nil)
                } else {
                    feed
                }
            }
        }
        .onAppear {
            SeerrStatusStore.installRequestHandler()
            viewModel.refreshIfNeeded()
        }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            // Not lazy: off-screen rows must exist for focus to move into them
            VStack(alignment: .leading, spacing: 56) {
                if let hero = viewModel.hero {
                    DiscoverHero(item: hero, viewModel: viewModel) {
                        open(hero)
                    }
                    .focusSection()
                }

                ForEach(viewModel.rows) { row in
                    DiscoverRowView(row: row, viewModel: viewModel, focusedItemID: $focusedItemID) { item in
                        open(item)
                    }
                }

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
            }
        }
        .scrollClipDisabled()
    }

    private func open(_ item: DiscoverItem) {
        router.route(to: .discoverTitle(item: item, feed: viewModel))
    }
}

// MARK: - Hero

/// Full-bleed top pick: title, why it was picked, a short summary and actions.
private struct DiscoverHero: View {

    let item: DiscoverItem
    @ObservedObject
    var viewModel: DiscoverViewModel
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            DiscoverTitleLogo(item: item, height: 150, maxWidth: 640)

            if let reason = item.reason {
                Text(reason)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let overview = item.title.overview, overview.isNotEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            HStack(spacing: 24) {
                Button(action: action) {
                    Label(L10n.discoverDetails, systemImage: "info.circle")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)

                Button {
                    viewModel.moreLikeThis(item.title)
                } label: {
                    Label(L10n.discoverMoreLikeThis, systemImage: "hand.thumbsup")
                }
                .buttonStyle(.glass)

                Button {
                    viewModel.notInterested(item.title)
                } label: {
                    Label(L10n.discoverNotInterested, systemImage: "hand.thumbsdown")
                }
                .buttonStyle(.glass)

                DiscoverProviderLogos(providers: item.providers, size: 44)
                    .padding(.leading, 12)
            }
            .padding(.top, 10)
        }
        .shadow(color: .black.opacity(0.35), radius: 12)
        .padding(.horizontal, 80)
        .frame(height: 760, alignment: .bottomLeading)
    }
}

// MARK: - Row

private struct DiscoverRowView: View {

    let row: DiscoverRow
    @ObservedObject
    var viewModel: DiscoverViewModel
    var focusedItemID: FocusState<String?>.Binding
    let open: (DiscoverItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(row.title)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 80)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(row.items) { item in
                        DiscoverCard(item: item, viewModel: viewModel) {
                            open(item)
                        }
                        .focused(focusedItemID, equals: item.id)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

// MARK: - Card

/// 16:9 backdrop card with the service and in-library badges, title and subtitle below.
struct DiscoverCard: View {

    let item: DiscoverItem
    @ObservedObject
    var viewModel: DiscoverViewModel
    let action: () -> Void

    @ObservedObject
    private var seerr = SeerrStatusStore.shared

    /// "Requested" / "Available" etc. from Seerr, for titles not already in the library.
    private var requestBadge: SeerrStatus? {
        guard !item.isInLibrary, let status = seerr.status(for: item.title), status != .notRequested else { return nil }

        return status
    }

    static let width: CGFloat = 400

    /// The reason when there is one (it's the useful part), otherwise the year.
    private var subtitle: String {
        item.reason ?? item.title.year ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: action) {
                ZStack {
                    ImageView(TMDBClient.imageURL(item.title.backdropPath, size: "w780"))
                        .placeholder { _ in Color.white.opacity(0.08) }
                        .failure { Color.white.opacity(0.08) }
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: Self.width, height: Self.width * 9 / 16)
                        .clipped()

                    if let provider = item.providers.first {
                        DiscoverProviderLogos(providers: [provider], size: 40)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }

                    if item.isInLibrary {
                        Label(L10n.discoverInLibrary, systemImage: "checkmark")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else if let requestBadge, let title = requestBadge.badgeTitle {
                        Label(title, systemImage: requestBadge.systemImage)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(width: Self.width, height: Self.width * 9 / 16)
            }
            .buttonStyle(.card)
            .contextMenu {
                Button(L10n.discoverMoreLikeThis, systemImage: "hand.thumbsup") {
                    viewModel.moreLikeThis(item.title)
                }
                Button(L10n.discoverNotInterested, systemImage: "hand.thumbsdown", role: .destructive) {
                    viewModel.notInterested(item.title)
                }
            }
            .accessibilityLabel(item.title.title)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if subtitle.isNotEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .onAppear {
            if !item.isInLibrary {
                seerr.prefetch(item.title)
            }
        }
    }
}

// MARK: - Shared pieces

/// Streaming service logos (TMDB provides square app icons).
struct DiscoverProviderLogos: View {

    let providers: [DiscoverProvider]
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(providers) { provider in
                ImageView(TMDBClient.imageURL(provider.logoPath, size: "w92"))
                    .placeholder { _ in EmptyView() }
                    .failure { EmptyView() }
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.22))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    .accessibilityLabel(provider.name)
            }
        }
    }
}

/// The title's logo artwork from TMDB, or its name in large type while loading or when missing.
struct DiscoverTitleLogo: View {

    let item: DiscoverItem
    let height: CGFloat
    let maxWidth: CGFloat
    var logoPath: String?

    @State
    private var loadedLogoPath: String?

    private var resolvedPath: String? {
        logoPath ?? loadedLogoPath
    }

    var body: some View {
        Group {
            if let resolvedPath {
                ImageView(TMDBClient.imageURL(resolvedPath, size: "w500"))
                    .placeholder { _ in titleText }
                    .failure { titleText }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: height, alignment: .bottomLeading)
            } else {
                titleText
            }
        }
        .frame(height: height, alignment: .bottomLeading)
        .task(id: item.id) {
            guard logoPath == nil else { return }

            loadedLogoPath = try? await TMDBClient.shared.details(kind: item.title.kind, id: item.title.tmdbID).logoPath
        }
        .accessibilityLabel(item.title.title)
    }

    private var titleText: some View {
        Text(item.title.title)
            .font(.system(size: 76, weight: .bold))
            .kerning(-1.5)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: maxWidth, alignment: .bottomLeading)
    }
}

/// Blurred art of the focused title behind everything; sharp at the top while the hero shows.
struct DiscoverBackground: View {

    let item: DiscoverItem?
    let isHeroVisible: Bool

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.059)

            if let item {
                ImageView(TMDBClient.imageURL(item.title.backdropPath, size: "w1280"))
                    .placeholder { _ in EmptyView() }
                    .failure { EmptyView() }
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: isHeroVisible ? 0 : 50)
                    .opacity(isHeroVisible ? 1 : 0.55)
                    .id(item.id)
                    .transition(.opacity)
            }

            // Keep text readable: darken bottom and leading edge
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.55), location: 0.6),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .center
            )
        }
        .animation(.easeOut(duration: 0.4), value: item?.id)
        .animation(.easeOut(duration: 0.4), value: isHeroVisible)
        .ignoresSafeArea()
    }
}

private struct DiscoverMessage: View {

    let text: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 30) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)

            if let retry {
                Button(L10n.retry, action: retry)
                    .buttonStyle(.glassProminent)
                    .tint(.white)
            }
        }
    }
}
