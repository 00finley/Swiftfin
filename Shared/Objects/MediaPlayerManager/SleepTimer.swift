//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import Logging

/// Stops playback after a set time or at the end of the current episode.
///
/// One timer belongs to each playback session (its `MediaPlayerManager`), so it keeps running while
/// the video plays in Picture in Picture and ends with the session. It's never saved across launches.
/// Time-based options carry over to the next episode; "End of this episode" ends with the episode.
///
/// When it fires, the audio fades out over `fadeDuration`, playback pauses, and the session stops
/// (reporting the position as usual), which dismisses the player.
@MainActor
final class SleepTimer: ObservableObject {

    enum Option: Hashable, Identifiable {

        case endOfEpisode
        case duration(Duration)

        static func minutes(_ minutes: Int) -> Option {
            .duration(.seconds(minutes * 60))
        }

        /// The choices offered in the player's menu, after "Off"
        static var presets: [Option] {
            var presets: [Option] = [.endOfEpisode, .minutes(15), .minutes(30), .minutes(45), .minutes(60)]

            #if DEBUG
            // UI tests use a short timer instead of waiting 15 real minutes
            if let seconds = SleepTimer.debugTestSeconds {
                presets.append(.duration(.seconds(seconds)))
            }
            #endif

            return presets
        }

        var id: String {
            switch self {
            case .endOfEpisode:
                "endOfEpisode"
            case let .duration(duration):
                "duration-\(Int(duration.seconds))"
            }
        }

        var isTimeBased: Bool {
            if case .duration = self {
                return true
            }
            return false
        }

        var displayTitle: String {
            switch self {
            case .endOfEpisode:
                L10n.sleepTimerEndOfEpisode
            case let .duration(duration):
                SleepTimer.durationLabel(duration)
            }
        }
    }

    /// How long the audio fades out before playback pauses
    static let fadeDuration: Duration = .seconds(5)

    /// The warning toast appears this long before the timer fires
    static let warningLead: Duration = .seconds(60)

    /// "Extend 15 min" on the warning toast
    static let extensionDuration: Duration = .seconds(15 * 60)

    /// Overlay action source ID used by the video player
    static let overlayActionSourceID = "sleepTimer"

    #if DEBUG
    /// `-GlassfinSleepTimerTestSeconds <n>` adds an n-second option to the menu (Debug builds, UI tests)
    nonisolated static var debugTestSeconds: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-GlassfinSleepTimerTestSeconds"),
              arguments.indices.contains(index + 1),
              let seconds = Int(arguments[index + 1]), seconds > 0
        else { return nil }

