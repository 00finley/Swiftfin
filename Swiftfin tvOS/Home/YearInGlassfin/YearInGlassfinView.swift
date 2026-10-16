//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// Which year the recap covers: the current one, or last year during January.
enum YearInGlassfin {

    static func year(at date: Date = GlassfinDate.now, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2026
        return parts.month == 1 ? year - 1 : year
    }

    /// The recap is a year-end reveal: it only appears (near the top of Home, and in Settings) from
    /// December 1 through January 15, when January shows last year's recap.
    static func isFeatured(at date: Date = GlassfinDate.now, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == 12 || (parts.month == 1 && (parts.day ?? 1) <= 15)
    }
}

extension NavigationRoute {

    static var yearInGlassfin: NavigationRoute {
        NavigationRoute(id: "yearInGlassfin") {
            YearInGlassfinView()
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

@MainActor
final class YearInGlassfinViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded(YearStats)
        case failed
    }

    @Published
    private(set) var state: State = .loading

    let year: Int

    private static var cache: [String: (date: Date, stats: YearStats)] = [:]

    init(year: Int = YearInGlassfin.year()) {
        self.year = year
    }

    func load() async {
        let key = "\(Container.shared.currentUserSession()?.user.id ?? "")-\(year)"
        if let cached = Self.cache[key], Date.now.timeIntervalSince(cached.date) < 10 * 60 {
            state = .loaded(cached.stats)
            return
        }

        do {
            let stats = try await YearInGlassfinLoader.load(year: year)
            Self.cache[key] = (.now, stats)
            state = .loaded(stats)
        } catch {
            state = .failed
        }
    }
}

// MARK: - Pages

private enum YearPage: Hashable, CaseIterable {
    case intro
    case hours
    case topShows
    case onRepeat
    case genres
    case when
    case binge
    case favorites
    case persona
    case summary

    static func pages(for stats: YearStats) -> [YearPage] {
        guard stats.hasData else { return [.intro, .summary] }

        return allCases.filter { page in
            switch page {
            case .topShows: stats.topTitles.isNotEmpty
            case .onRepeat: stats.mostWatchedEpisode != nil
            case .genres: stats.genres.isNotEmpty
            case .when: stats.busiestMonth != nil
            case .binge: stats.longestBinge != nil
            case .favorites: stats.favorites.isNotEmpty
            default: true
            }
        }
    }
}

/// Spotify Wrapped-style recap: full-screen glass cards over artwork, paged with left and right.
struct YearInGlassfinView: View {

    @StateObject
    private var viewModel = YearInGlassfinViewModel()

    @FocusState
    private var isFocused: Bool

    @Router
    private var router

    @State
    private var index = 0
    @State
    private var forward = true

    var body: some View {
        ZStack {
            Color.black

            switch viewModel.state {
            case .loading:
                ProgressView()

            case .failed:
                VStack(spacing: 30) {
                    Text(L10n.yearInGlassfinFailed)
                        .font(.headline)
                    Button(L10n.retry) {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.homeGlass)
                }

            case let .loaded(stats):
                pager(stats)
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func pager(_ stats: YearStats) -> some View {
        let pages = YearPage.pages(for: stats)
        let page = pages[min(index, pages.count - 1)]

        ZStack(alignment: .bottom) {
            YearPageView(page: page, stats: stats)
                .id(page)
                .transition(.asymmetric(
                    insertion: .offset(x: forward ? 160 : -160).combined(with: .opacity),
                    removal: .offset(x: forward ? -160 : 160).combined(with: .opacity)
                ))

            PageDots(count: pages.count, index: index, isLast: index == pages.count - 1)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .right:
                move(by: 1, count: pages.count)
            case .left:
                move(by: -1, count: pages.count)
            default: ()
            }
        }
        .onPlayPauseCommand {
            move(by: 1, count: pages.count)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            move(by: direction == .increment ? 1 : -1, count: pages.count)
        }
    }

    private func move(by step: Int, count: Int) {
        let next = index + step
        guard next >= 0, next < count else { return }

        forward = step > 0
        withAnimation(.spring(duration: 0.55, bounce: 0.12)) {
            index = next
        }
    }
}

private struct PageDots: View {

    let count: Int
    let index: Int
    let isLast: Bool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< count, id: \.self) { dot in
                Capsule()
                    .fill(Color.white.opacity(dot == index ? 1 : 0.35))
                    .frame(width: dot == index ? 34 : 12, height: 12)
            }

            Text(isLast ? L10n.yearInGlassfinMenuToClose : L10n.yearInGlassfinSwipeHint)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 10)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeOut(duration: 0.25), value: index)
        .accessibilityHidden(true)
    }
}

