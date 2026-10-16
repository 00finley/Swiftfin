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
    /// Jellyfin item ids keyed by TMDB key, from the last feed build.
    @Published
    private(set) var libraryItemIDs: [String: String] = [:]

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    private static var sharedInstance: DiscoverViewModel?

    /// One feed per signed-in user, shared by the Home rows, Categories and title pages
    /// so feedback (More Like This, Not Interested) updates every screen.
    static var shared: DiscoverViewModel {
        let userID = Container.shared.currentUserSession()?.user.id
        if let sharedInstance, sharedInstance.userID == userID {
            return sharedInstance
        }
        let model = DiscoverViewModel()
        model.userID = userID
        sharedInstance = model
        return model
    }

    private var userID: String?

    private var lastBuilt: Date?
    private var buildTask: Task<Void, Never>?
    private var ratingRefreshTask: Task<Void, Never>?

    /// Taste from the last feed build or Categories, dropped when ratings change.
    private(set) var taste: DiscoverTaste?
    private var tasteTask: Task<DiscoverTaste, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Rebuild after this long when the tab reappears.
    private let staleInterval: TimeInterval = 6 * 60 * 60

    init() {
        Defaults.publisher(keys: .Discover.providers, .Discover.region, options: [])
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh(force: true) }
            .store(in: &cancellables)

        // Ratings change what Categories ranks first
        Defaults.publisher(.Discover.profile, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.taste = nil
                self?.tasteTask = nil
                // "Reset Recommendations" in Settings clears the profile
                if change.newValue == DiscoverProfile() {
                    self?.refresh(force: true)
                }
            }
            .store(in: &cancellables)
    }

    private func makeEngine(_ userSession: UserSession) -> DiscoverEngine {
        DiscoverEngine(
            client: userSession.client,
            userID: userSession.user.id,
            providers: Defaults[.Discover.providers],
            region: Defaults[.Discover.region],
            profile: Defaults[.Discover.profile]
        )
    }

    /// The user's taste for ranking Categories; built once and reused until ratings change.
    func currentTaste() async -> DiscoverTaste {
        if let taste {
            return taste
        }
        if let tasteTask {
            return await tasteTask.value
        }
        guard let userSession else { return DiscoverTaste() }

        let engine = makeEngine(userSession)
        let task = Task { await engine.prepareContext().taste }
        tasteTask = task
        let built = await task.value
        if tasteTask == task {
            taste = built
            tasteTask = nil
        }
        return built
    }

    /// Starts building the taste in the background (e.g. when Categories opens).
    func prepareTaste() {
        guard taste == nil, tasteTask == nil else { return }

        Task { _ = await currentTaste() }
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

        let engine = makeEngine(userSession)

        buildTask = Task {
            do {
                let feed = try await engine.buildFeed()
                guard Task.isCancelled == false else { return }

                hero = feed.hero
                rows = feed.rows
                libraryItemIDs = feed.libraryItemIDs
                taste = feed.taste
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

    private var libraryTask: Task<Void, Never>?

    /// Loads just the library (for "In Library" badges) when no feed has been built yet,
    /// e.g. when Categories opens before Home's Discover rows load or with them turned off.
    func ensureLibrary() {
        guard libraryItemIDs.isEmpty, libraryTask == nil, buildTask == nil, let userSession else { return }

        let engine = makeEngine(userSession)
        libraryTask = Task {
            if let library = try? await engine.loadLibrary(), libraryItemIDs.isEmpty {
                libraryItemIDs = library.itemIDsByKey
            }
            libraryTask = nil
        }
    }

    // MARK: - Ratings

    /// The current rating (in-app, else the seed list, else It's OK).
    func rating(for title: DiscoverTitle) -> DiscoverRatingLevel {
        Defaults[.Discover.profile].level(for: title.id)
    }

    /// Love It / Like It feed recommendations; Not for Me hides the title everywhere; It's OK clears.
    func rate(_ title: DiscoverTitle, _ level: DiscoverRatingLevel) {
        var profile = Defaults[.Discover.profile]
        profile.rate(title.id, level, title: title)
        Defaults[.Discover.profile] = profile

        if level == .disliked {
            rows = rows.compactMap { row in
                let items = row.items.filter { $0.id != title.id }
                return items.isEmpty ? nil : DiscoverRow(kind: row.kind, title: row.title, items: items)
            }
            if hero?.id == title.id {
                hero = rows.first?.items.first
            }
        }

        scheduleRebuild()
    }

    /// Settings: rate by key (the title snapshot may be missing for older entries).
    func rate(key: String, _ level: DiscoverRatingLevel, title: DiscoverTitle?) {
        if let title {
            rate(title, level)
            return
        }
        var profile = Defaults[.Discover.profile]
        profile.rate(key, level, title: nil)
        Defaults[.Discover.profile] = profile
        scheduleRebuild()
    }

    /// Rebuilds the feed once the user stops rating for a moment.
    private func scheduleRebuild() {
        ratingRefreshTask?.cancel()
        ratingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            self?.refresh(force: true)
        }
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

            let hidden = Defaults[.Discover.profile].hiddenKeys
            var seen = Set<String>()
            moreLikeThis = (details.recommendations + details.similar)
                .filter { $0.backdropPath != nil && hidden.contains($0.id) == false && seen.insert($0.id).inserted }
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
