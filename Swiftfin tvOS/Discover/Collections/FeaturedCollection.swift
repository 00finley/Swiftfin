//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

extension Defaults.Keys.Discover {

    /// Featured holiday and seasonal collections in Categories and on Home.
    static var seasonalCollections: Defaults.Key<Bool> {
        Defaults.Key("discoverSeasonalCollections", default: true, suite: .currentUserSuite)
    }

    /// The fun and obscure days (Talk Like a Pirate Day, Back to the Future Day...) among them.
    static var funDays: Defaults.Key<Bool> {
        Defaults.Key("discoverFunDays", default: true, suite: .currentUserSuite)
    }
}

// MARK: - Calendar day

/// A day on the calendar, without a time zone, for holiday math.
struct CalendarDay: Hashable, Comparable, CustomStringConvertible {

    let year: Int
    let month: Int
    let day: Int

    /// Days since 1970-01-01.
    let ordinal: Int

    enum Weekday: Int {
        case sunday = 1
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
    }

    /// Out-of-range days roll over (Feb 30 is Mar 2).
    init(_ year: Int, _ month: Int, _ day: Int) {
        let months = year * 12 + month - 1
        let first = Self.ordinal(year: months >= 0 ? months / 12 : (months - 11) / 12, month: (months % 12 + 12) % 12 + 1, day: 1)
        self.init(ordinal: first + day - 1)
    }

    init(ordinal: Int) {
        // Howard Hinnant's civil_from_days
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        self.month = month
        self.day = day
        self.ordinal = ordinal
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// "2026-10-25"
    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1 ... 12).contains(parts[1]), (1 ... 31).contains(parts[2]) else { return nil }

        self.init(parts[0], parts[1], parts[2])
    }

    private static func ordinal(year: Int, month: Int, day: Int) -> Int {
        // Howard Hinnant's days_from_civil
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    func adding(days: Int) -> CalendarDay {
        CalendarDay(ordinal: ordinal + days)
    }

    func days(until other: CalendarDay) -> Int {
        other.ordinal - ordinal
    }

    var weekday: Weekday {
        // 1970-01-01 was a Thursday
        Weekday(rawValue: ((ordinal + 4) % 7 + 7) % 7 + 1)!
    }

    /// Noon on this day in `calendar`'s time zone (for formatting).
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysIn(month: Int, year: Int) -> Int {
        CalendarDay(year, month + 1, 1).adding(days: -1).day
    }

    /// The `n`th `weekday` of a month (1 = first); a negative `n` counts from the end (-1 = last).
    static func nth(_ n: Int, _ weekday: Weekday, month: Int, year: Int) -> CalendarDay {
        if n > 0 {
            let first = CalendarDay(year, month, 1)
            let offset = (weekday.rawValue - first.weekday.rawValue + 7) % 7
            return first.adding(days: offset + 7 * (n - 1))
        }
        let last = CalendarDay(year, month, daysIn(month: month, year: year))
        let offset = (last.weekday.rawValue - weekday.rawValue + 7) % 7
        return last.adding(days: -offset - 7 * (-n - 1))
    }

    /// Western Easter Sunday (the anonymous Gregorian computus).
    static func easter(year: Int) -> CalendarDay {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return CalendarDay(year, month, day)
    }
}

// MARK: - Lunar and announced dates

/// Dates that follow a lunar calendar or an announcement, through 2035.
enum FeaturedDateTable: Hashable {

    case lunarNewYear
    case diwali
    case oscars
    case emmys

    func day(in year: Int) -> CalendarDay? {
        switch self {
        case .lunarNewYear:
            Self.lunarNewYearDays[year].map { CalendarDay(year, $0.0, $0.1) }
        case .diwali:
            Self.diwaliDays[year].map { CalendarDay(year, $0.0, $0.1) }
        case .oscars:
            // Announced through 2028; later years estimated as the second Sunday of March
            Self.oscarsDays[year].map { CalendarDay(year, $0.0, $0.1) } ?? CalendarDay.nth(2, .sunday, month: 3, year: year)
        case .emmys:
            // Announced through 2026; later years estimated as the second Sunday of September
            Self.emmysDays[year].map { CalendarDay(year, $0.0, $0.1) } ?? CalendarDay.nth(2, .sunday, month: 9, year: year)
        }
    }

    private static let lunarNewYearDays: [Int: (Int, Int)] = [
        2025: (1, 29), 2026: (2, 17), 2027: (2, 6), 2028: (1, 26), 2029: (2, 13), 2030: (2, 3),
        2031: (1, 23), 2032: (2, 11), 2033: (1, 31), 2034: (2, 19), 2035: (2, 8),
    ]

