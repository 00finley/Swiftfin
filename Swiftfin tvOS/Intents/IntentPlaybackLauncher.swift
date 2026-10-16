//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// Finds shows and movies by name and starts playback for Siri / App Intents and `glassfin://` URL
/// actions, through the same route the Play button uses.
@MainActor
enum IntentPlaybackLauncher {

    enum LaunchError: Error, LocalizedError {
        case notSignedIn
        case noMatch(String)
        case nothingToResume
        case notPlayable(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "Open Glassfin and sign in first."
            case let .noMatch(name):
                "Couldn't find \"\(name)\" in your library."
            case .nothingToResume:
                "There's nothing to continue watching."
            case let .notPlayable(name):
                "\(name) has nothing to play."
            }
        }
    }

    private static let logger = Logger.swiftfin()

    // MARK: - Session

    /// The signed-in session, waiting briefly while the app launches and restores it.
    static func userSession(timeout: Duration = .seconds(10)) async throws -> UserSession {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if let session = Container.shared.userSessionManager().currentSession {
                return session
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        throw LaunchError.notSignedIn
    }

    /// Waits until the signed-in tabs are on screen so a route has somewhere to go.
    private static func waitForMainTabs(timeout: Duration = .seconds(10)) async {
        let deadline = ContinuousClock.now + timeout

        while TabCoordinator.current == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Library

    /// Every show and movie in the library (names only), for matching spoken titles.
    static func libraryTitles(userSession: UserSession) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userSession.user.id
        parameters.includeItemTypes = [.series, .movie]
        parameters.isRecursive = true
        parameters.sortBy = [.sortName]
        parameters.enableImages = false
        parameters.enableUserData = false

        let response = try await userSession.client.send(Paths.getItems(parameters: parameters))
        return response.value.items ?? []
    }

    /// Shows and movies matching a spoken or typed name, best first (fuzzy and case-insensitive).
    static func search(_ name: String, userSession: UserSession, limit: Int = 10) async throws -> [BaseItemDto] {
        let titles = try await libraryTitles(userSession: userSession)

        return TitleMatcher.rank(name, in: titles, title: { $0.displayTitle })
            .prefix(limit)
            .map(\.self)
    }

    /// Shows and movies to offer Siri: what's in progress or up next first, then the rest of the library.
    static func suggestions(userSession: UserSession, limit: Int = 50) async throws -> [BaseItemDto] {
        let inProgress = try await continueWatchingItems(userSession: userSession, limit: 20)
            .compactMap { item -> BaseItemDto? in
                guard item.type == .episode else { return item }

                return BaseItemDto(id: item.seriesID, name: item.seriesName, type: .series)
            }
        let library = try await libraryTitles(userSession: userSession)

        var seen = Set<String>()
        return (inProgress + library)
            .filter { $0.id != nil && seen.insert($0.id!).inserted }
            .prefix(limit)
            .map(\.self)
    }

    // MARK: - Choosing what to play

    /// In-progress videos, most recently watched first.
    static func continueWatchingItems(userSession: UserSession, limit: Int = 1) async throws -> [BaseItemDto] {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.userID = userSession.user.id
        parameters.mediaTypes = [.video]
        parameters.enableUserData = true
        parameters.limit = limit

        let response = try await userSession.client.send(Paths.getResumeItems(parameters: parameters))

        return (response.value.items ?? []).sorted {
            ($0.userData?.lastPlayedDate ?? .distantPast) > ($1.userData?.lastPlayedDate ?? .distantPast)
        }
    }

    /// For a show: the episode in progress, else Next Up, else the first episode. A movie plays itself
    /// (from its saved position).
    static func playbackTarget(for item: BaseItemDto, userSession: UserSession) async throws -> BaseItemDto? {
        guard item.type == .series else { return item }

        let client = userSession.client

        var resumeParameters = Paths.GetResumeItemsParameters()
        resumeParameters.userID = userSession.user.id
        resumeParameters.parentID = item.id
        // Without these the server can answer with the season folder
        resumeParameters.includeItemTypes = [.episode]
        resumeParameters.mediaTypes = [.video]
        resumeParameters.enableUserData = true
        resumeParameters.limit = 1
        if let resume = try await client.send(Paths.getResumeItems(parameters: resumeParameters)).value.items?.first {
            return resume
        }

        var nextUpParameters = Paths.GetNextUpParameters()
        nextUpParameters.userID = userSession.user.id
        nextUpParameters.seriesID = item.id
        nextUpParameters.enableRewatching = true
        if let nextUp = try await client.send(Paths.getNextUp(parameters: nextUpParameters)).value.items?.first,
           !nextUp.isMissing
        {
            return nextUp
        }

        var firstParameters = Paths.GetItemsParameters()
        firstParameters.userID = userSession.user.id
        firstParameters.parentID = item.id
        firstParameters.includeItemTypes = [.episode]
        firstParameters.isMissing = false
        firstParameters.isRecursive = true
        firstParameters.limit = 1
        firstParameters.sortOrder = [.ascending]

        return try await client.send(Paths.getItems(parameters: firstParameters)).value.items?.first
    }

    // MARK: - Playing

    /// Plays the show or movie with this ID (the resume or Next Up episode for a show).
    @discardableResult
    static func play(itemID: String, name: String? = nil) async throws -> BaseItemDto {
        let userSession = try await userSession()
        let item = try await userSession.getFullItem(id: itemID).snapshot

        guard let target = try await playbackTarget(for: item, userSession: userSession) else {
            throw LaunchError.notPlayable(name ?? item.displayTitle)
        }

        try await startPlayback(of: target, userSession: userSession)
        return target
    }

    /// Plays the best library match for a name.
    @discardableResult
    static func play(name: String) async throws -> BaseItemDto {
        let userSession = try await userSession()

        guard let match = try await search(name, userSession: userSession, limit: 1).first, let id = match.id else {
            throw LaunchError.noMatch(name)
        }

        logger.info("Intent matched a title", metadata: ["query": .string(name), "match": .string(match.displayTitle)])

        return try await play(itemID: id, name: match.displayTitle)
    }

    /// Plays the most recently watched in-progress video.
    @discardableResult
    static func continueWatching() async throws -> BaseItemDto {
        let userSession = try await userSession()

        guard let item = try await continueWatchingItems(userSession: userSession, limit: 1).first else {
            throw LaunchError.nothingToResume
        }

        try await startPlayback(of: item, userSession: userSession)
        return item
    }

    /// Presents the player the way the item page's Play button does (episodes get the episode queue,
    /// so next episode autoplay works).
    private static func startPlayback(of item: BaseItemDto, userSession: UserSession) async throws {
        let entry = try await userSession.getFullItem(id: item.id)

        // Keep the record alive until the playback provider takes ownership
        guard let provider = withExtendedLifetime(entry, {
            entry.snapshot.getPlaybackItemProvider(userSession: userSession)
        }) else {
            throw LaunchError.notPlayable(item.displayTitle)
        }

        let snapshot = entry.snapshot

        // A full-screen player already on screen stops first (Picture in Picture is replaced by the route)
        if let current = MediaPlayerManager.presented,
           current.state != .stopped,
           !PictureInPictureSession.shared.isHolding(current)
        {
            await current.stop()
            try? await Task.sleep(for: .milliseconds(800))
        }

        await waitForMainTabs()

        logger.info(
            "Starting playback from an intent",
            metadata: ["itemID": .string(snapshot.id ?? ""), "title": .string(snapshot.displayTitle)]
        )

        Container.shared.userSessionManager().routePublisher.send(
            .videoPlayer(
                provider: provider,
                queue: snapshot.type == .episode ? EpisodeMediaPlayerQueue(episode: snapshot) : nil
            )
        )
    }
}

