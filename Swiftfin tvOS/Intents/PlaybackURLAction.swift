//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppIntents
import Foundation
import Logging

/// `glassfin://` playback actions, the same as the Siri intents:
///
/// - `glassfin://play?title=Bake%20Off` plays the best library match (resume or Next Up episode)
/// - `glassfin://play?id=<itemID>` plays that show or movie
/// - `glassfin://continue` plays the most recent in-progress video
///
/// Debug builds also run the App Intent types themselves (`glassfin://intent/play?title=...`,
/// `glassfin://intent/playvideo?term=...`, `glassfin://intent/continue`), since the Simulator has
/// no Siri and tvOS has no Shortcuts app.
enum PlaybackURLAction {

    case play(title: String)
    case playItem(id: String)
    case continueWatching
    #if DEBUG
    case intentPlay(title: String)
    case intentPlayVideo(term: String)
    case intentContinue
    #endif

    init?(_ url: URL) {
        guard ["glassfin", "swiftfin", "jellyfin"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host()?.lowercased()
        else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func query(_ name: String) -> String? {
            components?.queryItems?.first { $0.name == name }?.value?.nilIfBlank
        }

        let path = url.pathComponents.first(where: { $0 != "/" })?.lowercased()

        switch (host, path) {
        case ("play", _):
            if let id = query("id") {
                self = .playItem(id: id)
            } else if let title = query("title") {
                self = .play(title: title)
            } else {
                return nil
            }

        case ("continue", _), ("resume", _):
            self = .continueWatching

        #if DEBUG
        case ("intent", "play"):
            guard let title = query("title") else { return nil }

            self = .intentPlay(title: title)

        case ("intent", "playvideo"):
            guard let term = query("term") else { return nil }

            self = .intentPlayVideo(term: term)

        case ("intent", "continue"):
            self = .intentContinue
        #endif

        default:
            return nil
        }
    }

    @MainActor
    func perform() async {
        let logger = Logger.swiftfin()

        do {
            switch self {
            case let .play(title):
                try await IntentPlaybackLauncher.play(name: title)

            case let .playItem(id):
                try await IntentPlaybackLauncher.play(itemID: id)

            case .continueWatching:
                try await IntentPlaybackLauncher.continueWatching()

            #if DEBUG
            case let .intentPlay(title):
                // Resolve the parameter the way Siri does, through the entity query
                guard let entity = try await LibraryItemQuery().entities(matching: title).first else {
                    throw IntentPlaybackLauncher.LaunchError.noMatch(title)
                }

                logger.info("Debug: running PlayShowIntent", metadata: ["show": .string(entity.name)])
                _ = try await PlayShowIntent(show: entity).perform()

            case let .intentPlayVideo(term):
                logger.info("Debug: running PlayVideoByNameIntent", metadata: ["term": .string(term)])
                _ = try await PlayVideoByNameIntent(term: term).perform()

            case .intentContinue:
                logger.info("Debug: running ContinueWatchingIntent")
                _ = try await ContinueWatchingIntent().perform()
            #endif
            }
        } catch {
            logger.error("Playback URL action failed", metadata: ["error": .string(error.localizedDescription)])
        }
    }
}
