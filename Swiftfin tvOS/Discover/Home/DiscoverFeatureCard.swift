//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Apple TV app feature card: tall 560×700 key art with the badge, logo,
/// "TV Show · Genre · Genre" line and a status line inside, bottom-left.
struct DiscoverFeatureCard: View {

    static let size = CGSize(width: 560, height: 700)
    private static let cornerRadius: CGFloat = 24

    let item: DiscoverItem
    let genreNames: [Int: String]
    @ObservedObject
    var feed: DiscoverViewModel
    let action: () -> Void

    @ObservedObject
    private var seerr = SeerrStatusStore.shared

    @State
    private var details: TMDBDetails?
    @State
    private var didLoadDetails = false

    private var title: DiscoverTitle {
        item.title
    }

    /// "TV Show · Mystery · Thriller"
    private var metadata: String {
        let genres = details.map { $0.genres.map(\.name) } ?? title.genreIDs.compactMap { genreNames[$0] }
        let kind = title.kind == .tv ? L10n.tvShow : L10n.movie
        return ([kind] + genres.prefix(2)).joined(separator: " · ")
    }

    private var badge: (text: String, systemImage: String?)? {
        if item.isInLibrary {
            return (L10n.discoverInLibrary, "checkmark")
        }
        if let status = seerr.status(for: title), let text = status.badgeTitle {
            return (text, status.systemImage)
        }
        if let date = title.releaseDate {
            let age = Date.now.timeIntervalSince(date)
            if age < 0 {
                return (L10n.discoverComingSoon, nil)
            }
            if age < 45 * 86400 {
                return (L10n.discoverNew, nil)
            }
        }
        return nil
    }

    /// Textless key art crops well to 4:5; otherwise the backdrop's center.
    private var artworkURL: URL? {
        if let poster = details?.textlessPosterPath {
            return TMDBClient.imageURL(poster, size: "w780")
        }
        return TMDBClient.imageURL(title.backdropPath ?? title.posterPath, size: "w1280")
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Color.white.opacity(0.06)

                if didLoadDetails {
                    ImageView(artworkURL)
                        .placeholder { _ in Color.clear }
                        .failure { Color.clear }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.size.width, height: Self.size.height)
                        .clipped()
                        .transition(.opacity)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.55), location: 0.65),
                        .init(color: .black.opacity(0.88), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 16) {
                    if let badge {
                        Label {
                            Text(badge.text)
                        } icon: {
                            if let systemImage = badge.systemImage {
                                Image(systemName: systemImage)
                            }
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                    }

                    logo

                    HStack(spacing: 12) {
                        if let provider = item.providers.first {
                            DiscoverProviderLogos(providers: [provider], size: 40)
                                .clipShape(.circle)
                        }
                        Text(metadata)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if let reason = item.reason {
                        Text(reason)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 8)
                .padding(40)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(DiscoverLiftButtonStyle(cornerRadius: Self.cornerRadius))
        .contextMenu {
            DiscoverFeedbackMenu(title: title, feed: feed)
        }
        .accessibilityLabel(title.title)
        .accessibilityValue([metadata, item.reason].compactMap(\.self).joined(separator: ", "))
        .task(id: item.id) {
            details = try? await TMDBClient.shared.details(kind: title.kind, id: title.tmdbID)
            withAnimation(.easeOut(duration: 0.25)) {
                didLoadDetails = true
            }
        }
        .onAppear {
            if !item.isInLibrary {
                seerr.prefetch(title)
            }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let logoPath = details?.logoPath {
            ImageView(TMDBClient.imageURL(logoPath, size: "w500"))
                .placeholder { _ in titleText }
                .failure { titleText }
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 130, alignment: .bottomLeading)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title.title)
            .font(.system(size: 50, weight: .bold))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 480, alignment: .leading)
    }
}

/// Top 10 card: 260 pt portrait art with a big rank numeral inside, top-left.
struct DiscoverTop10Card: View {

    static let size = CGSize(width: 260, height: 390)
    private static let cornerRadius: CGFloat = 16

    let item: DiscoverItem
    let rank: Int
    @ObservedObject
    var feed: DiscoverViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                ImageView(TMDBClient.imageURL(item.title.posterPath ?? item.title.backdropPath, size: "w500"))
                    .placeholder { _ in Color.white.opacity(0.06) }
                    .failure { Color.white.opacity(0.06) }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipped()

                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .center)

                Text("\(rank)")
                    .font(.system(size: 110, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .padding(.leading, 16)
                    .padding(.top, -6)

                if item.isInLibrary {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(10)
                        .glassEffect(.regular, in: .circle)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .accessibilityLabel(L10n.discoverInLibrary)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(DiscoverLiftButtonStyle(cornerRadius: Self.cornerRadius))
        .contextMenu {
            DiscoverFeedbackMenu(title: item.title, feed: feed)
        }
        .accessibilityLabel("\(rank). \(item.title.title)")
    }
}

/// More Like This / Not Interested, for long-press menus.
struct DiscoverFeedbackMenu: View {

    let title: DiscoverTitle
    let feed: DiscoverViewModel

    var body: some View {
        Button(L10n.discoverMoreLikeThis, systemImage: "hand.thumbsup") {
            feed.moreLikeThis(title)
        }
        Button(L10n.discoverNotInterested, systemImage: "hand.thumbsdown", role: .destructive) {
            feed.notInterested(title)
        }
    }
}

/// Focus treatment for art cards: lifts ×1.08 with a bright rim and a deeper shadow,
/// like the Apple TV app's feature cards.
struct DiscoverLiftButtonStyle: ButtonStyle {

    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        DiscoverLiftButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct DiscoverLiftButtonBody: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat

    var body: some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(isFocused ? 0.75 : 0.1), lineWidth: isFocused ? 3 : 1)
            }
            .contentShape(.rect(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed ? 1.03 : (isFocused ? 1.08 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.55 : 0.25), radius: isFocused ? 30 : 10, y: isFocused ? 22 : 6)
            .animation(.easeOut(duration: 0.2), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
