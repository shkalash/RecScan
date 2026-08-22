import Foundation
import Testing
@testable import RecScan

@Suite("Export summary totals")
struct ExportSummaryTests {

    private let calendar = TestCalendar.utcGregorian
    /// Receipts in these fixtures carry explicit codes; this is what an unstamped one
    /// would fall back to.
    private let defaultCurrency = "USD"

    private func snapshot(
        day: Int,
        month: Int,
        amount: Decimal?,
        currency: String? = "USD"
    ) -> ReceiptSnapshot {
        ReceiptSnapshot(
            id: UUID(),
            capturedAt: TestCalendar.date(year: 2026, month: month, day: day),
            createdAt: TestCalendar.date(year: 2026, month: month, day: day),
            modifiedAt: TestCalendar.date(year: 2026, month: month, day: day),
            relativePath: "Receipts/\(UUID().uuidString).heic",
            merchant: nil,
            amount: amount,
            currencyCode: currency,
            note: nil,
            ocrText: nil,
            categoryID: nil,
            needsReview: false
        )
    }

    @Test("Counts every receipt, including ones with no amount")
    func countsEverything() {
        let summary = ExportSummary(
            receipts: [
                snapshot(day: 1, month: 1, amount: 10),
                snapshot(day: 2, month: 1, amount: nil)
            ],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        #expect(summary.receiptCount == 2)
    }

    @Test("Totals are broken down by month within a currency")
    func totalsByMonth() {
        let summary = ExportSummary(
            receipts: [
                snapshot(day: 3, month: 1, amount: Decimal(string: "10.50")),
                snapshot(day: 20, month: 1, amount: Decimal(string: "4.50")),
                snapshot(day: 7, month: 2, amount: Decimal(string: "100.00"))
            ],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        let section = try! #require(summary.sections.first)
        #expect(summary.sections.count == 1)
        #expect(section.monthTotals.count == 2)
        #expect(section.monthTotals.map(\.total) == [Decimal(string: "100.00"), Decimal(string: "15.00")])
        #expect(section.total == Decimal(string: "115.00"))
    }

    @Test("Month sections run newest first, matching the library")
    func monthsAreDescending() throws {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 2, amount: 1), snapshot(day: 1, month: 5, amount: 1)],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        let section = try #require(summary.sections.first)
        #expect(section.monthTotals.map(\.id) == [
            TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0),
            TestCalendar.date(year: 2026, month: 2, day: 1, hour: 0)
        ])
    }

    // MARK: - Currency

    /// The summary used to keep only the most frequent currency and set a flag saying
    /// something had been dropped. The dropped receipts were invisible -- no row, no
    /// count -- so an export could understate a period with no way to tell.
    @Test("Every currency gets its own section; none is dropped")
    func everyCurrencyIsReported() throws {
        let summary = ExportSummary(
            receipts: [
                snapshot(day: 1, month: 3, amount: 10, currency: "USD"),
                snapshot(day: 2, month: 3, amount: 20, currency: "USD"),
                snapshot(day: 3, month: 3, amount: 999, currency: "JPY")
            ],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        #expect(summary.sections.map(\.currencyCode) == ["JPY", "USD"])
        #expect(summary.sections.map(\.total) == [999, 30])
        // Every receipt is accounted for somewhere.
        #expect(summary.sections.reduce(0) { $0 + $1.receiptCount } == 3)
    }

    @Test("Sections run biggest spend first, with a stable tie-break")
    func sectionsAreOrdered() {
        let summary = ExportSummary(
            receipts: [
                snapshot(day: 1, month: 3, amount: 5, currency: "AAA"),
                snapshot(day: 2, month: 3, amount: 5, currency: "BBB"),
                snapshot(day: 3, month: 3, amount: 50, currency: "CCC")
            ],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        #expect(summary.sections.map(\.currencyCode) == ["CCC", "AAA", "BBB"])
    }

    @Test("One currency produces exactly one section")
    func singleCurrency() {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 3, amount: 10), snapshot(day: 2, month: 3, amount: 5)],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        #expect(summary.sections.count == 1)
        #expect(summary.sections.first?.currencyCode == "USD")
    }

    @Test("A receipt stored before currency was stamped falls back to the default")
    func unstampedFallsBackToDefault() {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 3, amount: 10, currency: nil)],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        #expect(summary.sections.map(\.currencyCode) == ["USD"])
    }

    @Test("Receipts with no amounts produce no sections but are still counted")
    func noAmountsAtAll() {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 3, amount: nil), snapshot(day: 2, month: 3, amount: nil)],
            calendar: calendar,
            defaultCurrencyCode: defaultCurrency
        )

        #expect(summary.receiptCount == 2)
        #expect(summary.sections.isEmpty)
        #expect(summary.missingAmountCount == 2)
    }
}
