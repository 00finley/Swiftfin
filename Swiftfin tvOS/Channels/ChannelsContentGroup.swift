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

/// Home's "Channels" row: a large glass card per channel. Pressing one starts the channel.
struct ChannelsContentGroup: ContentGroup {

    let id = "home-channels"
    let viewModel = ChannelsViewModel()

    func body(with viewModel: ChannelsViewModel) -> some View {
        ChannelsSection(viewModel: viewModel)
    }
}

final class ChannelsViewModel: ViewModel, WithRefresh {

    struct Summary: Hashable {
        /// Series in the channel, by name
        var series: [BaseItemDto] = []
    }

    @Published
    private(set) var summaries: [String: Summary] = [:]
    /// The channel being started (its first episode is being picked)
    @Published
    private(set) var startingChannelID: String?
    @Published
    var errorMessage: String?

    let channels = ChannelCatalog.channels

    private var loadTask: Task<Void, Never>?

    override init() {
        super.init()

        // Edit Shows changed a channel: its card's art and count follow
        ChannelStore.shared
            .$revision
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func refresh() {
        reload()
    }

    func refresh() async {
        #if DEBUG
        ChannelStore.shared.resetAllIfRequested()
        #endif

        reload()
        if let loadTask {
            await homeAwait(upTo: 1.5, loadTask)
        }
    }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }

            var summaries: [String: Summary] = [:]
            for channel in channels {
                let series = await (try? ChannelLibrary.shared.series(in: channel)) ?? []
                summaries[channel.id] = Summary(series: series)
            }
            guard !Task.isCancelled else { return }

            self.summaries = summaries
        }
    }

    /// Picks the first episode and returns the player for it
    func start(_ channel: ChannelDefinition) async -> NavigationRoute? {
        guard startingChannelID == nil else { return nil }

        startingChannelID = channel.id
        defer { startingChannelID = nil }

        do {
            let pool = try await ChannelLibrary.shared.pool(for: channel)
            let queue = ChannelMediaPlayerQueue(channel: channel, pool: pool)

            guard let provider = queue.initialProvider() else {
                errorMessage = L10n.channelsNothingToPlay
                return nil
            }

            return .videoPlayer(provider: provider, queue: queue)
        } catch {
            logger.error("Channel didn't start", metadata: ["error": .string(error.localizedDescription)])
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Section

struct ChannelsSection: View {

    @ObservedObject
    var viewModel: ChannelsViewModel

    @ObservedObject
    private var store = ChannelStore.shared

    @Router
    private var router

    var body: some View {
        HomeShelf(L10n.channels) {
            ForEach(viewModel.channels) { channel in
                VStack(alignment: .leading, spacing: 30) {
                    ChannelCard(
                        channel: channel,
                        series: viewModel.summaries[channel.id]?.series,
                        nowPlaying: store.state(for: channel).nowPlaying,
                        isStarting: viewModel.startingChannelID == channel.id
                    ) {
                        Task {
                            if let route = await viewModel.start(channel) {
                                router.route(to: route)
                            }
                        }
                    }

                    ChannelOptionsRow(channel: channel, countsAsWatched: store.settings(for: channel).countsAsWatched) {
                        router.route(to: .channelEditShows(channel: channel))
                    } toggleCountsAsWatched: {
                        store.setCountsAsWatched(!store.settings(for: channel).countsAsWatched, for: channel)
                    }
                }
                .focusSection()
            }
        }
        .alert(
            L10n.error,
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

/// "Edit Shows" and the "Count as Watched" toggle under a channel's card
private struct ChannelOptionsRow: View {

    let channel: ChannelDefinition
    let countsAsWatched: Bool
    let editShows: () -> Void
    let toggleCountsAsWatched: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button(action: editShows) {
                Label(L10n.channelsEditShows, systemImage: "square.and.pencil")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 30)
                    .frame(height: 64)
            }
            .buttonStyle(.homeGlass)
            .accessibilityIdentifier("channel.editShows")

            Button(action: toggleCountsAsWatched) {
                HStack(spacing: 14) {
                    Image(systemName: countsAsWatched ? "checkmark.circle.fill" : "circle")
                    Text(L10n.channelsCountAsWatched)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 30)
                .frame(height: 64)
            }
            .buttonStyle(.homeGlass)
            .accessibilityIdentifier("channel.countsAsWatched")
            .accessibilityValue(countsAsWatched ? L10n.channelsOn : L10n.channelsOff)
            .accessibilityHint(L10n.channelsCountAsWatchedHint)
        }
    }
}

// MARK: - Card

/// A large glass card: the channel's name over a rotating collage of its shows' art,
/// with "Now: Bob's Burgers" once it has played something.
struct ChannelCard: View {

    static let size = CGSize(width: 1000, height: 440)

    let channel: ChannelDefinition
    /// Nil while loading
    let series: [BaseItemDto]?
    let nowPlaying: ChannelStore.NowPlaying?
    let isStarting: Bool
    let action: () -> Void

    @State
    private var rotation = 0

    private var status: String {
        if let nowPlaying {
            return L10n.channelsNow(nowPlaying.seriesName)
        }
        return channel.tagline
    }

    private var countLabel: String? {
        guard let series else { return nil }

        return series.count == 1 ? L10n.channelsOneShow : L10n.channelsShowCount(series.count.description)
    }

    var body: some View {
        Button(action: action) {
            ChannelCardBody(
                channel: channel,
                series: series ?? [],
                rotation: rotation,
                status: status,
                isLive: nowPlaying != nil,
                countLabel: countLabel,
                isStarting: isStarting
            )
        }
        .buttonStyle(ChannelCardButtonStyle())
        .accessibilityIdentifier("channel.card.\(channel.id)")
        .accessibilityLabel([channel.name, status, countLabel].compactMap(\.self).joined(separator: ", "))
        .task {
            // The collage turns over one tile every few seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.9)) {
                    rotation += 1
                }
            }
        }
    }
}

