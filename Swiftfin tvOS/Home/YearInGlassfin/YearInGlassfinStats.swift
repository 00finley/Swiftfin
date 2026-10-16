//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

/// One viewing of a movie or episode.
struct YearPlay: Hashable {

    let itemID: String
    let isEpisode: Bool
    let name: String
    let seriesID: String?
    let seriesName: String?
    let season: Int?
    let episode: Int?
    /// When it was played (Playback Reporting: when it started; otherwise Jellyfin's last played date)
    let date: Date
    /// Seconds watched (exact with Playback Reporting, otherwise estimated from the runtime)
    let seconds: Double
    /// How many times it was played (Jellyfin's lifetime play count without Playback Reporting)
    var plays: Int = 1
    let genres: [String]

    /// The show for an episode, the movie itself otherwise
    var titleID: String {
        seriesID ?? itemID
    }

    var titleName: String {
        seriesName ?? name
    }
}

/// Everything Your Year in Glassfin shows, computed on device from the year's plays.
struct YearStats: Equatable {

    struct TitleStat: Equatable, Identifiable {
        let id: String
        let name: String
        let isSeries: Bool
        let seconds: Double
        let episodes: Int
    }

    struct EpisodeStat: Equatable {
        let itemID: String
        let seriesID: String?
        let seriesName: String?
        let name: String
        let label: String?
        let plays: Int
        let seconds: Double
    }

    struct GenreShare: Equatable, Identifiable {
        let name: String
        let share: Double

        var id: String {
            name
        }
    }

    struct Binge: Equatable {
        let titleID: String
        let name: String
        let episodes: Int
        let seconds: Double
        let date: Date
    }

    struct Favorite: Equatable, Identifiable {
        let id: String
        let name: String
        let level: DiscoverRatingLevel
        /// Library item, for art
        let itemID: String?
        let tmdbBackdropPath: String?
    }

    struct Persona: Equatable {
        let title: String
        let line: String
    }

    var year: Int
    /// No Playback Reporting: minutes are estimated from runtimes and play counts
    var isEstimated: Bool
    var totalSeconds: Double = 0
    var episodeCount = 0
    var movieCount = 0
    var showCount = 0
    var topTitles: [TitleStat] = []
    var mostWatchedEpisode: EpisodeStat?
    var genres: [GenreShare] = []
    /// Seconds by month, 1...12
    var months: [Int: Double] = [:]
    /// Seconds by weekday, 1 (Sunday)...7
    var weekdays: [Int: Double] = [:]
    /// Seconds by hour, 0...23
    var hours: [Int: Double] = [:]
    var longestBinge: Binge?
    var favorites: [Favorite] = []
    var persona = Persona(title: "", line: "")

    var hasData: Bool {
        totalSeconds > 0
    }

    var totalHours: Int {
        Int((totalSeconds / 3600).rounded())
    }

    var busiestMonth: Int? {
        months.filter { $0.value > 0 }.max { $0.value < $1.value }?.key
    }

    var busiestWeekday: Int? {
        weekdays.filter { $0.value > 0 }.max { $0.value < $1.value }?.key
    }

    var topShows: [TitleStat] {
        topTitles.filter(\.isSeries)
    }

    // MARK: - Building

