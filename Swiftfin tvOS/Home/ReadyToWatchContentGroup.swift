//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import JellyfinAPI
import SwiftUI

extension Defaults.Keys {

    /// Ready to Watch titles the user has opened or played (`"tv-1396"`), so they lose the New badge.
    static var homeReadyToWatchSeen: Key<Set<String>> {
        Key("homeReadyToWatchSeen", default: [], suite: .currentUserSuite)
    }
}

/// "Ready to Watch": the user's Seerr requests that became available, matched to library items.
/// Hidden when Seerr isn't configured or nothing has arrived.
struct ReadyToWatchContentGroup: ContentGroup {

    let id = "home-ready-to-watch"
    let viewModel = ReadyToWatchViewModel()

    var _shouldBeResolved: Bool {
        viewModel.entries.isNotEmpty
    }

    func body(with viewModel: ReadyToWatchViewModel) -> some View {
        ReadyToWatchSection(viewModel: viewModel)
    }
}

final class ReadyToWatchViewModel: ViewModel, WithRefresh {

    struct Entry: Identifiable, Hashable {
        let request: SeerrClient.AvailableRequest
        let item: BaseItemDto

        var id: String {
            request.key
        }

        /// Played (or partly played) after it arrived counts as seen, wherever it was played
        var wasPlayedSinceAvailable: Bool {
            guard let data = item.userData else { return false }

            if let lastPlayed = data.lastPlayedDate {
                return lastPlayed >= (request.availableAt ?? .distantPast)
            }
            return data.isPlayed == true || (data.playbackPositionTicks ?? 0) > 0
        }
    }

    struct Background: WithRefresh {

        let viewModel: ReadyToWatchViewModel

        func refresh() {
            viewModel.reload()
        }

        func refresh() async {
            viewModel.reload()
        }
    }

    /// Titles stay in the row this long after arriving, or until watched to the end.
    static let window: TimeInterval = 45 * 86400

    @Published
    private(set) var entries: [Entry] = []
    @Published
    private(set) var seen: Set<String> = Defaults[.homeReadyToWatchSeen]

    var background: Background {
        get { Background(viewModel: self) }
        set {}
    }

    private var loadTask: Task<Void, Never>?

    override init() {
        super.init()

        Defaults.publisher(.homeReadyToWatchSeen, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.seen = change.newValue
            }
            .store(in: &cancellables)
    }

    func isNew(_ entry: Entry) -> Bool {
        !seen.contains(entry.id) && !entry.wasPlayedSinceAvailable
    }

    func markSeen(_ entry: Entry) {
        guard !seen.contains(entry.id) else { return }

        Defaults[.homeReadyToWatchSeen].insert(entry.id)
    }

    func refresh() {
        reload()
    }

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
        guard SeerrClient.isConfigured, let userSession else {
            entries = []
            return
        }

        do {
            async let requestsTask = SeerrClient.shared.availableRequests(jellyfinUserID: userSession.user.id)
            // Fresh user data, so something just watched drops out
            async let libraryTask = HomeLibraryIndex.shared.load(maxAge: 30)
            let (requests, library) = try await (requestsTask, libraryTask)

            entries = Self.entries(from: requests, library: library)
        } catch {
            logger.debug("Ready to Watch hidden: \(error.localizedDescription)")
            entries = []
        }
    }

    static func entries(from requests: [SeerrClient.AvailableRequest], library: HomeLibraryIndex.Snapshot, now: Date = .now) -> [Entry] {
        let byID = Dictionary(library.items.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { first, _ in first })

        let entries = requests.compactMap { request -> Entry? in
            guard let item = library.item(kind: request.kind, tmdbID: request.tmdbID)
                ?? request.jellyfinMediaID.flatMap({ byID[$0.replacing("-", with: "").lowercased()] ?? byID[$0] })
            else { return nil }

            // Finished: no longer "ready"
            if item.userData?.isPlayed == true {
                return nil
            }
            if let availableAt = request.availableAt, now.timeIntervalSince(availableAt) > window {
                return nil
            }
            return Entry(request: request, item: item)
        }
        return Array(entries.prefix(20))
    }
}

// MARK: - Section

struct ReadyToWatchSection: View {

    @ObservedObject
    var viewModel: ReadyToWatchViewModel

    @Router
    private var router

    private func subtitle(for entry: ReadyToWatchViewModel.Entry) -> String {
        let kind = entry.item.type == .movie ? L10n.movie : L10n.tvShow
        let status = entry.request.isPartial ? L10n.seerrPartiallyAvailable : nil
        return [kind, status].compactMap(\.self).joined(separator: " · ")
    }

    private func open(_ entry: ReadyToWatchViewModel.Entry) {
        viewModel.markSeen(entry)
        router.route(to: .item(item: entry.item))
    }

    private func play(_ entry: ReadyToWatchViewModel.Entry) {
        viewModel.markSeen(entry)
        Task { @MainActor in
            guard let item = await HomePlayback.playableItem(for: entry.item),
                  let provider = item.getPlaybackItemProvider(userSession: nil)
            else {
                router.route(to: .item(item: entry.item))
                return
            }

            router.route(
                to: .videoPlayer(provider: provider, queue: item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil)
            )
        }
    }

    var body: some View {
        HomeShelf(L10n.readyToWatch) {
            ForEach(viewModel.entries) { entry in
                let isNew = viewModel.isNew(entry)

                HomeRowCard(
                    title: entry.item.displayTitle,
                    subtitle: subtitle(for: entry),
                    badge: isNew ? L10n.homeNewBadge : nil,
                    accessibilityLabel: [entry.item.displayTitle, isNew ? L10n.homeNewBadge : nil, subtitle(for: entry)]
                        .compactMap(\.self)
                        .joined(separator: ", ")
                ) {
                    open(entry)
                } artwork: {
                    if let id = entry.item.id {
                        HomeLibraryArtwork(
                            itemID: id,
                            imageTags: entry.item.imageTags,
                            hasBackdrop: entry.item.backdropImageTags?.isNotEmpty ?? true
                        )
                    }
                }
                .contextMenu {
                    Button(L10n.play, systemImage: "play.fill") {
                        play(entry)
                    }
                    Button(L10n.goToItem, systemImage: "info.circle") {
                        open(entry)
                    }
                }
            }
        }
    }
}
