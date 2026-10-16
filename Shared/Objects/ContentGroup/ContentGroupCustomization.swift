//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@OptionSet<Int>
struct ContentGroupParentOption {

    private enum Options: Int {
        case ignoreSafeAreaTop
        /// The first group's preview is playing full screen; other groups fade out.
        case immersiveHero
        /// The hero has focus: keep the page scrolled to the top so its row stays cut off by the
        /// bottom edge, like the Apple TV app, instead of scrolling the focused card into view.
        case pinsToTop
    }
}

struct ContentGroupCustomizationKey: PreferenceKey {

    static var defaultValue: ContentGroupParentOption = []

    static func reduce(
        value: inout ContentGroupParentOption,
        nextValue: () -> ContentGroupParentOption
    ) {
        value.formUnion(nextValue())
    }
}
