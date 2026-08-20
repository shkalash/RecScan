import Foundation
import Testing
@testable import RecScan

@Suite("Library filter")
struct ReceiptFilterTests {

    private let calendar = TestCalendar.utcGregorian

    @Test("A fresh filter is inactive")
    func defaultFilterIsInactive() {
        #expect(!ReceiptFilter().isActive)
    }

    @Test("Choosing a preset activates the filter")
    func presetActivatesFilter() {
        #expect(ReceiptFilter(preset: .thisMonth).isActive)
    }

    @Test("Search text activates the filter, whitespace alone does not")
    func searchTextActivatesFilter() {
        #expect(ReceiptFilter(searchText: "coffee").isActive)
        #expect(!ReceiptFilter(searchText: "   \n").isActive)
    }

    @Test("A custom range covers whole days, so a single-day range is not empty")
    func customRangeCoversWholeDays() throws {
        let day = TestCalendar.date(year: 2026, month: 2, day: 10, hour: 14)
        let filter = ReceiptFilter(preset: .custom, customStart: day, customEnd: day)

        let interval = try #require(filter.resolvedInterval(calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2026, month: 2, day: 10, hour: 0))
        #expect(interval.end == TestCalendar.date(year: 2026, month: 2, day: 11, hour: 0))
        #expect(interval.contains(day))
    }

    @Test("A reversed custom range is normalised rather than producing nothing")
    func customRangeToleratesReversedBounds() throws {
        let start = TestCalendar.date(year: 2026, month: 2, day: 20)
        let end = TestCalendar.date(year: 2026, month: 2, day: 10)
        let filter = ReceiptFilter(preset: .custom, customStart: start, customEnd: end)

        let interval = try #require(filter.resolvedInterval(calendar: calendar))

        #expect(interval.start == TestCalendar.date(year: 2026, month: 2, day: 10, hour: 0))
        #expect(interval.end == TestCalendar.date(year: 2026, month: 2, day: 21, hour: 0))
    }

    @Test("All Time resolves to no interval")
    func allTimeResolvesToNil() {
        #expect(ReceiptFilter(preset: .allTime).resolvedInterval(calendar: calendar) == nil)
    }
}
