//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

/// Settings > Video Player > Playback > Show Exceptions: every series whose intro or credits
/// rule differs from the Skip Segments settings, including Glassfin's suggested exceptions for
/// shows in the library. Each one can be changed or reset from its menu.
struct ShowExceptionsView: View {

    struct Entry: Identifiable, Hashable {

        let id: String
        let name: String
        let providerIDs: [String: String]?
        let rule: ResolvedShowSkipRule

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.id == rhs.id && lhs.rule == rhs.rule && lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    @Default(.VideoPlayer.MediaSegments.showRules)
    private var rules
    @Default(.VideoPlayer.MediaSegments.intro)
    private var introBehavior
    @Default(.VideoPlayer.MediaSegments.outro)
    private var outroBehavior

    /// Library series matching a suggested exception
    @State
    private var seededSeries: [BaseItemDto] = []
    @State
    private var isLoading = true

    private var entries: [Entry] {
        _ = (introBehavior, outroBehavior)

        var entries: [Entry] = rules.compactMap { seriesID, rule in
            let providerIDs = seededSeries.first { $0.id == seriesID }?.providerIDs
            let resolved = ShowSkipRules.resolve(seriesID: seriesID, providerIDs: providerIDs)
            guard resolved.isException else { return nil }

            return Entry(id: seriesID, name: rule.seriesName, providerIDs: providerIDs, rule: resolved)
        }

        for series in seededSeries {
            guard let seriesID = series.id, rules[seriesID] == nil else { continue }

            let resolved = ShowSkipRules.resolve(seriesID: seriesID, providerIDs: series.providerIDs)
            guard resolved.isException else { continue }

            entries.append(Entry(id: seriesID, name: series.displayTitle, providerIDs: series.providerIDs, rule: resolved))
        }

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form(systemImage: "forward.end.alt") {
            Section {
                if entries.isEmpty {
                    Text(isLoading ? L10n.loading : L10n.showExceptionsEmpty)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            } header: {
                Text(L10n.showExceptions)
            } footer: {
                Text(L10n.showExceptionsDescription)
            }
        }
        .navigationTitle(L10n.showExceptions)
        .task {
            await loadSeededSeries()
        }
    }

    private func detail(for rule: ResolvedShowSkipRule) -> String {
        [
            "\(L10n.intro): \(rule.intro.displayTitle)",
            "\(L10n.credits): \(rule.credits.displayTitle)",
            rule.source == .seeded ? L10n.suggested : nil,
        ]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private func row(_ entry: Entry) -> some View {
        Menu {
            Section(L10n.intro) {
                choiceButtons(entry, type: .intro, selection: entry.rule.intro)
            }

            Section(L10n.credits) {
                choiceButtons(entry, type: .outro, selection: entry.rule.credits)
            }

            Divider()

            Button(L10n.resetToDefault, systemImage: "arrow.uturn.backward", role: .destructive) {
                ShowSkipRules.reset(seriesID: entry.id, providerIDs: entry.providerIDs)
            }
        } label: {
            HStack(spacing: 24) {
                Image(systemName: entry.rule.source == .seeded ? "sparkles" : "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name.isEmpty ? L10n.unknown : entry.name)
                        .lineLimit(1)

                    Text(detail(for: entry.rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel(entry.name)
        .accessibilityValue(detail(for: entry.rule))
    }

    @ViewBuilder
    private func choiceButtons(_ entry: Entry, type: MediaSegmentType, selection: ShowSkipChoice) -> some View {
        ForEach(ShowSkipChoice.allCases, id: \.self) { choice in
            Button(choice.displayTitle, systemImage: choice == selection ? "checkmark" : choice.systemImage) {
                ShowSkipRules.set(choice, for: type, seriesID: entry.id, seriesName: entry.name, providerIDs: entry.providerIDs)
            }
        }
    }

    /// Finds library series that match a suggested exception, by provider id, so the list works on
    /// any server.
    private func loadSeededSeries() async {
        defer { isLoading = false }

        guard let session = Container.shared.currentUserSession() else { return }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.includeItemTypes = [.series]
        parameters.isRecursive = true
        parameters.fields = [.providerIDs]
        parameters.enableImages = false
        parameters.enableUserData = false

        do {
            let response = try await session.client.send(Paths.getItems(parameters: parameters))
            seededSeries = (response.value.items ?? []).filter { ShowSkipRules.seed(for: $0.providerIDs) != nil }
        } catch {
            seededSeries = []
        }
    }
}
#endif
