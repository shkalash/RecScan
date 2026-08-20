import Foundation

/// Shared, locale-aware formatting for receipt values.
///
/// Responsibilities:
/// - Render dates, month headers and amounts consistently everywhere they appear.
///
/// Why centralised: the library grid, the detail view and the PDF must agree on how a
/// date and an amount look, and the PDF is the one place where a mismatch is visible
/// to somebody other than the user.
enum ReceiptFormatting {

    /// Month header, e.g. "March 2026".
    static func monthTitle(for date: Date, locale: Locale = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale)
                .year(.defaultDigits)
                .month(.wide)
        )
    }

    /// Medium date with no time component, e.g. "12 Mar 2026".
    static func receiptDate(for date: Date, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale).year().month().day())
    }

    /// An amount rendered in its own currency, or `nil` when there is no amount.
    ///
    /// Falls back to the locale's currency when the receipt carries no code, which is
    /// the common case for manually entered values.
    static func amount(_ amount: Decimal?, currencyCode: String?, locale: Locale = .current) -> String? {
        guard let amount else { return nil }
        let code = currencyCode ?? locale.currency?.identifier ?? fallbackCurrencyCode
        return amount.formatted(.currency(code: code).locale(locale))
    }

    /// File-name-safe timestamp for generated exports.
    static func exportTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppConstants.Format.posixLocaleIdentifier)
        formatter.dateFormat = AppConstants.Format.exportFileTimestamp
        return formatter.string(from: date)
    }

    /// Used only when the locale itself reports no currency, which happens for a few
    /// region-less locales in the simulator.
    private static let fallbackCurrencyCode = "USD"
}