// MARK: - Page content

private struct YearPageView: View {

    let page: YearPage
    let stats: YearStats

    private var topTitle: YearStats.TitleStat? {
        stats.topTitles.first
    }

    var body: some View {
        ZStack {
            background

            content
                .padding(.horizontal, 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Backgrounds

    @ViewBuilder
    private var background: some View {
        switch page {
        case .intro, .summary, .hours:
            ArtBackground(itemID: topTitle?.id, palette: .dusk)
        case .topShows:
            ArtBackground(itemID: topTitle?.id, palette: .ocean, blur: 0)
        case .onRepeat:
            ArtBackground(itemID: stats.mostWatchedEpisode?.seriesID ?? stats.mostWatchedEpisode?.itemID, palette: .ember, blur: 0)
        case .binge:
            ArtBackground(itemID: stats.longestBinge?.titleID, palette: .ember, blur: 0)
        case .favorites:
            ArtBackground(itemID: stats.favorites.first?.itemID, tmdbPath: stats.favorites.first?.tmdbBackdropPath, palette: .rose)
        case .genres:
            YearGradient(palette: .lagoon)
        case .when:
            YearGradient(palette: .ocean)
        case .persona:
            YearGradient(palette: .aurora)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch page {
        case .intro:
            VStack(spacing: 18) {
                Kicker(L10n.yearInGlassfin)
                Text(verbatim: String(stats.year))
                    .font(.system(size: 260, weight: .heavy, design: .rounded))
                    .kerning(-6)
                    .minimumScaleFactor(0.5)
                Text(stats.hasData ? L10n.yearInGlassfinIntro : L10n.yearInGlassfinEmpty)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
            }
            .shadow(color: .black.opacity(0.35), radius: 20)

        case .hours:
            GlassPanel {
                Kicker(L10n.yearInGlassfinYouWatched)
                BigNumber(YearCount.hours(stats.totalHours))
                Text(hoursDetail)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                if stats.isEstimated {
                    Text(L10n.yearInGlassfinEstimated)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 10)
                }
            }

        case .topShows:
            GlassPanel(width: 1300) {
                Kicker(L10n.yearInGlassfinTopShows)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(stats.topTitles.prefix(5).enumerated()), id: \.element.id) { rank, title in
                        TopTitleRow(rank: rank + 1, title: title)
                    }
                }
                .padding(.top, 12)
            }

        case .onRepeat:
            if let episode = stats.mostWatchedEpisode {
                GlassPanel {
                    Kicker(L10n.yearInGlassfinOnRepeat)
                    Text(episode.seriesName ?? episode.name)
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    Text([episode.label, episode.seriesName == nil ? nil : episode.name].compactMap(\.self).joined(separator: " · "))
                        .font(.headline)
                    Text(episode.plays > 1 ? L10n.yearInGlassfinPlayedTimes(episode.plays) : L10n.yearInGlassfinPlayedMost)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 8)
                }
            }

        case .genres:
            GlassPanel(width: 1300) {
                Kicker(L10n.yearInGlassfinGenres)
                Text(genreHeadline)
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                GenreBar(genres: Array(stats.genres.prefix(4)))
                    .padding(.top, 20)
            }

        case .when:
            GlassPanel(width: 1400) {
                Kicker(L10n.yearInGlassfinBusiest)
                if let month = stats.busiestMonth {
                    Text(L10n.yearInGlassfinMonthWasYours(Calendar.current.standaloneMonthSymbols[month - 1]))
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                MonthBars(months: stats.months, highlight: stats.busiestMonth)
                    .padding(.vertical, 20)
                if let weekday = stats.busiestWeekday {
                    Text(L10n.yearInGlassfinFavoriteDay(Calendar.current.weekdaySymbols[weekday - 1]))
                        .font(.headline)
                }
            }

        case .binge:
            if let binge = stats.longestBinge {
                GlassPanel {
                    Kicker(L10n.yearInGlassfinLongestBinge)
                    BigNumber(YearCount.episodes(binge.episodes))
                    Text(binge.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text([binge.date.formatted(.dateTime.month(.wide).day()), Self.duration(binge.seconds)].joined(separator: " · "))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

        case .favorites:
            VStack(alignment: .leading, spacing: 34) {
                Kicker(L10n.yearInGlassfinFavorites)
                HStack(alignment: .top, spacing: 40) {
                    ForEach(stats.favorites.prefix(4)) { favorite in
                        FavoriteTile(favorite: favorite)
                    }
                }
            }
            .padding(56)
            .glassEffect(.regular, in: .rect(cornerRadius: 48))

        case .persona:
            VStack(spacing: 24) {
                Kicker(L10n.yearInGlassfinPersona)
                Text(stats.persona.title)
                    .font(.system(size: 110, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 1500)
                Text(stats.persona.line)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 1200)
            }
            .shadow(color: .black.opacity(0.25), radius: 16)

        case .summary:
            YearSummaryCard(stats: stats)
        }
    }

    private var hoursDetail: String {
        let days = stats.totalSeconds / 86400
        let parts = [
            stats.episodeCount > 0 ? YearCount.episodes(stats.episodeCount) : nil,
            stats.movieCount > 0 ? YearCount.movies(stats.movieCount) : nil,
        ]
            .compactMap(\.self)
            .joined(separator: " · ")
        return days >= 1 ? "\(L10n.yearInGlassfinDays(String(format: "%.1f", days))) · \(parts)" : parts
    }

    private var genreHeadline: String {
        stats.genres
            .prefix(2)
            .map { "\(Int(($0.share * 100).rounded()))% \($0.name.lowercased())" }
            .joined(separator: ", ")
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}

// MARK: - Building blocks

/// "1 episode" / "12 episodes"
private enum YearCount {

    static func hours(_ count: Int) -> String {
        count == 1 ? L10n.yearInGlassfinOneHour : L10n.yearInGlassfinHours(count)
    }

    static func episodes(_ count: Int) -> String {
        count == 1 ? L10n.yearInGlassfinOneEpisode : L10n.yearInGlassfinEpisodeCount(count)
    }

    static func movies(_ count: Int) -> String {
        count == 1 ? L10n.yearInGlassfinOneMovie : L10n.yearInGlassfinMovieCount(count)
    }
}

private struct Kicker: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.heavy)
            .kerning(3)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.75))
    }
}

