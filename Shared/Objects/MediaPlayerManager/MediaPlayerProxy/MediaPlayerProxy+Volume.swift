//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import SwiftVLC

// Volume control for the sleep timer's fade out

extension AVMediaPlayerProxy: MediaPlayerVolumeConfigurable {

    func setVolume(_ volume: Float) {
        player.volume = max(0, min(1, volume))
    }
}

extension VLCMediaPlayerProxy: MediaPlayerVolumeConfigurable {

    func setVolume(_ volume: Float) {
        try? player.setAudioVolume(Volume(max(0, min(1, volume))))
    }
}