private struct ChannelCardButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        ChannelCardButtonBody(configuration: configuration)
    }
}

private struct ChannelCardButtonBody: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .environment(\.channelCardIsFocused, isFocused)
            .clipShape(.rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.85 : 0.12), lineWidth: isFocused ? 3 : 1)
            }
            .scaleEffect(configuration.isPressed ? 1.02 : (isFocused ? 1.05 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0.2), radius: isFocused ? 30 : 10, y: isFocused ? 18 : 6)
            .animation(.easeOut(duration: 0.2), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension EnvironmentValues {

    @Entry
    var channelCardIsFocused: Bool = false
}

private struct ChannelCardBody: View {

    @Environment(\.channelCardIsFocused)
    private var isFocused

    let channel: ChannelDefinition
    let series: [BaseItemDto]
    let rotation: Int
    let status: String
    let isLive: Bool
    let countLabel: String?
    let isStarting: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ChannelCollage(series: series, rotation: rotation)

            // Keep the label legible over bright art
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.35),
                    .init(color: .black.opacity(0.55), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ChannelNameBadge(channel: channel)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            label
                .padding(24)
        }
        .frame(width: ChannelCard.size.width, height: ChannelCard.size.height)
        .background(Color.white.opacity(0.06))
    }

    /// Glass, or white with a dark label when focused
    private var label: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 12) {
                    if isLive {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                    }

                    Text([status, countLabel].compactMap(\.self).joined(separator: " · "))
                        .accessibilityIdentifier("channel.card.status")
                        .lineLimit(1)
                }
                .font(.callout)
                .foregroundStyle(isFocused ? Color.black.opacity(0.7) : Color.white.opacity(0.8))
            }

            Spacer(minLength: 0)

            Group {
                if isStarting {
                    ProgressView()
                        .tint(isFocused ? .black : .white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.headline)
                }
            }
            .frame(width: 76, height: 76)
            .background {
                Circle()
                    .fill(isFocused ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
            }
        }
        .foregroundStyle(isFocused ? Color.black : Color.white)
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .background {
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .opacity(isFocused ? 0 : 1)
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .opacity(isFocused ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

/// Six tiles of the channel's shows, tilted; one tile turns over to another show each `rotation`
private struct ChannelCollage: View {

    static let tileCount = 6

    let series: [BaseItemDto]
    let rotation: Int

    private func series(forTile tile: Int) -> BaseItemDto? {
        guard series.isNotEmpty else { return nil }

        // Each rotation turns over the next tile in turn, to a show further along the list
        let turns = rotation / Self.tileCount + (tile < rotation % Self.tileCount ? 1 : 0)
        return series[(tile + turns * (Self.tileCount + 1)) % series.count]
    }

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = proxy.size.width / 2.6
            let tileHeight = tileWidth * 9 / 16

            ZStack {
                Color.black.opacity(0.3)

                if series.isEmpty {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 120))
                        .foregroundStyle(.white.opacity(0.18))
                } else {
                    // Two staggered rows
                    VStack(spacing: 18) {
                        HStack(spacing: 18) {
                            ForEach(0 ..< 3, id: \.self) { tile in
                                tileView(tile).frame(width: tileWidth, height: tileHeight)
                            }
                        }
                        .offset(x: -tileWidth * 0.3)

                        HStack(spacing: 18) {
                            ForEach(3 ..< Self.tileCount, id: \.self) { tile in
                                tileView(tile).frame(width: tileWidth, height: tileHeight)
                            }
                        }
                        .offset(x: tileWidth * 0.25)
                    }
                    .rotationEffect(.degrees(-8))
                    .scaleEffect(1.25)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func tileView(_ tile: Int) -> some View {
        let item = series(forTile: tile)

        ZStack {
            Color.white.opacity(0.08)

            if let item, let id = item.id {
                HomeLibraryArtwork(
                    itemID: id,
                    imageTags: item.imageTags,
                    hasBackdrop: item.backdropImageTags?.isNotEmpty ?? true,
                    maxWidth: 480
                )
                .id(id)
                .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: 18))
    }
}
