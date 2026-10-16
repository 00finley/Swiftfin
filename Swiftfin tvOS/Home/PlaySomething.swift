//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

// MARK: - Playback

enum HomePlayback {

    /// What to play for a library item: a movie or episode itself; for a series, its next-up
    /// episode, else its first episode (skipping specials). Fetched fresh for the saved position.
    @MainActor
    static func playableItem(for item: BaseItemDto) async -> BaseItemDto? {
        guard let session = Container.shared.currentUserSession(), let id = item.id else { return nil }

        var target: BaseItemDto? = item.type == .series ? nil : item

        if item.type == .series {
            var nextUp = Paths.GetNextUpParameters()
            nextUp.userID = session.user.id
            nextUp.seriesID = id
            nextUp.limit = 1
            target = try? await session.client.send(Paths.getNextUp(parameters: nextUp)).value.items?.first

            if target == nil {
                var episodes = Paths.GetEpisodesParameters()
                episodes.userID = session.user.id
                episodes.isMissing = false
                episodes.enableUserData = true
                let list = await (try? session.client.send(Paths.getEpisodes(seriesID: id, parameters: episodes)).value.items) ?? []
                target = list.first { ($0.parentIndexNumber ?? 0) >= 1 } ?? list.first
            }
        }

        guard let targetID = target?.id else { return nil }

        return await (try? session.client.send(Paths.getItem(itemID: targetID, userID: session.user.id)).value) ?? target
    }

    @MainActor
    static func playRoute(for item: BaseItemDto) -> NavigationRoute? {
        guard let provider = item.getPlaybackItemProvider(userSession: nil) else { return nil }

        return .videoPlayer(provider: provider, queue: item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil)
    }
}

// MARK: - Picking

/// Picks something the user will probably like, weighted by the Discover taste profile.
///
/// Candidates, strongest first: Next Up and in-progress items; shows in the library not yet started
/// that are rated or seeded Love It / Like It; unwatched movies. Each gets
/// `base + rating bonus + genre affinity`, and one is drawn at random weighted by `exp(score / 0.35)`,
/// so the best fits come up most but Shuffle Again still varies. About one press in six (or when the
/// library has nothing) offers a requestable title from the Discover feed instead.
@MainActor
struct PlaySomethingEngine {

    enum Target: Hashable {
        /// A movie, an episode, or a series to start from its first episode
        case library(BaseItemDto)
        case discover(DiscoverItem)
    }

    struct Candidate: Hashable {
        let id: String
        let target: Target
        let score: Double
        let reason: String
    }

    static let discoverChance = 1.0 / 6

    func candidates() async -> [Candidate] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        let client = session.client
        let userID = session.user.id

        var resume = Paths.GetResumeItemsParameters()
        resume.userID = userID
        resume.enableUserData = true
        resume.mediaTypes = [.video]
        resume.limit = 20
        resume.fields = [.genres, .overview]

        var nextUp = Paths.GetNextUpParameters()
        nextUp.userID = userID
        nextUp.enableUserData = true
        nextUp.limit = 20
        nextUp.fields = [.genres, .overview]

        async let resumeItems = try? client.send(Paths.getResumeItems(parameters: resume)).value.items
        async let nextUpItems = try? client.send(Paths.getNextUp(parameters: nextUp)).value.items
        async let libraryTask = try? HomeLibraryIndex.shared.load()
        async let tasteTask = Self.taste(within: 2)
        async let genreTask = Self.genreIDsByName()

        let library = await libraryTask ?? HomeLibraryIndex.Snapshot()
        let taste = await tasteTask
        let genreIDs = await genreTask
        let upNext = await (resumeItems ?? []) + (nextUpItems ?? [])

        let rated = Defaults[.Discover.profile].ratedTitles()
        let hidden = Defaults[.Discover.profile].hiddenKeys

