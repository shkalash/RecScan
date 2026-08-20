import Foundation
import Testing
@testable import RecScan

@Suite("Month grouping")
struct MonthGrouperTests {

    private let calendar = TestCalendar.utcGregorian

    private struct Item: Equatable {
        let date: Date
    }

    @Test("Items are bucketed by calendar month")
    func groupsByMonth() {
        let items = [
            Item(date: TestCalendar.date(year: 2026, month: 3, day: 1)),
            Item(date: TestCalendar.date(year: 2026, month: 3, day: 28)),
            Item(date: TestCalendar.date(year: 2026, month: 4, day: 2))
        ]

        let sections = MonthGrouper.group(items, calendar: calendar) { $0.date }

        #expect(sections.count == 2)
        #expect(sections.map(\.items.count) == [1, 2])
    }

    @Test("Sections run newest month first")
    func sectionsAreDescending() {
        let items = [
            Item(date: TestCalendar.date(year: 2025, month: 12, day: 5)),
            Item(date: TestCalendar.date(year: 2026, month: 6, day: 5)),
            Item(date: TestCalendar.date(year: 2026, month: 1, day: 5))
        ]

        let sections = MonthGrouper.group(items, calendar: calendar) { $0.date }

        #expect(sections.map(\.id) == [
            TestCalendar.date(year: 2026, month: 6, day: 1, hour: 0),
            TestCalendar.date(year: 2026, month: 1, day: 1, hour: 0),
            TestCalendar.date(year: 2025, month: 12, day: 1, hour: 0)
        ])
    }

    @Test("Items inside a section run newest first")
    func itemsAreDescendingWithinASection() {
        let older = Item(date: TestCalendar.date(year: 2026, month: 3, day: 2))
        let newer = Item(date: TestCalendar.date(year: 2026, month: 3, day: 25))

        let sections = MonthGrouper.group([older, newer], calendar: calendar) { $0.date }

        #expect(sections.first?.items == [newer, older])
    }

    @Test("An empty input yields no sections")
    func emptyInput() {
        #expect(MonthGrouper.group([Item](), calendar: calendar) { $0.date }.isEmpty)
    }
}