private struct BigNumber: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 170, weight: .heavy, design: .rounded))
            .kerning(-4)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

private struct GlassPanel<Content: View>: View {

    var width: CGFloat = 1180
    let content: Content

    init(width: CGFloat = 1180, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .foregroundStyle(.white)
        .padding(64)
        .frame(width: width, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 48))
    }
}

private struct TopTitleRow: View {

    let rank: Int
    let title: YearStats.TitleStat

    var body: some View {
        HStack(spacing: 28) {
            Text(verbatim: "\(rank)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .frame(width: 70, alignment: .leading)

            HomeLibraryArtwork(itemID: title.id, maxWidth: 220)
                .frame(width: 192, height: 108)
                .background(Color.white.opacity(0.08))
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .opacity(rank == 1 ? 1 : 0.92)
    }

    private var detail: String {
        let time = YearPageView.duration(title.seconds)
        return title.isSeries && title.episodes > 0 ? "\(YearCount.episodes(title.episodes)) · \(time)" : time
    }
}

private struct FavoriteTile: View {

    let favorite: YearStats.Favorite

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Color.white.opacity(0.08)
                if let itemID = favorite.itemID {
                    ImageView(HomeImages.url(itemID: itemID, type: .primary, maxWidth: 300))
                        .placeholder { _ in Color.clear }
                        .failure { Color.clear }
                        .aspectRatio(contentMode: .fill)
                } else {
                    ImageView(TMDBClient.imageURL(favorite.tmdbBackdropPath, size: "w780"))
                        .placeholder { _ in Color.clear }
                        .failure { Text(favorite.name).font(.headline).padding() }
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 260, height: 390)
            .clipShape(.rect(cornerRadius: 18))

            Label(favorite.name, systemImage: favorite.level.selectedSystemImage)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 260, alignment: .leading)
        }
    }
}

