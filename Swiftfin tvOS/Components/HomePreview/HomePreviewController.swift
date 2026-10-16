//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Combine
import Defaults
import FactoryKit
import Get
import JellyfinAPI
import Logging
import SwiftUI

/// Netflix-style preview for Home's Up Next row: after a card stays focused for a moment, its
/// episode plays behind the hero, then the rest of the UI steps aside.
///
/// Previews never send playback reports (start/progress/stopped), so the server's watch progress
/// is untouched. The preview uses its own play session, and its transcode is stopped when it ends.
///
/// Previews follow the same skip rules as the player (global settings plus the show's intro /
/// credits rule): skipped intros and recaps are jumped over, and skipped credits end the preview.
@MainActor
final class HomePreviewController: ObservableObject {

    /// The item whose video is on screen, set only once frames are actually rendering
    @Published
    private(set) var visibleItemID: String?

    /// The preview has been showing long enough for the UI to step aside
    @Published
    private(set) var isImmersive = false

    /// Zoom that crops letterbox bars baked into the video, so it fills the screen like the still
    @Published
    private(set) var videoScale: CGFloat = 1

    let player: AVPlayer = {
        let player = AVPlayer()
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        return player
    }()

    /// Placeholder for selectors that don't preview; never started
    static let disabled = HomePreviewController()

    static let startDelay: Duration = .milliseconds(1500)
    static let immersiveDelay: Duration = .seconds(8)
    static let volume: Float = 0.6

    private let logger = Logger.swiftfin()

    private var focusedItemID: String?
    private var loadingItemID: String?
    private var loadTask: Task<Void, Never>?
    private var immersiveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var segmentTimeObserver: Any?
    private var segmentObserver: MediaSegmentObserver?
    private var statusObservation: NSKeyValueObservation?
    private var isLayerReadyForDisplay = false
    private var startSeconds: Double = 0
    private var playSession: (id: String, deviceID: String)?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var cancellables: Set<AnyCancellable> = []

    private var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    init() {
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.stop() }
            .store(in: &cancellables)

