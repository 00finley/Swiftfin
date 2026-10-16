//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import UIKit

/// While active, swallows the next remote press or swipe at the window level and calls `onInput`
/// instead, so the first input after the Home preview goes full screen only brings the UI back
/// (Menu doesn't leave the screen, Select doesn't open the item, swipes don't move focus).
struct RemoteInputInterceptor: UIViewRepresentable {

    let isActive: Bool
    let onInput: () -> Void

    func makeUIView(context: Context) -> InterceptorView {
        let view = InterceptorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: InterceptorView, context: Context) {
        uiView.onInput = onInput
        uiView.isActive = isActive
    }

    static func dismantleUIView(_ uiView: InterceptorView, coordinator: ()) {
        uiView.isActive = false
    }

    final class InterceptorView: UIView {

        var onInput: (() -> Void)?

        var isActive = false {
            didSet {
                guard isActive != oldValue else { return }

                isActive ? install() : uninstall()
            }
        }

        private var recognizers: [UIGestureRecognizer] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                uninstall()
            } else if isActive, recognizers.isEmpty {
                install()
            }
        }

        private func install() {
            guard let window, recognizers.isEmpty else { return }

            let pressTypes: [UIPress.PressType] = [.upArrow, .downArrow, .leftArrow, .rightArrow, .select, .menu, .playPause]

            for pressType in pressTypes {
                let tap = UITapGestureRecognizer(target: self, action: #selector(handle))
                tap.allowedPressTypes = [NSNumber(value: pressType.rawValue)]
                tap.allowedTouchTypes = []
                tap.cancelsTouchesInView = true
                window.addGestureRecognizer(tap)
                recognizers.append(tap)
            }

            let swipe = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            swipe.cancelsTouchesInView = true
            window.addGestureRecognizer(swipe)
            recognizers.append(swipe)
        }

        private func uninstall() {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizers.removeAll()
        }

        @objc
        private func handle() {
            guard isActive else { return }

            onInput?()
        }

        @objc
        private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard isActive, recognizer.state == .began else { return }

            onInput?()
        }
    }
}
