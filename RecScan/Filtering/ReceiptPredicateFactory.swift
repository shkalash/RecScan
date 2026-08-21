import Foundation
import SwiftData

/// Builds the `Predicate<Receipt>` that backs the library's `@Query`.
///
/// Responsibilities:
/// - Turn resolved bounds, a search string and a category into one predicate.
///
/// ## Why two literals, and only two
/// `Predicate` values cannot be composed with `&&` after the fact, so the naive shape is
/// one literal per combination of active filters — four for dates and text, eight once
/// categories join, doubling with every filter after that.
///
/// Most filters can instead carry a value meaning "match everything", giving the predicate
/// a fixed shape. Measured against a real store, rather than assumed:
///
/// | Sentinel | Rows matched |
/// |---|---|
/// | `distantPast ..< distantFuture` | all — works |
/// | `matchesAnyCategory \|\| selected.contains(categoryID)` | all — works |
/// | `searchIndex.localizedStandardContains("")` | **none** — does not work |
///
/// Swift's `contains("")` is true, but SwiftData translates it to a store `CONTAINS`,
/// where an empty operand matches nothing. So text — and only text — needs a branch. Date
/// and category sentinels live inside both literals, which is what keeps this at two
/// rather than eight, and keeps the next filter from doubling it again.
///
/// Text matching goes through `Receipt.searchIndex` rather than the three source columns
/// (see `ReceiptSearchIndex`), and category matching through the denormalised `categoryID`
/// rather than a relationship — the type checker gave up on the optional-heavy version of
/// this predicate once already.
///
/// Category membership captures `[UUID?]`, not `[UUID]` or a `Set`: `categoryID` is
/// optional, and the closure form (`selected.contains { $0 == receipt.categoryID }`) does
/// not compile at all inside `#Predicate`. An array of optionals compares like for like
/// and translates into an `IN` query.
enum ReceiptPredicateFactory {

    /// - Parameter categoryIDs: categories to include. Empty means every category,
    ///   including uncategorised receipts.
    static func makePredicate(
        interval: DateInterval?,
        searchText: String,
        categoryIDs: Set<UUID> = []
    ) -> Predicate<Receipt> {
        // Resolved into plain values before the macro sees them: a `#Predicate` body
        // captures values, never expressions it would have to evaluate against the store.
        let lower = interval?.start ?? .distantPast
        let upper = interval?.end ?? .distantFuture
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty selection cannot be expressed as an empty `IN` list -- that matches
        // nothing rather than everything -- so it is short-circuited by a captured Bool.
        let selected: [UUID?] = categoryIDs.map { $0 }
        let matchesAnyCategory = categoryIDs.isEmpty

        guard !query.isEmpty else {
            return #Predicate<Receipt> { receipt in
                receipt.capturedAt >= lower
                    && receipt.capturedAt < upper
                    && (matchesAnyCategory || selected.contains(receipt.categoryID))
            }
        }

        return #Predicate<Receipt> { receipt in
            receipt.capturedAt >= lower
                && receipt.capturedAt < upper
                && receipt.searchIndex.localizedStandardContains(query)
                && (matchesAnyCategory || selected.contains(receipt.categoryID))
        }
    }
}
