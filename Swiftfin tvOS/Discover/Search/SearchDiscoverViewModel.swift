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
import JellyfinAPI

extension Defaults.Keys.Discover {

    /// Search shows TMDB titles that aren't in the library (to request) after the library results.
    static var searchIncludesRequestable: Defaults.Key<Bool> {
        Defaults.Key("discoverSearchIncludesRequestable", default: true, suite: .currentUserSuite)
    }
}

/// The TMDB half of the Search tab: movies and shows matching the query that aren't in the library,
/// plus the credits of a person the query names.
///
/// Runs beside the library search and never holds it up: typing is debounced, a new query
/// cancels the previous one, recent queries are cached, and any TMDB failure just leaves
/// the section empty so Search looks exactly as it does without TMDB.
@MainActor
final class SearchDiscoverViewModel: ObservableObject {

    struct Results: Equatable {
        let query: String
        var titles: [DiscoverTitle]
        var person: TMDBSearchPerson?
        var personTitles: [DiscoverTitle] = []
        /// TMDB keys ("tv-1396") of library items found by a Jellyfin search for the same text.
        var libraryKeys: Set<String> = []
        /// Normalized "kind|name|year" for library matches without a TMDB id.
        var libraryNames: Set<String> = []
    }

    @Published
    private(set) var results: Results?
    /// Streaming services per title (the user's services first), loaded for the first cards of each query.
    @Published
    private(set) var providers: [String: [DiscoverProvider]] = [:]

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    static let debounce: Duration = .milliseconds(350)
    private let cacheLimit = 30
    private let cacheTTL: TimeInterval = 10 * 60
    private let rowLength = 20

    private var query = ""
    private var task: Task<Void, Never>?
    private var cache: [String: (date: Date, results: Results)] = [:]
    private var cacheOrder: [String] = []
    private var providersRequested: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []

    var isEnabled: Bool {
        Defaults[.Discover.searchIncludesRequestable] && TMDBClient.isAvailable
    }

    init() {
        Defaults.publisher(.Discover.searchIncludesRequestable, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                let current = self.query
                self.query = ""
                self.search(current)
            }
            .store(in: &cancellables)
    }

    // MARK: - Search

    /// Call on every change of the search text.
    func search(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != query else { return }

        query = text
        task?.cancel()
        task = nil

        guard isEnabled, text.count >= 2 else {
            results = nil
            return
        }

        // Badges and the request button on cards and title pages
        SeerrStatusStore.installRequestHandler()
        DiscoverViewModel.shared.ensureLibrary()

        let key = text.lowercased()
        if let cached = cache[key], Date.now.timeIntervalSince(cached.date) < cacheTTL {
            results = cached.results
            task = Task { [weak self] in await self?.loadProviders(for: cached.results) }
            return
        }

        results = nil
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }

