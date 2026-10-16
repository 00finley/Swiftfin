//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import SwiftUI

/// A channel playing in the video player: the player's queue, so its `nextItem` is always the
/// channel's next random episode, and everything else about watching a channel.
///
/// - Every episode goes through the normal player (`MediaPlayerItem.build`), starting at 0:00, so
///   intros and credits follow the user's skip settings and the sleep timer and Picture in Picture
///   work as for any episode.
/// - Between episodes it shows the Up Next card (`card`), about 5 s, which Select skips.
/// - With "Count as Watched" off (the default) it removes the item's `MediaProgressObserver`
///   before the player connects it, so nothing is reported to the server, like the Home preview.
///   It ends each remux itself instead, as the stop report would have.
@MainActor
final class ChannelMediaPlayerQueue: ViewModel, MediaPlayerQueue {

    /// The Up Next card
    enum Card: Equatable {
        case hidden
        /// Over the last seconds of the episode
        case preroll(deadline: Date)
        /// Between episodes, over a blurred backdrop while the next one loads
        case transition(deadline: Date)

        var isVisible: Bool {
            self != .hidden
        }

        var deadline: Date? {
            switch self {
            case .hidden: nil
            case let .preroll(deadline), let .transition(deadline): deadline
            }
        }
    }

    /// How long the Up Next card shows between episodes
    static let upNextDuration: TimeInterval = 5
    /// How long Down's "what's playing" banner stays up
    static let infoDuration: TimeInterval = 6
    /// After the credits' own "Next Episode" countdown, the card only covers the loading
    private static let shortTransition: TimeInterval = 1.5

    let channel: ChannelDefinition
    let displayTitle: String
    let id = "ChannelMediaPlayerQueue"

    weak var manager: MediaPlayerManager? {
        didSet {
            guard manager !== oldValue else { return }

            observeManager()
        }
    }

    @Published
    var nextItem: MediaPlayerItemProvider? = nil
    @Published
    var previousItem: MediaPlayerItemProvider? = nil
    @Published
    var hasNextItem: Bool = false
    @Published
    var hasPreviousItem: Bool = false

    lazy var hasNextItemPublisher: Published<Bool>.Publisher = $hasNextItem
    lazy var hasPreviousItemPublisher: Published<Bool>.Publisher = $hasPreviousItem
    lazy var nextItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $nextItem
    lazy var previousItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $previousItem

    /// A channel goes on to its next episode even with next episode autoplay off
    var autoPlaysNextItem: Bool {
        true
    }

    /// The episode playing
    @Published
    private(set) var current: BaseItemDto?
    /// The episode that plays next
    @Published
    private(set) var upNext: BaseItemDto?
    @Published
    private(set) var card: Card = .hidden
    /// Down's "what's playing" banner is up
    @Published
    private(set) var isShowingInfo = false

    private let pool: ChannelLibrary.Pool
    private var failedEpisodeIDs: Set<String> = []
    private var playNowRequested = false
    private var skipRequested = false
    private var dismissedPrerollEpisodeID: String?
    private var lastSegmentCountdownDate: Date?
    /// The play session whose remux this queue ends itself (no progress reports)
    private var unreportedPlaySessionID: String?
    private var episodesStarted = 0
    private var ownedPress: UIPress.PressType?
    private var infoTask: Task<Void, Never>?
    private var managerCancellables: Set<AnyCancellable> = []

    init(channel: ChannelDefinition, pool: ChannelLibrary.Pool) {
        self.channel = channel
        self.displayTitle = channel.name
        self.pool = pool
        super.init()
    }

    // MARK: - Sessions

    private struct WeakQueue {
        weak var queue: ChannelMediaPlayerQueue?
    }

    private static var sessions: [WeakQueue] = []

    /// The channel playing in this player, if it's playing one
    static func session(for manager: MediaPlayerManager) -> ChannelMediaPlayerQueue? {
        sessions.lazy.compactMap(\.queue).first { $0.manager === manager }
    }

    /// The channel playing now, in the player or in Picture in Picture
    static func playing(_ channel: ChannelDefinition) -> ChannelMediaPlayerQueue? {
        sessions.lazy.compactMap(\.queue).first {
            $0.channel.id == channel.id && $0.manager != nil && $0.manager?.state != .stopped
        }
    }

    private static func register(_ queue: ChannelMediaPlayerQueue) {
        sessions = sessions.filter { $0.queue != nil && $0.queue !== queue } + [WeakQueue(queue: queue)]
    }

    // MARK: - Starting

