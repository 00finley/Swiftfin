//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What Discover knows about the user's taste, for ranking any list of TMDB titles
/// (Categories "For You" and search).
///
/// Built from watch history, ratings (including the seed list) and older genre feedback:
/// - **genre** and **keyword** affinity, roughly -1...1, weighted by how much each title counts
///   (finished or favorited history, Love It 1.4, Like It 0.8, Not for Me -0.8);
/// - **related**: titles TMDB recommends for the strongest seeds, 0...1.
struct DiscoverTaste {

    var genre: [Int: Double] = [:]
    var keyword: [Int: Double] = [:]
    var related: [String: Double] = [:]
    var libraryKeys: Set<String> = []
    /// Finished in Jellyfin or rated (rating a title means you've seen it)
    var watchedKeys: Set<String> = []
    var hiddenKeys: Set<String> = []

    var hasSignal: Bool {
        genre.isNotEmpty || keyword.isNotEmpty || related.isNotEmpty
    }

    // MARK: - Building

    /// One title's contribution: its genres and keywords, weighted (negative for dislikes).
    struct Source {
        let genres: [Int]
        let keywords: [Int]
        let weight: Double
    }

    mutating func learn(from sources: [Source], genreFeedback: [Int: Double]) {
        let totalWeight = max(1, sources.map { abs($0.weight) }.reduce(0, +))

        var genres: [Int: Double] = [:]
        var keywords: [Int: Double] = [:]
        var keywordSeeds: [Int: Int] = [:]
        for source in sources {
            for id in source.genres {
                genres[id, default: 0] += source.weight / totalWeight
            }
            for id in source.keywords {
                keywords[id, default: 0] += source.weight
                keywordSeeds[id, default: 0] += 1
            }
        }

        // Genres: the share of weight, stretched so the favorite genre is near 1
        let topGenre = genres.values.max() ?? 0
        let genreScale = topGenre > 0 ? min(3, 0.9 / topGenre) : 1
        for (id, value) in genres {
            genre[id] = value * genreScale
        }
        for (id, adjustment) in genreFeedback {
            genre[id, default: 0] += adjustment
        }
        genre = genre.mapValues { max(-1, min(1, $0)) }

        // Keywords: relative to the strongest; with enough titles, one-off keywords are noise
        let requiredSeeds = sources.count >= 6 ? 2 : 1
        let topKeyword = keywords.values.map(abs).max() ?? 0
        guard topKeyword > 0 else { return }

        for (id, value) in keywords where keywordSeeds[id, default: 0] >= requiredSeeds {
            keyword[id] = max(-1, min(1, value / topKeyword))
        }
    }

    // MARK: - Scoring

    /// Genre fit, -1...1: the mean over the title's genres, softened for many-genre titles.
    func genreScore(_ title: DiscoverTitle) -> Double {
        let values = title.genreIDs.map { genre[$0] ?? 0 }
        guard values.isNotEmpty else { return 0 }

        return max(-1, min(1, values.reduce(0, +) / Double(values.count).squareRoot()))
    }

    /// Keyword fit, -1...1 (0 when the title's keywords aren't known).
    func keywordScore(_ keywords: [Int]?) -> Double {
        guard let keywords, keywords.isNotEmpty else { return 0 }

        return max(-1, min(1, keywords.map { keyword[$0] ?? 0 }.reduce(0, +) / 2))
    }

    /// How well a title fits, about -1...1.6, before quality.
    func affinity(_ title: DiscoverTitle, keywords: [Int]? = nil) -> Double {
        0.9 * genreScore(title) + 0.7 * keywordScore(keywords) + 1.2 * (related[title.id] ?? 0)
    }

    /// "For You" order for one batch of TMDB results (which arrive in popularity order).
    ///
    /// score = 1.5 × affinity (scaled down for titles with few votes, so obscure ones can't ride
    /// affinity alone) + 0.8 × rating (vote average × vote confidence) + 0.4 × popularity (log)
    /// + 0.5 × the title's position in TMDB's order; watched titles −1.2, in-library −0.5.
    func forYouOrder(_ titles: [DiscoverTitle], keywords: [String: [Int]] = [:]) -> [DiscoverTitle] {
        let count = max(1, titles.count - 1)
        let scored = titles.enumerated().map { index, title -> (DiscoverTitle, Double) in
            let confidence = min(1, Double(title.voteCount) / 150)
            let quality = title.voteAverage / 10 * confidence
            let popularity = min(1, log10(1 + title.popularity) / 3)
            let position = 1 - Double(index) / Double(count)

            var fit = affinity(title, keywords: keywords[title.id])
            if fit > 0 {
                fit *= 0.3 + 0.7 * confidence
            }

            var score = 1.5 * fit + 0.8 * quality + 0.4 * popularity + 0.5 * position
            if watchedKeys.contains(title.id) {
                score -= 1.2
            } else if libraryKeys.contains(title.id) {
                score -= 0.5
            }
            return (title, score)
        }
        return stableSorted(scored)
    }

    /// Search order: exact title matches, then titles starting with the text, then the rest;
    /// within each, TMDB's relevance with a gentle nudge (a few places at most) toward the user's taste.
    func searchOrder(_ titles: [DiscoverTitle], query: String) -> [DiscoverTitle] {
        let needle = Self.normalized(query)
        let scored = titles.enumerated().map { index, title -> (DiscoverTitle, Double) in
            let name = Self.normalized(title.title)
            let tier: Double = name == needle ? 0 : (name.hasPrefix(needle) ? 1 : 2)
            let confidence = min(1, Double(title.voteCount) / 150)
            let nudge = 3 * max(0, min(1, affinity(title))) * confidence + 1.5 * title.voteAverage / 10 * confidence
            // Lower is better: tier dominates, then position less the nudge
            return (title, -(tier * 1000 + Double(index) - nudge))
        }
        return stableSorted(scored)
    }

    private func stableSorted(_ scored: [(DiscoverTitle, Double)]) -> [DiscoverTitle] {
        scored.enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1 ? lhs.offset < rhs.offset : lhs.element.1 > rhs.element.1
            }
            .map(\.element.0)
    }

    /// Lowercased, accents and punctuation removed, leading "the/a/an" dropped.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter(\.isNotEmpty)
        let trimmed = words.first.map { ["the", "a", "an"].contains($0) } == true && words.count > 1 ? Array(words.dropFirst()) : words
        return trimmed.joined(separator: " ")
    }
}
