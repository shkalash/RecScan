import Foundation
import Testing
@testable import RecScan

@Suite("Date range presets")
struct DateRangePresetTests {

    private let calendar = TestCalendar.utcGregorian
    /// Mid-May 2026 — inside Q2, and far enough from any boundary that an off-by-one
    /// in the interval maths is unambiguous.
    private let reference = TestCalendar.date(year: 2026, month: 5, day: 17)

    @Test("All Time applies no bound")
    func allTimeIsUnbounded() {
        #expect(DateRangePreset.allTime.dateInterval(reference: reference, calendar: calendar) == nil)
    }

    @Test("Custom takes its bounds from the filter, not the preset")
    func customDefersToTheFilter() {
        #expect(DateRangePreset.custom.dateInterval(reference: reference, calendar: calendar) == nil)
    }

    @Test("This Month spans the containing calendar month")
    func thisMonth() throws {
        let interval = try #require(DateRangePreset.thisMonth.dateInterval(reference: reference, calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0))
        #expect(interval.end == TestCalendar.date(year: 2026, month: 6, day: 1, hour: 0))
    }

    @Test("Last Month spans the preceding calendar month")
    func lastMonth() throws {
        let interval = try #require(DateRangePreset.lastMonth.dateInterval(reference: reference, calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2026, month: 4, day: 1, hour: 0))
        #expect(interval.end == TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0))
    }

    @Test("Last Month in January rolls back into the previous year")
    func lastMonthCrossesTheYearBoundary() throws {
        let january = TestCalendar.date(year: 2026, month: 1, day: 9)

        let interval = try #require(DateRangePreset.lastMonth.dateInterval(reference: january, calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2025, month: 12, day: 1, hour: 0))
        #expect(interval.end == TestCalendar.date(year: 2026, month: 1, day: 1, hour: 0))
    }

    @Test(
        "This Quarter covers the three-month block containing the reference date",
        arguments: [
            (month: 1, startMonth: 1, endMonth: 4, endYear: 2026),
            (month: 3, startMonth: 1, endMonth: 4, endYear: 2026),
            (month: 5, startMonth: 4, endMonth: 7, endYear: 2026),
            (month: 8, startMonth: 7, endMonth: 10, endYear: 2026),
            (month: 12, startMonth: 10, endMonth: 1, endYear: 2027)
        ]
    )
    func thisQuarter(month: Int, startMonth: Int, endMonth: Int, endYear: Int) throws {
        let date = TestCalendar.date(year: 2026, month: month, day: 15)

        let interval = try #require(DateRangePreset.thisQuarter.dateInterval(reference: date, calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2026, month: startMonth, day: 1, hour: 0))
        #expect(interval.end == TestCalendar.date(year: endYear, month: endMonth, day: 1, hour: 0))
    }

    @Test("This Year spans the containing calendar year")
    func thisYear() throws {
        let interval = try #require(DateRangePreset.thisYear.dateInterval(reference: reference, calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2026, month: 1, day: 1, hour: 0))
        #expect(interval.end == TestCalendar.date(year: 2027, month: 1, day: 1, hour: 0))
    }
}
