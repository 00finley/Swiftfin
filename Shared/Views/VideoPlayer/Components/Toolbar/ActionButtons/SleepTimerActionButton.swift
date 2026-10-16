//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    /// "Sleep Timer" in the player's "..." menu: Off, End of this episode, 15, 30, 45 or 60 minutes.
    struct SleepTimerMenu: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        var body: some View {
            Content(sleepTimer: manager.sleepTimer, isEpisode: manager.item.type == .episode)
        }
    }

    private struct Content: View {

        private static let offID = "off"

        @ObservedObject
        var sleepTimer: SleepTimer

        let isEpisode: Bool

        private var options: [SleepTimer.Option] {
            SleepTimer.Option.presets.filter { isEpisode || $0 != .endOfEpisode }
        }

        private var selection: Binding<String> {
            Binding(
                get: { sleepTimer.option?.id ?? Self.offID },
                set: { newID in
                    sleepTimer.set(SleepTimer.Option.presets.first { $0.id == newID })
                }
            )
        }

        var body: some View {
            Menu {
                Picker(L10n.sleepTimer, selection: selection) {
                    Text(L10n.sleepTimerOff)
                        .tag(Self.offID)

                    ForEach(options) { option in
                        Text(option.displayTitle)
                            .tag(option.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(L10n.sleepTimer)

                if let remainingLabel = sleepTimer.remainingLabel {
                    Text(remainingLabel)
                }

                Image(systemName: sleepTimer.option == nil ? "moon.zzz" : "moon.zzz.fill")
            }
        }
    }
}