        let seriesByID = Dictionary(
            library.items.filter { $0.type == .series }.compactMap { item in item.id.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )

        func key(for item: BaseItemDto) -> String? {
            let owner = item.type == .episode ? item.seriesID.flatMap { seriesByID[$0] } : item
            guard let tmdb = owner?.providerIDs?["Tmdb"] else { return nil }

            return "\(owner?.type == .movie ? "movie" : "tv")-\(tmdb)"
        }

        func level(_ key: String?) -> DiscoverRatingLevel {
            key.flatMap { rated[$0]?.level } ?? .neutral
        }

        func ratingBonus(_ level: DiscoverRatingLevel) -> Double {
            switch level {
            case .loved: 0.9
            case .liked: 0.5
            case .neutral: 0
            case .disliked: -3
            }
        }

        func genreFit(_ item: BaseItemDto) -> Double {
            guard let taste else { return 0 }

            let owner = item.type == .episode ? item.seriesID.flatMap { seriesByID[$0] } ?? item : item
            let ids = (owner.genres ?? []).compactMap { genreIDs[$0.lowercased()] }
            let values = ids.map { taste.genre[$0] ?? 0 }
            guard values.isNotEmpty else { return 0 }

            return max(-1, min(1, values.reduce(0, +) / Double(values.count).squareRoot()))
        }

        var candidates: [Candidate] = []
        var seenSeries = Set<String>()

        // Next Up and in-progress
        for item in upNext {
            guard let id = item.id, item.type == .episode || item.type == .movie else { continue }

            let seriesKey = item.seriesID ?? id
            guard seenSeries.insert(seriesKey).inserted else { continue }

            let itemKey = key(for: item)
            if let itemKey, hidden.contains(itemKey) {
                continue
            }

            let level = level(itemKey)
            candidates.append(Candidate(
                id: seriesKey,
                target: .library(item),
                score: 1.0 + ratingBonus(level) + 0.5 * genreFit(item),
                reason: item.type == .episode ? L10n.playSomethingReasonNextUp : L10n.playSomethingReasonResume
            ))
        }

        for item in library.items {
            guard let id = item.id, !seenSeries.contains(id) else { continue }

            let data = item.userData
            let itemKey = key(for: item)
            if let itemKey, hidden.contains(itemKey) {
                continue
            }

            let level = level(itemKey)

            switch item.type {
            case .series:
                // Not started, and rated or seeded Love It / Like It
                let started = data?.isPlayed == true || (data?.playedPercentage ?? 0) > 0 || data?.lastPlayedDate != nil
                guard !started, level == .loved || level == .liked else { continue }

                candidates.append(Candidate(
                    id: id,
                    target: .library(item),
                    score: 0.75 + ratingBonus(level) + 0.5 * genreFit(item),
                    reason: level == .loved ? L10n.playSomethingReasonLoved : L10n.playSomethingReasonLiked
                ))

            case .movie:
                let started = data?.isPlayed == true || (data?.playbackPositionTicks ?? 0) > 0
                guard !started, level != .disliked else { continue }

                let quality = (item.communityRating.map(Double.init) ?? 6.5) / 10
                candidates.append(Candidate(
                    id: id,
                    target: .library(item),
                    score: 0.35 + ratingBonus(level) + 0.7 * genreFit(item) + 0.3 * quality,
                    reason: level == .neutral ? L10n.playSomethingReasonMovie : (
                        level == .loved ? L10n.playSomethingReasonLoved : L10n.playSomethingReasonLiked
                    )
                ))

            default:
                continue
            }
        }

        // Requestable titles from the Discover feed (not in the library)
        let feed = DiscoverViewModel.shared
        let topPicks = feed.rows.first { $0.kind == .topPicks }?.items ?? []
        let pool = ([feed.hero].compactMap(\.self) + topPicks).filter { !$0.isInLibrary && !hidden.contains($0.id) }
        for (index, item) in pool.prefix(12).enumerated() {
            let fit = taste.map { $0.affinity(item.title) } ?? 0
            candidates.append(Candidate(
                id: item.id,
                target: .discover(item),
                score: 0.6 + 0.5 * fit - 0.03 * Double(index),
                reason: L10n.playSomethingReasonDiscover
            ))
        }

        return candidates
    }

