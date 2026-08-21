import Foundation
import Testing
@testable import RecScan

@Suite("Category report")
struct CategoryReportTests {

    private let groceries = UUID()
    private let fuel = UUID()

    private var names: [UUID: String] { [groceries: "Groceries", fuel: "Fuel"] }

    private func receipt(
        day: Int,
        month: Int = 4,
        amount: Decimal?,
        category: UUID? = nil,
        currency: String? = "USD"
    ) -> ReceiptSnapshot {
        let id = UUID()
        let date = TestCalendar.date(year: 2026, month: month, day: day)
        return ReceiptSnapshot(
            id: id, capturedAt: date, createdAt: date, modifiedAt: date,
            relativePath: "Receipts/\(id.uuidString).heic",
            merchant: nil, amount: amount, currencyCode: currency,
            note: nil, ocrText: nil, groupID: nil, pageIndex: 0,
            categoryID: category, needsReview: false
        )
    }

    private func report(
        _ receipts: [ReceiptSnapshot],
        interval: DateInterval? = nil
    ) -> CategoryReport {
        CategoryReport.make(
            allReceipts: receipts, names: names, interval: interval,
            defaultCurrencyCode: "USD", uncategorisedLabel: "Uncategorised"
        )
    }

    @Test("Totals are grouped by category and named")
    func groupsByCategory() throws {
        let result = report([
            receipt(day: 1, amount: 10, category: groceries),
            receipt(day: 2, amount: 15, category: groceries),
            receipt(day: 3, amount: 40, category: fuel)
        ])

        // Largest first: a report is read to find where the money went.
        #expect(result.lines.map(\.name) == ["Fuel", "Groceries"])
        #expect(result.lines.map(\.total) == [40, 25])
        #expect(result.grandTotal == 65)
    }

    @Test("Uncategorised receipts get their own line rather than vanishing")
    func uncategorisedIsALine() throws {
        let result = report([
            receipt(day: 1, amount: 10, category: groceries),
            receipt(day: 2, amount: 30)
        ])

        // If these were dropped, the lines would not add up to the total, which is the
        // fastest way to make a report untrustworthy.
        let uncategorised = try #require(result.lines.first { $0.isUncategorised })
        #expect(uncategorised.total == 30)
        #expect(result.lines.reduce(Decimal.zero) { $0 + $1.total } == result.grandTotal)
    }

    @Test("Only receipts inside the period are counted")
    func respectsDateRange() {
        let april = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 1, hour: 0),
            end: TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0)
        )

        let result = report([
            receipt(day: 5, month: 4, amount: 10, category: groceries),
            receipt(day: 5, month: 5, amount: 99, category: groceries)
        ], interval: april)

        #expect(result.grandTotal == 10)
        #expect(result.receiptCount == 1)
    }

    @Test("The period boundary is half-open, matching the library filter")
    func boundaryIsHalfOpen() {
        let april = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 1, hour: 0),
            end: TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0)
        )

        let result = report([
            receipt(day: 1, month: 4, amount: 10, category: fuel),
            receipt(day: 1, month: 5, amount: 10, category: fuel)
        ], interval: april)

        #expect(result.receiptCount == 1)
    }

    @Test("No interval means the whole library")
    func noIntervalIncludesEverything() {
        let result = report([
            receipt(day: 1, month: 1, amount: 10, category: fuel),
            receipt(day: 1, month: 12, amount: 10, category: fuel)
        ], interval: nil)

        #expect(result.grandTotal == 20)
    }

    @Test("Receipts with no amount are counted but do not affect totals")
    func countsUnpricedReceipts() {
        let result = report([
            receipt(day: 1, amount: 10, category: fuel),
            receipt(day: 2, amount: nil, category: fuel)
        ])

        #expect(result.receiptCount == 2)
        #expect(result.grandTotal == 10)
    }

    @Test("Mixed currencies are excluded and flagged")
    func flagsMixedCurrencies() {
        let result = report([
            receipt(day: 1, amount: 10, category: fuel, currency: "USD"),
            receipt(day: 2, amount: 20, category: fuel, currency: "USD"),
            receipt(day: 3, amount: 999, category: fuel, currency: "JPY")
        ])

        #expect(result.grandTotal == 30)
        #expect(result.hasExcludedCurrencies)
    }

    @Test("An empty period reports as empty rather than showing zeroes")
    func emptyPeriod() {
        let result = report([], interval: nil)

        #expect(result.isEmpty)
        #expect(result.lines.isEmpty)
    }
}
