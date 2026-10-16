//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct PictureInPicture: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var isPiPActive: Bool = false
        @State
        private var isPiPAvailable: Bool = false

        private var systemImage: String {
            if isPiPActive {
                VideoPlayerActionButton.pictureInPicture.secondarySystemImage
            } else {
                VideoPlayerActionButton.pictureInPicture.systemImage
            }
        }

        private var isPiPActivePublisher: AnyPublisher<Bool, Never> {
            (manager.proxy as? MediaPlayerPictureInPictureCapable)?
                .isPiPActive
                .$value
                .eraseToAnyPublisher()
                ?? Just(false).eraseToAnyPublisher()
        }

        private var isPiPAvailablePublisher: AnyPublisher<Bool, Never> {
            (manager.proxy as? MediaPlayerPictureInPictureCapable)?
                .isPiPAvailable
                .$value
                .eraseToAnyPublisher()
                ?? Just(false).eraseToAnyPublisher()
        }

        var body: some View {
            if manager.proxy is any MediaPlayerPictureInPictureCapable {
                Button(L10n.pictureInPicture, systemImage: systemImage) {
                    if isPiPActive {
                        manager.stopPictureInPicture()
                    } else {
                        manager.startPictureInPicture()
                    }
                }
                // Not possible until the video is ready
                .disabled(!isPiPActive && !isPiPAvailable)
                .onReceive(isPiPActivePublisher) { isPiPActive = $0 }
                .onReceive(isPiPAvailablePublisher) { isPiPAvailable = $0 }
            }
        }
    }
}
