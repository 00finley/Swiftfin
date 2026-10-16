//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Turns Claude's `{title, year, type}` picks into TMDB titles.
///
/// Each pick is searched as its own kind (`search/tv` with `first_air_date_year`, `search/movie` with
/// `year`), then without the year, then with `search/multi` (the Categories search request). The best
/// candidate wins by title similarity, then year, then kind, with popularity only breaking ties
/// ("Ghosts" 2019 is the BBC show, "Ghosts" 2021 the CBS one). Picks with no convincing match are dropped.
enum AskResolver {

    /// One resolved title per pick, in Claude's order; nil where nothing matched.
    static func resolve(_ picks: [AskResponse.Result]) async -> [DiscoverTitle?] {
        await withTaskGroup(of: (Int, DiscoverTitle?).self) { group in
            for (index, pick) in picks.enumerated() {
                group.addTask { await (index, resolve(pick)) }
            }
            var resolved = [DiscoverTitle?](repeating: nil, count: picks.count)
            for await (index, title) in group {
                resolved[index] = title
            }
            return resolved
        }
    }

    static func resolve(_ pick: AskResponse.Result) async -> DiscoverTitle? {
        let name = pick.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isNotEmpty else { return nil }

        let kinds: [DiscoverTitle.Kind] = pick.kind.map { [$0] } ?? [.tv, .movie]

        for kind in kinds {
            if let year = pick.year, let match = await best(in: search(name, kind: kind, year: year), for: pick) {
                return match
            }
            if let match = await best(in: search(name, kind: kind, year: nil), for: pick) {
                return match
            }
        }
        // Claude sometimes calls a miniseries a movie (or the other way around)
        let multi = await (try? TMDBClient.shared.search(name, page: 1).titles) ?? []
        return best(in: multi, for: pick)
    }

    // MARK: - Search

    private struct SearchResults: Decodable {
        let results: [RawTitle]
    }

    private static func search(_ name: String, kind: DiscoverTitle.Kind, year: Int?) async -> [DiscoverTitle] {
        var query = ["query": name, "page": "1", "include_adult": "false"]
        if let year {
            query[kind == .tv ? "first_air_date_year" : "year"] = String(year)
        }
        guard let data = try? await TMDBClient.shared.cachedData("search/\(kind.rawValue)", query: query),
              let decoded = try? JSONDecoder().decode(SearchResults.self, from: data)
        else { return [] }

        return decoded.results.compactMap { $0.title(defaultKind: kind) }
    }

    // MARK: - Matching

    /// The highest-scoring candidate among TMDB's first results, if it's convincing.
    static func best(in candidates: [DiscoverTitle], for pick: AskResponse.Result) -> DiscoverTitle? {
        let scored = candidates.prefix(10).map { ($0, score($0, for: pick)) }
        guard let top = scored.max(by: { $0.1 < $1.1 }) else { return nil }

        let similarity = titleSimilarity(pick.title, top.0.title)
        let yearDistance = distance(pick.year, top.0.year.flatMap(Int.init))
        // A near-exact name, or a close one from the right year
        let convincing = similarity >= 0.9 || (similarity >= 0.6 && (yearDistance ?? 9) <= 1)
        return convincing ? top.0 : nil
    }

    static func score(_ candidate: DiscoverTitle, for pick: AskResponse.Result) -> Double {
        let similarity = titleSimilarity(pick.title, candidate.title)

        var yearScore = 0.0
        if let gap = distance(pick.year, candidate.year.flatMap(Int.init)) {
            yearScore = switch gap {
            case 0: 1
            case 1: 0.6
            case 2: 0.2
            default: -0.5
            }
        }

        let kindScore = pick.kind == nil || pick.kind == candidate.kind ? 0.3 : 0
        let popularity = min(1, log10(1 + candidate.popularity) / 3) * 0.15
        let votes = min(1, Double(candidate.voteCount) / 200) * 0.1
        let art = candidate.backdropPath == nil ? -0.1 : 0

        return 3 * similarity + yearScore + kindScore + popularity + votes + art
    }

    private static func distance(_ lhs: Int?, _ rhs: Int?) -> Int? {
        guard let lhs, let rhs else { return nil }

        return abs(lhs - rhs)
    }

    /// 1 for the same name (ignoring case, accents, punctuation, "&"/"and" and a leading "The"),
    /// otherwise how many words the two share, discounted when one only contains the other.
    static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalized(lhs)
        let b = normalized(rhs)
        guard a.isNotEmpty, b.isNotEmpty else { return 0 }

        if a == b {
            return 1
        }
        if a.replacing(" ", with: "") == b.replacingOccurrences(of: " ", with: "") {
            return 0.97
        }

        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        let shared = Double(wordsA.intersection(wordsB).count)
        let jaccard = shared / Double(wordsA.union(wordsB).count)

        // "Shogun" vs "Shogun 2024 Special": containment counts, but less than equality
        let contained = wordsA.isSubset(of: wordsB) || wordsB.isSubset(of: wordsA)
        return contained ? max(jaccard, 0.6 + 0.3 * jaccard) : jaccard
    }

    static func normalized(_ text: String) -> String {
        DiscoverTaste.normalized(text.replacing("&", with: " and "))
    }
}
