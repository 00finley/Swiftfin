//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Detail page for a Discover title, styled like the library's cinematic item page.
struct DiscoverTitleView: View {

    @StateObject
    private var viewModel: DiscoverTitleViewModel
    @ObservedObject
    var feed: DiscoverViewModel
    @ObservedObject
    private var seerr = SeerrStatusStore.shared

    @State
    private var isRequesting = false
    @State
    private var toast: Toast?

    @Router
    private var router

    init(item: DiscoverItem, feed: DiscoverViewModel) {
        _viewModel = StateObject(wrappedValue: DiscoverTitleViewModel(item: item))
        self.feed = feed
    }

    private var item: DiscoverItem {
        viewModel.item
    }

    private struct Toast: Equatable {
        let message: String
        let isError: Bool
    }

    /// Seerr status for titles that aren't already in the library (nil when Seerr isn't set up).
    private var requestStatus: SeerrStatus? {
        guard viewModel.libraryItemID == nil, SeerrClient.isConfigured, DiscoverRequests.handler != nil else { return nil }

        return seerr.status(for: item.title) ?? .notRequested
    }

    private func request() {
        guard let handler = DiscoverRequests.handler, !isRequesting else { return }

        isRequesting = true

        Task {
            do {
                try await handler(item.title)
                show(Toast(message: L10n.seerrRequestedToast, isError: false))
            } catch {
                show(Toast(message: error.localizedDescription, isError: true))
            }
            isRequesting = false
        }
    }

    /// Opens the YouTube app at the trailer (a deep link only; nothing is streamed here).
    private func openTrailer(_ key: String) {
        guard let trailer = ExternalTrailerURL(string: "https://www.youtube.com/watch?v=\(key)"), trailer.canBeOpened else {
            show(Toast(message: L10n.discoverYouTubeNotInstalled, isError: true))
            return
        }

        UIApplication.shared.open(trailer.deepLink) { success in
            if !success {
                show(Toast(message: L10n.discoverYouTubeNotInstalled, isError: true))
            }
        }
    }

    private func show(_ newToast: Toast) {
        withAnimation(.easeOut(duration: 0.25)) {
            toast = newToast
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast == newToast {
                withAnimation(.easeIn(duration: 0.25)) {
                    toast = nil
                }
            }
        }
    }

    private var infoLine: String {
        let details = viewModel.details
        let region = Defaults[.Discover.region]
        let genres = details?.genres.prefix(2).map(\.name).joined(separator: ", ")
        let length: String? = if let seasons = details?.seasons, item.title.kind == .tv {
            seasons == 1 ? L10n.discoverOneSeason : L10n.discoverSeasons(seasons)
        } else if let minutes = details?.runtimeMinutes, minutes > 0 {
            Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        } else {
            nil
        }
        let rating = item.title.voteCount >= 20 ? String(format: "★ %.1f", item.title.voteAverage) : nil

        return [item.title.year, genres, details?.certificationsByRegion[region], length, rating]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 56) {
                header
                    .focusSection()

                if viewModel.moreLikeThis.isNotEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L10n.discoverMoreLikeThis)
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal, 80)

                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 40) {
                                ForEach(viewModel.moreLikeThis) { entry in
                                    DiscoverCard(item: entry, viewModel: feed) {
                                        router.route(to: .discoverTitle(item: entry, feed: feed))
                                    }
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

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
            }
        }
        .scrollClipDisabled()
        .background {
            DiscoverBackground(item: item, isHeroVisible: true)
        }
        .overlay(alignment: .top) {
            if let toast {
                Label(toast.message, systemImage: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 18)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .task {
            await viewModel.load()
        }
        .task(id: viewModel.libraryItemID) {
            guard viewModel.libraryItemID == nil, SeerrClient.isConfigured else { return }

            _ = try? await seerr.refresh(item.title)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            DiscoverTitleLogo(item: item, height: 170, maxWidth: 680, logoPath: viewModel.details?.logoPath)

            if infoLine.isNotEmpty {
                Text(infoLine)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let overview = viewModel.details?.title.overview ?? item.title.overview, overview.isNotEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            availability

            HStack(spacing: 24) {
                if let libraryItemID = viewModel.libraryItemID {
                    Button {
                        router.route(to: .item(id: libraryItemID))
                    } label: {
                        Label(L10n.discoverOpenInLibrary, systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                }

                if let requestStatus {
                    if requestStatus == .notRequested {
                        Button(action: request) {
                            Label(L10n.seerrRequest, systemImage: isRequesting ? "ellipsis" : "plus")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .disabled(isRequesting)
                    } else if let title = requestStatus.badgeTitle {
                        // Status only; not focusable
                        Label(title, systemImage: requestStatus.systemImage)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .glassEffect(.regular, in: .capsule)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }

                if let trailerKey = viewModel.details?.trailerKey {
                    Button {
                        openTrailer(trailerKey)
                    } label: {
                        Label(L10n.discoverWatchTrailer, systemImage: "play.rectangle")
                    }
                    .buttonStyle(GlassChipButtonStyle())
                }

                DiscoverRatingControl(title: item.title, feed: feed) { level in
                    if level == .disliked {
                        show(Toast(message: L10n.discoverHiddenToast, isError: false))
                    }
                }
            }
            .padding(.top, 8)
        }
        .shadow(color: .black.opacity(0.35), radius: 12)
        .padding(.horizontal, 80)
        .frame(height: 840, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var availability: some View {
        if viewModel.providers.isNotEmpty {
            HStack(spacing: 18) {
                Text(L10n.discoverAvailableOn(viewModel.providers.map(\.name).prefix(3).joined(separator: ", ")))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))

                DiscoverProviderLogos(providers: Array(viewModel.providers.prefix(5)), size: 52)
            }
        } else if viewModel.details != nil {
            Text(L10n.discoverNotStreaming)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

/// Love It / Like It / It's OK / Not for Me as one row of glass choices; the current rating is
/// white with a dark label, like the focused choice. Picking the current rating again clears it.
struct DiscoverRatingControl: View {

    let title: DiscoverTitle
    let feed: DiscoverViewModel
    var onRate: (DiscoverRatingLevel) -> Void = { _ in }

    @Default(.Discover.profile)
    private var profile

    var body: some View {
        let current = profile.level(for: title.id)

        HStack(spacing: 16) {
            ForEach(DiscoverRatingLevel.displayOrder, id: \.self) { level in
                // It's OK shows as chosen only when it overrides a seeded rating
                let isSelected = level == current && (level != .neutral || profile.ratings[title.id]?.level == .neutral)

                Button {
                    let newLevel = isSelected ? DiscoverRatingLevel.neutral : level
                    feed.rate(title, newLevel)
                    onRate(newLevel)
                } label: {
                    Label(level.title, systemImage: isSelected ? level.selectedSystemImage : level.systemImage)
                }
                .buttonStyle(GlassChipButtonStyle(isSelected: isSelected, solidSelection: true))
                .accessibilityLabel(level.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.discoverRate)
    }
}
