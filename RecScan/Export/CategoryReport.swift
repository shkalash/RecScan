import Foundation

/// Spend per category over a date range, one section per currency.
///
/// Responsibilities:
/// - Total the receipts in a period, broken down by currency and then by category.
///
/// ## Why currency splits the report rather than filtering it
/// A report is bounded by a date range, not by a currency. Asking "what did I spend in
/// August" and being shown only the shekels — with no sign that the euros existed — is
/// not a partial answer, it is a wrong one. Each currency therefore gets its own section
/// with its own categories and its own total, and nothing is left out.
///
/// Converting between them is a separate question, and needs a rate and the user's
/// say-so; this reports what was actually spent.
///
/// ## Uncategorised is a row, not an omission
/// Receipts with no category are bucketed under `nil` and shown like any other line.
/// Dropping them would make the rows fail to add up to the total, which is the fastest
/// way to make a report untrustworthy.
struct CategoryReport: Sendable {

    /// One category's figures. `categoryID` is `nil` for uncategorised receipts.
    struct Line: CurrencyTableRow, Identifiable {
        let id: UUID?
        let name: String
        let count: Int
        let total: Decimal

        var isUncategorised: Bool { id == nil }
    }

    /// Everything spent in one currency during the period.
    struct Section: CurrencySection {
        /// The currency code, which is also the identity.
        let id: String
        var currencyCode: String { id }
        let lines: [Line]
        let receiptCount: Int
        let total: Decimal

        var rows: [Line] { lines }
    }

    let interval: DateInterval?
    /// One section per currency present, biggest spend first.
    let sections: [Section]
    /// Every receipt in the period, including ones with no amount.
    let receiptCount: Int
    /// How many of those carry no amount, so a missed one is visible rather than absent.
    ///
    /// Reported once for the whole period rather than per currency: a receipt with no
    /// amount has not been filled in, and filing it under a currency would imply a
    /// certainty the receipt does not have.
    let missingAmountCount: Int

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

        sections = totals.currencies.map { currency in
            Section(
                id: currency.currencyCode,
                lines: currency.groups.map { group in
                    Line(
                        id: group.id,
                        name: group.id.flatMap { names[$0] } ?? uncategorisedLabel,
                        count: group.count,
                        total: group.total
                    )
                },
                receiptCount: currency.receiptCount,
                total: currency.total
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
