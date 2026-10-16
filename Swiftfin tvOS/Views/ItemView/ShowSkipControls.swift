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

/// The show's intro / credits rule as two rows of glass choices ("Intro: Skip / Watch",
/// "Credits: Skip / Watch"). The chosen option is white with a dark label, like the rating control
/// on Discover title pages.
struct ShowSkipControls: View {

    enum Control: Hashable {
        case intro(ShowSkipChoice)
        case credits(ShowSkipChoice)
    }

    let seriesID: String
    let seriesName: String
    let providerIDs: [String: String]?
    let focus: FocusState<Control?>.Binding

    /// Observed so the controls follow changes from elsewhere (Settings > Show Exceptions)
    @Default(.VideoPlayer.MediaSegments.showRules)
    private var rules

    private var rule: ResolvedShowSkipRule {
        _ = rules
        return ShowSkipRules.resolve(seriesID: seriesID, providerIDs: providerIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            row(L10n.intro, type: .intro, selection: rule.intro, control: Control.intro)
            row(L10n.credits, type: .outro, selection: rule.credits, control: Control.credits)
        }
    }

    private func row(
        _ title: String,
        type: MediaSegmentType,
        selection: ShowSkipChoice,
        control: @escaping (ShowSkipChoice) -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 130, alignment: .leading)

            ForEach(ShowSkipChoice.allCases, id: \.self) { choice in
                let isSelected = choice == selection

                Button {
                    ShowSkipRules.set(
                        choice,
                        for: type,
                        seriesID: seriesID,
                        seriesName: seriesName,
                        providerIDs: providerIDs
                    )
                } label: {
                    Label(choice.displayTitle, systemImage: isSelected ? "checkmark" : choice.systemImage)
                }
                .buttonStyle(GlassChipButtonStyle(isSelected: isSelected, solidSelection: true))
                .focused(focus, equals: control(choice))
                .accessibilityLabel("\(title), \(choice.displayTitle)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("showSkip.\(type == .intro ? "intro" : "credits").\(choice.rawValue)")
            }
        }
    }
}

extension ShowSkipChoice {

    var systemImage: String {
        switch self {
        case .skip:
            "forward.fill"
        case .watch:
            "eye"
        }
    }
}