    /// Lakshmi Puja, the main day
    private static let diwaliDays: [Int: (Int, Int)] = [
        2025: (10, 20), 2026: (11, 8), 2027: (10, 29), 2028: (10, 17), 2029: (11, 5), 2030: (10, 26),
        2031: (11, 14), 2032: (11, 2), 2033: (10, 22), 2034: (11, 10), 2035: (10, 31),
    ]

    private static let oscarsDays: [Int: (Int, Int)] = [2025: (3, 2), 2026: (3, 15), 2027: (3, 14), 2028: (3, 5)]

    private static let emmysDays: [Int: (Int, Int)] = [2025: (9, 14), 2026: (9, 14)]
}

// MARK: - Collection

/// A featured collection on Glassfin's yearly calendar (Halloween, Lunar New Year, Back to the Future Day...):
/// when it features, how it ranks against others, and the TMDB queries behind it.
struct FeaturedCollection: Identifiable, Hashable {

    enum Tier: Hashable {
        /// Holidays, heritage months and seasons
        case major
        /// Fun and obscure days, behind their own setting
        case fun
    }

    struct MonthDay: Hashable {
        let month: Int
        let day: Int

        init(_ month: Int, _ day: Int) {
            self.month = month
            self.day = day
        }
    }

    /// When the event itself happens each year.
    enum Rule: Hashable {
        /// A fixed span; one ending earlier in the year than it starts runs into the next (Dec 26–Jan 7)
        case range(from: MonthDay, through: MonthDay)
        case month(Int)
        case day(MonthDay)
        /// The `n`th weekday of a month (-1 = last), e.g. Thanksgiving
        case weekday(Int, CalendarDay.Weekday, month: Int)
        /// A week starting on the `n`th weekday of a month (Shark Week)
        case week(Int, CalendarDay.Weekday, month: Int)
        case easter
        case fridayThe13th
        case leapDay
        case table(FeaturedDateTable)
        /// Munich's 16 days: from the Saturday 15 days before October's first Sunday, through that Sunday
        /// (or October 3 when it's later)
        case oktoberfest
    }

    /// One part of a shelf's query; a shelf's parts must all match (Halloween AND Horror).
    struct Part: Hashable {
        let movie: BrowseClause?
        let tv: BrowseClause?
    }

    /// A browsable slice of the collection (Halloween: Spooky Fun, Family & Animated, Scarier).
    struct Shelf: Identifiable, Hashable {
        let id: String
        let title: String
        let parts: [Part]
    }

    let id: String
    let title: String
    let tagline: String
    let tier: Tier
    let rule: Rule
    /// Days before the event that it starts featuring
    var lead = 0
    /// Days after the event that it keeps featuring
    var trail = 0
    /// Higher wins the hero when several are active
    let priority: Int
    /// Textless art for tiles that haven't loaded the collection's own picks
    let backdropPath: String?
    /// The first is the default
    let shelves: [Shelf]
    /// Curated titles shown first, as TMDB keys ("tv-8592")
    var pins: [String] = []

