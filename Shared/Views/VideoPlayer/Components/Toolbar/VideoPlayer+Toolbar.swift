//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct Toolbar: View {

        typealias ViewState = VideoPlayer.ViewState

        /// tvOS: the Apple TV app's 66 pt circular glass buttons
        static let buttonSize: CGFloat = UIDevice.isTV ? 66 : 44

        @Environment(ViewState.self)
        private var viewState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @Router
        private var router

        @ViewBuilder
        private var closeButton: some View {
            Button {
                if viewState.isPresentingSupplement {
                    viewState.selectedSupplementID = nil
                } else {
                    manager.stop()
                    router.dismiss()
                }
            } label: {
                Label(
                    L10n.close,
                    systemImage: viewState.isPresentingSupplement ? "chevron.down" : "xmark"
                )
                .labelStyle(.iconOnly)
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)
        }

        @ViewBuilder
        private var content: some View {
            #if os(tvOS)
            // Apple TV app: the circular buttons line up with the big title, flush with the right margin
            HStack(alignment: .playerTitle, spacing: 40) {
                TitleView(item: manager.item)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ActionButtons()
                    .frame(height: Self.buttonSize)
                    .alignmentGuide(.playerTitle) { $0[VerticalAlignment.center] }
            }
            #else
            HStack(alignment: .center) {
                closeButton
                    .modifier(OverlayBarButtonStyleModifier())

                TitleView(item: manager.item)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ActionButtons()
                    .frame(height: Self.buttonSize)
                    .padding(.horizontal)
            }
            #endif
        }

        var body: some View {
            content
                .font(.system(size: UIDevice.isTV ? 30 : 24, weight: .semibold))
                .menuStyle(OverlayMenuStyle())
                #if os(iOS)
                .background {
                    EmptyHitTestView()
                }
                #endif
        }
    }
}

extension VideoPlayer.PlaybackControls.Toolbar {

    struct TitleView: PlatformView {

        @State
        private var subtitleContentSize: CGSize = .zero

        @SharedBaseItem
        var item: BaseItemDto

        private var _titleSubtitle: (title: String, subtitle: String?) {
            if item.type == .episode {
                if let parentTitle = item.parentTitle {
                    return (title: parentTitle, subtitle: item.playerEpisodeLocator ?? item.seasonEpisodeLabel)
                }
            }

            return (title: item.displayTitle, subtitle: nil)
        }

        @ViewBuilder
        private func _subtitle(_ subtitle: String) -> some View {
            Text(subtitle)
                .font(UIDevice.isTV ? .caption : .subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .trackingSize($subtitleContentSize)
        }

        var iOSView: some View {
            Text(_titleSubtitle.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomLeading) {
                    if let subtitle = _titleSubtitle.subtitle {
                        _subtitle(subtitle)
                            .lineLimit(1)
                            .offset(y: subtitleContentSize.height)
                    }
                }
        }

        var tvOSView: some View {
            // Apple TV app: "S3, E11 • Episode Title" (about 27 pt) above the show title (about 57 pt bold).
            // Movies show only their title.
            let titles = item.playerTitles

            VStack(alignment: .leading, spacing: 4) {
                if let subtitle = titles.subtitle {
                    Text(subtitle)
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text(titles.title)
                    .font(.system(size: 57, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .alignmentGuide(.playerTitle) { $0[VerticalAlignment.center] }
            }
            .lineLimit(1)
        }
    }
}

extension VerticalAlignment {

    private enum PlayerTitle: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    /// tvOS player: the center of the big title, which the bar's buttons line up with
    static let playerTitle = VerticalAlignment(PlayerTitle.self)
}