    /// A provider for the first episode. It plays right away, without the Up Next card.
    func initialProvider() -> MediaPlayerItemProvider? {
        guard let episode = pick(excludingCurrent: false), let item = pool.items[episode.id] else { return nil }

        return provider(for: item, isInitial: true)
    }

    private func provider(for item: BaseItemDto, isInitial: Bool) -> MediaPlayerItemProvider {
        MediaPlayerItemProvider(item: item) { [weak self] item, modifyItem in
            guard let self else { throw CancellationError() }

            return try await self.resolve(item, modifyItem: modifyItem, isInitial: isInitial)
        }
    }

    // MARK: - Picking

    private func pick(excludingCurrent: Bool) -> ChannelEpisode? {
        let history = ChannelStore.shared.state(for: channel).history
        var excluded = failedEpisodeIDs
        if excludingCurrent, let currentID = current?.id {
            excluded.insert(currentID)
        }

        return ChannelShuffler.pick(from: pool.episodes, history: history, excluding: excluded)
            // A one-episode pool repeats rather than ending the channel
            ?? ChannelShuffler.pick(from: pool.episodes, history: history, excluding: failedEpisodeIDs)
    }

    private func prepareNext() {
        guard let episode = pick(excludingCurrent: true), let item = pool.items[episode.id] else {
            upNext = nil
            nextItem = nil
            hasNextItem = false
            return
        }

        upNext = item
        nextItem = provider(for: item, isInitial: false)
        hasNextItem = true
    }

    // MARK: - Resolving

    /// Builds the episode through the normal player path. Between episodes the Up Next card waits
    /// out its time while the episode loads; Select (or Right) ends the wait.
    private func resolve(
        _ episode: BaseItemDto,
        modifyItem: (@Sendable (inout BaseItemDto) -> Void)?,
        isInitial: Bool
    ) async throws -> MediaPlayerItem {
        let isInPiP = isInPictureInPicture

        let deadline: Date = {
            if isInitial || isInPiP || skipRequested {
                return .now
            }
            // The card has been up over the end of the episode
            if case let .preroll(deadline) = card {
                return deadline
            }
            // The credits' "Next Episode" countdown already said what's next
            if let lastSegmentCountdownDate, Date.now.timeIntervalSince(lastSegmentCountdownDate) < 3 {
                return .now.addingTimeInterval(Self.shortTransition)
            }
            return .now.addingTimeInterval(Self.upNextDuration)
        }()

        skipRequested = false
        playNowRequested = false
        if !isInitial, !isInPiP {
            upNext = episode
            card = .transition(deadline: deadline)
        }
        do {
            return try await build(episode, waitingUntil: deadline, modifyItem: modifyItem)
        } catch {
            card = .hidden
            throw error
        }
    }

    /// Loads the episode while the card waits out its time; picks another if it fails to load
    private func build(
        _ episode: BaseItemDto,
        waitingUntil deadline: Date,
        modifyItem: (@Sendable (inout BaseItemDto) -> Void)?
    ) async throws -> MediaPlayerItem {
        var episode = episode

        for attempt in 0 ..< 3 {
            let target = episode
            let loading = Task { try await self.build(target, modifyItem: modifyItem) }

            while Date.now < deadline, !playNowRequested, !isInPictureInPicture {
                // The user closed the player or the sleep timer stopped it
                if Task.isCancelled || manager == nil || manager?.state == .stopped {
                    loading.cancel()
                    throw CancellationError()
                }
                try? await Task.sleep(for: .milliseconds(100))
            }

            do {
                return try await loading.value
            } catch {
                if error is CancellationError || Task.isCancelled || manager?.state == .stopped {
                    throw error
                }

                logger.warning(
                    "Channel episode didn't load, picking another",
                    metadata: ["itemID": .string(episode.id ?? ""), "error": .string(error.localizedDescription)]
                )
                if let id = episode.id {
                    failedEpisodeIDs.insert(id)
                }

                guard attempt < 2, let replacement = pick(excludingCurrent: true), let item = pool.items[replacement.id] else {
                    throw error
                }

                episode = item
                upNext = item
            }
        }

        throw ErrorMessage(L10n.unknownError)
    }

    private func build(
        _ episode: BaseItemDto,
        modifyItem: (@Sendable (inout BaseItemDto) -> Void)?
    ) async throws -> MediaPlayerItem {
        let bitrate = manager?.playbackBitrate ?? Defaults[.VideoPlayer.Playback.appMaximumBitrate]
        let startTicks = Self.startTicks(for: episode)

        let item = try await MediaPlayerItem.build(for: episode, requestedBitrate: bitrate) { item in
            // Every channel episode starts at 0:00, whatever its resume point
            if item.userData == nil {
                item.userData = UserItemDataDto(key: item.id ?? "")
            }
            item.userData?.playbackPositionTicks = startTicks
            modifyItem?(&item)
        }

        removeProgressReportingIfNeeded(from: item)
        return item
    }

