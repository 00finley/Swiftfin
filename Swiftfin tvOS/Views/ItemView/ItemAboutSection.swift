//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// The Apple TV app's About section: glass summary and rating cards, then the Information,
/// Languages and Playback columns. A column gets a glass panel while it has focus.
///
/// Playback (series and their episodes) holds the show's intro / credits rule.
struct ItemAboutSection: View {

    @Router
    private var router

    let item: BaseItemDto
    /// The item's media, or the series' next-up episode's
    let mediaSource: MediaSourceInfo?

    @FocusState
    private var focusedSkipControl: ShowSkipControls.Control?

    @State
    private var seriesProviderIDs: [String: String]?

    private static let columnWidth: CGFloat = 560
    private static let cardHeight: CGFloat = 300

    private var seriesID: String? {
        item.type == .series ? item.id : item.seriesID
    }

    private var seriesName: String {
        (item.type == .series ? item.name : item.seriesName) ?? item.displayTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(L10n.about)
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 40) {
                summaryCard

                if hasRatings {
                    ratingCard
                }
            }
            .focusSection()

            HStack(alignment: .top, spacing: 40) {
                informationColumn

                if languageRows.isNotEmpty {
                    languagesColumn
                }

                if let seriesID {
                    playbackColumn(seriesID: seriesID)
                }
            }
            .padding(.top, 30)
            .focusSection()
        }
        .edgePadding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: seriesID) {
            guard seriesID != nil else { return }

            _ = await ShowSkipRules.resolve(for: item)
            seriesProviderIDs = seriesID.flatMap(ShowSkipRules.cachedProviderIDs(seriesID:))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.about)
    }

    // MARK: - Cards

    private var summaryCard: some View {
        Button {
            router.route(to: .itemOverview(item: item))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.displayTitle)
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let genres = item.genres?.prefix(3), genres.isNotEmpty {
                    Text(genres.joined(separator: ", "))
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                if let overview = item.overview, overview.isNotEmpty {
                    (Text(overview) + Text("  ") + Text(L10n.more.uppercased()).foregroundStyle(.white.opacity(0.6)))
                        .font(.system(size: 25, weight: .medium))
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(AboutGlassCardButtonStyle())
        .frame(width: Self.columnWidth, height: Self.cardHeight)
        .accessibilityIdentifier("about.summary")
    }

    private var hasRatings: Bool {
        item.officialRating?.isNotEmpty == true || (item.communityRating ?? 0) > 0 || (item.criticRating ?? 0) > 0
    }

    private var ratingCard: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 14) {
                if let rating = item.officialRating, rating.isNotEmpty {
                    Text(rating)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer(minLength: 0)

                if let community = item.communityRating, community > 0 {
                    ratingLine(
                        icon: Image(systemName: "star.fill"),
                        value: String(format: "%.1f", community),
                        label: L10n.communityRating
                    )
                }

                if let critic = item.criticRating, critic > 0 {
                    ratingLine(
                        icon: Image(critic >= 60 ? .tomatoFresh : .tomatoRotten),
                        value: String(format: "%.0f%%", critic),
                        label: L10n.critics
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(AboutGlassCardButtonStyle())
        .frame(width: 300, height: Self.cardHeight)
    }

    private func ratingLine(icon: Image, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                icon
                    .symbolRenderingMode(.monochrome)
                Text(value)
            }
            .font(.system(size: 29, weight: .semibold))
            .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Columns

    private var informationRows: [(String, String)] {
        var rows: [(String, String)] = []

        if item.type == .series, let year = item.premiereDateYear {
            let end = item.status == "Ended" ? item.endDate.map { $0.formatted(.dateTime.year()) } : nil
            rows.append((L10n.released, end.map { "\(year)–\($0)" } ?? year))
        } else if let date = item.premiereDate {
            rows.append((L10n.released, date.formatted(date: .long, time: .omitted)))
        }

        if let rating = item.officialRating, rating.isNotEmpty {
            rows.append((L10n.rated, rating))
        }

        if let studio = item.studios?.compactMap(\.name).first {
            rows.append((item.type == .series || item.type == .episode ? L10n.network : L10n.studio, studio))
        }

        if let region = item.productionLocations?.first(where: \.isNotEmpty) {
            rows.append((L10n.regionOfOrigin, region))
        } else if item.type != .series, let runtime = item.runtime {
            rows.append((L10n.runtime, runtime.formatted(.hourMinuteAbbreviated)))
        }

        return Array(rows.prefix(4))
    }

    private var informationColumn: some View {
        Button {
            router.route(to: .itemOverview(item: item))
        } label: {
            AboutColumn(title: L10n.information) {
                ForEach(informationRows, id: \.0) { row in
                    AboutColumnRow(label: row.0, value: row.1)
                }
            }
        }
        .buttonStyle(AboutColumnButtonStyle())
        .frame(width: Self.columnWidth)
        .accessibilityIdentifier("about.information")
    }

    private var languageRows: [(String, String)] {
        guard let streams = mediaSource?.mediaStreams else { return [] }

        let audio = streams.filter { $0.type == .audio }
        let subtitles = streams.filter { $0.type == .subtitle }
        var rows: [(String, String)] = []

        // Jellyfin doesn't know a title's original language; the first audio track usually is
        if let original = audio.min(by: { ($0.index ?? 0) < ($1.index ?? 0) })?.languageName {
            rows.append((L10n.originalAudio, original))
        }

        let audioDescriptions = Array(audio.map(\.languageDescription).uniqued())
        if audioDescriptions.isNotEmpty {
            rows.append((L10n.audio, audioDescriptions.joined(separator: ", ")))
        }

        let subtitleDescriptions = Array(subtitles.map(\.subtitleDescription).uniqued())
        if subtitleDescriptions.isNotEmpty {
            rows.append((L10n.subtitles, subtitleDescriptions.joined(separator: ", ")))
        }

        return rows
    }

    private var languagesColumn: some View {
        Button {
            if let mediaSource {
                router.route(to: .mediaSourceInfo(source: mediaSource))
            }
        } label: {
            AboutColumn(title: L10n.languages) {
                ForEach(languageRows, id: \.0) { row in
                    AboutColumnRow(label: row.0, value: row.1, lineLimit: 4)
                }
            }
        }
        .buttonStyle(AboutColumnButtonStyle())
        .frame(width: Self.columnWidth)
        .accessibilityIdentifier("about.languages")
    }

    private func playbackColumn(seriesID: String) -> some View {
        let providerIDs = item.type == .series ? item.providerIDs : seriesProviderIDs
        let rule = ShowSkipRules.resolve(seriesID: seriesID, providerIDs: providerIDs)

        return AboutColumn(title: L10n.playback) {
            ShowSkipControls(
                seriesID: seriesID,
                seriesName: seriesName,
                providerIDs: providerIDs,
                focus: $focusedSkipControl
            )
            .padding(.vertical, 6)

            Text(rule.source == .seeded ? L10n.showSkipSuggested : L10n.recapsAlwaysSkipped)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .aboutColumnPanel(isFocused: focusedSkipControl != nil)
        .frame(width: Self.columnWidth)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("about.playback")
    }
}

// MARK: - Components

/// A column like the Apple TV app's Information / Languages / Accessibility columns.
private struct AboutColumn<Content: View>: View {

    let title: String
    @ViewBuilder
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AboutColumnRow: View {

    let label: String
    let value: String
    var lineLimit: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {

    /// The focused column's glass panel, reaching a little past the column's text.
    func aboutColumnPanel(isFocused: Bool) -> some View {
        padding(20)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.clear)
                    .glassEffect(isFocused ? .regular : .identity, in: .rect(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(isFocused ? 0.25 : 0), radius: 18, y: 10)
            }
            .padding(-20)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

/// Bare until focused, then on a glass panel (Information, Languages).
private struct AboutColumnButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        AboutColumnButtonBody(configuration: configuration)
    }
}

private struct AboutColumnButtonBody: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .aboutColumnPanel(isFocused: isFocused)
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.02 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A resting glass card that lifts and brightens when focused (summary, rating).
private struct AboutGlassCardButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        AboutGlassCardBody(configuration: configuration)
    }
}

private struct AboutGlassCardBody: View {

    @Environment(\.isFocused)
    private var isFocused

    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(
                isFocused ? .regular.tint(.white.opacity(0.12)) : .regular,
                in: .rect(cornerRadius: 24, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.05 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Language descriptions

extension MediaStream {

    /// "English", from the stream's ISO 639 code
    var languageName: String? {
        guard let language, language.isNotEmpty, language != "und" else { return nil }

        return Locale.current.localizedString(forLanguageCode: language) ?? language
    }

    /// "English (Dolby Atmos, 5.1)"
    var languageDescription: String {
        let name = languageName ?? L10n.unknown
        var details: [String] = []

        if isDolbyAtmos {
            details.append("Dolby Atmos")
        } else if let codec = codec?.lowercased() {
            switch codec {
            case "eac3": details.append("Dolby Digital+")
            case "ac3": details.append("Dolby Digital")
            case "truehd": details.append("Dolby TrueHD")
            case "dts": details.append("DTS")
            case "aac": details.append("AAC")
            case "flac": details.append("FLAC")
            default: break
            }
        }

        if let layout = channelLayout?.lowercased() {
            if layout.hasPrefix("7.1") {
                details.append("7.1")
            } else if layout.hasPrefix("5.1") {
                details.append("5.1")
            } else if layout == "stereo" {
                details.append(L10n.stereo)
            }
        }

        if isAudioDescription {
            details.append("AD")
        }

        return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
    }

    /// "English (SDH)"
    var subtitleDescription: String {
        let name = languageName ?? L10n.unknown
        var details: [String] = []

        if isHearingImpaired == true {
            details.append("SDH")
        }
        if isForced == true {
            details.append(L10n.forced)
        }

        return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
    }
}