        // Never two videos (and two soundtracks) at once: no previews while Picture in Picture plays
        PictureInPictureSession.shared
            .$isActive
            .filter(\.self)
            .sink { [weak self] _ in self?.stop() }
            .store(in: &cancellables)
    }

    // MARK: - Focus

    /// Call whenever the focused Up Next item changes (nil when focus leaves the row and hero).
    func focusChanged(to item: BaseItemDto?) {
        guard item?.id != focusedItemID else { return }

        focusedItemID = item?.id
        stop()

        guard let item,
              let itemID = item.id,
              Defaults[.VideoPlayer.HomePreviews.autoplay],
              !PictureInPictureSession.shared.isActive,
              [.episode, .movie, .video].contains(item.type)
        else { return }

        loadingItemID = itemID
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.startDelay)
            guard !Task.isCancelled else { return }

            await self?.start(item)
        }
    }

    /// Any remote input: bring the UI back and wait again before stepping aside.
    func userDidInteract() {
        guard visibleItemID != nil else { return }

        if isImmersive {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                isImmersive = false
            }
        }
        scheduleImmersive()
    }

    /// Whether the item's preview video is on screen.
    func isShowing(_ itemID: String?) -> Bool {
        itemID != nil && itemID == visibleItemID
    }

    /// Current preview position for the item, if its video is on screen: where full playback should
    /// continue from when the user clicks in.
    func continuationTicks(for itemID: String?) -> Int? {
        guard isShowing(itemID) else { return nil }

        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return nil }

        logger.info(
            "Continuing Home preview into playback",
            metadata: [
                "itemID": .string(itemID ?? ""),
                "previewStartSeconds": .stringConvertible(startSeconds),
                "positionSeconds": .stringConvertible(seconds),
            ]
        )

        return Int(seconds * 10_000_000)
    }

    func layerReadyForDisplayChanged(_ isReady: Bool) {
        isLayerReadyForDisplay = isReady
    }

    // MARK: - Playback

    private func start(_ item: BaseItemDto) async {
        guard let itemID = item.id else { return }

        do {
            // Same PlaybackInfo flow as real playback (AVPlayer profile -> HLS remux/transcode URL),
            // but nothing here reports playback to the server.
            let playbackItem = try await MediaPlayerItem.build(for: item, videoPlayerType: .avPlayer)

            guard !Task.isCancelled, loadingItemID == itemID else {
                stopEncoding(playSessionID: playbackItem.playSessionID)
                return
            }

            // Fetches the item's segments and resolves the show's skip rule
            segmentObserver = playbackItem.mediaSegmentObserver

            if let deviceID = Container.shared.currentUserSession()?.client.configuration.deviceID {
                playSession = (playbackItem.playSessionID, deviceID)
            }

            let ticks = playbackItem.baseItem.userData?.playbackPositionTicks ?? 0
            startSeconds = Double(ticks) / 10_000_000

            let playerItem = AVPlayerItem(url: playbackItem.url)
            playerItem.preferredForwardBufferDuration = 4

            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            playerItem.add(output)
            videoOutput = output

            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

            player.isMuted = !Defaults[.VideoPlayer.HomePreviews.sound]
            player.volume = Self.volume
            player.replaceCurrentItem(with: playerItem)

            statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
                Task { @MainActor in
                    guard let self, observedItem.status == .readyToPlay, self.loadingItemID == itemID,
                          !PictureInPictureSession.shared.isActive
                    else { return }

                    await self.beginPlayback(of: itemID)
                }
            }
        } catch {
            logger.warning("Home preview unavailable", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    private func beginPlayback(of itemID: String) async {
        statusObservation = nil

        if startSeconds > 1 {
            let target = CMTime(seconds: startSeconds, preferredTimescale: 600)
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
        }
        guard loadingItemID == itemID else { return }

        player.play()
        observeSegments(of: itemID)

        // Reveal only once frames are flowing: the layer can display and playback has advanced
        let startTime = player.currentTime().seconds
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.loadingItemID == itemID, self.visibleItemID == nil else { return }
                guard self.player.timeControlStatus == .playing,
                      self.isLayerReadyForDisplay,
                      time.seconds - startTime > 0.3
                else { return }

                self.videoScale = self.letterboxScale(at: time)

                withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.6)) {
                    self.visibleItemID = itemID
                }
                self.logger.info(
                    "Home preview visible",
                    metadata: [
                        "itemID": .string(itemID),
                        "previewStartSeconds": .stringConvertible(self.startSeconds),
                        "positionSeconds": .stringConvertible(time.seconds),
                    ]
                )
                self.scheduleImmersive()
            }
        }
    }

    /// Jumps past intros and recaps the show skips, and ends the preview at credits it skips.
    private func observeSegments(of itemID: String) {
        guard segmentObserver != nil else { return }

        segmentTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.loadingItemID == itemID, time.seconds.isFinite,
                      let action = self.segmentObserver?.previewAction(at: .seconds(time.seconds))
                else { return }

                switch action {
                case let .seek(end):
                    self.logger.info("Home preview skipped a segment", metadata: ["itemID": .string(itemID)])
                    self.player.seek(to: CMTime(seconds: end.seconds, preferredTimescale: 600))

                case .stop:
                    self.logger.info("Home preview reached skipped credits", metadata: ["itemID": .string(itemID)])
                    self.stop()
                }
            }
        }
    }

    /// Samples the current frame and measures black bars at the top and bottom. Returns the zoom
    /// that removes them (1 when the picture is full frame).
    private func letterboxScale(at time: CMTime) -> CGFloat {
        guard let videoOutput,
              let buffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        else { return 1 }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 1 }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        func isBlackRow(_ y: Int) -> Bool {
            var total = 0
            let samples = 48
            for i in 0 ..< samples {
                let x = (width * (2 * i + 1)) / (2 * samples)
                let offset = y * bytesPerRow + x * 4
                total += Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])
            }
            return total / (samples * 3) < 18
        }

        var top = 0
        while top < height / 3, isBlackRow(top) {
            top += 2
        }
        var bottom = 0
        while bottom < height / 3, isBlackRow(height - 1 - bottom) {
            bottom += 2
        }

        let bar = CGFloat(min(top, bottom)) / CGFloat(height)
        guard bar > 0.03 else { return 1 }

        return min(1 / (1 - 2 * bar), 1.4)
    }

    private func scheduleImmersive() {
        immersiveTask?.cancel()
        immersiveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.immersiveDelay)
            guard !Task.isCancelled, let self, self.visibleItemID != nil else { return }

            withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                self.isImmersive = true
            }
        }
    }

    /// Stops the preview, releases the player item and ends the server-side transcode.
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        immersiveTask?.cancel()
        immersiveTask = nil
        statusObservation = nil
        loadingItemID = nil
        videoOutput = nil

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let segmentTimeObserver {
            player.removeTimeObserver(segmentTimeObserver)
            self.segmentTimeObserver = nil
        }
        segmentObserver = nil

        if player.currentItem != nil {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }

        if visibleItemID != nil || isImmersive {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                visibleItemID = nil
                isImmersive = false
            }
        }

        if let playSession {
            stopEncoding(playSessionID: playSession.id, deviceID: playSession.deviceID)
            self.playSession = nil
        }
    }

    /// Ends the HLS transcode so the server doesn't keep remuxing after the preview is gone.
    private func stopEncoding(playSessionID: String, deviceID: String? = nil) {
        guard let session = Container.shared.currentUserSession() else { return }

        let deviceID = deviceID ?? session.client.configuration.deviceID

        Task {
            let request = Request<Void>(
                path: "/Videos/ActiveEncodings",
                method: .delete,
                query: [("deviceId", deviceID), ("playSessionId", playSessionID)]
            )
            _ = try? await session.client.send(request)
        }
    }
}