    /// One weighted draw. Discover titles come up about one press in `1 / discoverChance`.
    static func choose(
        from candidates: [Candidate],
        excluding offered: Set<String>,
        discoverChance: Double = discoverChance,
        using generator: inout some RandomNumberGenerator
    ) -> Candidate? {
        let fresh = candidates.filter { !offered.contains($0.id) }
        let pool = fresh.isEmpty ? candidates : fresh

        let library = pool.filter {
            if case .library = $0.target {
                true
            } else {
                false
            }
        }
        let discover = pool.filter {
            if case .discover = $0.target {
                true
            } else {
                false
            }
        }

        let useDiscover = discover.isNotEmpty && (library.isEmpty || Double.random(in: 0 ..< 1, using: &generator) < discoverChance)
        let options = useDiscover ? discover : library
        guard options.isNotEmpty else { return nil }

        let weights = options.map { exp($0.score / 0.35) }
        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0 ..< total, using: &generator)
        for (option, weight) in zip(options, weights) {
            roll -= weight
            if roll < 0 {
                return option
            }
        }
        return options.last
    }

    private static func taste(within seconds: Double) async -> DiscoverTaste? {
        let feed = DiscoverViewModel.shared
        if let taste = feed.taste {
            return taste
        }
        guard TMDBClient.isAvailable else { return nil }

        return await withTaskGroup(of: DiscoverTaste?.self) { group in
            group.addTask { await feed.currentTaste() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// TMDB genre ids by lowercased name, so Jellyfin's genre names (from TMDB metadata) match the taste.
    private static func genreIDsByName() async -> [String: Int] {
        guard TMDBClient.isAvailable, let names = try? await TMDBClient.shared.genres() else { return [:] }

        var result: [String: Int] = [:]
        for (id, name) in names {
            result[name.lowercased()] = id
            // TV's combined genres also appear split in Jellyfin ("Action & Adventure" vs "Action")
            for part in name.components(separatedBy: " & ") where result[part.lowercased()] == nil {
                result[part.lowercased()] = id
            }
        }
        result["science fiction"] = result["science fiction"] ?? result["sci-fi & fantasy"]
        result["sci-fi"] = result["sci-fi"] ?? result["science fiction"]
        return result
    }
}

// MARK: - Content group

/// "Play Something": one press picks something to watch and starts it after a short reveal.
///
/// It's its own slim group under Recently Added rather than a button in the hero: the hero's
/// focus and scroll pinning (CinematicItemSelector) assume its buttons belong to the focused item,
/// and a group of its own needs no changes there.
struct PlaySomethingContentGroup: ContentGroup {

    let id = "home-play-something"
    let viewModel = PlaySomethingViewModel()

    func body(with viewModel: PlaySomethingViewModel) -> some View {
        PlaySomethingSection(viewModel: viewModel)
    }
}

final class PlaySomethingViewModel: ViewModel, WithRefresh {

    struct Reveal: Identifiable {
        let id = UUID()
        let candidate: PlaySomethingEngine.Candidate
        /// What plays (an episode or movie); nil for a Discover title
        let playable: BaseItemDto?
        let title: String
        let detail: String?
        let artworkURLs: [URL?]
        let discoverTitle: DiscoverTitle?
    }

    @Published
    private(set) var isPicking = false
    @Published
    var reveal: Reveal?

    private var candidates: [PlaySomethingEngine.Candidate]?
    private var candidatesDate: Date?
    private var offered = Set<String>()
    private var generator = SystemRandomNumberGenerator()

    func refresh() {
        warmUp()
    }

    func refresh() async {
        warmUp()
    }

    /// Builds the taste in the background so the first press is quick.
    private func warmUp() {
        candidates = nil
        if TMDBClient.isAvailable {
            DiscoverViewModel.shared.prepareTaste()
        }
    }

    func pick() {
        guard !isPicking else { return }

        isPicking = true
        Task {
            defer { isPicking = false }

            if candidates == nil || Date.now.timeIntervalSince(candidatesDate ?? .distantPast) > 120 {
                candidates = await PlaySomethingEngine().candidates()
                candidatesDate = .now
            }
            let pool = candidates ?? []

            // A pick can fail to resolve (a show with no episodes); try a few
            for _ in 0 ..< 4 {
                guard let candidate = PlaySomethingEngine.choose(from: pool, excluding: offered, using: &generator) else { break }

                offered.insert(candidate.id)
                if offered.count >= pool.count {
                    offered = [candidate.id]
                }
                if let reveal = await makeReveal(for: candidate) {
                    self.reveal = reveal
                    return
                }
            }
        }
    }

    func shuffle() {
        reveal = nil
        Task {
            // Let the reveal fade before the next one
            try? await Task.sleep(for: .milliseconds(150))
            pick()
        }
    }

    private func makeReveal(for candidate: PlaySomethingEngine.Candidate) async -> Reveal? {
        switch candidate.target {
        case let .library(item):
            guard let playable = await HomePlayback.playableItem(for: item) else { return nil }

            let isEpisode = playable.type == .episode
            let title = isEpisode ? (playable.seriesName ?? item.displayTitle) : playable.displayTitle
            let detail = isEpisode
                ? [
                    HomeRowFormat.episodeLabel(season: playable.parentIndexNumber, episodes: playable.indexNumber.map { [$0] } ?? []),
                    playable.name
                ]
                .compactMap(\.self)
                .joined(separator: " · ")
                : [playable.productionYear.map(String.init), playable.runTimeLabel].compactMap(\.self).joined(separator: " · ")

            let artID = isEpisode ? (playable.seriesID ?? playable.id) : playable.id
            let urls: [URL?] = artID.map { id in
                [HomeImages.url(itemID: id, type: .backdrop, maxWidth: 1920), HomeImages.url(itemID: id, type: .primary, maxWidth: 1920)]
            } ?? []

            return Reveal(
                candidate: candidate,
                playable: playable,
                title: title,
                detail: detail.isEmpty ? nil : detail,
                artworkURLs: urls,
                discoverTitle: nil
            )

        case let .discover(item):
            return Reveal(
                candidate: candidate,
                playable: nil,
                title: item.title.title,
                detail: [item.title.year, item.reason].compactMap(\.self).joined(separator: " · "),
                artworkURLs: [TMDBClient.imageURL(item.title.backdropPath, size: "w1280")],
                discoverTitle: item.title
            )
        }
    }
}

// MARK: - Views

struct PlaySomethingSection: View {

    @ObservedObject
    var viewModel: PlaySomethingViewModel

    @Router
    private var router

    /// Runs once the reveal has gone, so the player isn't pushed under a dismissing cover.
    @State
    private var pendingRoute: NavigationRoute?

    var body: some View {
        HStack(spacing: 30) {
            Button {
                viewModel.pick()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: viewModel.isPicking ? "ellipsis" : "shuffle")
                        .symbolEffect(.pulse, isActive: viewModel.isPicking)
                    Text(L10n.playSomething)
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 40)
                .frame(height: 76)
            }
            .buttonStyle(.homeGlass)
            .accessibilityHint(L10n.playSomethingHint)

            Text(L10n.playSomethingCaption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .edgePadding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .fullScreenCover(item: $viewModel.reveal) {
            if let route = pendingRoute {
                pendingRoute = nil
                router.route(to: route)
            }
        } content: { reveal in
            PlaySomethingRevealView(reveal: reveal) {
                viewModel.shuffle()
            } onCancel: {
                viewModel.reveal = nil
            } onFinish: {
                finish(reveal)
            }
        }
    }

    private func finish(_ reveal: PlaySomethingViewModel.Reveal) {
        if let playable = reveal.playable {
            pendingRoute = HomePlayback.playRoute(for: playable)
        } else if let title = reveal.discoverTitle, case let .discover(item) = reveal.candidate.target {
            pendingRoute = .discoverTitle(
                item: DiscoverItem(title: title, providers: item.providers, libraryItemID: nil, reason: item.reason),
                feed: .shared
            )
        }
        viewModel.reveal = nil
    }
}

/// The ~3 second glass card before playback: "Playing The Owl House · S1, E1", with Shuffle Again and Cancel.
struct PlaySomethingRevealView: View {

    /// About 3 seconds; Debug builds accept `-GlassfinRevealSeconds <n>` so UI tests can read the card.
    static var duration: Double {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "GlassfinRevealSeconds")
        if override > 0 {
            return override
        }
        #endif
        return 3
    }

    let reveal: PlaySomethingViewModel.Reveal
    let onShuffle: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void

    @State
    private var progress: CGFloat = 0
    @State
    private var isShown = false

    @FocusState
    private var focusedButton: Int?

    private var isDiscover: Bool {
        reveal.playable == nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            ImageView(reveal.artworkURLs)
                .placeholder { _ in Color.black }
                .failure { Color.black }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .scaleEffect(isShown ? 1.0 : 1.06)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.2),
                    .init(color: .black.opacity(0.75), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            card
                .padding(.bottom, 90)
                .opacity(isShown ? 1 : 0)
                .offset(y: isShown ? 0 : 40)
        }
        .ignoresSafeArea()
        .onAppear {
            focusedButton = 0
            withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                isShown = true
            }
            withAnimation(.linear(duration: Self.duration)) {
                progress = 1
            }
        }
        .task(id: reveal.id) {
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }

            onFinish()
        }
        .onPlayPauseCommand(perform: onFinish)
        .onExitCommand(perform: onCancel)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isDiscover ? L10n.playSomethingHowAbout : L10n.playSomethingPlaying)
                .font(.caption)
                .fontWeight(.bold)
                .kerning(2)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 10)

            Text(reveal.title)
                .accessibilityIdentifier("playSomething.title")
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 8)

            if let detail = reveal.detail, detail.isNotEmpty {
                Text(detail)
                    .accessibilityIdentifier("playSomething.detail")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.bottom, 6)
            }

            Text(isDiscover ? L10n.playSomethingOpensInDiscover : reveal.candidate.reason)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .padding(.bottom, 28)

            // Countdown to playback
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .padding(.bottom, 32)
                .accessibilityHidden(true)

            HStack(spacing: 24) {
                Button(action: onShuffle) {
                    Label(L10n.playSomethingShuffleAgain, systemImage: "shuffle")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 34)
                        .frame(height: 66)
                }
                .buttonStyle(.homeGlass)
                .focused($focusedButton, equals: 0)

                Button(action: onCancel) {
                    Text(L10n.cancel)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 34)
                        .frame(height: 66)
                }
                .buttonStyle(.homeGlass)
                .focused($focusedButton, equals: 1)
            }
        }
        .foregroundStyle(.white)
        .padding(48)
        .frame(width: 1040, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 44))
        .accessibilityElement(children: .contain)
    }
}
