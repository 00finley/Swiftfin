//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import UIKit

/// The color wash behind an item page, taken from its artwork and cached per item.
///
/// The artwork's dominant color is darkened until white text over it keeps at least 7:1 contrast
/// (WCAG AAA, the HIG's Dark Mode target), so the wash tints the page without hurting legibility.
@MainActor
final class ArtworkColorStore: ObservableObject {

    static let shared = ArtworkColorStore()

    /// Highest relative luminance for the wash: (1.0 + 0.05) / (0.1 + 0.05) = 7:1 against white
    nonisolated static let maximumLuminance: CGFloat = 0.1

    @Published
    private(set) var colors: [String: Color] = [:]

    private var resolving: Set<String> = []

    func color(for key: String?) -> Color? {
        key.flatMap { colors[$0] }
    }

    /// Computes the wash color for `key` from `image` once; later calls use the cache.
    func resolve(_ key: String?, from image: UIImage) {
        guard let key, colors[key] == nil, resolving.insert(key).inserted else { return }

        Task.detached(priority: .utility) {
            let color = image.interestingColor().map { Self.washColor(from: UIColor($0)) }

            await MainActor.run {
                self.resolving.remove(key)
                if let color {
                    self.colors[key] = Color(uiColor: color)
                }
            }
        }
    }

    /// Keeps the hue, tames the saturation and lowers the brightness until the luminance is low
    /// enough for white text.
    nonisolated static func washColor(from color: UIColor) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        saturation = min(max(saturation * 1.1, 0.25), 0.7)
        brightness = min(brightness, 0.6)

        var result = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        while relativeLuminance(of: result) > maximumLuminance, brightness > 0.05 {
            brightness -= 0.02
            result = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        }

        return result
    }

    nonisolated static func relativeLuminance(of color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
