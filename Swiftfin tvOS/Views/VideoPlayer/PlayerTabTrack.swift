//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The player's bottom tabs ("Info", "Chapters", "Episodes"), like the Apple TV app: 62 pt glass
/// capsules that turn white with a dark label when focused.
///
/// Behaves like `SelectionTrack`: while the tabs have focus the focused tab is highlighted,
/// otherwise the presented supplement's tab is.
struct PlayerTabTrack<Elements: RandomAccessCollection, ID: Hashable>: View {

    static var height: CGFloat {
        62
    }

    private let elements: Elements
    private let id: KeyPath<Elements.Element, ID>
    private let title: KeyPath<Elements.Element, String>
    private let selection: ID?
    private let focus: FocusState<ID?>.Binding
    private let spacing: CGFloat
    private let action: (Elements.Element) -> Void

    init(
        _ elements: Elements,
        id: KeyPath<Elements.Element, ID>,
        title: KeyPath<Elements.Element, String>,
        selection: ID?,
        focus: FocusState<ID?>.Binding,
        spacing: CGFloat = 24,
        action: @escaping (Elements.Element) -> Void
    ) {
        self.elements = elements
        self.id = id
        self.title = title
        self.selection = selection
        self.focus = focus
        self.spacing = spacing
        self.action = action
    }

    private var highlightedID: ID? {
        focus.wrappedValue ?? selection
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(elements, id: id) { element in
                Button(element[keyPath: title]) {
                    action(element)
                }
                .focused(focus, equals: element[keyPath: id])
                .isSelected(highlightedID == element[keyPath: id])
            }
        }
        .buttonStyle(PlayerTabButtonStyle(isSelectionActive: focus.wrappedValue != nil))
    }
}

private struct PlayerTabButtonStyle: ButtonStyle {

    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isSelected)
    private var isSelected

    let isSelectionActive: Bool

    private var isHighlighted: Bool {
        isSelected || (isEnabled && isFocused)
    }

    private var highlightOpacity: Double {
        guard isHighlighted else { return 0 }

        return isFocused || isSelectionActive ? 1 : 0.35
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 29, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(isHighlighted && highlightOpacity == 1 ? Color.black : Color.white)
            .padding(.horizontal, 30)
            .frame(height: PlayerTabTrack<[Int], Int>.height)
            .background {
                Color.clear
                    .glassEffect(.regular.interactive(isEnabled), in: .capsule)
                    .overlay {
                        Capsule()
                            .fill(.white)
                            .opacity(highlightOpacity)
                    }
            }
            .contentShape(.capsule)
            .scaleEffect(isEnabled && isFocused ? 1.06 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.5)
            .shadow(color: isEnabled && isFocused ? .black.opacity(0.45) : .clear, radius: 12, y: 4)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: isSelected)
            .animation(.easeOut(duration: 0.12), value: isSelectionActive)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
