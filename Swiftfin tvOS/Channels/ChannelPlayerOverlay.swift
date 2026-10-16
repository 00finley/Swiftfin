//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// Drawn over the player's controls while a channel plays: the Up Next card and Down's
/// "what's playing" banner. Nothing for normal playback. It never takes focus: the channel's
/// queue handles the remote through `VideoPlayer.ViewState.pressInterceptor`.
struct ChannelPlayerOverlay: View {

    @EnvironmentObject
    private var manager: MediaPlayerManager

    var body: some View {
        if let queue = ChannelMediaPlayerQueue.session(for: manager) {
            ChannelPlayerOverlayContent(queue: queue)
        }
    }
}

private struct ChannelPlayerOverlayContent: View {

    /// tvOS: the player's controls end this far above the screen's bottom (`VideoPlayer+Container`)
    static let controlsBottomInset: CGFloat = 126
    /// Cards sit 80 pt from the screen's edges, like the player's title block
    static let margin: CGFloat = 80

    @Environment(VideoPlayer.ViewState.self)
    private var viewState

    @ObservedObject
    var queue: ChannelMediaPlayerQueue

    private var isTransition: Bool {
        if case .transition = queue.card {
            return true
        }
        return false
    }

    private var showsInfo: Bool {
        queue.isShowingInfo && !queue.card.isVisible && viewState.presentation == .hidden
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isTransition {
                ChannelTransitionBackdrop(channel: queue.channel, episode: queue.upNext)
                    .padding(.bottom, -Self.controlsBottomInset)
                    .transition(.opacity)
            }

            if queue.card.isVisible, let upNext = queue.upNext {
                ChannelUpNextCard(episode: upNext, deadline: queue.card.deadline)
                    .padding(.leading, Self.margin)
                    .offset(y: Self.controlsBottomInset - Self.margin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showsInfo, let current = queue.current {
                ChannelNowPlayingBanner(channel: queue.channel, episode: current, upNext: queue.upNext)
                    .padding(.leading, Self.margin)
                    .offset(y: Self.controlsBottomInset - Self.margin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.45, bounce: 0.12), value: queue.card)
        .animation(.spring(duration: 0.45, bounce: 0.12), value: showsInfo)
        .onAppear {
            viewState.pressInterceptor = { [weak queue, weak viewState] type, phase in
                guard let queue, let viewState else { return false }

                return queue.handlePress(type, phase: phase, viewState: viewState)
            }
        }
        .onDisappear {
            viewState.pressInterceptor = nil
        }
        .onChange(of: isTransition) {
            // Between episodes the card is the only thing on screen
            if isTransition {
                viewState.hideControls()
            }
        }
        .onChange(of: viewState.presentation) {
            // The controls came up: the banner's job is done
            if viewState.presentation != .hidden, queue.isShowingInfo {
                queue.hideInfo()
            }
        }
    }
}

// MARK: - Up Next card

/// "Up Next · American Dad! · S7, E12 · Title", with the countdown to playback. Select plays it now.
struct ChannelUpNextCard: View {

    let episode: BaseItemDto
    let deadline: Date?

    private var detail: String {
        [episode.playerEpisodeLocator, episode.name].compactMap(\.self).joined(separator: " · ")
    }

    private var seriesName: String {
        episode.seriesName ?? episode.displayTitle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            ChannelEpisodeThumbnail(episode: episode)
                .frame(width: 320, height: 180)
                .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.channelsUpNext)
                    .font(.caption)
                    .fontWeight(.bold)
                    .kerning(2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 8)

                Text(seriesName)
                    .accessibilityIdentifier("channel.upNext.series")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                Text(detail)
                    .accessibilityIdentifier("channel.upNext.detail")
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 20)

                HStack(spacing: 20) {
                    // The card's one action, drawn as a focused button: white with a dark label
                    Label(L10n.channelsPlayNow, systemImage: "play.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 48)
                        .background(Capsule().fill(.white))

                    ChannelCountdownBar(deadline: deadline, duration: ChannelMediaPlayerQueue.upNextDuration)
                        .frame(width: 180, height: 6)
                }
            }
            .frame(width: 440, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 40))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("channel.upNext")
        .accessibilityLabel(L10n.channelsUpNextShow([seriesName, detail].filter(\.isNotEmpty).joined(separator: " · ")))
    }
}

/// Fills as the Up Next countdown runs out
private struct ChannelCountdownBar: View {

