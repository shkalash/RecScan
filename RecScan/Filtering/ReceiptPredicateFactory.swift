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
/// | `matchesAnyCategory \|\| categoryID == wanted` | all — works |
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
enum ReceiptPredicateFactory {

    static func makePredicate(
        interval: DateInterval?,
        searchText: String,
        categoryID: UUID? = nil
    ) -> Predicate<Receipt> {
        // Resolved into plain values before the macro sees them: a `#Predicate` body
        // captures values, never expressions it would have to evaluate against the store.
        let lower = interval?.start ?? .distantPast
        let upper = interval?.end ?? .distantFuture
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantedCategory = categoryID
        let matchesAnyCategory = categoryID == nil

        guard !query.isEmpty else {
            return #Predicate<Receipt> { receipt in
                receipt.capturedAt >= lower
                    && receipt.capturedAt < upper
                    && (matchesAnyCategory || receipt.categoryID == wantedCategory)
            }
        }

        return #Predicate<Receipt> { receipt in
            receipt.capturedAt >= lower
                && receipt.capturedAt < upper
                && receipt.searchIndex.localizedStandardContains(query)
                && (matchesAnyCategory || receipt.categoryID == wantedCategory)
        }
    }
}
