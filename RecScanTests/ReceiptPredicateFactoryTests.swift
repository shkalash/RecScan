import Foundation
import SwiftData
import Testing
@testable import RecScan

/// Exercises the predicates against a real store.
///
/// These run through `ModelContext.fetch` on purpose: a `#Predicate` that compiles can
/// still trap or silently mistranslate once SwiftData converts it into a query, and
/// evaluating the predicate in Swift would not catch that.
@Suite("Receipt predicates")
struct ReceiptPredicateFactoryTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let calendar = TestCalendar.utcGregorian

    init() throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = ModelContext(container)
    }

    @discardableResult
    private func insert(
        day: Int,
        month: Int = 4,
        merchant: String? = nil,
        note: String? = nil,
        ocrText: String? = nil
    ) -> Receipt {
        let receipt = Receipt(
            capturedAt: TestCalendar.date(year: 2026, month: month, day: day),
            relativePath: "Receipts/\(UUID().uuidString).heic",
            merchant: merchant,
            note: note,
            ocrText: ocrText,
            searchIndex: ReceiptSearchIndex.make(merchant: merchant, note: note, ocrText: ocrText)
        )
        context.insert(receipt)
        return receipt
    }

    private func fetch(interval: DateInterval?, searchText: String) throws -> [Receipt] {
        try context.fetch(
            FetchDescriptor<Receipt>(
                predicate: ReceiptPredicateFactory.makePredicate(interval: interval, searchText: searchText)
            )
        )
    }

    @Test("No bounds and no query returns everything")
    func unfilteredReturnsEverything() throws {
        insert(day: 1)
        insert(day: 2)

        #expect(try fetch(interval: nil, searchText: "").count == 2)
    }

    @Test("The date bound is half-open: the start is included, the end is not")
    func dateBoundIsHalfOpen() throws {
        insert(day: 1)
        insert(day: 15)
        insert(day: 30)
        let interval = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 15, hour: 0),
            end: TestCalendar.date(year: 2026, month: 4, day: 30, hour: 0)
        )

        let results = try fetch(interval: interval, searchText: "")

        #expect(results.count == 1)
        #expect(results.first?.capturedAt == TestCalendar.date(year: 2026, month: 4, day: 15))
    }

    @Test("A This Month preset resolves and queries without trapping")
    func presetIntervalQueries() throws {
        insert(day: 10, month: 4)
        insert(day: 10, month: 5)
        let reference = TestCalendar.date(year: 2026, month: 4, day: 20)
        let interval = DateRangePreset.thisMonth.dateInterval(reference: reference, calendar: calendar)

        #expect(try fetch(interval: interval, searchText: "").count == 1)
    }

    @Test("Search matches the merchant, the note and the recognised text")
    func searchCoversEveryField() throws {
        insert(day: 1, merchant: "Blue Bottle")
        insert(day: 2, note: "reimbursable")
        insert(day: 3, ocrText: "TOTAL 12.34 THANK YOU")
        insert(day: 4, merchant: "Unrelated")

        #expect(try fetch(interval: nil, searchText: "bottle").count == 1)
        #expect(try fetch(interval: nil, searchText: "reimburs").count == 1)
        #expect(try fetch(interval: nil, searchText: "thank").count == 1)
    }

    @Test("Search ignores case and surrounding whitespace")
    func searchIsCaseInsensitive() throws {
        insert(day: 1, merchant: "Blue Bottle")

        #expect(try fetch(interval: nil, searchText: "  BLUE  ").count == 1)
    }

    @Test("Date bounds and search text apply together")
    func combinedFiltering() throws {
        insert(day: 5, month: 4, merchant: "Blue Bottle")
        insert(day: 5, month: 5, merchant: "Blue Bottle")
        insert(day: 6, month: 4, merchant: "Other")
        let interval = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 1, hour: 0),
            end: TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0)
        )

        let results = try fetch(interval: interval, searchText: "blue")

        #expect(results.count == 1)
        #expect(results.first?.capturedAt == TestCalendar.date(year: 2026, month: 4, day: 5))
    }

    @Test("A query matching nothing returns nothing")
    func noMatches() throws {
        insert(day: 1, merchant: "Blue Bottle")

        #expect(try fetch(interval: nil, searchText: "zzz").isEmpty)
    }
}
