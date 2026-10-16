//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A person matched by a title search (e.g. "Pedro Pascal").
struct TMDBSearchPerson: Hashable, Identifiable {

    let id: Int
    let name: String
    /// "Acting", "Directing", "Writing"...
    let department: String?
}

/// TMDB search for the Search tab: titles plus the person the query names, if any.
///
/// Uses the same `search/multi` request (and so the same cache entry) as `TMDBClient.search`,
/// which the Categories search field pages through.
enum TMDBSearch {

    struct Result: Hashable {
        /// Movies and shows in TMDB's relevance order.
        let titles: [DiscoverTitle]
        let person: TMDBSearchPerson?
    }

    static func search(_ text: String) async throws -> Result {
        let data = try await TMDBClient.shared.cachedData("search/multi", query: [
            "query": text,
            "page": "1",
            "include_adult": "false",
        ])

        let titles = try JSONDecoder().decode(TitleList.self, from: data).results.compactMap { $0.title(defaultKind: nil) }
        let entries = try JSONDecoder().decode(EntryList.self, from: data).results

        return Result(titles: titles, person: person(in: entries, matching: text))
    }

    /// The person's best-known movies and shows: acting roles for actors, directing and
    /// writing credits otherwise. Talk shows, news and appearances as themselves are left out.
    static func credits(for person: TMDBSearchPerson) async throws -> [DiscoverTitle] {
        let data = try await TMDBClient.shared.cachedData("person/\(person.id)/combined_credits")
        let titles = try JSONDecoder().decode(CreditTitles.self, from: data)
        let meta = try JSONDecoder().decode(CreditMeta.self, from: data)

        let isActor = person.department == nil || person.department == "Acting"
        let pairs: [(RawTitle, CreditMeta.Entry)] = isActor
            ? Array(zip(titles.cast, meta.cast))
            : Array(zip(titles.crew, meta.crew)).filter { creatorJobs.contains($0.1.job ?? "") }

        var seen = Set<String>()
        return pairs
            .filter { _, entry in
                let genres = Set(entry.genre_ids ?? [])
                let character = (entry.character ?? "").lowercased()
                return genres.isDisjoint(with: excludedGenres) && selfRoles.contains { character.contains($0) } == false
            }
            .compactMap { raw, _ in raw.title(defaultKind: nil) }
            .filter { $0.backdropPath != nil && $0.voteCount >= 10 }
            .sorted { $0.popularity > $1.popularity }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: - Matching

    /// The person a query is about: TMDB's top result when it's a person, or an exact name match.
    private static func person(in entries: [Entry], matching text: String) -> TMDBSearchPerson? {
        let query = normalized(text)
        guard query.count >= 4 else { return nil }

        let people = entries.filter { $0.media_type == "person" && $0.name?.isEmpty == false }
        let match = people.first { normalized($0.name ?? "") == query }
            ?? (entries.first?.media_type == "person" && normalized(entries.first?.name ?? "").hasPrefix(query) ? entries.first : nil)

        guard let match, let name = match.name else { return nil }

        return TMDBSearchPerson(id: match.id, name: name, department: match.known_for_department)
    }

    /// Lowercased, accent-free letters and digits ("Amélie!" → "amelie").
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static let creatorJobs: Set<String> = ["Director", "Creator", "Writer", "Screenplay", "Novel"]
    /// Talk, News
    private static let excludedGenres: Set<Int> = [10767, 10763]
    private static let selfRoles = ["self", "himself", "herself", "themselves", "uncredited"]

    // MARK: - Response types

    private struct TitleList: Decodable {
        let results: [RawTitle]
    }

    private struct EntryList: Decodable {
        let results: [Entry]
    }

    private struct Entry: Decodable {
        let id: Int
        let media_type: String?
        let name: String?
        let known_for_department: String?
    }

    private struct CreditTitles: Decodable {
        let cast: [RawTitle]
        let crew: [RawTitle]
    }

    private struct CreditMeta: Decodable {

        struct Entry: Decodable {
            let character: String?
            let job: String?
            let genre_ids: [Int]?
        }

        let cast: [Entry]
        let crew: [Entry]
    }
}
