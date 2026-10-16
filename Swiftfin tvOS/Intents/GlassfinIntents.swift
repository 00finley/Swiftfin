//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppIntents
import JellyfinAPI

// Siri and App Intents: "Play The Diplomat in Glassfin", "Resume Bake Off in Glassfin",
// "Continue watching in Glassfin". All of them open the app and play through the normal player.

// MARK: - Library item entity

/// A show or movie in the signed-in Jellyfin library, so Siri can suggest and resolve titles.
struct LibraryItemEntity: AppEntity {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show or Movie"
    static let defaultQuery = LibraryItemQuery()

    let id: String
    let name: String
    let isMovie: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: isMovie ? "Movie" : "TV Show"
        )
    }

    init(id: String, name: String, isMovie: Bool) {
        self.id = id
        self.name = name
        self.isMovie = isMovie
    }

    init?(_ item: BaseItemDto) {
        guard let id = item.id else { return nil }

        self.init(id: id, name: item.displayTitle, isMovie: item.type == .movie)
    }
}

/// Matches spoken names against the library (fuzzy, case-insensitive) and suggests what's in progress first.
struct LibraryItemQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [LibraryItemEntity.ID]) async throws -> [LibraryItemEntity] {
        let userSession = try await IntentPlaybackLauncher.userSession()
        let titles = try await IntentPlaybackLauncher.libraryTitles(userSession: userSession)
        let byID = Dictionary(titles.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { first, _ in first })

        return identifiers.compactMap { byID[$0].flatMap(LibraryItemEntity.init) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LibraryItemEntity] {
        let userSession = try await IntentPlaybackLauncher.userSession()

        return try await IntentPlaybackLauncher.search(string, userSession: userSession)
            .compactMap(LibraryItemEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [LibraryItemEntity] {
        let userSession = try await IntentPlaybackLauncher.userSession()

        return try await IntentPlaybackLauncher.suggestions(userSession: userSession)
            .compactMap(LibraryItemEntity.init)
    }
}

// MARK: - Intents

/// Plays a show (its in-progress or Next Up episode) or a movie.
struct PlayShowIntent: AppIntent {

    static let title: LocalizedStringResource = "Play Show or Movie"
    static let description = IntentDescription("Plays the next episode of a show, or a movie, from your Jellyfin library.")
    static let openAppWhenRun = true

    @Parameter(title: "Show or Movie", requestValueDialog: "Which show or movie?")
    var show: LibraryItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$show)")
    }

    init() {}

    init(show: LibraryItemEntity) {
        self.show = show
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentPlaybackLauncher.play(itemID: show.id, name: show.name)
        return .result()
    }
}

/// Plays the most recently watched in-progress video.
struct ContinueWatchingIntent: AppIntent {

    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Resumes what you watched most recently.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentPlaybackLauncher.continueWatching()
        return .result()
    }
}

/// The system "play video" intent (tvOS 17.2+): Siri passes the spoken title as free text, which is
/// matched against the library like `PlayShowIntent`.
struct PlayVideoByNameIntent: PlayVideoIntent {

    static let title: LocalizedStringResource = "Play Video"
    static let supportedCategories: [VideoCategory] = [.tv, .movies]

    @Parameter(title: "Title")
    var term: String

    init() {}

    init(term: String) {
        self.term = term
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentPlaybackLauncher.play(name: term)
        return .result()
    }
}

// MARK: - App Shortcuts

/// Phrases Siri recognizes without any setup. Each must contain the app name.
struct GlassfinShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayShowIntent(),
            phrases: [
                "Play \(\.$show) in \(.applicationName)",
                "Play \(\.$show) on \(.applicationName)",
                "Watch \(\.$show) in \(.applicationName)",
                "Watch \(\.$show) on \(.applicationName)",
                "Resume \(\.$show) in \(.applicationName)",
                "Resume \(\.$show) on \(.applicationName)",
                "Continue \(\.$show) in \(.applicationName)",
                "Play a show in \(.applicationName)",
                "Watch something in \(.applicationName)",
            ],
            shortTitle: "Play Show",
            systemImageName: "play.tv"
        )

        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Continue watching in \(.applicationName)",
                "Continue watching on \(.applicationName)",
                "Resume watching in \(.applicationName)",
                "Keep watching in \(.applicationName)",
                "Resume \(.applicationName)",
            ],
            shortTitle: "Continue Watching",
            systemImageName: "play.circle"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .navy
}
