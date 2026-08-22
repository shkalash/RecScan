import Foundation
import Testing
@testable import RecScan

/// Formatting is locale-driven, so these pin an explicit locale rather than the device's.
@Suite("Receipt formatting")
struct ReceiptFormattingTests {

    private let date = TestCalendar.date(year: 2026, month: 3, day: 12)
    private let british = Locale(identifier: "en_GB")

    @Test("The tile date drops the year, which the month section already gives")
    func tileDateHasNoYear() {
        let formatted = ReceiptFormatting.tileDate(for: date, locale: british)

        #expect(formatted.contains("12"))
        #expect(formatted.contains("Mar"))
        #expect(!formatted.contains("2026"))
    }

    @Test("The full receipt date keeps the year")
    func receiptDateKeepsYear() {
        #expect(ReceiptFormatting.receiptDate(for: date, locale: british).contains("2026"))
    }

    @Test("An amount uses the receipt's own currency, not the default")
    func amountUsesItsOwnCurrency() throws {
        let formatted = try #require(
            ReceiptFormatting.amount(
                Decimal(string: "52.30"), currencyCode: "ILS", defaultCode: "USD", locale: british
            )
        )

        #expect(formatted.contains("₪"))
        #expect(!formatted.contains("$"))
    }

    @Test("An amount with no currency of its own falls back to the default")
    func amountFallsBackToDefault() throws {
        let formatted = try #require(
            ReceiptFormatting.amount(
                Decimal(string: "52.30"), currencyCode: nil, defaultCode: "USD", locale: british
            )
        )

        #expect(formatted.contains("$"))
    }

    @Test("No amount formats as nothing, so the caller decides what to show")
    func noAmountIsNil() {
        #expect(ReceiptFormatting.amount(nil, currencyCode: "ILS", defaultCode: "USD") == nil)
    }
}
