//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import UIKit

/// Full-width Liquid Glass search field, like the Apple TV app's: a glass capsule with a magnifying glass
/// and the prompt or the query, and a glass × to clear it.
///
/// tvOS draws its own white box around a focused `TextField`, so the visible field is a button; selecting it
/// brings up the system keyboard through a hidden `UITextField`, and the query stays in the capsule afterwards.
struct GlassSearchField: View {

    @Binding
    var text: String
    let prompt: String
    var clearLabel: String = L10n.categoriesClearSearch

    @StateObject
    private var keyboard = SearchKeyboardController()

    var body: some View {
        HStack(spacing: 24) {
            Button {
                keyboard.begin()
            } label: {
                HStack(spacing: 22) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityHidden(true)

                    if text.isEmpty {
                        Text(prompt)
                            .font(.system(size: 29, weight: .medium))
                            .opacity(0.62)
                    } else {
                        Text(text)
                            .font(.system(size: 31, weight: .semibold))
                    }

                    Spacer(minLength: 0)
                }
                .lineLimit(1)
            }
            .buttonStyle(GlassSearchFieldStyle())
            .accessibilityLabel(prompt)
            .accessibilityValue(text)
            .accessibilityIdentifier("glassSearchField")
            .background {
                SearchKeyboardBridge(text: $text, prompt: prompt, controller: keyboard)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }

            if text.isNotEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassChipButtonStyle(isCircle: true))
                .accessibilityLabel(clearLabel)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: text.isEmpty)
    }
}

// MARK: - Style

/// Glass capsule; focused it turns white with a bright rim, dark text and a slight lift
/// (the app's focused-chip look, scaled for a full-width field).
private struct GlassSearchFieldStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        GlassSearchFieldBody(configuration: configuration)
    }
}

private struct GlassSearchFieldBody: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background {
                Capsule()
                    .fill(.white)
                    .opacity(isFocused ? 1 : 0)
            }
            .glassEffect(isFocused ? .identity : .regular, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(isFocused ? 0.95 : 0.14), lineWidth: isFocused ? 3 : 1)
                    .shadow(color: .white.opacity(isFocused ? 0.55 : 0), radius: 10)
            }
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 1.0 : (isFocused ? 1.02 : 1))
            .offset(y: isFocused ? -3 : 0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 22, y: 12)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Keyboard

/// Never takes focus itself (the glass button opens the keyboard), but can still become first responder.
private final class KeyboardOnlyTextField: UITextField {

    override var canBecomeFocused: Bool {
        false
    }
}

/// Brings up the tvOS keyboard for the hidden text field.
@MainActor
final class SearchKeyboardController: ObservableObject {

    weak var field: UITextField?

    func begin() {
        field?.becomeFirstResponder()
    }
}

/// An invisible `UITextField` that only exists to drive the system keyboard; edits flow into `text` live.
private struct SearchKeyboardBridge: UIViewRepresentable {

    @Binding
    var text: String
    let prompt: String
    let controller: SearchKeyboardController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = KeyboardOnlyTextField()
        field.borderStyle = .none
        field.placeholder = prompt
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.text = text
        field.isAccessibilityElement = false
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidChange(_:)),
            name: UITextField.textDidChangeNotification,
            object: field
        )
        controller.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        // While the keyboard is up the field is the source of truth (tvOS may commit its text late)
        if !field.isEditing, field.text != text {
            field.text = text
        }
        field.placeholder = prompt
        controller.field = field
    }

    final class Coordinator: NSObject, UITextFieldDelegate {

        var text: Binding<String>
        /// The text as last typed; Menu on the tvOS keyboard reverts the field, but the query should stay.
        private var lastEdit: String?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc
        func changed(_ field: UITextField) {
            lastEdit = field.text ?? ""
            update(from: field)
        }

        @objc
        func textDidChange(_ notification: Notification) {
            if let field = notification.object as? UITextField, field.isEditing {
                lastEdit = field.text ?? ""
                update(from: field)
            }
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            lastEdit = nil
        }

        private func update(from field: UITextField) {
            let value = field.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if let lastEdit, field.text != lastEdit {
                field.text = lastEdit
            }
            update(from: field)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}