    private static func startTicks(for episode: BaseItemDto) -> Int {
        #if DEBUG
        // UI tests: `-GlassfinChannelStartNearEnd <n>` starts each episode n seconds before its end
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-GlassfinChannelStartNearEnd"),
           arguments.indices.contains(index + 1),
           let seconds = Int(arguments[index + 1]),
           let runtime = episode.runTimeTicks
        {
            return max(0, runtime - seconds * 10_000_000)
        }
        #endif
        return 0
    }

    // MARK: - Progress

    private var countsAsWatched: Bool {
        ChannelStore.shared.settings(for: channel).countsAsWatched
    }

    /// Without "Count as Watched", the item never gets a progress observer: no start, progress or
    /// stopped reports, so the server's resume points, played state and Next Up stay as they were.
    private func removeProgressReportingIfNeeded(from item: MediaPlayerItem) {
        guard !countsAsWatched else { return }

        item.observers.removeAll { $0 is MediaProgressObserver }
    }

    /// Ends the server's remux for a play session this queue kept from reporting (a stopped report
    /// would have ended it), so it doesn't keep running after the episode.
    private func stopEncoding(playSessionID: String) {
        guard let session = Container.shared.currentUserSession() else { return }

        let deviceID = session.client.configuration.deviceID

        Task {
            let request = Request<Void>(
                path: "/Videos/ActiveEncodings",
                method: .delete,
                query: [("deviceId", deviceID), ("playSessionId", playSessionID)]
            )
            _ = try? await session.client.send(request)
        }
    }

    // MARK: - Manager

    private func observeManager() {
        managerCancellables = []

        guard let manager else { return }

        Self.register(self)

        // Published before the manager connects the item's observers (`willSet`)
        manager.$playbackItem
            .sink { [weak self] item in
                self?.playbackItemWillChange(to: item)
            }
            .store(in: &managerCancellables)

        manager.$state
            .sink { [weak self] state in
                guard state == .stopped else { return }

                self?.didStop()
            }
            .store(in: &managerCancellables)

        manager.secondsBox
            .$value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.secondsDidChange(seconds)
            }
            .store(in: &managerCancellables)

