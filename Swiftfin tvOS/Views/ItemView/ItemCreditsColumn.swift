//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// "Starring Seth Rogen, Rose Byrne, Luke Macfarlane" / "Director …" at the right of the hero,
/// bottom-aligned with the buttons. Labels are 50% white and names are white, from Jellyfin People.
struct ItemCreditsColumn: View {

    let item: BaseItemDto

    private static let maximumStarring = 3

    private var starring: [String] {
        Self.names(in: item.people, kinds: [.actor, .guestStar], limit: Self.maximumStarring)
    }

    private var directors: [String] {
        Self.names(in: item.people, kinds: [.director], limit: 2)
    }

    private var creators: [String] {
        Self.names(in: item.people, kinds: [.creator], limit: 2)
    }

    static func names(in people: [BaseItemPerson]?, kinds: Set<PersonKind>, limit: Int) -> [String] {
        Array(
            (people ?? [])
                .filter { $0.type.map(kinds.contains) == true }
                .compactMap(\.name)
                .filter(\.isNotEmpty)
                .uniqued()
                .prefix(limit)
        )
    }

    private func line(_ label: String, _ names: [String]) -> Text {
        Text("\(label) ").foregroundStyle(.white.opacity(0.5)) +
            Text(names.joined(separator: ", ")).foregroundStyle(.white)
    }

    var body: some View {
        if starring.isNotEmpty || directors.isNotEmpty || creators.isNotEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if starring.isNotEmpty {
                    line(L10n.starring, starring)
                }

                if directors.isNotEmpty {
                    line(L10n.director, directors)
                } else if creators.isNotEmpty {
                    line(L10n.createdBy, creators)
                }
            }
            .font(.system(size: 27, weight: .medium))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
