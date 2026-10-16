//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct ContentGroupVStack: View {

    let groups: [any ContentGroup]
    var isHeroImmersive: Bool = false

    private var spacing: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }

    /// Scroll target placed one group spacing above a group, so scrolling a group to the top leaves
    /// its header inside the 60pt top safe area instead of under the screen edge.
    static func scrollAnchorID(for groupID: String) -> String {
        "\(groupID)-scrollAnchor"
    }

    @ViewBuilder
    private func makeGroupBody(_ group: some ContentGroup) -> some View {
        group.body(with: group.viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                makeGroupBody(group)
                    .eraseToAnyView()
                    .coordinatedFocus(group.id)
                    .id(group.id)
                    .background(alignment: .top) {
                        Color.clear
                            .frame(height: spacing)
                            .id(Self.scrollAnchorID(for: group.id))
                            .padding(.top, -spacing)
                    }
                    .opacity(isHeroImmersive && index > 0 ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
