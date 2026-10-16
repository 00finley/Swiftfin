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
/// and offers skip / next episode overlay actions according to the user's settings.
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
    private var segments: [MediaSegmentDto] = []
    private var lastSeconds: Duration?
    private var dismissedSegmentIDs: Set<String> = []
    private var autoSkippedSegmentIDs: Set<String> = []
    private var countdownTask: Task<Void, Never>?
    private var observerCancellables: Set<AnyCancellable> = []

    init(item: MediaPlayerItem) {
        self.itemID = item.baseItem.id
        super.init()

        fetchSegments()
    }

    deinit {
        countdownTask?.cancel()
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

            do {
                let request = Paths.getItemSegments(
                    itemID: itemID,
                    includeSegmentTypes: MediaSegmentType.skippableCases
                )
                let response = try await client.send(request)

                segments = Self.deduplicated(response.value.items ?? [])

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

    private func secondsDidChange(_ seconds: Duration) {
        defer { lastSeconds = seconds }

        guard isCurrentItem else {
            setActiveSegment(nil)
            return
        }

        let segment = segments.first { segment in
            guard let start = segment.startSeconds, let end = segment.endSeconds else { return false }

            return (start ..< end).contains(seconds) && segment.type?.behavior != .off
        }

        guard let segment, let segmentID = segment.id else {
            setActiveSegment(nil)
            return
        }

        if segment.type?.behavior == .autoSkip,
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

    private func setActiveSegment(_ segment: MediaSegmentDto?) {
        guard segment?.id != activeSegment?.id else { return }

        activeSegment = segment
        stopCountdown()

        if segment?.type == .outro, canPlayNextItem {
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
