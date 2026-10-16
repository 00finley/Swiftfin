//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation

/// One question to glassfin-helper and what came back, as a small state machine:
/// idle → thinking (→ waiting to retry while the helper is busy) → results, or one of the
/// friendly failure states. Menu cancels while thinking or waiting.
@MainActor
final class AskViewModel: ObservableObject {

    struct Answer: Equatable {
        let query: String
        let interpretation: String?
        /// Resolved titles in Claude's order, Not for Me titles and unresolvable picks left out
        let items: [DiscoverItem]
        let cached: Bool
    }

    enum Phase: Equatable {
        case idle
        /// Waiting for Claude (and then TMDB)
        case thinking(query: String, since: Date)
        /// 503 busy: trying again at `until`
        case waitingToRetry(query: String, until: Date)
        case results(Answer)
        /// 429: the profile's or the household's daily cap
        case capReached(resetsAt: Date?, household: Bool)
        /// Configured, but the helper didn't answer (the Mac may be asleep)
        case offline
        /// 403: not on the home network
        case notOnHomeNetwork(message: String?)
        /// 503 ask_disabled: the helper's kill switch
        case disabled(message: String?)
        case failed(message: String)

        var isWorking: Bool {
            switch self {
            case .thinking, .waitingToRetry: true
            default: false
            }
        }
    }

    @Published
    private(set) var phase: Phase = .idle
    /// Streaming badges for the result cards, loaded after the answer shows.
    @Published
    private(set) var providers: [String: [DiscoverProvider]] = [:]

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    /// The question last sent (so closing the keyboard doesn't ask the same thing twice)
    private(set) var lastAsked: String?

    private var task: Task<Void, Never>?
    private let maxBusyRetries = 5

    /// The taste payload, built when the screen opens and reused for a few minutes, so asking (and
    /// re-asking a recent question, which the helper answers from its cache) doesn't wait on it.
    private var tasteTask: Task<AskRequest.Taste, Never>?
    private var tasteStarted: Date?
    private let tasteLifetime: TimeInterval = 5 * 60

    /// Starts building the taste payload (ratings, seeds and Jellyfin history) if it isn't fresh.
    @discardableResult
    func prepareTaste() -> Task<AskRequest.Taste, Never> {
        if let tasteTask, let tasteStarted, Date.now.timeIntervalSince(tasteStarted) < tasteLifetime {
            return tasteTask
        }
        let session = userSession
        let task = Task { await AskTaste.build(client: session?.client, userID: session?.user.id) }
        tasteTask = task
        tasteStarted = .now
        return task
    }

    // MARK: - Asking