    /// - Parameters:
    ///   - plays: the year's plays
    ///   - favorites: rated titles, Love It first
    static func build(
        year: Int,
        plays: [YearPlay],
        isEstimated: Bool,
        favorites: [Favorite],
        calendar: Calendar = .current
    ) -> YearStats {
        var stats = YearStats(year: year, isEstimated: isEstimated)
        let plays = plays.filter { $0.seconds > 0 }.sorted { $0.date < $1.date }
        guard plays.isNotEmpty else {
            stats.favorites = favorites
            stats.persona = persona(for: stats)
            return stats
        }

        stats.totalSeconds = plays.map(\.seconds).reduce(0, +)
        stats.episodeCount = Set(plays.filter(\.isEpisode).map(\.itemID)).count
        stats.movieCount = Set(plays.filter { !$0.isEpisode }.map(\.itemID)).count
        stats.showCount = Set(plays.compactMap(\.seriesID)).count

        // Top titles by time
        var titleSeconds: [String: Double] = [:]
        var titleEpisodes: [String: Set<String>] = [:]
        var titleNames: [String: (String, Bool)] = [:]
        for play in plays {
            titleSeconds[play.titleID, default: 0] += play.seconds
            if play.isEpisode {
                titleEpisodes[play.titleID, default: []].insert(play.itemID)
            }
            titleNames[play.titleID] = (play.titleName, play.isEpisode)
        }
        stats.topTitles = titleSeconds
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(10)
            .map { id, seconds in
                TitleStat(
                    id: id,
                    name: titleNames[id]?.0 ?? "",
                    isSeries: titleNames[id]?.1 ?? false,
                    seconds: seconds,
                    episodes: titleEpisodes[id]?.count ?? 0
                )
            }

        // Most-watched episode: most plays, then most time
        var episodePlays: [String: (count: Int, seconds: Double, play: YearPlay)] = [:]
        for play in plays where play.isEpisode {
            let current = episodePlays[play.itemID]
            // Without Playback Reporting each item appears once, carrying its play count
            let count = isEstimated ? play.plays : (current?.count ?? 0) + 1
            episodePlays[play.itemID] = (count, (current?.seconds ?? 0) + play.seconds, play)
        }
        if let best = episodePlays.values.max(by: { lhs, rhs in
            lhs.count == rhs.count ? lhs.seconds < rhs.seconds : lhs.count < rhs.count
        }) {
            stats.mostWatchedEpisode = EpisodeStat(
                itemID: best.play.itemID,
                seriesID: best.play.seriesID,
                seriesName: best.play.seriesName,
                name: best.play.name,
                label: HomeRowFormat.episodeLabel(season: best.play.season, episodes: best.play.episode.map { [$0] } ?? []),
                plays: max(1, best.count),
                seconds: best.seconds
            )
        }

        // Genres: each play's time split over its genres
        var genreSeconds: [String: Double] = [:]
        var genreTotal = 0.0
        for play in plays where play.genres.isNotEmpty {
            let share = play.seconds / Double(play.genres.count)
            for genre in play.genres {
                genreSeconds[genre, default: 0] += share
            }
            genreTotal += play.seconds
        }
        if genreTotal > 0 {
            stats.genres = genreSeconds
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { GenreShare(name: $0.key, share: $0.value / genreTotal) }
        }

        // When
        for play in plays {
            let parts = calendar.dateComponents([.month, .weekday, .hour], from: play.date)
            if let month = parts.month {
                stats.months[month, default: 0] += play.seconds
            }
            if let weekday = parts.weekday {
                stats.weekdays[weekday, default: 0] += play.seconds
            }
            if let hour = parts.hour {
                stats.hours[hour, default: 0] += play.seconds
            }
        }

        stats.longestBinge = longestBinge(in: plays, exact: !isEstimated)
        stats.favorites = favorites
        stats.persona = persona(for: stats)
        return stats
    }

    /// The most episodes of one show watched back to back: each next episode starts within
    /// 40 minutes of the previous one ending (or, from last-played dates alone, within its own
    /// runtime plus 40 minutes of the previous one).
    static func longestBinge(in plays: [YearPlay], exact: Bool) -> Binge? {
        let gap: TimeInterval = 40 * 60
        var best: Binge?

        let bySeries = Dictionary(grouping: plays.filter { $0.isEpisode && $0.seriesID != nil }, by: { $0.seriesID! })
        for (seriesID, episodes) in bySeries {
            let sorted = episodes.sorted { $0.date < $1.date }
            var run: [YearPlay] = []

            func close() {
                let distinct = Set(run.map(\.itemID)).count
                guard distinct >= 2 else { return }

                let seconds = run.map(\.seconds).reduce(0, +)
                if best == nil || distinct > best!.episodes || (distinct == best!.episodes && seconds > best!.seconds) {
                    best = Binge(titleID: seriesID, name: run[0].titleName, episodes: distinct, seconds: seconds, date: run[0].date)
                }
            }

            for play in sorted {
                if let last = run.last {
                    let allowed = exact
                        ? last.date.addingTimeInterval(last.seconds + gap)
                        : last.date.addingTimeInterval(play.seconds + gap)
                    if play.date > allowed {
                        close()
                        run = []
                    }
                }
                run.append(play)
            }
            close()
        }
        return best
    }

    // MARK: - Persona

