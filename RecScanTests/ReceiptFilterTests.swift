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

    @Test("Choosing a category activates the filter")
    func categoryActivatesFilter() {
        // Without this the toolbar badge would not light up for a category-only filter,
        // and a narrowed library would look like the whole library.
        #expect(ReceiptFilter(categoryIDs: [UUID()]).isActive)
        #expect(!ReceiptFilter(categoryIDs: []).isActive)
    }

    @Test("Toggling adds and removes categories")
    func togglingCategories() {
        var filter = ReceiptFilter()
        let first = UUID(), second = UUID()

        filter.toggleCategory(first)
        filter.toggleCategory(second)
        #expect(filter.categoryIDs == [first, second])

        filter.toggleCategory(first)
        #expect(filter.categoryIDs == [second])
    }

    @Test("Removing the last category means all, not none")
    func emptyingMeansAll() {
        var filter = ReceiptFilter()
        let only = UUID()
        filter.toggleCategory(only)

        filter.toggleCategory(only)

        #expect(filter.categoryIDs.isEmpty)
        #expect(!filter.isActive)
        #expect(filter.includes(categoryID: UUID()))
    }

    @Test("An empty selection includes every category")
    func emptyIncludesEverything() {
        let filter = ReceiptFilter()

        #expect(filter.includes(categoryID: UUID()))
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
