//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import Logging

/// Keeps a player going in Picture in Picture after its full-screen view is dismissed.
///
/// While Picture in Picture is active this holds the manager and proxy (the view normally owns
/// the proxy), so playback and progress reports continue while the user browses the app or
/// leaves it. Restoring presents the player again with the same manager and proxy; closing the
/// window stops playback.
@MainActor
final class PictureInPictureSession: ObservableObject {

    static let shared = PictureInPictureSession()

    /// Whether a video is playing in Picture in Picture
    @Published
    private(set) var isActive = false

    private(set) var manager: MediaPlayerManager?
    private var proxy: (any VideoMediaPlayerLayoutConfigurable)?

    /// The manager whose full-screen player view is on screen, if any
    private weak var presentedPlayerManager: MediaPlayerManager?

    private var isRestoring = false
    private var restoreCompletion: ((Bool) -> Void)?
    private var restoreTimeoutTask: Task<Void, Never>?

    private let logger = Logger.swiftfin()

    private init() {}

    // MARK: - Lifecycle (called by the proxy's AVPictureInPictureController delegate)

    func didStart(proxy: any VideoMediaPlayerLayoutConfigurable) {
        guard let manager = proxy.manager else { return }

        self.manager = manager
        self.proxy = proxy
        isRestoring = false
        isActive = true

        logger.info("Picture in Picture started", metadata: ["itemID": .string(manager.item.id ?? "")])
    }

    /// The user asked to go back to full screen: present the player again with the same manager and proxy.
    func restore(proxy: any VideoMediaPlayerLayoutConfigurable, completion: @escaping (Bool) -> Void) {
        guard let manager, self.proxy === proxy, manager.state != .stopped else {
            completion(false)
            return
        }

        // The player view never left (iOS keeps it presented during Picture in Picture)
        if presentedPlayerManager === manager {
            completion(true)
            return
        }

        isRestoring = true
        restoreCompletion = completion

        // Finish even if the player view never attaches the layer (AVKit waits for this)
        restoreTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            self?.completeRestore()
        }

        logger.info("Restoring Picture in Picture to full screen")

        Container.shared.userSessionManager().routePublisher.send(.videoPlayer(manager: manager))
    }

    /// The restored player view put the video layer back on screen.
    func playerLayerDidAttach(proxy: any VideoMediaPlayerLayoutConfigurable) {
        guard isRestoring, self.proxy === proxy else { return }

        completeRestore()
    }

    func didStop(proxy: any VideoMediaPlayerLayoutConfigurable) {
        guard self.proxy === proxy else { return }

        let manager = manager
        let isBackOnScreen = manager != nil && presentedPlayerManager === manager

        completeRestore()
        release()

        // Closing the window (rather than going back to full screen) ends playback, as does a
        // restore whose player view never appeared (nothing would own the player)
        if !isBackOnScreen, let manager, manager.state != .stopped {
            logger.info("Picture in Picture ended without the player on screen, stopping playback")
            manager.stop()
        }
    }

    // MARK: - Player view

    func playerViewDidAppear(for manager: MediaPlayerManager) {
        presentedPlayerManager = manager
    }

    func playerViewDidDisappear(for manager: MediaPlayerManager) {
        guard presentedPlayerManager === manager else { return }

        presentedPlayerManager = nil
    }

    // MARK: - Queries

    /// The proxy to reuse when the player view is presented again for a restore.
    func restoringProxy(for manager: MediaPlayerManager) -> (any VideoMediaPlayerLayoutConfigurable)? {
        guard isRestoring, self.manager === manager else { return nil }

        return proxy
    }

    /// A restore is presenting the player view again
    var isRestoringPlayer: Bool {
        isRestoring
    }

    func isRestoring(_ manager: MediaPlayerManager) -> Bool {
        isRestoring && self.manager === manager
    }

    /// Whether this manager's player is (or is about to be) in Picture in Picture, so dismissing
    /// its view must not stop playback.
    func isHolding(_ manager: MediaPlayerManager) -> Bool {
        self.manager === manager
    }

    // MARK: - Replacing

    /// Ends the Picture in Picture playback before another video starts, so two players never play at once.
    func stopForNewPlayback(of newManager: MediaPlayerManager) {
        guard let manager, manager !== newManager else { return }

        let proxy = proxy
        release()

        logger.info("Replacing Picture in Picture playback with a new video")

        proxy?.pause()
        (proxy as? MediaPlayerPictureInPictureCapable)?.stopPiP()
        manager.stop()
    }

    // MARK: - Private

    private func completeRestore() {
        restoreTimeoutTask?.cancel()
        restoreTimeoutTask = nil

        if let restoreCompletion {
            self.restoreCompletion = nil
            restoreCompletion(true)
        }
    }

    private func release() {
        manager = nil
        proxy = nil
        isRestoring = false
        isActive = false
    }
}
