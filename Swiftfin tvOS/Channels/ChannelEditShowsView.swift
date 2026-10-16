//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension NavigationRoute {

    @MainActor
    static func channelEditShows(channel: ChannelDefinition) -> NavigationRoute {
        NavigationRoute(id: "channelEditShows-\(channel.id)") {
            ChannelEditShowsView(channel: channel)
        }
    }
}

/// Edit Shows: every show in the library with a glass toggle. Shows that match the channel's
/// rule come first; the order never changes while toggling, so focus stays put.
struct ChannelEditShowsView: View {

    let channel: ChannelDefinition

    @ObservedObject
    private var store = ChannelStore.shared

    @State
    private var series: [BaseItemDto]?
    @State
    private var errorMessage: String?

    private var matching: [BaseItemDto] {
        (series ?? []).filter { channel.pool.matches($0) }
    }

    private var others: [BaseItemDto] {
        (series ?? []).filter { !channel.pool.matches($0) }
    }

    private var includedCount: Int {
        (series ?? []).count { isIncluded($0) }
    }

    private func isIncluded(_ item: BaseItemDto) -> Bool {
        guard let id = item.id else { return false }

        return store.includes(id, matchesRule: channel.pool.matches(item), in: channel)
    }

    private func toggle(_ item: BaseItemDto) {
        guard let id = item.id else { return }

        store.setIncluded(!isIncluded(item), seriesID: id, matchesRule: channel.pool.matches(item), in: channel)
    }

    private let columns = [GridItem(.flexible(), spacing: 40), GridItem(.flexible(), spacing: 40)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 50)

                if let series {
                    if series.isEmpty {
                        Text(L10n.channelsNoShowsInLibrary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        section(L10n.channelsMatchingShows, items: matching)
                        section(L10n.channelsOtherShows, items: others)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .background {
            LinearGradient(colors: [Color(white: 0.11), Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .task {
            do {
                series = try await ChannelLibrary.shared.allSeries(maxAge: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                ChannelNameBadge(channel: channel, isOnGlass: true)

                Text(L10n.channelsEditShows)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(L10n.channelsEditShowsDescription(channel.name))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)

                if series != nil {
                    Text(includedCount == 1 ? L10n.channelsOneShow : L10n.channelsShowCount(includedCount.description))
                        .accessibilityIdentifier("channel.edit.count")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer()

            Button {
                store.resetShows(for: channel)
            } label: {
                Label(L10n.channelsResetShows, systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 30)
                    .frame(height: 64)
            }
            .buttonStyle(.homeGlass)
            .accessibilityIdentifier("channel.edit.reset")
        }
        .focusSection()
    }

    @ViewBuilder
    private func section(_ title: String, items: [BaseItemDto]) -> some View {
        if items.isNotEmpty {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 24)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                ForEach(items, id: \.id) { item in
                    ChannelShowToggleRow(series: item, isOn: isIncluded(item)) {
                        toggle(item)
                    }
                }
            }
            .padding(.bottom, 60)
            .focusSection()
        }
    }
}

/// A show with its glass switch. Focused: white with a dark label.
private struct ChannelShowToggleRow: View {

    let series: BaseItemDto
    let isOn: Bool
    let action: () -> Void

    private var detail: String {
        [series.genres?.prefix(2).joined(separator: ", "), series.officialRating]
            .compactMap(\.self)
            .filter(\.isNotEmpty)
            .joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            ChannelShowToggleLabel(series: series, detail: detail, isOn: isOn)
        }
        .buttonStyle(ChannelToggleRowStyle())
        .accessibilityIdentifier("channel.show.\(series.displayTitle)")
        .accessibilityLabel(series.displayTitle)
        .accessibilityValue(isOn ? L10n.channelsOn : L10n.channelsOff)
        .accessibilityAddTraits(.isToggle)
    }
}

private struct ChannelShowToggleLabel: View {

    @Environment(\.isFocused)
    private var isFocused

    let series: BaseItemDto
    let detail: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Color.white.opacity(0.08)

                if let id = series.id {
                    HomeLibraryArtwork(
                        itemID: id,
                        imageTags: series.imageTags,
                        hasBackdrop: series.backdropImageTags?.isNotEmpty ?? true,
                        maxWidth: 240
                    )
                }
            }
            .frame(width: 192, height: 108)
            .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(series.displayTitle)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if detail.isNotEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            ChannelGlassSwitch(isOn: isOn, isFocused: isFocused)
        }
        .padding(18)
        .padding(.trailing, 10)
        .foregroundStyle(isFocused ? Color.black : Color.white)
    }
}

/// A switch in the Liquid Glass style: a glass track, tinted when on, with a white knob
private struct ChannelGlassSwitch: View {

    let isOn: Bool
    let isFocused: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isFocused && !isOn ? Color.black.opacity(0.12) : Color.clear)
                .glassEffect(isOn ? .regular.tint(.green) : .regular, in: .capsule)
                .frame(width: 92, height: 52)

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .frame(width: 44, height: 44)
                .padding(4)
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: isOn)
        .accessibilityHidden(true)
    }
}

private struct ChannelToggleRowStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        ChannelToggleRowBody(configuration: configuration)
    }
}

private struct ChannelToggleRowBody: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .background {
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: 28))
                        .opacity(isFocused ? 0 : 1)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white)
                        .opacity(isFocused ? 1 : 0)
                }
            }
            .contentShape(.rect(cornerRadius: 28))
            .scaleEffect(configuration.isPressed ? 1.01 : (isFocused ? 1.04 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
