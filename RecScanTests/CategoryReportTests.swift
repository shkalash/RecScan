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
            note: nil, ocrText: nil,
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

    /// Most fixtures use one currency, where the report is a single section.
    private func onlySection(_ report: CategoryReport) throws -> CategoryReport.Section {
        #expect(report.sections.count == 1)
        return try #require(report.sections.first)
    }

    @Test("Totals are grouped by category and named")
    func groupsByCategory() throws {
        let section = try onlySection(report([
            receipt(day: 1, amount: 10, category: groceries),
            receipt(day: 2, amount: 15, category: groceries),
            receipt(day: 3, amount: 40, category: fuel)
        ]))

        // Largest first: a report is read to find where the money went.
        #expect(section.lines.map(\.name) == ["Fuel", "Groceries"])
        #expect(section.lines.map(\.total) == [40, 25])
        #expect(section.total == 65)
    }

    @Test("Uncategorised receipts get their own line rather than vanishing")
    func uncategorisedIsALine() throws {
        let result: CategoryReport = report([
            receipt(day: 1, amount: 10, category: groceries),
            receipt(day: 2, amount: 30)
        ])

        // If these were dropped, the lines would not add up to the total, which is the
        // fastest way to make a report untrustworthy.
        let section = try onlySection(result)
        let uncategorised = try #require(section.lines.first { $0.isUncategorised })
        #expect(uncategorised.total == 30)
        #expect(section.lines.reduce(Decimal.zero) { $0 + $1.total } == section.total)
    }

    @Test("Only receipts inside the period are counted")
    func respectsDateRange() throws {
        let april = DateInterval(
            start: TestCalendar.date(year: 2026, month: 4, day: 1, hour: 0),
            end: TestCalendar.date(year: 2026, month: 5, day: 1, hour: 0)
        )

        let result = report([
            receipt(day: 5, month: 4, amount: 10, category: groceries),
            receipt(day: 5, month: 5, amount: 99, category: groceries)
        ], interval: april)

        #expect(try onlySection(result).total == 10)
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
    func noIntervalIncludesEverything() throws {
        let section = try onlySection(report([
            receipt(day: 1, month: 1, amount: 10, category: fuel),
            receipt(day: 1, month: 12, amount: 10, category: fuel)
        ], interval: nil))

        #expect(section.total == 20)
    }

    @Test("Receipts with no amount are counted but do not affect totals")
    func countsUnpricedReceipts() throws {
        let result = report([
            receipt(day: 1, amount: 10, category: fuel),
            receipt(day: 2, amount: nil, category: fuel)
        ])

        #expect(result.receiptCount == 2)
        #expect(try onlySection(result).total == 10)
        #expect(result.missingAmountCount == 1)
    }

    /// The report is read to spot a receipt that was never filled in, so the count has
    /// to be reported rather than left to be inferred from a total that looks fine.
    @Test("Receipts with no amount are reported, not silently dropped")
    func reportsMissingAmounts() {
        let result = report([
            receipt(day: 1, amount: 10, category: fuel),
            receipt(day: 2, amount: nil, category: fuel),
            receipt(day: 3, amount: nil)
        ])

        #expect(result.missingAmountCount == 2)
    }

    @Test("Nothing missing means nothing to report")
    func noMissingAmounts() {
        let result = report([receipt(day: 1, amount: 10, category: fuel)])

        #expect(result.missingAmountCount == 0)
    }

    @Test("A receipt outside the period is not counted as missing an amount")
    func missingCountRespectsPeriod() {
        let result = report(
            [receipt(day: 1, amount: nil), receipt(day: 1, month: 7, amount: nil)],
            interval: DateInterval(
                start: TestCalendar.date(year: 2026, month: 4, day: 1),
                end: TestCalendar.date(year: 2026, month: 5, day: 1)
            )
        )

        #expect(result.missingAmountCount == 1)
    }

    // MARK: - Currency

    /// The report used to keep only the most frequent currency and flag the rest as
    /// "excluded". Those receipts had no line and no count -- asking what a period cost
    /// and being shown part of it, with no way to see the rest, is a wrong answer rather
    /// than a partial one.
    @Test("Each currency gets its own section, and none is dropped")
    func splitsByCurrency() {
        let result = report([
            receipt(day: 1, amount: 10, category: fuel, currency: "USD"),
            receipt(day: 2, amount: 20, category: fuel, currency: "USD"),
            receipt(day: 3, amount: 999, category: fuel, currency: "JPY")
        ])

        #expect(result.sections.map(\.currencyCode) == ["JPY", "USD"])
        #expect(result.sections.map(\.total) == [999, 30])
        #expect(result.sections.reduce(0) { $0 + $1.receiptCount } == 3)
    }

    @Test("Each currency keeps its own category breakdown")
    func categoriesAreScopedToTheirCurrency() throws {
        let result = report([
            receipt(day: 1, amount: 10, category: fuel, currency: "USD"),
            receipt(day: 2, amount: 30, category: groceries, currency: "USD"),
            receipt(day: 3, amount: 500, category: fuel, currency: "JPY")
        ])

        let jpy = try #require(result.sections.first { $0.currencyCode == "JPY" })
        let usd = try #require(result.sections.first { $0.currencyCode == "USD" })

        #expect(jpy.lines.map(\.name) == ["Fuel"])
        #expect(usd.lines.map(\.name) == ["Groceries", "Fuel"])
        #expect(usd.lines.map(\.total) == [30, 10])
    }

    @Test("Sections run biggest spend first, with a stable tie-break")
    func sectionsAreOrdered() {
        let result = report([
            receipt(day: 1, amount: 5, category: fuel, currency: "BBB"),
            receipt(day: 2, amount: 5, category: fuel, currency: "AAA"),
            receipt(day: 3, amount: 50, category: fuel, currency: "CCC")
        ])

        #expect(result.sections.map(\.currencyCode) == ["CCC", "AAA", "BBB"])
    }

    /// Changing the default currency must not make older receipts vanish from a report.
    @Test("A receipt stored before currency was stamped falls back to the default")
    func unstampedFallsBackToDefault() {
        let result = report([receipt(day: 1, amount: 10, category: fuel, currency: nil)])

        #expect(result.sections.map(\.currencyCode) == ["USD"])
    }

    @Test("An empty period reports as empty rather than showing zeroes")
    func emptyPeriod() {
        let result = report([], interval: nil)

        #expect(result.isEmpty)
        #expect(result.sections.isEmpty)
    }
}
