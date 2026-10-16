//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

extension DiscoverTitle {

    /// A library show or movie as a Discover title, via its TMDB provider id.
    init?(libraryItem item: BaseItemDto) {
        guard item.type == .series || item.type == .movie,
              let tmdbID = item.providerIDs?["Tmdb"].flatMap(Int.init)
        else { return nil }

        self.init(
            kind: item.type == .movie ? .movie : .tv,
            tmdbID: tmdbID,
            title: item.displayTitle,
            overview: item.overview,
            backdropPath: nil,
            posterPath: nil,
            date: item.premiereDate.map { DiscoverTitle.dateFormatter.string(from: $0) },
            genreIDs: [],
            popularity: 0,
            voteAverage: 0,
            voteCount: 0
        )
    }
}

/// The rating menu on library show and movie pages: the same four choices as Discover,
/// stored in the Discover profile by TMDB id.
struct DiscoverLibraryRatingMenu<Label: View>: View {

    let title: DiscoverTitle
    let label: (DiscoverRatingLevel) -> Label

    @Default(.Discover.profile)
    private var profile

    var body: some View {
        // It's OK is checked only when it overrides a seeded rating
        let rated = profile.level(for: title.id)
        let current: DiscoverRatingLevel? = rated == .neutral && profile.ratings[title.id] == nil ? nil : rated

        Menu {
            ForEach(DiscoverRatingLevel.displayOrder, id: \.self) { level in
                Button(
                    level.title,
                    systemImage: level == current ? "checkmark" : level.systemImage,
                    role: level == .disliked ? .destructive : nil
                ) {
                    DiscoverViewModel.shared.rate(title, level)
                }
            }
        } label: {
            label(rated)
        }
        .accessibilityLabel(L10n.discoverRate)
        .accessibilityValue(rated.title)
    }
}
