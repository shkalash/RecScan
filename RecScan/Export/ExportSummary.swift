import Foundation

/// Aggregated figures for the optional summary page.
///
/// Responsibilities:
/// - Count the exported receipts and total their amounts, broken down by month.
///
/// ## Why currency is handled the way it is
/// Summing across currencies produces a meaningless number. The summary picks the
/// most frequent currency among receipts that have an amount, totals only those, and
/// reports whether anything was left out so the page can say so plainly.
struct ExportSummary: Sendable, Equatable {

    /// One month's figures.
    struct MonthTotal: Sendable, Equatable, Identifiable {
        /// Start of the month; doubles as identity and sort key.
        let id: Date
        let count: Int
        let total: Decimal
    }

    let receiptCount: Int
    let monthTotals: [MonthTotal]
    let grandTotal: Decimal
    /// Currency the totals are expressed in, or `nil` when no receipt carried an amount.
    let currencyCode: String?
    /// `true` when amounts in other currencies were excluded from the totals.
    let hasExcludedCurrencies: Bool

    /// Memberwise initialiser, used by the exporter's tests to construct a summary
    /// with a chosen breakdown rather than deriving one from hundreds of receipts.
    init(
        receiptCount: Int,
        monthTotals: [MonthTotal],
        grandTotal: Decimal,
        currencyCode: String?,
        hasExcludedCurrencies: Bool
    ) {
        self.receiptCount = receiptCount
        self.monthTotals = monthTotals
        self.grandTotal = grandTotal
        self.currencyCode = currencyCode
        self.hasExcludedCurrencies = hasExcludedCurrencies
    }

    /// Builds a summary from the receipts about to be exported.
    ///
    /// - Parameter calendar: the calendar that defines month boundaries.
    init(
        receipts: [ReceiptSnapshot],
        calendar: Calendar = .current,
        defaultCurrencyCode: String = AppSettings.fallbackCurrencyCode
    ) {
        // Grouping, totalling and currency resolution all live in ReceiptTotals; this
        // only supplies the month key and the newest-first order.
        let totals = ReceiptTotals(
            receipts: receipts,
            defaultCurrencyCode: defaultCurrencyCode,
            key: { receipt in
                calendar.dateInterval(of: .month, for: receipt.capturedAt)?.start
                    ?? calendar.startOfDay(for: receipt.capturedAt)
            },
            areInIncreasingOrder: { $0.id > $1.id }
        )

        receiptCount = totals.receiptCount
        monthTotals = totals.groups.map { MonthTotal(id: $0.id, count: $0.count, total: $0.total) }
        grandTotal = totals.grandTotal
        currencyCode = totals.currencyCode
        hasExcludedCurrencies = totals.hasExcludedCurrencies
    }

}
