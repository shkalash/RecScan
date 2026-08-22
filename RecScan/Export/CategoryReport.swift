import Foundation

/// Spend per category over a date range.
///
/// Responsibilities:
/// - Total the receipts in a period, broken down by category.
///
/// ## Uncategorised is a row, not an omission
/// Receipts with no category are bucketed under `nil` and shown like any other line.
/// Dropping them would make the rows fail to add up to the total, which is the fastest
/// way to make a report untrustworthy.
struct CategoryReport: Sendable {

    /// One category's figures. `categoryID` is `nil` for uncategorised receipts.
    struct Line: Sendable, Identifiable {
        let id: UUID?
        let name: String
        let count: Int
        let total: Decimal

        var isUncategorised: Bool { id == nil }
    }

    let interval: DateInterval?
    let lines: [Line]
    /// Every receipt in the period, including ones with no amount.
    let receiptCount: Int
    /// How many of those carry no amount, so a missed one is visible rather than absent.
    let missingAmountCount: Int
    let grandTotal: Decimal
    let currencyCode: String?
    let hasExcludedCurrencies: Bool

    var isEmpty: Bool { receiptCount == 0 }

    /// - Parameters:
    ///   - receipts: already narrowed to the period of interest.
    ///   - names: category id to display name, for labelling the rows.
    init(
        receipts: [ReceiptSnapshot],
        names: [UUID: String],
        interval: DateInterval?,
        defaultCurrencyCode: String,
        uncategorisedLabel: String
    ) {
        self.interval = interval

        let totals = ReceiptTotals(
            receipts: receipts,
            defaultCurrencyCode: defaultCurrencyCode,
            key: { $0.categoryID },
            // Largest spend first: a report is read to find where the money went.
            areInIncreasingOrder: { $0.total > $1.total }
        )

        receiptCount = totals.receiptCount
        missingAmountCount = totals.unpricedCount
        grandTotal = totals.grandTotal
        currencyCode = totals.currencyCode
        hasExcludedCurrencies = totals.hasExcludedCurrencies

        lines = totals.groups.map { group in
            Line(
                id: group.id,
                name: group.id.flatMap { names[$0] } ?? uncategorisedLabel,
                count: group.count,
                total: group.total
            )
        }
    }

    /// Narrows `receipts` to `interval` before reporting.
    ///
    /// Done here rather than by the caller so the in-app screen and the PDF cannot drift
    /// apart on what "in the period" means.
    static func make(
        allReceipts: [ReceiptSnapshot],
        names: [UUID: String],
        interval: DateInterval?,
        defaultCurrencyCode: String,
        uncategorisedLabel: String
    ) -> CategoryReport {
        let scoped = interval.map { window in
            // Half-open, matching the library's filter: the start is in, the end is not.
            allReceipts.filter { $0.capturedAt >= window.start && $0.capturedAt < window.end }
        } ?? allReceipts

        return CategoryReport(
            receipts: scoped,
            names: names,
            interval: interval,
            defaultCurrencyCode: defaultCurrencyCode,
            uncategorisedLabel: uncategorisedLabel
        )
    }
}
