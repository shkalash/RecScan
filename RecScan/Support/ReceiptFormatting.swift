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

    /// Day and month only, e.g. "12 Mar".
    ///
    /// For the grid tile, where the library is already sectioned by month and repeating
    /// the year on every thumbnail would spend the little room there is on the one part
    /// the reader already knows.
    static func tileDate(for date: Date, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale).month(.abbreviated).day())
    }

    /// An amount rendered in its own currency, or `nil` when there is no amount.
    ///
    /// - Parameter defaultCode: currency to use when the receipt carries none. Passed in
    ///   rather than read from settings so this stays pure and testable — see
    ///   `AppSettings`.
    static func amount(
        _ amount: Decimal?,
        currencyCode: String?,
        defaultCode: String,
        locale: Locale = .current
    ) -> String? {
        guard let amount else { return nil }
        return amount.formatted(.currency(code: currencyCode ?? defaultCode).locale(locale))
    }

    /// File-name-safe timestamp for generated exports.
    static func exportTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppConstants.Format.posixLocaleIdentifier)
        formatter.dateFormat = AppConstants.Format.exportFileTimestamp
        return formatter.string(from: date)
    }

}