    /// A deterministic "persona" from the stats: a habit adjective plus a noun for the top genre,
    /// with a line explaining both.
    static func persona(for stats: YearStats) -> Persona {
        guard stats.hasData else {
            return Persona(title: L10n.yearPersonaNewcomerTitle, line: L10n.yearPersonaNewcomerLine)
        }

        let total = max(1, stats.totalSeconds)
        let night = [22, 23, 0, 1, 2, 3].map { stats.hours[$0] ?? 0 }.reduce(0, +) / total
        let weekend = ((stats.weekdays[1] ?? 0) + (stats.weekdays[7] ?? 0)) / total
        let binge = stats.longestBinge?.episodes ?? 0
        let movies = Double(stats.movieCount) / Double(max(1, stats.movieCount + stats.episodeCount))

        let habit: (String, String) = if binge >= 6 {
            (L10n.yearPersonaBinge, L10n.yearPersonaBingeLine(binge))
        } else if night >= 0.4 {
            (L10n.yearPersonaNightOwl, L10n.yearPersonaNightOwlLine)
        } else if weekend >= 0.55 {
            (L10n.yearPersonaWeekend, L10n.yearPersonaWeekendLine)
        } else if movies >= 0.5 {
            (L10n.yearPersonaCinephile, L10n.yearPersonaCinephileLine)
        } else if stats.showCount >= 12 {
            (L10n.yearPersonaExplorer, L10n.yearPersonaExplorerLine(stats.showCount))
        } else {
            (L10n.yearPersonaDevoted, L10n.yearPersonaDevotedLine)
        }

        let genre = stats.genres.first?.name.lowercased() ?? ""
        let noun: String
        let genreLine: String
        switch genre {
        case let g where g.contains("comedy"):
            (noun, genreLine) = (L10n.yearPersonaComedy, L10n.yearPersonaComedyLine)
        case let g where g.contains("animation") || g.contains("kids") || g.contains("family"):
            (noun, genreLine) = (L10n.yearPersonaAnimation, L10n.yearPersonaAnimationLine)
        case let g where g.contains("reality") || g.contains("game show") || g.contains("talk"):
            (noun, genreLine) = (L10n.yearPersonaReality, L10n.yearPersonaRealityLine)
        case let g where g.contains("documentary") || g.contains("history") || g.contains("news"):
            (noun, genreLine) = (L10n.yearPersonaDocumentary, L10n.yearPersonaDocumentaryLine)
        case let g where g.contains("crime") || g.contains("mystery") || g.contains("thriller"):
            (noun, genreLine) = (L10n.yearPersonaMystery, L10n.yearPersonaMysteryLine)
        case let g where g.contains("sci") || g.contains("fantasy"):
            (noun, genreLine) = (L10n.yearPersonaSciFi, L10n.yearPersonaSciFiLine)
        case let g where g.contains("politics") || g.contains("war"):
            (noun, genreLine) = (L10n.yearPersonaPolitics, L10n.yearPersonaPoliticsLine)
        case let g where g.contains("action") || g.contains("adventure"):
            (noun, genreLine) = (L10n.yearPersonaAction, L10n.yearPersonaActionLine)
        case let g where g.contains("horror"):
            (noun, genreLine) = (L10n.yearPersonaHorror, L10n.yearPersonaHorrorLine)
        case let g where g.contains("romance"):
            (noun, genreLine) = (L10n.yearPersonaRomance, L10n.yearPersonaRomanceLine)
        case let g where g.contains("drama"):
            (noun, genreLine) = (L10n.yearPersonaDrama, L10n.yearPersonaDramaLine)
        default:
            (noun, genreLine) = (L10n.yearPersonaStories, L10n.yearPersonaStoriesLine)
        }

        return Persona(title: L10n.yearPersonaTitle(habit.0, noun), line: "\(habit.1) \(genreLine)")
    }
}

// MARK: - Favorites

extension YearStats {

    /// Love It titles first, then Like It (in-app ratings made by the end of the year, and the seed
    /// list), up to 6. Names come from the library, the rating's snapshot, or TMDB.
    @MainActor
    static func favorites(year: Int, library: HomeLibraryIndex.Snapshot, calendar: Calendar = .current) async -> [Favorite] {
        let profile = Defaults[.Discover.profile]
        let rated = profile.ratedTitles()

        let ranked = rated.values
            .filter { title in
                guard title.level == .loved || title.level == .liked else { return false }

                // Seeds have no date; in-app ratings count from the year they were made
                guard let date = profile.ratings[title.key]?.date else { return true }

                return calendar.component(.year, from: date) <= year
            }
            .sorted { lhs, rhs in
                lhs.level.rawValue == rhs.level.rawValue ? lhs.key < rhs.key : lhs.level.rawValue > rhs.level.rawValue
            }
            .prefix(6)

        var favorites: [Favorite] = []
        for title in ranked {
            let item = title.kind.flatMap { library.item(kind: $0, tmdbID: title.tmdbID) }
            var snapshot = title.title
            if item == nil, snapshot == nil, TMDBClient.isAvailable, let kind = title.kind, let id = title.tmdbID {
                snapshot = try? await TMDBClient.shared.details(kind: kind, id: id).title
            }
            guard let name = item?.displayTitle ?? snapshot?.title else { continue }

            favorites.append(Favorite(
                id: title.key,
                name: name,
                level: title.level,
                itemID: item?.id,
                tmdbBackdropPath: snapshot?.backdropPath
            ))
        }
        return favorites
    }
}
