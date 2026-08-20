import Foundation
import Testing
@testable import RecScan

@Suite("Export summary totals")
struct ExportSummaryTests {

    private let calendar = TestCalendar.utcGregorian
    private let locale = Locale(identifier: "en_US")

    private func snapshot(
        day: Int,
        month: Int,
        amount: Decimal?,
        currency: String? = "USD"
    ) -> ReceiptSnapshot {
        ReceiptSnapshot(
            id: UUID(),
            capturedAt: TestCalendar.date(year: 2026, month: month, day: day),
            relativePath: "Receipts/\(UUID().uuidString).heic",
            merchant: nil,
            amount: amount,
            currencyCode: currency,
            note: nil,
            ocrText: nil,
            groupID: nil,
            pageIndex: 0
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
            locale: locale
        )

        #expect(summary.receiptCount == 2)
    }

    @Test("Totals are broken down by month and add up to the grand total")
    func totalsByMonth() {
        let summary = ExportSummary(
            receipts: [
                snapshot(day: 3, month: 1, amount: Decimal(string: "10.50")),
                snapshot(day: 20, month: 1, amount: Decimal(string: "4.50")),
                snapshot(day: 7, month: 2, amount: Decimal(string: "100.00"))
            ],
            calendar: calendar,
            locale: locale
        )

        #expect(summary.monthTotals.count == 2)
        #expect(summary.monthTotals.map(\.total) == [Decimal(string: "100.00"), Decimal(string: "15.00")])
        #expect(summary.grandTotal == Decimal(string: "115.00"))
    }

    @Test("Month sections run newest first, matching the library")
    func monthsAreDescending() {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 2, amount: 1), snapshot(day: 1, month: 5, amount: 1)],
            calendar: calendar,
            locale: locale
        )

        #expect(summary.monthTotals.map(\.id) == [
            TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0),
            TestCalendar.date(year: 2026, month: 2, day: 1, hour: 0)
        ])
    }

    @Test("Totals use the most common currency and flag what was left out")
    func excludesMinorityCurrencies() {
        let summary = ExportSummary(
            receipts: [
                snapshot(day: 1, month: 3, amount: 10, currency: "USD"),
                snapshot(day: 2, month: 3, amount: 20, currency: "USD"),
                snapshot(day: 3, month: 3, amount: 999, currency: "JPY")
            ],
            calendar: calendar,
            locale: locale
        )

        #expect(summary.currencyCode == "USD")
        #expect(summary.grandTotal == 30)
        #expect(summary.hasExcludedCurrencies)
    }

    @Test("A single currency is never reported as mixed")
    func singleCurrencyIsNotFlagged() {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 3, amount: 10), snapshot(day: 2, month: 3, amount: 5)],
            calendar: calendar,
            locale: locale
        )

        #expect(!summary.hasExcludedCurrencies)
    }

    @Test("Receipts with no amounts produce a zero total and no currency")
    func noAmountsAtAll() {
        let summary = ExportSummary(
            receipts: [snapshot(day: 1, month: 3, amount: nil), snapshot(day: 2, month: 3, amount: nil)],
            calendar: calendar,
            locale: locale
        )

        #expect(summary.receiptCount == 2)
        #expect(summary.grandTotal == .zero)
        #expect(summary.currencyCode == nil)
        #expect(summary.monthTotals.isEmpty)
    }
}
