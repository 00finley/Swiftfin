//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ActionBar: View {

        @FocusState
        private var focusedButton: String?

        @ObservedObject
        var provider: ItemContentGroupProvider

        private var buttonConfiguration = ItemActionButtons.Configuration()

        let alignment: HorizontalAlignment
        let axis: Axis

        init(
            provider: ItemContentGroupProvider,
            alignment: HorizontalAlignment = .center,
            axis: Axis = .vertical
        ) {
            self.provider = provider
            self.alignment = alignment
            self.axis = axis
        }

        private var playButtonWidth: CGFloat {
            UIDevice.isTV ? 420 : 220
        }

        var body: some View {
            let (visible, overflow, menu) = buttonConfiguration.resolvedButtons(for: provider)
            let defaultFocusedButton = provider.item.presentPlayButton ?
                ItemView.Component.play : visible.first?.id ?? ItemView.Component.menu

            let layout = axis == .vertical
                ? AnyLayout(VStackLayout(alignment: alignment, spacing: UIDevice.isTV ? 24 : 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: UIDevice.isTV ? 24 : 8))

            layout {
                if provider.item.presentPlayButton {
                    PlayButton(provider: provider)
                        .coordinatedFocus(ItemView.Component.play, selection: $focusedButton)
                        .frame(width: axis == .horizontal ? playButtonWidth : nil)
                        .frame(height: UIDevice.isTV ? 75 : 44)
                }

                ItemActionButtons(
                    provider: provider,
                    buttons: visible,
                    overflowButtons: overflow,
                    menuButtons: menu,
                    focusedButton: $focusedButton
                )
                .fixedSize(horizontal: axis == .horizontal, vertical: false)
            }
            .focusSection()
            .defaultFocus(
                $focusedButton,
                defaultFocusedButton,
                priority: .userInitiated
            )
            .multilineTextAlignment(.center)
        }
    }
}
