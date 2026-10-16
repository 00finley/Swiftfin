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
import SwiftUI
import Transmission

struct VideoPlayer: View {

    @Environment(\.presentationCoordinator)
    private var presentationCoordinator

    @InjectedObject(\.mediaPlayerManager)
    private var manager: MediaPlayerManager

    @LazyState
    private var proxy: any VideoMediaPlayerLayoutConfigurable

    @Router
    private var router

    @State
    private var isBeingDismissedByTransition = false
    @State
    private var isDismissingForPictureInPicture = false
    @State
    private var safeAreaInsets: EdgeInsets = .init()

    #if os(iOS)
    @State
    private var scrubbingStartTime: CFTimeInterval? = nil
    #endif

    @State
    private var viewState: ViewState = .init()

    init() {
        // Back from Picture in Picture: keep the player that's been playing
        if PictureInPictureSession.shared.isRestoringPlayer,
           let restoredProxy = PictureInPictureSession.shared.restoringProxy(for: FactoryKit.Container.shared.mediaPlayerManager())
        {
            self._proxy = .init(wrappedValue: restoredProxy)
            return
        }

        switch Defaults[.VideoPlayer.videoPlayerType] {
        case .avPlayer:
            self._proxy = .init(wrappedValue: AVMediaPlayerProxy())
        case .mpv:
            self._proxy = .init(wrappedValue: MPVMediaPlayerProxy())
        case .vlc:
            self._proxy = .init(wrappedValue: VLCMediaPlayerProxy())
        }
    }

    #if os(tvOS)
    private var pictureInPictureActivePublisher: AnyPublisher<Bool, Never> {
        (proxy as? MediaPlayerPictureInPictureCapable)?
            .isPiPActive
            .$value
            .removeDuplicates()
            .eraseToAnyPublisher()
            ?? Just(false).eraseToAnyPublisher()
    }
    #endif

    var body: some View {
        Container(
            viewState: viewState,
            manager: manager,
            videoSize: proxy.videoSize
        ) { videoLayout in
            proxy.videoPlayerBody(layout: videoLayout)
                .eraseToAnyView()
        } playbackControls: {
            PlaybackControls()
        }
        .onAppear {
            manager.proxy = proxy
            PictureInPictureSession.shared.playerViewDidAppear(for: manager)

            if !PictureInPictureSession.shared.isRestoring(manager) {
                manager.start()
            }
        }
        .prefersStatusBarHidden(!viewState.isPresentingControls)
        #if os(iOS)
        .onChange(of: viewState.isScrubbing) {
            if viewState.isScrubbing {
                scrubbingStartTime = CACurrentMediaTime()
                return
            }

            guard let scrubbingStartTime else { return }

            self.scrubbingStartTime = nil
            let scrubbingDelta = CACurrentMediaTime() - scrubbingStartTime
            let secondsDelta = abs(manager.seconds - viewState.scrubbedSeconds.value)

            guard secondsDelta >= .seconds(1), scrubbingDelta >= 0.1 else { return }

            let scrubbedSeconds = viewState.scrubbedSeconds.value
            manager.seconds = scrubbedSeconds
            proxy.setSeconds(scrubbedSeconds)
        }
        #endif
        .preference(
            key: PresentationControllerShouldDismissPreferenceKey.self,
            value: viewState.presentationControllerShouldDismiss
        )
        .onChange(of: presentationCoordinator.isPresented) {
            guard !presentationCoordinator.isPresented else { return }

            isBeingDismissedByTransition = true

            guard !PictureInPictureSession.shared.isHolding(manager) else { return }

            manager.stop()
        }
        .onReceive(manager.$playbackItem) { newItem in
            // TODO: move to container view
            if PictureInPictureSession.shared.isRestoring(manager) {
                viewState.scrubbedSeconds.value = manager.seconds
            } else {
                viewState.scrubbedSeconds.value = newItem?.baseItem.startSeconds ?? .zero
            }
        }
        .onDisappear {
            PictureInPictureSession.shared.playerViewDidDisappear(for: manager)
        }
        #if os(tvOS)
        .onReceive(pictureInPictureActivePublisher) { isActive in
            // The video continues in the Picture in Picture window: step out of the way, back to
            // wherever the user was
            guard isActive, !isDismissingForPictureInPicture, !PictureInPictureSession.shared.isRestoring(manager) else { return }

            isDismissingForPictureInPicture = true
            router.dismiss()
        }
        #endif
        .onReceive(manager.$state) { newState in
            if newState == .stopped, !isBeingDismissedByTransition {
                router.dismiss()
            }
        }

        .alert(
            L10n.error,
            isPresented: .constant(manager.error != nil)
        ) {
            Button(L10n.close, role: .cancel) {
                FactoryKit.Container.shared.mediaPlayerManager.reset()
                router.dismiss()
            }
        } message: {
            Text(L10n.unableToLoadThisItem)
        }
        .environment(\.safeAreaInsets, safeAreaInsets)
        .colorScheme(.dark) // use over `preferredColorScheme(.dark)` to not have destination change
        .supportedOrientations(.allButUpsideDown)
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onSceneDidEnterBackground {
            let isPictureInPictureActive = (proxy as? MediaPlayerPictureInPictureCapable)?.isPiPActive.value == true
            if Defaults[.VideoPlayer.Transition.pauseOnBackground], !isPictureInPictureActive {
                manager.setPlaybackRequestStatus(status: .paused)
            }
        }
        .onSizeChanged { _, safeArea in
            self.safeAreaInsets = safeArea.max(EdgeInsets.edgePadding)
        }
    }
}
