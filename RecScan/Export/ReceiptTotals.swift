import Foundation

/// Counts and sums receipts, grouped by whatever key the caller cares about.
///
/// Responsibilities:
/// - Bucket receipts by a key, total each bucket, and resolve one currency for the lot.
///
/// ## Why this is generic
/// The PDF summary groups by month and the expense report groups by category, but the
/// awkward parts — deciding which currency the totals are even in, and saying what got
/// left out — are identical. Writing them twice would mean two places to get mixed
/// currencies wrong.
///
/// ## Currency
/// Summing across currencies produces a meaningless number, so the most frequent currency
/// among receipts that have an amount wins, only those are totalled, and whether anything
/// was excluded is reported so the caller can say so plainly.
struct ReceiptTotals<Key: Hashable & Sendable>: Sendable {

    /// One bucket's figures.
    struct Group: Sendable, Identifiable {
        let id: Key
        let count: Int
        let total: Decimal
    }

    /// Buckets, in the order the caller's sort produced.
    let groups: [Group]
    /// Every receipt considered, including ones with no amount.
    let receiptCount: Int
    /// Receipts in the period carrying no amount at all.
    ///
    /// Surfaced rather than silently dropped: a receipt with no amount is usually one
    /// that has not been filled in yet, and a report that simply omits it hides the
    /// omission behind a total that looks complete.
    let unpricedCount: Int
    let grandTotal: Decimal
    /// The currency the totals are in, or `nil` when no receipt carried an amount.
    let currencyCode: String?
    /// `true` when amounts in other currencies were left out of the totals.
    let hasExcludedCurrencies: Bool

    /// - Parameters:
    ///   - key: which bucket a receipt belongs in.
    ///   - areInIncreasingOrder: bucket ordering, applied after totalling.
    init(
        receipts: [ReceiptSnapshot],
        defaultCurrencyCode: String,
        key: (ReceiptSnapshot) -> Key,
        areInIncreasingOrder: (Group, Group) -> Bool
    ) {
        receiptCount = receipts.count

        let priced = receipts.filter { $0.amount != nil }
        unpricedCount = receipts.count - priced.count
        let dominant = Self.dominantCurrencyCode(in: priced, defaultCode: defaultCurrencyCode)
        currencyCode = dominant

        let counted = priced.filter {
            Self.effectiveCurrencyCode(for: $0, defaultCode: defaultCurrencyCode) == dominant
        }
        hasExcludedCurrencies = counted.count != priced.count

        let buckets = Dictionary(grouping: counted, by: key)
        groups = buckets
            .map { key, contents in
                Group(
                    id: key,
                    count: contents.count,
                    total: contents.reduce(Decimal.zero) { $0 + ($1.amount ?? .zero) }
                )
            }
            .sorted(by: areInIncreasingOrder)

        grandTotal = groups.reduce(Decimal.zero) { $0 + $1.total }
    }

    // MARK: - Currency

    private static func effectiveCurrencyCode(
        for receipt: ReceiptSnapshot, defaultCode: String
    ) -> String? {
        receipt.currencyCode ?? defaultCode
    }

    private static func dominantCurrencyCode(
        in receipts: [ReceiptSnapshot], defaultCode: String
    ) -> String? {
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
