import Foundation

/// Counts and sums receipts, split by currency and grouped by whatever key the caller
/// cares about.
///
/// Responsibilities:
/// - Partition receipts by currency, then bucket each currency's receipts by a key.
///
/// ## Why this is generic
/// The PDF summary groups by month and the expense report groups by category, but the
/// awkward part — never letting two currencies meet in one sum — is identical. Writing
/// it twice would mean two places to get it wrong.
///
/// ## Currency
/// Adding shekels to euros produces a meaningless number, so each currency is totalled
/// separately and every one of them is reported.
///
/// This previously picked the single most frequent currency, totalled only those receipts
/// and set a flag saying something had been left out. That was worse than it sounds: the
/// excluded receipts were not merely unsummed, they were absent — no line, no count, no
/// hint of which ones. A period's spending cannot be read off a report that quietly drops
/// part of it, so nothing is dropped now.
struct ReceiptTotals<Key: Hashable & Sendable>: Sendable {

    /// One bucket's figures within a single currency.
    struct Group: Sendable, Identifiable {
        let id: Key
        let count: Int
        let total: Decimal
    }

    /// Everything spent in one currency, bucketed by the caller's key.
    struct CurrencyTotals: Sendable, Identifiable {
        /// The currency code, which is also the identity.
        let id: String
        var currencyCode: String { id }
        /// Buckets, in the order the caller's sort produced.
        let groups: [Group]
        /// Receipts contributing to this currency's totals.
        let receiptCount: Int
        let total: Decimal
    }

    /// One entry per currency present, biggest spend first.
    let currencies: [CurrencyTotals]
    /// Every receipt considered, including ones with no amount.
    let receiptCount: Int
    /// Receipts carrying no amount at all.
    ///
    /// Surfaced rather than silently dropped: a receipt with no amount is usually one
    /// that has not been filled in yet, and a report that simply omits it hides the
    /// omission behind a total that looks complete.
    let unpricedCount: Int

    /// - Parameters:
    ///   - defaultCurrencyCode: used for receipts stored before currency was stamped.
    ///   - key: which bucket a receipt belongs in.
    ///   - areInIncreasingOrder: bucket ordering within a currency, applied after totalling.
    init(
        receipts: [ReceiptSnapshot],
        defaultCurrencyCode: String,
        key: (ReceiptSnapshot) -> Key,
        areInIncreasingOrder: (Group, Group) -> Bool
    ) {
        receiptCount = receipts.count

        let priced = receipts.filter { $0.amount != nil }
        unpricedCount = receipts.count - priced.count

        let byCurrency = Dictionary(grouping: priced) {
            $0.currencyCode ?? defaultCurrencyCode
        }

        // Built with a loop and explicit types rather than a chain of nested closures:
        // the generic Key plus three levels of inference defeated the type checker.
        var perCurrency: [CurrencyTotals] = []
        perCurrency.reserveCapacity(byCurrency.count)

        for (code, contents) in byCurrency {
            let buckets: [Key: [ReceiptSnapshot]] = Dictionary(grouping: contents, by: key)

            var groups: [Group] = []
            groups.reserveCapacity(buckets.count)
            for (bucketKey, bucket) in buckets {
                var sum = Decimal.zero
                for receipt in bucket { sum += receipt.amount ?? .zero }
                groups.append(Group(id: bucketKey, count: bucket.count, total: sum))
            }
            groups.sort(by: areInIncreasingOrder)

            var currencyTotal = Decimal.zero
            for group in groups { currencyTotal += group.total }

            perCurrency.append(
                CurrencyTotals(
                    id: code,
                    groups: groups,
                    receiptCount: contents.count,
                    total: currencyTotal
                )
            )
        }

        // Biggest spend first, since that is what a report is read for. Ties break on
        // the code so the order is stable across runs rather than dictionary order.
        perCurrency.sort { lhs, rhs in
            lhs.total == rhs.total ? lhs.id < rhs.id : lhs.total > rhs.total
        }
        currencies = perCurrency
    }
}
