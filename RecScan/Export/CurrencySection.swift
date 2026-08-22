import Foundation

/// One currency's slice of a report or summary.
///
/// Responsibilities:
/// - Give the report and the summary one shape to be paginated and drawn through.
///
/// Why a protocol: the expense report lists categories and the export summary lists
/// months, but both are "a currency, its rows, and its total", and both have to break
/// across PDF pages the same way. Without this the pagination would exist twice, and the
/// two would drift the first time either was tuned.
protocol CurrencySection: Sendable, Identifiable where ID == String {

    associatedtype Row: CurrencyTableRow

    /// The currency code, which is also the identity.
    var currencyCode: String { get }
    /// The lines shown under this currency.
    var rows: [Row] { get }
    /// Receipts contributing to this currency.
    var receiptCount: Int { get }
    /// Sum of the rows.
    var total: Decimal { get }
}


/// One printable line: whatever it is named after, it has a count and a total.
///
/// Lets the PDF draw a month row and a category row with the same code — only the label
/// differs, and the caller supplies that.
protocol CurrencyTableRow: Sendable {
    var count: Int { get }
    var total: Decimal { get }
}