    /// Sends `text` (trimmed, at most 300 characters). A new question replaces one in flight.
    func ask(_ text: String) {
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AskGlassfin.maxQueryLength))
        guard query.isNotEmpty else { return }

        task?.cancel()
        lastAsked = query
        providers = [:]
        phase = .thinking(query: query, since: .now)

        // Badges and Request on the result cards and title pages
        SeerrStatusStore.installRequestHandler()
        DiscoverViewModel.shared.ensureLibrary()

        task = Task { [weak self] in
            await self?.run(query)
        }
    }

    /// Menu while thinking: stop waiting and go back to the suggestions (the question stays in the field).
    func cancel() {
        task?.cancel()
        task = nil
        lastAsked = nil
        phase = .idle
    }

    func retry() {
        if let lastAsked {
            ask(lastAsked)
        }
    }

    /// When the screen opens without a question: show "offline" or "turned off" before anyone types.
    func checkAvailability() {
        guard phase == .idle else { return }

        Task { [weak self] in
            let health = await AskGlassfin.health()
            guard let self, self.phase == .idle else { return }

            if health == nil {
                self.phase = .offline
            } else if health?.askEnabled == false {
                self.phase = .disabled(message: nil)
            }
        }
    }

    private func run(_ query: String) async {
        let session = userSession
        let taste = await prepareTaste().value
        guard !Task.isCancelled else { return }

        let request = AskRequest(
            query: query,
            profile: Self.profileID(session?.user.id),
            taste: taste,
            services: AskTaste.services,
            limit: AskGlassfin.resultLimit
        )

        var busyRetries = 0
        while !Task.isCancelled {
            do {
                let response: AskResponse = try await GlassfinHelperClient.shared.post("ask", body: request, as: AskResponse.self)
                guard !Task.isCancelled else { return }

                AskGlassfin.store(response.remaining)
                AskGlassfin.remember(query)
                await show(response, for: query)
                return
            } catch {
                guard !Task.isCancelled else { return }

                if case let .server(503, "busy"?, _, retryAfter)? = error as? GlassfinHelperError, busyRetries < maxBusyRetries {
                    busyRetries += 1
                    let wait = min(60, max(2, retryAfter ?? 30))
                    phase = .waitingToRetry(query: query, until: .now.addingTimeInterval(wait))
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }

                    phase = .thinking(query: query, since: .now)
                    continue
                }

                phase = Self.phase(for: error)
                if case .capReached = phase {
                    Defaults[.Discover.askRemaining] = .today(0)
                }
                return
            }
        }
    }

    private func show(_ response: AskResponse, for query: String) async {
        let resolved = await AskResolver.resolve(response.results)
        guard !Task.isCancelled else { return }

        let hidden = Defaults[.Discover.profile].hiddenKeys
        let library = DiscoverViewModel.shared.libraryItemIDs
        var seen = Set<String>()
        var items: [DiscoverItem] = []
        for (pick, title) in zip(response.results, resolved) {
            guard let title, hidden.contains(title.id) == false, seen.insert(title.id).inserted else { continue }

            let why = pick.why?.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(DiscoverItem(
                title: title,
                providers: [],
                libraryItemID: library[title.id],
                reason: why?.isEmpty == false ? why : title.year
            ))
        }

        phase = .results(Answer(
            query: query,
            interpretation: response.interpretation?.trimmingCharacters(in: .whitespacesAndNewlines),
            items: items,
            cached: response.cached == true
        ))

        await loadProviders(for: items.map(\.title))
    }

    // MARK: - Errors

    static func phase(for error: Error) -> Phase {
        guard let error = error as? GlassfinHelperError else {
            return .failed(message: L10n.askGlassfinFailed)
        }

        switch error {
        case .notConfigured, .unreachable:
            return .offline
        case .timedOut:
            return .failed(message: L10n.askGlassfinTimedOut)
        case .unauthorized:
            return .failed(message: L10n.askGlassfinUnauthorized)
        case .invalidResponse:
            return .failed(message: L10n.askGlassfinFailed)
        case let .server(status, code, message, retryAfter):
            switch (status, code) {
            case (429, _):
                return .capReached(
                    resetsAt: retryAfter.map { Date.now.addingTimeInterval($0) },
                    household: code == "daily_cap_global"
                )

            case (403, _):
                return .notOnHomeNetwork(message: message)

            case (503, "ask_disabled"?):
                return .disabled(message: message)

            case (503, "busy"?):
                return .failed(message: message ?? L10n.askGlassfinBusy)

            default:
                return .failed(message: message ?? L10n.askGlassfinFailed)
            }
        }
    }

    /// The helper accepts `[A-Za-z0-9_-]{1,64}`; Jellyfin ids are 32 hex characters (dashes dropped just in case).
    static func profileID(_ userID: String?) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let cleaned = String((userID ?? "").filter { allowed.contains($0) }.prefix(64))
        return cleaned.isEmpty ? "default" : cleaned
    }

    // MARK: - Services

    /// The user's services for the first cards (TMDB caches these for a day).
    private func loadProviders(for titles: [DiscoverTitle]) async {
        let region = Defaults[.Discover.region]
        let mine = Set(Defaults[.Discover.providers])

        await withTaskGroup(of: (String, [DiscoverProvider]).self) { group in
            for title in titles.prefix(12) {
                group.addTask {
                    let all = await (try? TMDBClient.shared.providers(for: title, region: region)) ?? []
                    return (title.id, all.filter { mine.contains($0.id) })
                }
            }
            for await (id, services) in group where !Task.isCancelled {
                providers[id] = services
            }
        }
    }
}