        return seconds
    }
    #endif

    /// The selected option, or nil when the timer is off
    @Published
    private(set) var option: Option?

    /// Time left before the timer fires (media time for "End of this episode")
    @Published
    private(set) var remaining: Duration?

    /// Within the last minute: the player shows the warning toast
    @Published
    private(set) var isWarning = false

    /// The audio is fading out and playback is about to stop
    @Published
    private(set) var isFiring = false

    /// The timer stopped playback. The session must not continue into the next episode.
    private(set) var didFire = false

    /// Sent when the timer stops playback, with the item that was playing.
    let firedPublisher = PassthroughSubject<BaseItemDto, Never>()

    weak var manager: MediaPlayerManager? {
        didSet {
            guard manager !== oldValue else { return }

            observeManager()
        }
    }

    /// For time-based options: when the timer fires
    private var deadline: Date?
    /// For "End of this episode": the episode the timer was set for
    private var episodeID: String?

    private var tickTask: Task<Void, Never>?
    private var fireTask: Task<Void, Never>?
    private var managerCancellables: Set<AnyCancellable> = []

    private let logger = Logger.swiftfin()

    deinit {
        tickTask?.cancel()
        fireTask?.cancel()
    }

    // MARK: - Setting

    func set(_ option: Option?) {
        guard !isFiring else { return }

        self.option = option
        isWarning = false

        switch option {
        case let .duration(duration):
            deadline = .now.addingTimeInterval(duration.seconds)
            episodeID = nil

        case .endOfEpisode:
            deadline = nil
            episodeID = manager?.item.id

        case nil:
            deadline = nil
            episodeID = nil
        }

        logger.info("Sleep timer set", metadata: ["option": .string(option?.id ?? "off")])

        update()
        restartTicking()
    }

    /// Adds `extensionDuration` from the warning toast. "End of this episode" becomes a timer that
    /// fires that long after the episode would have ended, so it can carry on into the next episode.
    func extend() {
        // Extending during the fade out keeps playing
        if isFiring {
            cancelFiring()
        }

        guard option != nil else { return }

        let remaining = remaining ?? .zero

        // The extended timer is no longer one of the presets (so none shows as selected), and
        // "End of this episode" becomes a timer that can carry on into the next episode
        let extended = remaining + Self.extensionDuration
        self.option = .duration(extended)
        deadline = .now.addingTimeInterval(extended.seconds)
        episodeID = nil

        isWarning = false
        logger.info("Sleep timer extended")
        update()
        restartTicking()
    }

    private func cancelFiring() {
        fireTask?.cancel()
        fireTask = nil
        isFiring = false
        (manager?.proxy as? MediaPlayerVolumeConfigurable)?.setVolume(1)
        logger.info("Sleep timer fade out cancelled")
    }

    // MARK: - Overlay action

    /// The warning toast, shown in the last minute and during the fade out. Select extends the timer.
    var overlayActions: [VideoPlayerOverlayAction] {
        guard option != nil, isWarning || isFiring else { return [] }

        return [
            VideoPlayerOverlayAction(
                id: "extend",
                title: L10n.sleepTimerExtend,
                systemImage: "plus",
                style: .toast(message: L10n.sleepTimerWarning, systemImage: "moon.zzz.fill")
            ) { [weak self] in
                self?.extend()
            },
        ]
    }

    /// Whether the session may move on to the next episode (autoplay at credits or at the end)
    var allowsNextItem: Bool {
        !didFire && !isFiring && option != .endOfEpisode
    }

    // MARK: - Labels

    /// "15 minutes" for the menu
    nonisolated static func durationLabel(_ duration: Duration) -> String {
        let seconds = Int(duration.seconds.rounded())

        guard seconds >= 60, seconds.isMultiple(of: 60) else {
            return L10n.sleepTimerSeconds(seconds.description)
        }

        return L10n.sleepTimerMinutes((seconds / 60).description)
    }

    /// "29 min left" while the timer runs, shown under the menu title
    var remainingLabel: String? {
        guard let option else { return nil }
        guard let remaining else {
            return option == .endOfEpisode ? L10n.sleepTimerEndOfEpisode : nil
        }

        let seconds = Int(remaining.seconds.rounded(.up))

        if seconds < 60 {
            return L10n.sleepTimerSecondsLeft(seconds.description)
        }

        return L10n.sleepTimerMinutesLeft(Int((Double(seconds) / 60).rounded(.up)).description)
    }

    // MARK: - Ticking

    private func restartTicking() {
        tickTask?.cancel()
        tickTask = nil

        guard option != nil else { return }

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                self?.update()
            }
        }
    }

    private func update() {
        guard let option, !isFiring else {
            remaining = nil
            isWarning = false
            return
        }

        let newRemaining: Duration? = switch option {
        case .duration:
            deadline.map { .seconds(max(0, $0.timeIntervalSinceNow)) }

        case .endOfEpisode:
            remainingInEpisode()
        }

        remaining = newRemaining

        guard let newRemaining else {
            isWarning = false
            return
        }

        let shouldWarn = newRemaining <= Self.warningLead
        if shouldWarn != isWarning {
            isWarning = shouldWarn
        }

        // Start fading so the audio is gone when the time is up
        if newRemaining <= Self.fadeDuration {
            fire()
        }
    }

    /// Media time left until the episode's credits (or its end, without a credits segment).
    private func remainingInEpisode() -> Duration? {
        guard let manager,
              manager.state == .playback,
              manager.playbackItem?.baseItem.id == episodeID,
              let runtime = manager.item.runtime, runtime > .zero
        else { return nil }

        let stopPoint = manager.mediaSegmentObserver?.creditsStart.map { min($0, runtime) } ?? runtime
        let rate = max(manager.rate, 0.25)

        return .seconds(max(0, (stopPoint - manager.seconds).seconds / rate))
    }

    // MARK: - Firing

    /// Stops playback now, as when the time is up. Without `fade` (playback already reached the
    /// end) it pauses and stops right away.
    func fire(fade: Bool = true) {
        guard !isFiring, fireTask == nil, let manager else { return }

        isFiring = true
        isWarning = false
        tickTask?.cancel()
        tickTask = nil

        logger.info("Sleep timer fired, stopping playback", metadata: ["option": .string(option?.id ?? "off")])

        fireTask = Task { [weak self] in
            await self?.fadeOutAndStop(manager, fade: fade)
        }
    }

    private func fadeOutAndStop(_ manager: MediaPlayerManager, fade: Bool) async {
        let volumeProxy = manager.proxy as? MediaPlayerVolumeConfigurable

        if fade, manager.playbackRequestStatus == .playing, let volumeProxy {
            let steps = 25
            let stepDuration = Self.fadeDuration / steps

            for step in 1 ... steps {
                // Stop fading if the player went away (closed by the user meanwhile)
                guard manager.state != .stopped else { break }

                volumeProxy.setVolume(Float(steps - step) / Float(steps))
                try? await Task.sleep(for: stepDuration)

                // Extended from the toast
                guard !Task.isCancelled else { return }
            }
        }

        guard !Task.isCancelled else { return }

        didFire = true

        if manager.state != .stopped {
            await manager.setPlaybackRequestStatus(status: .paused)
        }

        volumeProxy?.setVolume(1)

        let item = manager.item
        option = nil
        remaining = nil
        isFiring = false
        fireTask = nil

        firedPublisher.send(item)

        guard manager.state != .stopped else { return }

        // Picture in Picture: close the window too. Stopping the session reports the position.
        if PictureInPictureSession.shared.isHolding(manager) {
            manager.stopPictureInPicture()
        }

        await manager.stop()
    }

    // MARK: - Manager

    private func observeManager() {
        managerCancellables = []

        guard let manager else { return }

        // Only time-based options carry over to another episode
        manager.$playbackItem
            .removeDuplicates { $0?.baseItem.id == $1?.baseItem.id }
            .dropFirst()
            .sink { [weak self] newItem in
                guard let self, let option, !option.isTimeBased, !isFiring else { return }

                if newItem?.baseItem.id != episodeID {
                    logger.info("Sleep timer cleared: \"End of this episode\" doesn't carry over")
                    set(nil)
                }
            }
            .store(in: &managerCancellables)

        manager.$state
            .sink { [weak self] state in
                guard state == .stopped, let self, !isFiring else { return }

                tickTask?.cancel()
                tickTask = nil
                option = nil
                remaining = nil
                isWarning = false
            }
            .store(in: &managerCancellables)
    }
}

/// Players whose volume can be faded for the sleep timer
@MainActor
protocol MediaPlayerVolumeConfigurable {

    /// 0...1, applied on top of the system volume
    func setVolume(_ volume: Float)
}
