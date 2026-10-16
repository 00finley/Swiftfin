//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// "Now" for date-dependent features (Your Year in Glassfin is featured in December).
///
/// Debug builds accept a `-GlassfinDate yyyy-MM-dd` launch argument (or a full ISO 8601 date) to
/// pretend it's another day, e.g. `-GlassfinDate 2026-12-05` to see December's Home.
enum GlassfinDate {

    static var now: Date {
        #if DEBUG
        if let override {
            return override
        }
        #endif
        return .now
    }

    #if DEBUG
    /// Launch arguments land in UserDefaults' argument domain.
    static let override: Date? = {
        guard let text = UserDefaults.standard.string(forKey: "GlassfinDate")?.trimmingCharacters(in: .whitespaces),
              text.isNotEmpty
        else { return nil }

        if let date = ISO8601DateFormatter().date(from: text) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: text) else { return nil }

        // The given day at the current time of day, so "today" math still moves
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: .now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }()
    #endif
}
