//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct UnplayedIndicator: View {

    @Default(.accentColor)
    private var accentColor

    let count: Int?

    var body: some View {
        if let count, count > 0 {
            Quadrant(.topTrailing) {
                QuadrantItem(color: accentColor) {
                    Text(count.description)
                        .font(.body)
                        .fontWeight(.semibold)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.posterAccessibilityUnplayedCount(count.formatted()))
        } else {
            Circle()
                .fill(accentColor)
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.45), radius: 4)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityLabel(L10n.unplayed)
        }
    }
}

private struct Q3RightTriangle: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        return path
    }
}
