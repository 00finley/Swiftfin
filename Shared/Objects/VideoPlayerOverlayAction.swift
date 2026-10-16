//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@MainActor
struct VideoPlayerOverlayAction: Identifiable {

    /// How the action is drawn
    enum Style {
        /// A white capsule button (skip intro, next episode)
        case button
        /// A glass toast with a message and the action as its button (sleep timer)
        case toast(message: String, systemImage: String)
    }

    let id: String
    let title: String
    let systemImage: String?
    /// A small line above the title, e.g. "Up Next · S2, E3"
    let subtitle: String?
    let style: Style
    let action: @MainActor () -> Void

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        subtitle: String? = nil,
        style: Style = .button,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.style = style
        self.action = action
    }
}
