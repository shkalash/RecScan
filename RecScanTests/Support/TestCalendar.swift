import Foundation

/// Calendars and dates fixed against a known timezone.
///
/// Date-boundary assertions are meaningless if the calendar drifts with the test
/// machine's locale, so every date test builds its inputs from here.
enum TestCalendar {

    static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        calendar: Calendar = TestCalendar.utcGregorian
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let date = calendar.date(from: components) else {
            preconditionFailure("Invalid test date \(year)-\(month)-\(day)")
        }
        return date
    }
}
