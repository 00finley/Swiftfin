//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation

/// Infinite paging over one or more TMDB list sources (e.g. `/discover/tv` and `/discover/movie`),
/// interleaved page by page, de-duplicated and limited to titles with art.
@MainActor
final class DiscoverTitlePager: ObservableObject {

    typealias Source = @Sendable (Int) async throws -> TMDBPage

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published
    private(set) var titles: [DiscoverTitle] = []
    @Published
    private(set) var phase: Phase = .idle
    @Published
    private(set) var isLoadingMore = false

    private var sources: [Source] = []
    private var nextPage: [Int] = []
    private var totalPages: [Int] = []
    private var seen: Set<String> = []
    private var task: Task<Void, Never>?
    private var generation = 0

    var isExhausted: Bool {
        zip(nextPage, totalPages).allSatisfy { $0 > $1 }
    }

    func reset(_ sources: [Source]) {
        task?.cancel()
        task = nil
        generation += 1
        self.sources = sources
        nextPage = Array(repeating: 1, count: sources.count)
        totalPages = Array(repeating: 1, count: sources.count)
        titles = []
        seen = []
        isLoadingMore = false
        phase = sources.isEmpty ? .loaded : .loading
        loadMore()
    }

    /// Call as items appear; fetches the next pages when the user is near the end.
    func loadMoreIfNeeded(after title: DiscoverTitle) {
        guard let index = titles.firstIndex(where: { $0.id == title.id }), index >= titles.count - 8 else { return }

        loadMore()
    }

    func loadMore() {
        guard task == nil, sources.isNotEmpty, !isExhausted else { return }

        let generation = generation
        isLoadingMore = titles.isNotEmpty

        task = Task { [weak self] in
            guard let self else { return }

            var added = 0
            var rounds = 0
            var failed = false

            // Keep going until a screenful arrives (filters can drop many results)
            while added < 12, rounds < 3, !self.isExhausted, !Task.isCancelled {
                rounds += 1
                let active = self.sources.indices.filter { self.nextPage[$0] <= self.totalPages[$0] }
                let requests = active.map { (index: $0, page: self.nextPage[$0], source: self.sources[$0]) }

                let pages = await withTaskGroup(of: (Int, TMDBPage?).self) { group in
                    for request in requests {
                        group.addTask { await (request.index, try? request.source(request.page)) }
                    }
                    var results: [Int: TMDBPage?] = [:]
                    for await (index, page) in group {
                        results[index] = page
                    }
                    return results
                }

                guard generation == self.generation else { return }

                var batches: [[DiscoverTitle]] = []
                for index in active {
                    if let page = pages[index] ?? nil {
                        self.nextPage[index] = page.page + 1
                        self.totalPages[index] = page.totalPages
                        batches.append(page.titles)
                    } else {
                        // Stop this source; others carry on
                        self.totalPages[index] = 0
                        failed = true
                    }
                }

                var fresh: [DiscoverTitle] = []
                for position in 0 ..< (batches.map(\.count).max() ?? 0) {
                    for batch in batches where position < batch.count {
                        let title = batch[position]
                        if title.backdropPath != nil, self.seen.insert(title.id).inserted {
                            fresh.append(title)
                        }
                    }
                }
                self.titles.append(contentsOf: fresh)
                added += fresh.count
            }

            guard generation == self.generation else { return }

            self.phase = failed && self.titles.isEmpty ? .failed : .loaded
            self.isLoadingMore = false
            self.task = nil
        }
    }
}

/// Category results: the combined query, its filter chips and the paged titles.
@MainActor
final class CategoryResultsViewModel: ObservableObject {

    @Published
    var query: BrowseQuery {
        didSet {
            guard query != oldValue else { return }

            // Adding a TV-only category while on Movies (or the reverse) switches back to both
            if query.kinds.isEmpty, query.media != .both {
                var both = query
                both.media = .both
                if both.kinds.isNotEmpty {
                    query.media = .both
                }
            }
            reload()
        }
    }

    let pager = DiscoverTitlePager()

    private var cancellables: Set<AnyCancellable> = []

    init(query: BrowseQuery) {
        self.query = query
        pager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        reload()
    }

    /// Movies and/or TV the current combination can return.
    var availableKinds: [DiscoverTitle.Kind] {
        query.kinds
    }

    func reload() {
        let providers = Defaults[.Discover.providers]
        let region = Defaults[.Discover.region]
        let sources: [DiscoverTitlePager.Source] = query.kinds.compactMap { kind in
            guard let parameters = query.parameters(for: kind, myProviders: providers, region: region) else { return nil }

            return { page in try await TMDBClient.shared.discover(kind: kind, query: parameters, page: page) }
        }
        pager.reset(sources)
    }

    func toggle(_ category: BrowseCategory) {
        if query.categories.contains(where: { $0.id == category.id }) {
            query.remove(category)
        } else {
            query.add(category)
        }
    }
}

/// Title search for the Categories page (debounced).
@MainActor
final class CategorySearchViewModel: ObservableObject {

    @Published
    var text = ""

    let pager = DiscoverTitlePager()

    private var cancellables: Set<AnyCancellable> = []

    var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        trimmed.count >= 2
    }

    init() {
        pager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $text
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(450), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard text.count >= 2 else {
                    self?.pager.reset([])
                    return
                }

                self?.pager.reset([{ page in try await TMDBClient.shared.search(text, page: page) }])
            }
            .store(in: &cancellables)
    }
}

extension BrowseCategory {

    /// Every category in landing-page order, with tiles for the user's services.
    static func grouped(providers: [Int], logos: [Int: String]) -> [(group: Group, categories: [BrowseCategory])] {
        let services = DiscoverProvider.supported
            .filter { providers.contains($0.id) }
            .map { BrowseCategory.service($0, logoPath: logos[$0.id]) }

        return Group.allCases.compactMap { group in
            let categories = group == .services ? services : catalog.filter { $0.group == group }
            return categories.isEmpty ? nil : (group, categories)
        }
    }
}