    static func == (lhs: FeaturedCollection, rhs: FeaturedCollection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Queries

    /// The shelf's parts as categories, so `BrowseQuery` builds the `/discover` requests.
    func categories(for shelf: Shelf) -> [BrowseCategory] {
        shelf.parts.enumerated().map { index, part in
            BrowseCategory(
                id: "collection-\(id)-\(shelf.id)-\(index)",
                title: shelf.title,
                group: .celebrate,
                backdropPath: backdropPath,
                movie: part.movie,
                tv: part.tv
            )
        }
    }

    /// For You order, any service (titles that aren't streaming can be requested).
    func query(for shelf: Shelf, media: BrowseQuery.Media = .both) -> BrowseQuery {
        BrowseQuery(categories: categories(for: shelf), media: media, onMyServices: false, sort: .forYou)
    }

    /// Pins apply to the default shelf.
    func pins(for shelf: Shelf) -> [String] {
        shelf.id == shelves.first?.id ? pins : []
    }

    // MARK: Dates

    /// The event's days in a given year (Friday the 13th can happen up to three times; Leap Day only in leap years).
    func events(in year: Int) -> [ClosedRange<CalendarDay>] {
        func single(_ day: CalendarDay?) -> [ClosedRange<CalendarDay>] {
            day.map { [$0 ... $0] } ?? []
        }

        switch rule {
        case let .range(from, through):
            let start = CalendarDay(year, from.month, from.day)
            let wraps = (through.month, through.day) < (from.month, from.day)
            let end = CalendarDay(
                wraps ? year + 1 : year,
                through.month,
                min(through.day, CalendarDay.daysIn(month: through.month, year: wraps ? year + 1 : year))
            )
            return [start ... end]

        case let .month(month):
            return [CalendarDay(year, month, 1) ... CalendarDay(year, month, CalendarDay.daysIn(month: month, year: year))]

        case let .day(day):
            return single(CalendarDay(year, day.month, day.day))

        case let .weekday(n, weekday, month):
            return single(CalendarDay.nth(n, weekday, month: month, year: year))

        case let .week(n, weekday, month):
            let start = CalendarDay.nth(n, weekday, month: month, year: year)
            return [start ... start.adding(days: 6)]

        case .easter:
            return single(CalendarDay.easter(year: year))

        case .fridayThe13th:
            return (1 ... 12).map { CalendarDay(year, $0, 13) }.filter { $0.weekday == .friday }.map { $0 ... $0 }

        case .leapDay:
            return CalendarDay.isLeapYear(year) ? single(CalendarDay(year, 2, 29)) : []

        case let .table(table):
            return single(table.day(in: year))

        case .oktoberfest:
            let sunday = CalendarDay.nth(1, .sunday, month: 10, year: year)
            return [sunday.adding(days: -15) ... max(sunday, CalendarDay(year, 10, 3))]
        }
    }

    /// Every occurrence whose featuring window overlaps these years, in order.
    func occurrences(years: ClosedRange<Int>) -> [FeaturedOccurrence] {
        years.flatMap { events(in: $0) }
            .map { FeaturedOccurrence(
                collection: self,
                event: $0,
                window: $0.lowerBound.adding(days: -lead) ... $0.upperBound.adding(days: trail)
            ) }
            .sorted { $0.window.lowerBound < $1.window.lowerBound }
    }

    /// The occurrence featuring on `day`, if any.
    func occurrence(on day: CalendarDay) -> FeaturedOccurrence? {
        occurrences(years: day.year - 1 ... day.year + 1).first { $0.window.contains(day) }
    }

    /// The occurrence featuring on `day`, else the next one.
    func nextOccurrence(from day: CalendarDay) -> FeaturedOccurrence? {
        occurrences(years: day.year - 1 ... day.year + 8).first { $0.window.upperBound >= day }
    }
}

/// One year's occurrence of a collection.
struct FeaturedOccurrence: Identifiable, Hashable {

    let collection: FeaturedCollection
    /// The holiday itself
    let event: ClosedRange<CalendarDay>
    /// When it features: the event plus its lead and trailing days
    let window: ClosedRange<CalendarDay>

    var id: String {
        "\(collection.id)-\(event.lowerBound)"
    }

    var isSingleDay: Bool {
        event.lowerBound == event.upperBound
    }

    /// One-day holidays take the hero on the day itself and the day before.
    func isPeak(on day: CalendarDay) -> Bool {
        isSingleDay && (day == event.lowerBound || day == event.lowerBound.adding(days: -1))
    }

    /// Days between `day` and the event (0 during it).
    func distance(from day: CalendarDay) -> Int {
        if day < event.lowerBound {
            return day.days(until: event.lowerBound)
        }
        if day > event.upperBound {
            return event.upperBound.days(until: day)
        }
        return 0
    }
}

// MARK: - Schedule

enum FeaturedSchedule {

    /// Today, or in Debug builds the `-GlassfinDate 2026-10-25` launch argument.
    static var today: CalendarDay {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "GlassfinDate"), let day = CalendarDay(string: text) {
            return day
        }
        #endif
        return CalendarDay(.now)
    }

    static func collections(includeFun: Bool, from calendar: [FeaturedCollection] = FeaturedCollection.calendar) -> [FeaturedCollection] {
        calendar.filter { includeFun || $0.tier == .major }
    }

    /// Collections featuring on `day`, best first: a one-day holiday on its day or the day before,
    /// then higher priority, then the closest event, then the shorter (more specific) window.
    static func active(on day: CalendarDay, in collections: [FeaturedCollection]) -> [FeaturedOccurrence] {
        collections.compactMap { $0.occurrence(on: day) }
            .sorted { lhs, rhs in
                let left = (
                    lhs.isPeak(on: day) ? 1 : 0,
                    lhs.collection.priority,
                    -lhs.distance(from: day),
                    -lhs.window.lowerBound.days(until: lhs.window.upperBound)
                )
                let right = (
                    rhs.isPeak(on: day) ? 1 : 0,
                    rhs.collection.priority,
                    -rhs.distance(from: day),
                    -rhs.window.lowerBound.days(until: rhs.window.upperBound)
                )
                return left == right ? lhs.collection.id < rhs.collection.id : left > right
            }
    }

    /// Every collection's current or next occurrence, soonest first (featuring now comes first).
    static func upcoming(from day: CalendarDay, in collections: [FeaturedCollection]) -> [FeaturedOccurrence] {
        collections.compactMap { $0.nextOccurrence(from: day) }
            .sorted { lhs, rhs in
                let left = max(lhs.window.lowerBound, day), right = max(rhs.window.lowerBound, day)
                return left == right ? lhs.event.lowerBound < rhs.event.lowerBound : left < right
            }
    }
}