private struct GenreBar: View {

    let genres: [YearStats.GenreShare]

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.42),
        Color(red: 1.0, green: 0.78, blue: 0.3),
        Color(red: 0.36, green: 0.85, blue: 0.75),
        Color(red: 0.55, green: 0.6, blue: 1.0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GeometryReader { proxy in
                HStack(spacing: 6) {
                    ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                        Capsule()
                            .fill(Self.colors[index % Self.colors.count])
                            .frame(width: max(14, (proxy.size.width - 18) * genre.share))
                    }
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                }
            }
            .frame(height: 30)

            HStack(spacing: 40) {
                ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Self.colors[index % Self.colors.count])
                            .frame(width: 18, height: 18)
                        Text(verbatim: "\(Int((genre.share * 100).rounded()))% \(genre.name)")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct MonthBars: View {

    let months: [Int: Double]
    let highlight: Int?

    var body: some View {
        let top = max(1, months.values.max() ?? 1)
        let symbols = Calendar.current.veryShortStandaloneMonthSymbols

        HStack(alignment: .bottom, spacing: 22) {
            ForEach(1 ... 12, id: \.self) { month in
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(month == highlight ? 1 : 0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(12, 220 * (months[month] ?? 0) / top))
                    Text(symbols[month - 1])
                        .font(.caption)
                        .fontWeight(month == highlight ? .heavy : .medium)
                        .foregroundStyle(.white.opacity(month == highlight ? 1 : 0.6))
                }
            }
        }
        .frame(height: 270, alignment: .bottom)
    }
}

// MARK: - Summary

/// The last card, made to be photographed: the year, the persona and the headline stats.
private struct YearSummaryCard: View {

    let stats: YearStats