    let deadline: Date?
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation) { context in
            let left = deadline.map { max(0, $0.timeIntervalSince(context.date)) } ?? duration
            let fraction = 1 - min(1, left / duration)

            Capsule()
                .fill(Color.white.opacity(0.22))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Between episodes

/// The next show's art, blurred, with the channel's name: the screen between two episodes
private struct ChannelTransitionBackdrop: View {

    let channel: ChannelDefinition
    let episode: BaseItemDto?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            if let seriesID = episode?.seriesID {
                ImageView([
                    HomeImages.url(itemID: seriesID, type: .backdrop, maxWidth: 960),
                    HomeImages.url(itemID: seriesID, type: .primary, maxWidth: 960),
                ])
                .placeholder { _ in Color.black }
                .failure { Color.black }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: 40)
                .scaleEffect(1.1)
                .opacity(0.75)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.15), location: 0),
                    .init(color: .black.opacity(0.7), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ChannelNameBadge(channel: channel)
                .padding(.top, 70)
                .padding(.leading, 80)
        }
        .ignoresSafeArea()
    }
}

// MARK: - What's playing

/// Down on the remote: the show, the episode and the channel
struct ChannelNowPlayingBanner: View {

    let channel: ChannelDefinition
    let episode: BaseItemDto
    let upNext: BaseItemDto?

    private var detail: String {
        [episode.playerEpisodeLocator, episode.name].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChannelNameBadge(channel: channel, isOnGlass: true)
                .padding(.bottom, 18)

            Text(episode.seriesName ?? episode.displayTitle)
                .accessibilityIdentifier("channel.info.series")
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 4)

            Text(detail)
                .accessibilityIdentifier("channel.info.detail")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.bottom, 22)

            HStack(spacing: 28) {
                if let upNext {
                    Text(L10n.channelsUpNextShow(upNext.seriesName ?? upNext.displayTitle))
                        .lineLimit(1)
                }

                Label(L10n.channelsNextEpisode, systemImage: "chevron.right.circle")
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(40)
        .frame(minWidth: 640, maxWidth: 1000, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(.regular, in: .rect(cornerRadius: 40))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("channel.info")
    }
}

/// "● ADULT ANIMATION": the channel's name with a live dot
struct ChannelNameBadge: View {

    let channel: ChannelDefinition
    var isOnGlass = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)

            Image(systemName: channel.systemImage)

            Text(channel.name)
                .textCase(.uppercase)
                .kerning(2)
        }
        .font(.caption)
        .fontWeight(.bold)
        .foregroundStyle(.white)
        .padding(.horizontal, isOnGlass ? 0 : 22)
        .padding(.vertical, isOnGlass ? 0 : 12)
        .background {
            if !isOnGlass {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

/// An episode's still, else its show's art
struct ChannelEpisodeThumbnail: View {

    let episode: BaseItemDto

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)

            ImageView([
                episode.id.flatMap { HomeImages.url(itemID: $0, type: .primary, maxWidth: 400) },
                episode.seriesID.flatMap { HomeImages.url(itemID: $0, type: .thumb, maxWidth: 400) },
                episode.seriesID.flatMap { HomeImages.url(itemID: $0, type: .backdrop, maxWidth: 400) },
            ])
            .placeholder { _ in Color.clear }
            .failure { Color.clear }
            .aspectRatio(contentMode: .fill)
        }
        .clipped()
    }
}

// MARK: - Queue tab

/// The player's Queue tab during a channel: what's up next, with Play Now
struct ChannelQueueSupplementView: PlatformView {

    @ObservedObject
    var queue: ChannelMediaPlayerQueue

    var iOSView: some View {
        EmptyView()
    }

    var tvOSView: some View {
        HStack(alignment: .center, spacing: 40) {
            if let upNext = queue.upNext {
                Button {
                    queue.skip()
                } label: {
                    ChannelEpisodeThumbnail(episode: upNext)
                        .frame(width: 410, height: 230)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(alignment: .bottomLeading) {
                            Label(L10n.channelsPlayNow, systemImage: "play.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(16)
                        }
                }
                .buttonStyle(.card)
                .coordinatedFocus(queue.preferredFocusID)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.channelsUpNext)
                        .font(.caption)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text(upNext.seriesName ?? upNext.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Text([upNext.playerEpisodeLocator, upNext.name].compactMap(\.self).joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    ChannelNameBadge(channel: queue.channel, isOnGlass: true)
                        .padding(.top, 16)
                }
                .frame(maxWidth: 800, alignment: .leading)
            }
        }
        .padding(.horizontal, VideoPlayer.PlaybackControls.horizontalMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}
