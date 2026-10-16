//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation

@MainActor
final class DiscoverViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded
        case error
    }

    @Published
    private(set) var state: State = .loading
    @Published
    private(set) var hero: DiscoverItem?
    @Published
    private(set) var rows: [DiscoverRow] = []

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    private var lastBuilt: Date?
    private var buildTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Rebuild after this long when the tab reappears.
    private let staleInterval: TimeInterval = 6 * 60 * 60

    init() {
        Defaults.publisher(keys: .Discover.providers, .Discover.region, options: [])
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh(force: true) }
            .store(in: &cancellables)

        // "Reset Recommendations" in Settings clears the profile
        Defaults.publisher(.Discover.profile, options: [])
            .filter { $0.newValue == DiscoverProfile() }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)
    }

    func refreshIfNeeded() {
        guard let lastBuilt, Date.now.timeIntervalSince(lastBuilt) < staleInterval else {
            refresh(force: rows.isEmpty == false)
            return
        }
    }

    func refresh(force: Bool = false) {
        guard let userSession else { return }
        guard force || buildTask == nil else { return }

        buildTask?.cancel()
        if rows.isEmpty {
            state = .loading
        }

        let engine = DiscoverEngine(
            client: userSession.client,
            userID: userSession.user.id,
            providers: Defaults[.Discover.providers],
            region: Defaults[.Discover.region],
            profile: Defaults[.Discover.profile]
        )

        buildTask = Task {
            do {
                let feed = try await engine.buildFeed()
                guard Task.isCancelled == false else { return }

                hero = feed.hero
                rows = feed.rows
                lastBuilt = .now
                state = .loaded
            } catch {
                guard Task.isCancelled == false else { return }

                if rows.isEmpty {
                    state = .error
                }
            }
            buildTask = nil
        }
    }

    // MARK: - Feedback

    /// Hide the title everywhere and lean away from its genres.
    func notInterested(_ title: DiscoverTitle) {
        var profile = Defaults[.Discover.profile]
        profile.dismissed.insert(title.id)
        profile.liked[title.id] = nil
        for genre in title.genreIDs {
            profile.genreFeedback[genre] = max(-1, (profile.genreFeedback[genre] ?? 0) - 0.15)
        }
        Defaults[.Discover.profile] = profile

        rows = rows.compactMap { row in
            let items = row.items.filter { $0.id != title.id }
            return items.isEmpty ? nil : DiscoverRow(kind: row.kind, title: row.title, items: items)
        }
        if hero?.id == title.id {
            hero = rows.first?.items.first
        }
    }

    /// Use the title as a recommendation seed and lean toward its genres, then rebuild.
    func moreLikeThis(_ title: DiscoverTitle) {
        var profile = Defaults[.Discover.profile]
        profile.liked[title.id] = title
        profile.dismissed.remove(title.id)
        for genre in title.genreIDs {
            profile.genreFeedback[genre] = min(1, (profile.genreFeedback[genre] ?? 0) + 0.1)
        }
        Defaults[.Discover.profile] = profile

        refresh(force: true)
    }

    func isLiked(_ title: DiscoverTitle) -> Bool {
        Defaults[.Discover.profile].liked[title.id] != nil
    }

    func resetPersonalization() {
        Defaults[.Discover.profile] = .init()
        refresh(force: true)
    }
}

/// Loads full details for one Discover title.
@MainActor
final class DiscoverTitleViewModel: ObservableObject {

    @Published
    private(set) var details: TMDBDetails?
    @Published
    private(set) var providers: [DiscoverProvider] = []
    @Published
    private(set) var moreLikeThis: [DiscoverItem] = []
    @Published
    private(set) var libraryItemID: String?
    @Published
    private(set) var failed = false

    let item: DiscoverItem

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    init(item: DiscoverItem) {
        self.item = item
        self.libraryItemID = item.libraryItemID
        self.providers = item.providers
    }

    func load() async {
        let region = Defaults[.Discover.region]
        let services = Defaults[.Discover.providers]

        do {
            let details = try await TMDBClient.shared.details(kind: item.title.kind, id: item.title.tmdbID)
            self.details = details

            // The user's services; otherwise the top few, skipping add-on channels (e.g. "HBO Max Amazon Channel")
            let all = (details.providersByRegion[region] ?? []).filter { $0.name.localizedCaseInsensitiveContains("channel") == false }
            let mine = all.filter { services.contains($0.id) }
            providers = mine.isEmpty ? Array(all.prefix(3)) : mine

            let dismissed = Defaults[.Discover.profile].dismissed
            var seen = Set<String>()
            moreLikeThis = (details.recommendations + details.similar)
                .filter { $0.backdropPath != nil && dismissed.contains($0.id) == false && seen.insert($0.id).inserted }
                .prefix(20)
                .map { DiscoverItem(title: $0, providers: [], libraryItemID: nil, reason: nil) }
        } catch {
            failed = true
        }

        if libraryItemID == nil, let userSession {
            let engine = DiscoverEngine(
                client: userSession.client,
                userID: userSession.user.id,
                providers: services,
                region: region,
                profile: Defaults[.Discover.profile]
            )
            if let library = try? await engine.loadLibrary() {
                libraryItemID = library.itemIDsByKey[item.title.id]
                moreLikeThis = moreLikeThis.map { entry in
                    var entry = entry
                    entry.libraryItemID = library.itemIDsByKey[entry.title.id]
                    return entry
                }
            }
        }
    }
}

/// Seerr (or another request service) can plug in here later to add a "Request" button
/// on titles that aren't in the library.
enum DiscoverRequests {

    @MainActor
    static var handler: ((DiscoverTitle) async throws -> Void)?
}
