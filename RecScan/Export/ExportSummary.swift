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
        receiptCount = receipts.count

        let priced = receipts.filter { $0.amount != nil }
        let dominantCurrency = Self.dominantCurrencyCode(in: priced, defaultCode: defaultCurrencyCode)
        currencyCode = dominantCurrency

        let counted = priced.filter {
            Self.effectiveCurrencyCode(for: $0, defaultCode: defaultCurrencyCode) == dominantCurrency
        }
        hasExcludedCurrencies = counted.count != priced.count

        let sections = MonthGrouper.group(counted, calendar: calendar) { $0.capturedAt }
        monthTotals = sections.map { section in
            MonthTotal(
                id: section.id,
                count: section.items.count,
                total: section.items.reduce(Decimal.zero) { $0 + ($1.amount ?? .zero) }
            )
        }

        grandTotal = monthTotals.reduce(Decimal.zero) { $0 + $1.total }
    }

    // MARK: - Private

    private static func effectiveCurrencyCode(for receipt: ReceiptSnapshot, defaultCode: String) -> String? {
        receipt.currencyCode ?? defaultCode
    }

    private static func dominantCurrencyCode(in receipts: [ReceiptSnapshot], defaultCode: String) -> String? {
        let codes = receipts.compactMap { effectiveCurrencyCode(for: $0, defaultCode: defaultCode) }
        guard !codes.isEmpty else { return nil }

        let frequencies = codes.reduce(into: [String: Int]()) { counts, code in
            counts[code, default: 0] += 1
        }
        // Ties break on the code itself so the result is deterministic across runs.
        return frequencies.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
