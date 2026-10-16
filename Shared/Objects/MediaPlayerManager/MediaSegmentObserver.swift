//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI

extension MediaPlayerManager {

    var mediaSegmentObserver: MediaSegmentObserver? {
        playbackItem?.mediaSegmentObserver
    }
}

extension MediaPlayerItem {

    var mediaSegmentObserver: MediaSegmentObserver? {
        observers.lazy.compactMap { $0 as? MediaSegmentObserver }.first
    }
}

/// Watches playback against the item's media segments (intro, recap, credits, ...)
/// and offers skip / next episode overlay actions according to the user's settings
/// and the show's intro / credits rule (`ShowSkipRules`).
final class MediaSegmentObserver: ViewModel, MediaPlayerObserver {

    /// Overlay action supplement ID used by the video player.
    static let overlayActionSourceID = "mediaSegments"

    /// Seconds counted down before auto playing the next episode during credits.
    static let nextEpisodeCountdown = 5

    /// The maximum jump between consecutive updates for a segment entry
    /// to count as natural playback rather than a seek.
    private static let naturalEntryThreshold: Duration = .seconds(3)

    @Published
    private(set) var activeSegment: MediaSegmentDto?
    @Published
    private(set) var countdown: Int?

    /// "Watching intro" / "Watching credits": a short-lived chip shown instead of a skip button
    /// when the show's rule is to watch that segment.
    @Published
    private(set) var watchingNotice: MediaSegmentType?

    /// With credits set to Watch: seconds left in the file while the next episode countdown shows
    @Published
    private(set) var endOfFileCountdown: Int?

    /// The show's intro / credits rule; nil for items that aren't episodes (global settings apply)
    private(set) var rule: ResolvedShowSkipRule?

    /// How long the "Watching intro" chip stays up
    static let watchingNoticeDuration: Duration = .seconds(5)