        manager.$playbackItem
            .map { item -> AnyPublisher<Int?, Never> in
                item?.mediaSegmentObserver?.$countdown.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()
            }
            .switchToLatest()
            .sink { [weak self] countdown in
                if countdown != nil {
                    self?.lastSegmentCountdownDate = .now
                }
            }
            .store(in: &managerCancellables)
    }

    private func playbackItemWillChange(to item: MediaPlayerItem?) {
        guard let item else { return }

        // Also covers items the player rebuilds itself (another audio track or bitrate)
        removeProgressReportingIfNeeded(from: item)

        if let previous = unreportedPlaySessionID, previous != item.playSessionID {
            stopEncoding(playSessionID: previous)
        }
        unreportedPlaySessionID = countsAsWatched ? nil : item.playSessionID

        // The same episode rebuilt
        guard item.baseItem.id != current?.id else { return }

        let episode = item.baseItem
        current = episode
        card = .hidden
        dismissedPrerollEpisodeID = nil
        episodesStarted += 1

        if let id = episode.id {
            ChannelStore.shared.recordPlayed(
                ChannelEpisode(id: id, seriesID: episode.seriesID ?? id),
                seriesName: episode.seriesName ?? episode.displayTitle,
                pool: pool.episodes,
                in: channel
            )
        }

        prepareNext()

        // Like a channel bug: what's on, as each new episode starts (the controls cover the first)
        if episodesStarted > 1, !isInPictureInPicture {
            showInfo()
        }
    }

    private func didStop() {
        if let unreportedPlaySessionID {
            stopEncoding(playSessionID: unreportedPlaySessionID)
            self.unreportedPlaySessionID = nil
        }

        card = .hidden
        hideInfo()
        managerCancellables = []
    }

    private var isInPictureInPicture: Bool {
        guard let manager else { return false }

        return PictureInPictureSession.shared.isActive && PictureInPictureSession.shared.isHolding(manager)
    }

    // MARK: - Up Next over the end of the episode

    private func secondsDidChange(_ seconds: Duration) {
        guard let manager, manager.state == .playback else { return }

        if case .transition = card {
            return
        }

        guard !isInPictureInPicture,
              nextItem != nil,
              // "End of this episode" on the sleep timer: the channel stops here
              manager.sleepTimer.allowsNextItem,
              manager.playbackRequestStatus == .playing,
              let runtime = manager.item.runtime, runtime > .zero,
              current?.id != dismissedPrerollEpisodeID
        else {
            if case .preroll = card {
                card = .hidden
            }
            return
        }

        let left = (runtime - seconds).seconds / max(manager.rate, 0.25)

        if left > 0, left <= Self.upNextDuration {
            if card == .hidden {
                card = .preroll(deadline: .now.addingTimeInterval(left))
                hideInfo()
            }
        } else if case .preroll = card {
            card = .hidden
        }
    }

    // MARK: - Actions

    /// Right on the remote, and Select on the Up Next card: the next episode now
    func skip() {
        if case .transition = card {
            playNowRequested = true
            return
        }

        guard let manager, let nextItem else { return }

        hideInfo()
        skipRequested = true
        manager.playNewItem(provider: nextItem)
    }

    /// Back on the Up Next card over the end of the episode: the episode plays out
    func dismissPreroll() {
        dismissedPrerollEpisodeID = current?.id
        card = .hidden
    }

    func showInfo() {
        isShowingInfo = true

        infoTask?.cancel()
        infoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.infoDuration))
            guard !Task.isCancelled else { return }

            self?.isShowingInfo = false
        }
    }

    func hideInfo() {
        infoTask?.cancel()
        infoTask = nil
        isShowingInfo = false
    }

    // MARK: - Remote

    /// Presses offered by the player before its own handling (`VideoPlayer.ViewState.pressInterceptor`).
    ///
    /// While the transport bar is hidden, Right skips to the next channel episode (instead of
    /// jumping ahead; Left still jumps back) and Down shows what's playing (a second Down opens the
    /// controls as usual). Select plays the Up Next card's episode now; Back dismisses the card
    /// over the end of an episode. Between episodes the card owns the remote (Back still exits). With the bar up, everything is the
    /// player's.
    ///
    /// - Returns: Whether the press was handled here.
    func handlePress(_ type: UIPress.PressType, phase: UIPress.Phase, viewState: VideoPlayer.ViewState) -> Bool {
        let handled = _handlePress(type, phase: phase, viewState: viewState)
        logger
            .debug(
                "Channel press type=\(type.rawValue) phase=\(phase.rawValue) presentation=\(viewState.presentation) actions=\(viewState.overlayActions.count) handled=\(handled)"
            )
        return handled
    }

    private func _handlePress(_ type: UIPress.PressType, phase: UIPress.Phase, viewState: VideoPlayer.ViewState) -> Bool {
        if case .transition = card {
            switch type {
            case .select, .rightArrow:
                if phase == .ended {
                    playNowRequested = true
                }
                return true

            case .upArrow, .downArrow, .leftArrow:
                return true

            default:
                return false
            }
        }

        switch type {
        case .menu:
            // Back also arrives as a cancelled press (its tap recognizer takes it); act once, on the end
            guard phase == .ended, case .preroll = card, viewState.presentation == .hidden else { return false }

            dismissPreroll()
            return true

        case .select:
            guard phase == .ended,
                  case .preroll = card,
                  viewState.presentation == .hidden,
                  !viewState.isOverlayActionFocused
            else { return false }

            skip()
            return true

        case .rightArrow, .downArrow:
            if phase == .began {
                if type == .downArrow, isShowingInfo {
                    // A second Down: the usual controls
                    hideInfo()
                    return false
                }
                guard isTransportBarHidden(viewState) else { return false }

                // Act as the press begins: with a skip button focused, the focus engine cancels
                // the press instead of ending it
                ownedPress = type
                if type == .rightArrow {
                    skip()
                } else {
                    showInfo()
                }
                return true
            }

            // Keep the rest of a press that began here (and only that)
            guard ownedPress == type else { return false }

            if phase == .ended || phase == .cancelled {
                ownedPress = nil
            }
            return true

        default:
            return false
        }
    }

    /// No scrubber, controls or tabs on screen. A single skip / next episode button may be up
    /// (Right has nowhere to move focus then); with two, Right moves between them as usual.
    private func isTransportBarHidden(_ viewState: VideoPlayer.ViewState) -> Bool {
        viewState.presentation == .hidden
            && !viewState.isScrubbing
            && !viewState.isPresentingCloseConfirmation
            && viewState.overlayActions.count <= 1
    }

    // MARK: - Supplement

    var videoPlayerBody: some PlatformView {
        ChannelQueueSupplementView(queue: self)
    }
}
