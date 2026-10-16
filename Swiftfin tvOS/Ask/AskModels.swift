//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

// MARK: - Wire types (glassfin-helper `POST /ask`)

/// `POST /ask` body. See glassfin-helper's README for the contract.
struct AskRequest: Encodable, Equatable {

    struct Taste: Encodable, Equatable {
        var loved: [String] = []
        var liked: [String] = []
        var disliked: [String] = []
        var recentlyWatched: [String] = []
    }

    let query: String
    /// Jellyfin user id (`[A-Za-z0-9_-]{1,64}`)
    let profile: String
    let taste: Taste
    let services: [String]
    let limit: Int
}

/// `POST /ask` answer.
struct AskResponse: Decodable, Equatable {

    struct Result: Decodable, Hashable {
        let title: String
        let year: Int?
        /// "tv" or "movie"
        let type: String?
        let why: String?

        var kind: DiscoverTitle.Kind? {
            switch type?.lowercased() {
            case "tv", "show", "series": .tv
            case "movie", "film": .movie
            default: nil
            }
        }
    }

    struct Remaining: Decodable, Equatable {
        let profile: Int?
        let global: Int?
    }

    let interpretation: String?
    let results: [Result]
    let generatedAt: String?
    let cached: Bool?
    let remaining: Remaining?

    private enum CodingKeys: String, CodingKey {
        case interpretation
        case results
        case generatedAt
        case cached
        case remaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interpretation = try? container.decodeIfPresent(String.self, forKey: .interpretation)
        // A malformed entry shouldn't sink the whole answer
        results = (try? container.decode([FailableResult].self, forKey: .results))?.compactMap(\.value) ?? []
        generatedAt = try? container.decodeIfPresent(String.self, forKey: .generatedAt)
        cached = try? container.decodeIfPresent(Bool.self, forKey: .cached)
        remaining = try? container.decodeIfPresent(Remaining.self, forKey: .remaining)
    }

    private struct FailableResult: Decodable {
        let value: Result?

        init(from decoder: Decoder) throws {
            value = try? Result(from: decoder)
        }
    }
}

/// `GET /health` with the token (only the parts Ask Glassfin reads).
struct HelperHealth: Decodable {

    struct Usage: Decodable {
        let global: Int?
        let globalCap: Int?
        let profileCap: Int?
    }

    let ok: Bool?
    let askEnabled: Bool?
    let usageToday: Usage?

    /// Questions left today for a profile that hasn't asked yet (the per-profile cap or what's left globally).
    var freshRemaining: Int? {
        guard let usageToday, let profileCap = usageToday.profileCap else { return nil }
        guard let globalCap = usageToday.globalCap else { return profileCap }

        return max(0, min(profileCap, globalCap - (usageToday.global ?? 0)))
    }
}

// MARK: - Stored per user

/// The last `remaining` count the helper reported, for Settings ("Questions Left Today").
struct AskRemainingSnapshot: Codable, Hashable, Defaults.Serializable {

    /// What this profile can still ask today (the smaller of its own and the household's count)
    let count: Int
    /// Local day it was reported on (yyyy-MM-dd); counts reset at the Mac's midnight
    let day: String

    static func today(_ count: Int, date: Date = .now) -> AskRemainingSnapshot {
        AskRemainingSnapshot(count: count, day: dayString(date))
    }

    var isToday: Bool {
        day == Self.dayString(.now)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension Defaults.Keys.Discover {

    /// Ask Glassfin on/off (Settings → Discover); the entry points also need the helper configured.
    static var askEnabled: Defaults.Key<Bool> {
        Defaults.Key("discoverAskEnabled", default: true, suite: .currentUserSuite)
    }

    /// The last 10 questions, newest first.
    static var askHistory: Defaults.Key<[String]> {
        Defaults.Key("discoverAskHistory", default: [], suite: .currentUserSuite)
    }

    static var askRemaining: Defaults.Key<AskRemainingSnapshot?> {
        Defaults.Key("discoverAskRemaining", suite: .currentUserSuite)
    }
}

// MARK: - Feature

enum AskGlassfin {

    static let historyLimit = 10
    static let maxQueryLength = 300
    static let resultLimit = 20

    /// The helper is configured in this build (`GLASSFIN_HELPER_URL` / `GLASSFIN_HELPER_TOKEN`).
    /// Without it the Ask entry points don't appear at all.
    static var isConfigured: Bool {
        GlassfinHelperClient.isConfigured
    }

    /// Whether to show the Ask entry points (configured and turned on in Settings).
    static func isAvailable(enabled: Bool = Defaults[.Discover.askEnabled]) -> Bool {
        isConfigured && enabled
    }

    /// Adds a question to the front of the history (case-insensitive duplicates move up).
    static func remember(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return }

        var history = Defaults[.Discover.askHistory]
        history.removeAll { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        history.insert(trimmed, at: 0)
        Defaults[.Discover.askHistory] = Array(history.prefix(historyLimit))
    }

    static func store(_ remaining: AskResponse.Remaining?) {
        guard let remaining else { return }

        let counts = [remaining.profile, remaining.global].compactMap(\.self)
        guard let count = counts.min() else { return }

        Defaults[.Discover.askRemaining] = .today(max(0, count))
    }

    /// The helper's health with the token; nil when it can't be reached.
    static func health() async -> HelperHealth? {
        try? await GlassfinHelperClient.shared.get("health", timeout: 5, as: HelperHealth.self)
    }
}