    /// Whether the player is currently showing overlay actions.
    /// The next item countdown only runs while its button is visible.
    var isPresentingActions: (@MainActor () -> Bool)?

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager {
                setup(with: manager)
            }
        }
    }

    private let itemID: String?
    private let baseItem: BaseItemDto
    private(set) var segments: [MediaSegmentDto] = []
    private var isLoaded = false
    private var noticedSegmentIDs: Set<String> = []
    private var noticeTask: Task<Void, Never>?
    private var lastSeconds: Duration?
    private var dismissedSegmentIDs: Set<String> = []
    private var autoSkippedSegmentIDs: Set<String> = []
    private var countdownTask: Task<Void, Never>?
    private var observerCancellables: Set<AnyCancellable> = []

    init(item: MediaPlayerItem) {
        self.itemID = item.baseItem.id
        self.baseItem = item.baseItem
        super.init()

        fetchSegments()
    }

    deinit {
        countdownTask?.cancel()
        noticeTask?.cancel()
    }

    private func setup(with manager: MediaPlayerManager) {
        observerCancellables = []

        manager.secondsBox
            .$value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.secondsDidChange($0) }
            .store(in: &observerCancellables)
    }

    private func fetchSegments() {
        guard let itemID else { return }

        Task { [weak self] in
            guard let self, let client = userSession?.client else { return }

            if baseItem.type == .episode, baseItem.seriesID != nil {
                let rule = await ShowSkipRules.resolve(for: baseItem)
                self.rule = rule
                logger.info(
                    "Show skip rule",
                    metadata: [
                        "seriesID": .string(baseItem.seriesID ?? ""),
                        "intro": .string(rule.intro.rawValue),
                        "credits": .string(rule.credits.rawValue),
                        "source": .string("\(rule.source)"),
                    ]
                )
            }

            do {
                let request = Paths.getItemSegments(
                    itemID: itemID,
                    includeSegmentTypes: MediaSegmentType.skippableCases
                )
                let response = try await client.send(request)

                segments = Self.deduplicated(response.value.items ?? [])
                isLoaded = true

                if let seconds = manager?.seconds {
                    secondsDidChange(seconds)
                }
            } catch {
                logger.error("Failed to fetch media segments for item \(itemID): \(error.localizedDescription)")
            }
        }
    }

    /// Multiple segment providers can report the same segment.
    private static func deduplicated(_ segments: [MediaSegmentDto]) -> [MediaSegmentDto] {
        var seen: Set<String> = []

        return segments
            .filter { $0.startTicks != nil && $0.endTicks != nil && $0.id != nil }
            .sorted { ($0.startTicks ?? 0) < ($1.startTicks ?? 0) }
            .filter { segment in
                let startSecond = (segment.startTicks ?? 0) / 10_000_000
                return seen.insert("\(segment.type?.rawValue ?? ""):\(startSecond)").inserted
            }
    }

    // MARK: - Playback

    private var isCurrentItem: Bool {
        manager?.playbackItem?.baseItem.id == itemID
    }

    private var canPlayNextItem: Bool {
        manager?.queue?.nextItem != nil &&
            userSession?.user.data.configuration?.enableNextEpisodeAutoPlay == true &&
            // "End of this episode" on the sleep timer: no next episode countdown
            manager?.sleepTimer.allowsNextItem != false
    }

    /// Where the credits start, if the item has a credits segment.
    var creditsStart: Duration? {
        segments.first { $0.type == .outro }?.startSeconds
    }

    /// Whether the show's rule is to watch the credits (no credits skip, autoplay at the real end).
    var isWatchingCredits: Bool {
        rule?.credits == .watch
    }

    /// Where "End of this episode" on the sleep timer stops: the credits, unless the show's
    /// credits are watched, then the real end of the file (nil).
    var sleepTimerStopPoint: Duration? {
        isWatchingCredits ? nil : creditsStart
    }

    /// The segment behavior for this item; nil means the show's rule is to watch it.
    func behavior(for type: MediaSegmentType?) -> MediaSegmentBehavior? {
        guard let type else { return .off }

        return type.behavior(with: rule)
    }

    private func secondsDidChange(_ seconds: Duration) {
        defer { lastSeconds = seconds }

        guard isCurrentItem else {
            setActiveSegment(nil)
            endOfFileCountdown = nil
            return
        }

        updateEndOfFileCountdown(at: seconds)

        let segment = segments.first { segment in
            guard let start = segment.startSeconds, let end = segment.endSeconds else { return false }

            return (start ..< end).contains(seconds) && behavior(for: segment.type) != .off
        }

        guard let segment, let segmentID = segment.id else {
            setActiveSegment(nil)
            return
        }

        // The show's rule is to watch this segment: no button, just a short "Watching intro" chip
        guard let behavior = behavior(for: segment.type) else {
            setActiveSegment(nil)
            if isNaturalEntry(into: segment, at: seconds), noticedSegmentIDs.insert(segmentID).inserted {
                showWatchingNotice(for: segment.type)
            }
            return
        }

        if behavior == .autoSkip,
           !autoSkippedSegmentIDs.contains(segmentID),
           isNaturalEntry(into: segment, at: seconds)
        {
            autoSkippedSegmentIDs.insert(segmentID)
            perform(segment)
            return
        }

        guard !dismissedSegmentIDs.contains(segmentID) else {
            setActiveSegment(nil)
            return
        }

        setActiveSegment(segment)
    }

    private func isNaturalEntry(into segment: MediaSegmentDto, at seconds: Duration) -> Bool {
        guard let start = segment.startSeconds else { return false }
        guard let lastSeconds else {
            return seconds - start <= Self.naturalEntryThreshold
        }

        return lastSeconds <= start && seconds - lastSeconds <= Self.naturalEntryThreshold
    }

    private func showWatchingNotice(for type: MediaSegmentType?) {
        logger.info("Watching segment per the show's rule", metadata: ["type": .string(type?.rawValue ?? "")])
        noticeTask?.cancel()
        watchingNotice = type

        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.watchingNoticeDuration)
            guard !Task.isCancelled else { return }

            self?.watchingNotice = nil
        }
    }

    /// Credits set to Watch: the next episode countdown runs over the last seconds of the file,
    /// and the file's natural end plays the next episode (or the sleep timer stops playback).
    private func updateEndOfFileCountdown(at seconds: Duration) {
        guard isWatchingCredits, canPlayNextItem,
              let runtime = manager?.item.runtime, runtime > .zero
        else {
            if endOfFileCountdown != nil {
                endOfFileCountdown = nil
            }
            return
        }

        let remaining = (runtime - seconds).seconds
        let newValue: Int? = remaining > 0 && remaining <= Double(Self.nextEpisodeCountdown)
            ? Int(remaining.rounded(.up))
            : nil

        if newValue != endOfFileCountdown {
            endOfFileCountdown = newValue
        }
    }

    private func setActiveSegment(_ segment: MediaSegmentDto?) {
        guard segment?.id != activeSegment?.id else { return }

        activeSegment = segment
        stopCountdown()

        if segment?.type == .outro, canPlayNextItem, behavior(for: .outro) != nil {
            startCountdown()
        }
    }

    // MARK: - Actions

    /// Skips the segment, or plays the next item when skipping credits with a next item queued.
    private func perform(_ segment: MediaSegmentDto) {
        if segment.type == .outro, canPlayNextItem {
            playNextItem()
            return
        }

        guard let end = segment.endSeconds, let manager else { return }

        if let segmentID = segment.id {
            dismissedSegmentIDs.insert(segmentID)
        }
        setActiveSegment(nil)

        manager.seconds = end
        manager.proxy?.setSeconds(end)
    }

    private func playNextItem() {
        guard let nextItem = manager?.queue?.nextItem else { return }

        stopCountdown()
        activeSegment = nil
        manager?.playNewItem(provider: nextItem)
    }

    /// Hides the current segment's action and lets the segment play.
    func dismissActiveSegment() {
        guard let segmentID = activeSegment?.id else { return }

        dismissedSegmentIDs.insert(segmentID)
        setActiveSegment(nil)
    }

    // MARK: - Home preview

    enum PreviewAction: Equatable {
        /// Jump past a skipped segment
        case seek(Duration)
        /// The credits are skipped: end the preview here
        case stop
    }

    private var previewSkippedSegmentIDs: Set<String> = []

    /// What the Home preview (which has no buttons) does at `seconds`: it jumps past segments the
    /// show skips and ends at credits it skips. Watched segments play.
    func previewAction(at seconds: Duration) -> PreviewAction? {
        guard isLoaded else { return nil }

        let segment = segments.first { segment in
            guard let start = segment.startSeconds, let end = segment.endSeconds else { return false }

            return (start ..< end).contains(seconds)
        }

        guard let segment, let segmentID = segment.id, let end = segment.endSeconds else { return nil }
        guard let behavior = behavior(for: segment.type), behavior != .off else { return nil }

        if segment.type == .outro {
            return .stop
        }

        guard previewSkippedSegmentIDs.insert(segmentID).inserted else { return nil }

        return .seek(end)
    }

    // MARK: - Next item countdown

    private func startCountdown() {
        countdown = Self.nextEpisodeCountdown

        countdownTask = Task { [weak self] in
            while let self, let remaining = countdown, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                // Hold the countdown while paused or while the button is hidden behind the controls
                if manager?.playbackRequestStatus == .playing, isPresentingActions?() ?? true {
                    countdown = remaining - 1
                }
            }

            guard !Task.isCancelled else { return }

            self?.playNextItem()
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    // MARK: - Overlay actions

    var overlayActions: [VideoPlayerOverlayAction] {
        if let endOfFileCountdown {
            let subtitle = manager?.queue?.nextItem?.item.playerEpisodeLocator.map { L10n.upNextEpisode($0) }

            return [
                VideoPlayerOverlayAction(
                    id: "endOfFile",
                    title: L10n.nextEpisodeIn(endOfFileCountdown.description),
                    systemImage: "forward.end.fill",
                    subtitle: subtitle
                ) { [weak self] in
                    self?.playNextItem()
                },
            ]
        }

        guard let segment = activeSegment, let type = segment.type, let segmentID = segment.id else { return [] }

        if type == .outro, canPlayNextItem {
            let title = countdown.map { L10n.nextEpisodeIn($0.description) } ?? L10n.nextEpisode
            // "Up Next · S2, E3"
            let subtitle = manager?.queue?.nextItem?.item.playerEpisodeLocator.map { L10n.upNextEpisode($0) }

            return [
                VideoPlayerOverlayAction(id: segmentID, title: title, systemImage: "forward.end.fill", subtitle: subtitle) { [weak self] in
                    self?.playNextItem()
                },
            ]
        }

        return [
            VideoPlayerOverlayAction(id: segmentID, title: type.skipButtonTitle, systemImage: "forward.fill") { [weak self] in
                self?.perform(segment)
            },
        ]
    }
}
