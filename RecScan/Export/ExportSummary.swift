import Foundation

/// Aggregated figures for the optional summary page, one section per currency.
///
/// Responsibilities:
/// - Count the exported receipts and total their amounts, by currency and then by month.
///
/// ## Why currency splits the summary
/// Same reason as `CategoryReport`: summing across currencies produces a meaningless
/// number, and picking one currency and dropping the rest produces a wrong one. Each
/// currency gets its own months and its own total.
struct ExportSummary: Sendable, Equatable {

    /// One month's figures within a currency.
    struct MonthTotal: CurrencyTableRow, Equatable, Identifiable {
        /// Start of the month; doubles as identity and sort key.
        let id: Date
        let count: Int
        let total: Decimal
    }

    /// Everything exported in one currency.
    struct Section: CurrencySection, Equatable {
        /// The currency code, which is also the identity.
        let id: String
        var currencyCode: String { id }
        let monthTotals: [MonthTotal]
        let receiptCount: Int
        let total: Decimal

        var rows: [MonthTotal] { monthTotals }
    }

    let receiptCount: Int
    /// One section per currency present, biggest spend first.
    let sections: [Section]
    /// Exported receipts carrying no amount.
    let missingAmountCount: Int

    /// Memberwise initialiser, used by the exporter's tests to construct a summary
    /// with a chosen breakdown rather than deriving one from hundreds of receipts.
    init(receiptCount: Int, sections: [Section], missingAmountCount: Int = 0) {
        self.receiptCount = receiptCount
        self.sections = sections
        self.missingAmountCount = missingAmountCount
    }

    /// Builds a summary from the receipts about to be exported.
    ///
    /// - Parameter calendar: the calendar that defines month boundaries.
    init(
        receipts: [ReceiptSnapshot],
        calendar: Calendar = .current,
        defaultCurrencyCode: String = AppSettings.fallbackCurrencyCode
    ) {
        // Grouping, totalling and the currency split all live in ReceiptTotals; this
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
        missingAmountCount = totals.unpricedCount
        sections = totals.currencies.map { currency in
            Section(
                id: currency.currencyCode,
                monthTotals: currency.groups.map {
                    MonthTotal(id: $0.id, count: $0.count, total: $0.total)
                },
                receiptCount: currency.receiptCount,
                total: currency.total
            )
        }
    }
}
