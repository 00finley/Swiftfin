//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct FilterBarModifier: ViewModifier {

    @Default(.accentColor)
    private var accentColor

    @Router
    private var router

    @ObservedObject
    var viewModel: FilterViewModel

    let types: [ItemFilterType]

    /// One labeled entry point instead of a rail of unlabeled icons.
    @ViewBuilder
    private var sortAndFilterMenu: some View {
        Menu {
            ForEach(types, id: \.self) { type in
                Button(type.displayTitle, systemImage: type.systemImage) {
                    router.route(to: .filter(type: type, viewModel: viewModel))
                }
            }

            if viewModel.hasActiveFilters {
                Divider()

                Button(L10n.reset, systemImage: "arrow.counterclockwise", role: .destructive) {
                    viewModel.reset(filterType: nil)
                }
            }
        } label: {
            Label(
                L10n.sortAndFilter,
                systemImage: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease"
            )
            .font(.callout)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
        }
        .menuStyle(.button)
        .buttonStyle(.capsule(selectionTint: accentColor, focusTint: .white))
        .isSelected(viewModel.hasActiveFilters)
    }

    func body(content: Content) -> some View {
        if types.isEmpty {
            content
        } else {
            content
                .focusSection()
                .safeAreaInset(edge: .top, alignment: .trailing, spacing: 0) {
                    sortAndFilterMenu
                        .focusSection()
                        .edgePadding(.horizontal)
                        .padding(.bottom, 24)
                }
        }
    }
}