    private var tiles: [(String, String)] {
        var tiles: [(String, String)] = [(L10n.yearInGlassfinSummaryHours, YearCount.hours(stats.totalHours))]
        if let show = stats.topShows.first ?? stats.topTitles.first {
            tiles.append((L10n.yearInGlassfinSummaryTopShow, show.name))
        }
        if let genre = stats.genres.first {
            tiles.append((L10n.yearInGlassfinSummaryTopGenre, genre.name))
        }
        if let month = stats.busiestMonth {
            tiles.append((L10n.yearInGlassfinSummaryBusiestMonth, Calendar.current.standaloneMonthSymbols[month - 1]))
        }
        if let binge = stats.longestBinge {
            tiles.append((L10n.yearInGlassfinSummaryBinge, YearCount.episodes(binge.episodes)))
        }
        if let favorite = stats.favorites.first {
            tiles.append((L10n.yearInGlassfinSummaryFavorite, favorite.name))
        }
        return Array(tiles.prefix(6))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            // Key art of the top title
            ZStack {
                YearGradient(palette: .dusk)
                if let id = stats.topTitles.first?.id {
                    ImageView(HomeImages.url(itemID: id, type: .primary, maxWidth: 480))
                        .placeholder { _ in Color.clear }
                        .failure { Color.clear }
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 440, height: 660)
            .clipShape(.rect(cornerRadius: 30))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 16)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(verbatim: String(stats.year))
                        .font(.system(size: 120, weight: .heavy, design: .rounded))
                        .kerning(-3)
                    Text(L10n.yearInGlassfin)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Text(stats.persona.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 34)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)],
                    alignment: .leading,
                    spacing: 30
                ) {
                    ForEach(tiles, id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(label)
                                .font(.caption)
                                .fontWeight(.heavy)
                                .kerning(2)
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(value)
                                .font(.headline)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 20)

                HStack(spacing: 14) {
                    Image(.glassfinGlyph)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                    Text(verbatim: "Glassfin")
                        .font(.callout)
                        .fontWeight(.bold)
                    if stats.isEstimated {
                        Text(L10n.yearInGlassfinEstimatedShort)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: 900, height: 660, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .padding(60)
        .glassEffect(.regular, in: .rect(cornerRadius: 56))
        .padding(.bottom, 60)
    }
}

// MARK: - Backgrounds

private enum YearPalette {
    case dusk
    case ocean
    case ember
    case rose
    case lagoon
    case aurora

    var colors: [Color] {
        switch self {
        case .dusk: [
                .init(red: 0.16, green: 0.07, blue: 0.32),
                .init(red: 0.55, green: 0.15, blue: 0.45),
                .init(red: 0.95, green: 0.45, blue: 0.35)
            ]

        case .ocean: [
                .init(red: 0.02, green: 0.1, blue: 0.3),
                .init(red: 0.05, green: 0.35, blue: 0.6),
                .init(red: 0.3, green: 0.75, blue: 0.85)
            ]

        case .ember: [
                .init(red: 0.25, green: 0.04, blue: 0.04),
                .init(red: 0.7, green: 0.2, blue: 0.08),
                .init(red: 1.0, green: 0.6, blue: 0.2)
            ]

        case .rose: [
                .init(red: 0.3, green: 0.03, blue: 0.2),
                .init(red: 0.8, green: 0.2, blue: 0.45),
                .init(red: 1.0, green: 0.65, blue: 0.7)
            ]

        case .lagoon: [
                .init(red: 0.02, green: 0.2, blue: 0.2),
                .init(red: 0.05, green: 0.55, blue: 0.45),
                .init(red: 0.75, green: 0.95, blue: 0.5)
            ]

        case .aurora: [
                .init(red: 0.05, green: 0.05, blue: 0.25),
                .init(red: 0.35, green: 0.15, blue: 0.75),
                .init(red: 0.2, green: 0.85, blue: 0.7)
            ]
        }
    }
}

private struct YearGradient: View {

    let palette: YearPalette

    var body: some View {
        let c = palette.colors
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                c[0], c[0], c[1],
                c[0], c[1], c[2],
                c[1], c[2], c[2],
            ]
        )
        .ignoresSafeArea()
    }
}

/// The title's backdrop, tinted with the page's palette so the glass and type stay readable.
private struct ArtBackground: View {

    let itemID: String?
    var tmdbPath: String?
    let palette: YearPalette
    var blur: CGFloat = 30

    var body: some View {
        ZStack {
            YearGradient(palette: palette)

            if let itemID {
                ImageView([HomeImages.url(itemID: itemID, type: .backdrop, maxWidth: 1920)])
                    .placeholder { _ in Color.clear }
                    .failure { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: blur)
                    .opacity(0.85)
            } else if let tmdbPath {
                ImageView(TMDBClient.imageURL(tmdbPath, size: "w1280"))
                    .placeholder { _ in Color.clear }
                    .failure { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: blur)
                    .opacity(0.85)
            }

            LinearGradient(colors: [palette.colors[0].opacity(0.25), palette.colors[0].opacity(0.8)], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: 1920, height: 1080)
        .clipped()
        .ignoresSafeArea()
    }
}