// MARK: - Matching

/// Ranks titles against a spoken name: exact, then prefix, then containment, then word overlap and
/// edit distance, ignoring case, accents, punctuation and a leading "The".
enum TitleMatcher {

    static func normalize(_ string: String) -> String {
        let folded = string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacing("&", with: " and ")
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var words = String(cleaned).split(separator: " ").map(String.init)

        if words.first == "the", words.count > 1 {
            words.removeFirst()
        }

        return words.joined(separator: " ")
    }

    /// 0 (no match) ... 1 (exact)
    static func score(_ query: String, _ title: String) -> Double {
        let q = normalize(query), t = normalize(title)
        guard !q.isEmpty, !t.isEmpty else { return 0 }

        if q == t {
            return 1
        }
        if t.hasPrefix(q) {
            return 0.9
        }
        if t.contains(q) {
            return 0.8
        }
        if q.contains(t) {
            return 0.7
        }

        let queryWords = Set(q.split(separator: " ")), titleWords = Set(t.split(separator: " "))
        let overlap = Double(queryWords.intersection(titleWords).count) / Double(max(queryWords.count, 1))

        let distance = Double(editDistance(Array(q), Array(t)))
        let similarity = 1 - distance / Double(max(q.count, t.count))

        return max(overlap * 0.75, similarity * 0.7)
    }

    static func rank<T>(_ query: String, in items: [T], title: (T) -> String, minimumScore: Double = 0.45) -> [T] {
        items
            .map { (item: $0, score: score(query, title($0))) }
            .filter { $0.score >= minimumScore }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0 ... b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1 ... a.count {
            current[0] = i
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }
}
