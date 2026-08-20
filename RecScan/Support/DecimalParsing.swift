import Foundation

/// Locale-aware parsing and rendering of the amount field.
///
/// Responsibilities:
/// - Convert between the text the user types and a `Decimal`.
///
/// ## Why not `TextField(value:format:)`
/// A receipt's amount is genuinely optional, and the value-based `TextField` cannot
/// represent "no amount" — it forces a zero. Text-backed entry keeps the empty state
/// distinguishable from a real 0.00.
enum DecimalParsing {

    /// Parses user input, accepting both the locale's separators and a plain dot.
    ///
    /// - Returns: `nil` for empty or unparseable input.
    static func decimal(from text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true

        if let number = formatter.number(from: trimmed) as? NSDecimalNumber {
            return number.decimalValue
        }

        // Fall back to the POSIX interpretation. Someone typing "12.50" on a locale
        // that uses a comma still means twelve fifty.
        return Decimal(string: trimmed, locale: Locale(identifier: AppConstants.Format.posixLocaleIdentifier))
    }

    /// Renders a decimal for editing — plain digits, no currency symbol or grouping.
    static func editableText(from amount: Decimal?, locale: Locale = .current) -> String {
        guard let amount else { return "" }
        return amount.formatted(.number.grouping(.never).locale(locale))
    }
}
