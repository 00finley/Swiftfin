//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Settings → Discover → Your Ratings: rated titles grouped by level (including the build's seed
/// list), each one changeable or clearable.
struct DiscoverRatingsView: View {

    @Default(.Discover.profile)
    private var profile

    @State
    private var names: [String: DiscoverTitle] = [:]

    private let feed = DiscoverViewModel.shared

    private var rated: [DiscoverRatedTitle] {
        Array(profile.ratedTitles().values)
    }

    private func title(for entry: DiscoverRatedTitle) -> DiscoverTitle? {
        entry.title ?? names[entry.key]
    }

    private func sortName(_ entry: DiscoverRatedTitle) -> String {
        title(for: entry)?.title ?? entry.key
    }

    var body: some View {
        Form(systemImage: "heart.text.square") {
            if rated.isEmpty {
                Section {
                    Text(L10n.discoverNoRatings)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(DiscoverRatingLevel.displayOrder, id: \.self) { level in
                let entries = rated
                    .filter { $0.level == level }
                    .sorted { sortName($0).localizedCaseInsensitiveCompare(sortName($1)) == .orderedAscending }

                if entries.isNotEmpty {
                    Section(level.title) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
            }

            Section {} footer: {
                Text(L10n.discoverYourRatingsDescription)
            }
        }
        .navigationTitle(L10n.discoverYourRatings)
        .task(id: rated.map(\.key)) {
            let missing = rated.filter { $0.title == nil && names[$0.key] == nil }.map(\.key)
            guard missing.isNotEmpty else { return }

            let infos = await DiscoverTitleInfoStore.shared.infos(for: missing)
            for (key, info) in infos {
                names[key] = info.title
            }
        }
    }

    private func row(_ entry: DiscoverRatedTitle) -> some View {
        let title = title(for: entry)
        let kind = (title?.kind ?? entry.kind) == .tv ? L10n.tvShow : L10n.movie
        let detail = [kind, title?.year, entry.isSeed ? L10n.discoverFromSeedList : nil]
            .compactMap(\.self)
            .joined(separator: " · ")

        return Menu {
            ForEach(DiscoverRatingLevel.displayOrder, id: \.self) { level in
                Button(level.title, systemImage: level == entry.level ? "checkmark" : level.systemImage) {
                    feed.rate(key: entry.key, level, title: title)
                }
            }
            if entry.level != .neutral || !entry.isSeed {
                Divider()
                Button(L10n.discoverClearRating, systemImage: "xmark", role: .destructive) {
                    feed.rate(key: entry.key, .neutral, title: title)
                }
            }
        } label: {
            HStack(spacing: 24) {
                Image(systemName: entry.level.selectedSystemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title?.title ?? "\u{2026}")
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel(title?.title ?? entry.key)
        .accessibilityValue(entry.level.title)
    }
}
