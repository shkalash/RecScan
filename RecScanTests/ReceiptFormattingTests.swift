import Foundation
import Testing
@testable import RecScan

/// Formatting is locale-driven, so these pin an explicit locale rather than the device's.
@Suite("Receipt formatting")
struct ReceiptFormattingTests {

    private let date = TestCalendar.date(year: 2026, month: 3, day: 12)
    private let british = Locale(identifier: "en_GB")

    @Test("The tile date is numeric and drops the year")
    func tileDateIsNumericAndYearless() {
        let formatted = ReceiptFormatting.tileDate(for: date, locale: british)

        // A month name is too wide for a thumbnail, and the grid is already by month.
        #expect(formatted == "12/03")
        #expect(!formatted.contains("2026"))
    }

    /// The order is the locale's, so the caller never has to decide which comes first.
    @Test("The tile date follows the locale's own day/month order")
    func tileDateFollowsLocaleOrder() {
        #expect(ReceiptFormatting.tileDate(for: date, locale: Locale(identifier: "en_US")) == "03/12")
        #expect(ReceiptFormatting.tileDate(for: date, locale: Locale(identifier: "en_GB")) == "12/03")
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
