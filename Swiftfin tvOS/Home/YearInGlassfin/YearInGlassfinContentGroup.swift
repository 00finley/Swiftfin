//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The Home banner that opens Your Year in Glassfin, near the top of Home from December 1 through
/// January 15 (see YearInGlassfin.isFeatured).
struct YearInGlassfinContentGroup: ContentGroup {

    let id = "home-year-in-glassfin"
    let isFeatured: Bool

    func body(with viewModel: Empty) -> some View {
        YearInGlassfinBanner(isFeatured: isFeatured)
    }
}

struct YearInGlassfinBanner: View {

    let isFeatured: Bool

    @Router
    private var router

    private var year: Int {
        YearInGlassfin.year()
    }

    var body: some View {
        Button {
            router.route(to: .yearInGlassfin)
        } label: {
            ZStack(alignment: .leading) {
                MeshGradient(
                    width: 3,
                    height: 2,
                    points: [[0, 0], [0.55, 0], [1, 0], [0, 1], [0.45, 1], [1, 1]],
                    colors: [
                        .init(red: 0.16, green: 0.07, blue: 0.32), .init(red: 0.55, green: 0.15, blue: 0.45), .init(
                            red: 0.95,
                            green: 0.45,
                            blue: 0.35
                        ),
                        .init(red: 0.05, green: 0.05, blue: 0.25), .init(red: 0.35, green: 0.15, blue: 0.75), .init(
                            red: 0.2,
                            green: 0.75,
                            blue: 0.7
                        ),
                    ]
                )

                Text(verbatim: String(year))
                    .font(.system(size: isFeatured ? 300 : 220, weight: .heavy, design: .rounded))
                    .kerning(-8)
                    .foregroundStyle(.white.opacity(0.14))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 40)
                    .offset(y: isFeatured ? 30 : 24)

                HStack(spacing: 36) {
                    Image(.glassfinGlyph)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isFeatured ? 120 : 92, height: isFeatured ? 120 : 92)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                    VStack(alignment: .leading, spacing: 8) {
                        if isFeatured {
                            Text(L10n.yearInGlassfinItsHere)
                                .font(.caption)
                                .fontWeight(.heavy)
                                .kerning(3)
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text(L10n.yearInGlassfinYour(String(year)))
                            .font(isFeatured ? .title2 : .headline)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        Text(L10n.yearInGlassfinBannerSubtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 56)
            }
            .frame(height: isFeatured ? 320 : 220)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.card)
        .edgePadding(.horizontal)
        .padding(.vertical, 10)
        .focusSection()
        .accessibilityLabel(L10n.yearInGlassfinYour(String(year)))
    }
}
