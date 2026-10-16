//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// "Coming This Week": new episodes of followed shows over the next 7 days, from Sonarr's calendar
/// through glassfin-helper. Hidden when nothing is coming or the helper isn't configured or reachable.
struct ComingThisWeekContentGroup: ContentGroup {

    let id = "home-coming-this-week"
    let viewModel = ComingThisWeekViewModel()

    var _shouldBeResolved: Bool {
        viewModel.entries.isNotEmpty
    }

    func body(with viewModel: ComingThisWeekViewModel) -> some View {
        ComingThisWeekSection(viewModel: viewModel)
    }
}

final class ComingThisWeekViewModel: ViewModel, WithRefresh {

    /// One show on one day; several episodes dropping together share a card ("S5, E1–E2").
    struct Entry: Identifiable, Hashable {
        let seriesName: String
        let tmdbID: Int?
        let tvdbID: Int?
        let season: Int?
        let episodes: [Int]
        let episodeTitle: String?
        let airDate: Date
        let hasFile: Bool
        let network: String?
        var libraryItem: BaseItemDto?

        var id: String {
            "\(tmdbID.map(String.init) ?? seriesName)-\(Calendar.current.startOfDay(for: airDate).timeIntervalSince1970)"
        }

        var episodeLabel: String? {
            HomeRowFormat.episodeLabel(season: season, episodes: episodes)
        }
    }

    struct Background: WithRefresh {

        let viewModel: ComingThisWeekViewModel

        func refresh() {
            viewModel.reload()
        }

        func refresh() async {
            viewModel.reload()
        }
    }

    @Published
    private(set) var entries: [Entry] = []

    var background: Background {
        get { Background(viewModel: self) }
        set {}
    }

    private var loadTask: Task<Void, Never>?

    func refresh() {
        reload()
    }

    /// Starts loading and waits briefly, so a fast helper makes Home's first paint.
    func refresh() async {
        reload()
        if let loadTask {
            await homeAwait(upTo: 1.5, loadTask)
        }
    }

    func reload() {
        guard loadTask == nil else { return }

        loadTask = Task { [weak self] in
            await self?.load()
            self?.loadTask = nil
        }
    }

    private func load() async {
        guard GlassfinHelperClient.isConfigured else {
            entries = []
            return
        }

        do {
            let episodes = try await GlassfinHelperClient.shared.calendar(days: 7)
            let library = try? await HomeLibraryIndex.shared.load()
            entries = Self.entries(from: episodes, library: library)
        } catch {
            // Not reachable, or Sonarr isn't (the SSD unmounted): the row just isn't there
            logger.debug("Coming This Week hidden: \(error.localizedDescription)")
            entries = []
        }
    }

    static func entries(
        from episodes: [HelperCalendarEpisode],
        library: HomeLibraryIndex.Snapshot?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Entry] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }

        var order: [String] = []
        var grouped: [String: Entry] = [:]

        for episode in episodes {
            guard let name = episode.series, let date = episode.airDate, date >= start, date < end else { continue }

            let day = calendar.startOfDay(for: date)
            let key = "\(episode.seriesTmdbId.map(String.init) ?? name)|\(episode.season ?? -1)|\(day.timeIntervalSince1970)"

            if var existing = grouped[key] {
                if let number = episode.episode {
                    existing = Entry(
                        seriesName: existing.seriesName,
                        tmdbID: existing.tmdbID,
                        tvdbID: existing.tvdbID,
                        season: existing.season,
                        episodes: existing.episodes + [number],
                        episodeTitle: existing.episodeTitle,
                        airDate: min(existing.airDate, date),
                        hasFile: existing.hasFile && (episode.hasFile ?? false),
                        network: existing.network,
                        libraryItem: existing.libraryItem
                    )
                    grouped[key] = existing
                }
                continue
            }

            let item = library?.item(kind: .tv, tmdbID: episode.seriesTmdbId)
                ?? episode.seriesTvdbId.flatMap { library?.seriesByTVDB[$0] }

            order.append(key)
            grouped[key] = Entry(
                seriesName: name,
                tmdbID: episode.seriesTmdbId,
                tvdbID: episode.seriesTvdbId,
                season: episode.season,
                episodes: episode.episode.map { [$0] } ?? [],
                episodeTitle: episode.title,
                airDate: date,
                hasFile: episode.hasFile ?? false,
                network: episode.network,
                libraryItem: item
            )
        }

        return order.compactMap { grouped[$0] }
            .sorted { $0.airDate < $1.airDate }
    }
}

// MARK: - Section

struct ComingThisWeekSection: View {

    @ObservedObject
    var viewModel: ComingThisWeekViewModel

    @Router
    private var router

    private func subtitle(for entry: ComingThisWeekViewModel.Entry) -> String {
        [entry.episodeLabel, HomeRowFormat.relativeDay(entry.airDate)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private func open(_ entry: ComingThisWeekViewModel.Entry) {
        if let item = entry.libraryItem {
            router.route(to: .item(item: item))
        } else if let tmdbID = entry.tmdbID {
            // Followed in Sonarr but not in the library yet: its Discover page
            let title = DiscoverTitle(
                kind: .tv,
                tmdbID: tmdbID,
                title: entry.seriesName,
                overview: nil,
                backdropPath: nil,
                posterPath: nil,
                date: nil,
                genreIDs: [],
                popularity: 0,
                voteAverage: 0,
                voteCount: 0
            )
            router.route(to: .discoverTitle(item: DiscoverItem(title: title, providers: []), feed: .shared))
        }
    }

    var body: some View {
        HomeShelf(L10n.comingThisWeek) {
            ForEach(viewModel.entries) { entry in
                HomeRowCard(
                    title: entry.seriesName,
                    subtitle: subtitle(for: entry),
                    badge: entry.hasFile ? L10n.homeReadyBadge : nil,
                    badgeSystemImage: entry.hasFile ? "checkmark" : nil,
                    accessibilityLabel: [entry.seriesName, entry.episodeLabel, entry.episodeTitle, HomeRowFormat.relativeDay(entry.airDate)]
                        .compactMap(\.self)
                        .joined(separator: ", ")
                ) {
                    open(entry)
                } artwork: {
                    if let item = entry.libraryItem, let id = item.id {
                        HomeLibraryArtwork(
                            itemID: id,
                            imageTags: item.imageTags,
                            hasBackdrop: item.backdropImageTags?.isNotEmpty ?? true
                        )
                    } else if let tmdbID = entry.tmdbID {
                        HomeTMDBArtwork(kind: .tv, tmdbID: tmdbID, fallbackName: entry.seriesName)
                    } else {
                        Text(entry.seriesName)
                            .font(.headline)
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            }
        }
    }
}
