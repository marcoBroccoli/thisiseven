import Foundation

public extension Calendar {
    /// Household civil calendar — matches `Amsterdam` in `backend/internal/api/types.go`.
    /// "Today", due phrases, and week tips are computed in this zone.
    static let evenHousehold: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")
            ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Formats a date as a civil `yyyy-MM-dd` in this calendar's time zone.
    /// Prefer this over `ISO8601DateFormatter` for date-only values — that
    /// formatter defaults to GMT and shifts local midnights into the previous day.
    func evenCivilDateString(from date: Date) -> String {
        evenCivilDateFormatter.string(from: date)
    }

    /// Parses a civil `yyyy-MM-dd` as start-of-day in this calendar's time zone.
    func evenParseCivilDate(_ string: String) -> Date? {
        evenCivilDateFormatter.date(from: string)
    }

    private var evenCivilDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = self
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
