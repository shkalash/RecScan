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
        ocrText: String? = nil,
        categoryID: UUID? = nil,
        needsReview: Bool = false
    ) -> Receipt {
        let receipt = Receipt(
            capturedAt: TestCalendar.date(year: 2026, month: month, day: day),
            relativePath: "Receipts/\(UUID().uuidString).heic",
            merchant: merchant,
            note: note,
            ocrText: ocrText,
            categoryID: categoryID,
            needsReview: needsReview,
            searchIndex: ReceiptSearchIndex.make(merchant: merchant, note: note, ocrText: ocrText)
        )
        context.insert(receipt)
        return receipt
    }

    private func fetch(
        interval: DateInterval? = nil,
        searchText: String = "",
        categoryIDs: Set<UUID> = [],
        includesUncategorised: Bool = false,
        needsReviewOnly: Bool = false
    ) throws -> [Receipt] {
        try fetch(
            ReceiptPredicateFactory.makePredicate(
                interval: interval, searchText: searchText,
                categoryIDs: categoryIDs, includesUncategorised: includesUncategorised,
                needsReviewOnly: needsReviewOnly
            )
        )
    }

    private func fetch(_ predicate: Predicate<Receipt>) throws -> [Receipt] {
        try context.fetch(FetchDescriptor<Receipt>(predicate: predicate))
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

    @Test("An empty query matches every row")
    func emptyQueryMatchesEverything() throws {
        // Measured, not assumed: `contains("")` is true in Swift but matches nothing once
        // SwiftData translates it, which is why an empty query takes its own branch
        // rather than riding the sentinel the date and category filters use.
        insert(day: 1, merchant: "Blue Bottle")
        insert(day: 2)

        #expect(try fetch(searchText: "").count == 2)
    }

    @Test("The unbounded date sentinel matches every row")
    func unboundedDatesMatchEverything() throws {
        insert(day: 1, month: 1)
        insert(day: 1, month: 12)

        #expect(try fetch(interval: nil).count == 2)
    }

    @Test("Filtering by one category returns only that category")
    func filtersByCategory() throws {
        let wanted = UUID()
        insert(day: 1, categoryID: wanted)
        insert(day: 2, categoryID: UUID())
        insert(day: 3)

        let results = try fetch(categoryIDs: [wanted])

        #expect(results.count == 1)
        #expect(results.first?.categoryID == wanted)
    }

    @Test("Several categories can be mixed")
    func filtersBySeveralCategories() throws {
        let first = UUID(), second = UUID()
        insert(day: 1, categoryID: first)
        insert(day: 2, categoryID: second)
        insert(day: 3, categoryID: UUID())
        insert(day: 4)

        let results = try fetch(categoryIDs: [first, second])

        #expect(results.count == 2)
        #expect(Set(results.compactMap(\.categoryID)) == [first, second])
    }

    @Test("No category selection returns every receipt, categorised or not")
    func noCategoryReturnsEverything() throws {
        insert(day: 1, categoryID: UUID())
        insert(day: 2)

        // An empty selection must mean "all", not "none" -- an empty IN list would match
        // nothing, so it is short-circuited rather than passed to the store.
        #expect(try fetch(categoryIDs: []).count == 2)
    }

    @Test("Uncategorised receipts are excluded once any category is selected")
    func uncategorisedExcludedWhenFiltering() throws {
        let wanted = UUID()
        insert(day: 1, categoryID: wanted)
        insert(day: 2)

        #expect(try fetch(categoryIDs: [wanted]).count == 1)
    }

    @Test("Category, date and text all apply together")
    func allThreeCombine() throws {
        let wanted = UUID()
        insert(day: 5, month: 4, merchant: "Blue Bottle", categoryID: wanted)
        insert(day: 5, month: 5, merchant: "Blue Bottle", categoryID: wanted)
        insert(day: 6, month: 4, merchant: "Other", categoryID: wanted)
        insert(day: 7, month: 4, merchant: "Blue Bottle")
        let interval = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 1, hour: 0),
            end: TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0)
        )

        let results = try fetch(interval: interval, searchText: "blue", categoryIDs: [wanted])

        #expect(results.count == 1)
        #expect(results.first?.capturedAt == TestCalendar.date(year: 2026, month: 4, day: 5))
    }

    @Test("The needs-review filter narrows to unconfirmed receipts")
    func filtersByNeedsReview() throws {
        insert(day: 1, needsReview: true)
        insert(day: 2, needsReview: true)
        insert(day: 3)

        #expect(try fetch(needsReviewOnly: true).count == 2)
    }

    @Test("Leaving the needs-review filter off returns everything")
    func needsReviewOffReturnsEverything() throws {
        insert(day: 1, needsReview: true)
        insert(day: 2)

        #expect(try fetch(needsReviewOnly: false).count == 2)
    }

    @Test("Needs-review combines with the other filters")
    func needsReviewCombines() throws {
        let wanted = UUID()
        insert(day: 1, categoryID: wanted, needsReview: true)
        insert(day: 2, categoryID: wanted)
        insert(day: 3, needsReview: true)

        let results = try fetch(categoryIDs: [wanted], needsReviewOnly: true)

        #expect(results.count == 1)
    }

    @Test("A query matching nothing returns nothing")
    func noMatches() throws {
        insert(day: 1, merchant: "Blue Bottle")

        #expect(try fetch(interval: nil, searchText: "zzz").isEmpty)
    }

    // MARK: - Uncategorised

    /// Runs through a real fetch, like the rest of this suite: the sentinel shape here is
    /// exactly the kind that compiles and then matches the wrong rows.
    @Test("Uncategorised on its own matches only receipts with no category")
    func uncategorisedAlone() throws {
        let fuel = UUID()
        insert(day: 1, categoryID: fuel)
        insert(day: 2, categoryID: nil)
        insert(day: 3, categoryID: nil)
        try context.save()

        let matches = try fetch(
            ReceiptPredicateFactory.makePredicate(
                interval: nil, searchText: "", includesUncategorised: true
            )
        )

        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.categoryID == nil })
    }

    /// The trap: an empty category set normally means "everything". With the
    /// uncategorised flag on it must not, or the filter would return the whole library.
    @Test("Uncategorised does not fall back to matching everything")
    func uncategorisedIsNotAWildcard() throws {
        insert(day: 1, categoryID: UUID())
        insert(day: 2, categoryID: UUID())
        insert(day: 3, categoryID: nil)
        try context.save()

        let matches = try fetch(
            ReceiptPredicateFactory.makePredicate(
                interval: nil, searchText: "", includesUncategorised: true
            )
        )

        #expect(matches.count == 1)
    }

    @Test("Uncategorised combines with chosen categories rather than replacing them")
    func uncategorisedCombinesWithCategories() throws {
        let fuel = UUID()
        let food = UUID()
        insert(day: 1, categoryID: fuel)
        insert(day: 2, categoryID: food)
        insert(day: 3, categoryID: nil)
        try context.save()

        let matches = try fetch(
            ReceiptPredicateFactory.makePredicate(
                interval: nil, searchText: "", categoryIDs: [fuel], includesUncategorised: true
            )
        )

        #expect(matches.count == 2)
        #expect(Set(matches.map(\.categoryID)) == [fuel, nil])
    }

    @Test("Neither flag set still matches every category")
    func noCategoryFilterMatchesEverything() throws {
        insert(day: 1, categoryID: UUID())
        insert(day: 2, categoryID: nil)
        try context.save()

        let matches = try fetch(
            ReceiptPredicateFactory.makePredicate(interval: nil, searchText: "")
        )

        #expect(matches.count == 2)
    }

    @Test("Uncategorised still respects the date range and the review flag")
    func uncategorisedComposesWithOtherTerms() throws {
        insert(day: 5, month: 4, categoryID: nil, needsReview: true)
        insert(day: 5, month: 4, categoryID: nil, needsReview: false)
        insert(day: 5, month: 7, categoryID: nil, needsReview: true)
        try context.save()

        let april = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 1),
            end: TestCalendar.date(year: 2026, month: 5, day: 1)
        )
        let matches = try fetch(
            ReceiptPredicateFactory.makePredicate(
                interval: april, searchText: "", includesUncategorised: true, needsReviewOnly: true
            )
        )

        #expect(matches.count == 1)
    }

}
