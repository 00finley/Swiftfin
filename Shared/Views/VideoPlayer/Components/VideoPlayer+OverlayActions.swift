//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension VideoPlayer {

    struct OverlayActions: View {

        @Environment(ViewState.self)
        private var viewState

        @FocusState
        private var focusedAction: String?

        private var actions: [ViewState.OverlayAction] {
            viewState.visibleElements.contains(.overlayActions) ? viewState.overlayActions : []
        }

        var body: some View {
            ViewThatFits(in: .horizontal) {
                buttons(axis: .horizontal)
                #if os(tvOS)
                ScrollView(.horizontal) {
                    buttons(axis: .horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .fixedSize(horizontal: false, vertical: true)
                #else
                buttons(axis: .vertical)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(.easeInOut(duration: 0.35), value: viewState.segmentWatchingNotice)
            #if os(tvOS)
            .focusSection()
            .onMoveCommand { direction in
                if viewState.presentation == .hidden, direction == .up || direction == .down {
                    viewState.showControls()
                }
            }
            .onChange(of: actions.map(\.id), initial: true) { oldIDs, _ in
                viewState.updateOverlayActionFocus(previousIDs: oldIDs)
            }
            .onChange(of: viewState.presentation) {
                viewState.updateOverlayActionFocus()
            }
            .onChange(of: viewState.isPresentingCloseConfirmation) {
                if !viewState.isPresentingCloseConfirmation {
                    viewState.updateOverlayActionFocus()
                }
            }
            #endif
        }

        private func buttons(axis: Axis) -> some View {
            let layout = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: UIDevice.isTV ? 24 : 12))
                : AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))

            return layout {
                if let notice = viewState.segmentWatchingNotice {
                    WatchingNoticeChip(type: notice)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                ForEach(actions) { action in
                    switch action.button.style {
                    case .button:
                        Button {
                            viewState.performOverlayAction(action.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                if let subtitle = action.button.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.black.opacity(0.6))
                                }

                                if let systemImage = action.button.systemImage {
                                    Label(action.button.title, systemImage: systemImage)
                                } else {
                                    Text(action.button.title)
                                }
                            }
                        }
                        .buttonStyle(OverlayActionButtonStyle())
                        .coordinatedFocus(action.id.focusID, selection: $focusedAction)

                    case let .toast(message, messageSystemImage):
                        Button {
                            viewState.performOverlayAction(action.id)
                        } label: {
                            OverlayToastLabel(
                                message: message,
                                messageSystemImage: messageSystemImage,
                                title: action.button.title,
                                systemImage: action.button.systemImage
                            )
                        }
                        .buttonStyle(OverlayToastButtonStyle())
                        .coordinatedFocus(action.id.focusID, selection: $focusedAction)
                    }
                }
            }
        }
    }

    /// "Watching intro": a small glass chip in place of the skip button when the show's rule is to
    /// watch that segment. Not focusable; it fades out on its own.
    private struct WatchingNoticeChip: View {

        let type: MediaSegmentType

        private var title: String {
            type == .outro ? L10n.watchingCredits : L10n.watchingIntro
        }

        var body: some View {
            Label(title, systemImage: "eye")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .lineLimit(1)
                .padding(.horizontal, UIDevice.isTV ? 28 : 16)
                .padding(.vertical, UIDevice.isTV ? 14 : 8)
                .backport
                .glassEffect(.regular, in: .capsule)
                .background(Color.black.opacity(0.3), in: Capsule())
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// The sleep timer warning: a glass toast with a message and its action, which turns white when focused.
    private struct OverlayToastLabel: View {

        @Environment(\.isFocused)
        private var isFocused

        let message: String
        let messageSystemImage: String
        let title: String
        let systemImage: String?

        var body: some View {
            HStack(spacing: UIDevice.isTV ? 24 : 12) {
                Label(message, systemImage: messageSystemImage)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)

                Group {
                    if let systemImage {
                        Label(title, systemImage: systemImage)
                    } else {
                        Text(title)
                    }
                }
                .font(.callout)
                .fontWeight(.semibold)
                .padding(.horizontal, UIDevice.isTV ? 24 : 14)
                .padding(.vertical, UIDevice.isTV ? 10 : 6)
                .foregroundStyle(isFocused ? .black : .white)
                .background(isFocused ? Color.white : Color.white.opacity(0.18), in: Capsule())
            }
            .lineLimit(1)
        }
    }

    private struct OverlayToastButtonStyle: ButtonStyle {

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.accessibilityReduceMotion)
        private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.leading, UIDevice.isTV ? 28 : 16)
                .padding(.trailing, UIDevice.isTV ? 10 : 6)
                .padding(.vertical, UIDevice.isTV ? 10 : 6)
                .backport
                .glassEffect(.regular, in: .capsule)
                .background(Color.black.opacity(0.35), in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(isFocused && !reduceMotion ? 1.04 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0.2), radius: isFocused ? 14 : 4)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }

    private struct OverlayActionButtonStyle: ButtonStyle {

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.isEnabled)
        private var isEnabled
        @Environment(\.accessibilityReduceMotion)
        private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.black)
                .symbolRenderingMode(.monochrome)
                .padding(.horizontal, UIDevice.isTV ? 28 : 20)
                .padding(.vertical, UIDevice.isTV ? 16 : 10)
                .frame(minHeight: 44)
                .background(.white, in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0.2), radius: isFocused ? 12 : 4)
                .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.5)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