            await self?.run(text, key: key)
        }
    }

    private func run(_ text: String, key: String) async {
        async let searchRequest = TMDBSearch.search(text)
        async let libraryRequest = libraryMatches(for: text)

        guard let found = try? await searchRequest else {
            // Not configured, offline or rate limited: Search stays library-only
            _ = await libraryRequest
            return
        }

        let library = await libraryRequest
        guard !Task.isCancelled, text == query else { return }

        var results = Results(
            query: text,
            titles: found.titles.filter { $0.backdropPath != nil },
            person: found.person,
            libraryKeys: library.keys,
            libraryNames: library.names
        )
        self.results = results

        if let person = found.person, let credits = try? await TMDBSearch.credits(for: person) {
            guard !Task.isCancelled, text == query else { return }

            let shown = Set(results.titles.map(\.id))
            results.personTitles = Array(credits.filter { shown.contains($0.id) == false }.prefix(rowLength * 2))
            self.results = results
        }

        store(results, key: key)
        await loadProviders(for: results)
    }

    private func store(_ results: Results, key: String) {
        cache[key] = (.now, results)
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    // MARK: - Display

    /// The rows to show: library titles left out (they're in the rows above), at most one row each.
    func items(libraryItemIDs: [String: String]) -> (titles: [DiscoverItem], personTitles: [DiscoverItem]) {
        guard let results else { return ([], []) }

        func isInLibrary(_ title: DiscoverTitle) -> Bool {
            libraryItemIDs[title.id] != nil
                || results.libraryKeys.contains(title.id)
                || results.libraryNames.contains(Self.nameKey(kind: title.kind, name: title.title, year: title.year))
        }

        func item(_ title: DiscoverTitle) -> DiscoverItem {
            DiscoverItem(
                title: title,
                providers: providers[title.id] ?? [],
                libraryItemID: nil,
                reason: [title.kind == .tv ? L10n.tvShow : L10n.movie, title.year].compactMap(\.self).joined(separator: " · ")
            )
        }

        let titles = results.titles.filter { !isInLibrary($0) }.prefix(rowLength).map(item)
        let personTitles = results.personTitles.filter { !isInLibrary($0) }.prefix(rowLength).map(item)
        return (Array(titles), Array(personTitles))
    }

    func hasItems(libraryItemIDs: [String: String]) -> Bool {
        let items = items(libraryItemIDs: libraryItemIDs)
        return items.titles.isNotEmpty || items.personTitles.isNotEmpty
    }

    // MARK: - Library matching

    /// Movies and shows in the library matching the text, so their TMDB entries aren't shown twice.
    /// This answers immediately for the query; the full library map (`DiscoverViewModel.libraryItemIDs`)
    /// covers person credits once it has loaded.
    private func libraryMatches(for text: String) async -> (keys: Set<String>, names: Set<String>) {
        guard let userSession else { return ([], []) }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userSession.user.id
        parameters.searchTerm = text
        parameters.isRecursive = true
        parameters.includeItemTypes = [.movie, .series]
        parameters.fields = [.providerIDs]
        parameters.enableUserData = false
        parameters.enableImages = false
        parameters.limit = 100

        guard let items = try? await userSession.client.send(Paths.getItems(parameters: parameters)).value.items else {
            return ([], [])
        }

        var keys = Set<String>()
        var names = Set<String>()
        for item in items {
            let kind: DiscoverTitle.Kind = item.type == .movie ? .movie : .tv
            if let tmdb = item.providerIDs?["Tmdb"].flatMap(Int.init) {
                keys.insert("\(kind.rawValue)-\(tmdb)")
            } else if let name = item.name {
                names.insert(Self.nameKey(kind: kind, name: name, year: item.productionYear.map(String.init)))
            }
        }
        return (keys, names)
    }

    private static func nameKey(kind: DiscoverTitle.Kind, name: String, year: String?) -> String {
        "\(kind.rawValue)|\(TMDBSearch.normalized(name))|\(year ?? "")"
    }

    // MARK: - Services

    /// Streaming badges for the first cards of each row (TMDB caches these for a day).
    private func loadProviders(for results: Results) async {
        let region = Defaults[.Discover.region]
        let mine = Defaults[.Discover.providers]
        let titles = (results.titles.prefix(12) + results.personTitles.prefix(8))
            .filter { providersRequested.insert($0.id).inserted }

        await withTaskGroup(of: (String, [DiscoverProvider]?).self) { group in
            for title in titles {
                group.addTask {
                    guard let all = try? await TMDBClient.shared.providers(for: title, region: region) else { return (title.id, nil) }

                    // The user's services first; add-on channels ("HBO Max Amazon Channel") never
                    let services = all.filter { $0.name.localizedCaseInsensitiveContains("channel") == false }
                    return (title.id, services.filter { mine.contains($0.id) } + services.filter { !mine.contains($0.id) })
                }
            }
            for await (id, services) in group {
                if let services {
                    providers[id] = services
                } else {
                    // Try again next time the title shows up
                    providersRequested.remove(id)
                }
            }
        }
    }
}
