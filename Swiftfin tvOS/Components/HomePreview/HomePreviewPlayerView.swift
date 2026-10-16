//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import SwiftUI

/// Video layer for the Home preview. Reports when it can actually display frames, so the
/// still image stays up until then.
struct HomePreviewPlayerView: UIViewRepresentable {

    let player: AVPlayer
    let onReadyForDisplayChange: (Bool) -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        view.onReadyForDisplayChange = onReadyForDisplayChange
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.onReadyForDisplayChange = onReadyForDisplayChange
    }

    final class PlayerLayerView: UIView {

        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }

        var onReadyForDisplayChange: ((Bool) -> Void)?

        private var observation: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            observation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let isReady = layer.isReadyForDisplay
                DispatchQueue.main.async {
                    self?.onReadyForDisplayChange?(isReady)
                }
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
