import Foundation
import SwiftData

/// Builds the `Predicate<Receipt>` that backs the library's `@Query`.
///
/// Responsibilities:
/// - Turn resolved bounds and a search string into a predicate.
///
/// ## Why the four cases are spelled out
/// `Predicate` values cannot be composed with `&&` after the fact, and a `#Predicate`
/// body may not branch on an optional captured from outside. Each combination of
/// "has date bounds" × "has search text" therefore needs its own literal.
///
/// Text matching goes through `Receipt.searchIndex` rather than the three source
/// columns — see `ReceiptSearchIndex` for the reason.
enum ReceiptPredicateFactory {

    static func makePredicate(interval: DateInterval?, searchText: String) -> Predicate<Receipt> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (interval, query.isEmpty) {
        case (nil, true):
            return #Predicate<Receipt> { _ in true }

        case (nil, false):
            return #Predicate<Receipt> { receipt in
                receipt.searchIndex.localizedStandardContains(query)
            }

        case (.some(let interval), true):
            // Bounds are hoisted into local constants: the predicate captures values,
            // never expressions it would have to evaluate against the store.
            let lower = interval.start
            let upper = interval.end
            return #Predicate<Receipt> { receipt in
                receipt.capturedAt >= lower && receipt.capturedAt < upper
            }

        case (.some(let interval), false):
            let lower = interval.start
            let upper = interval.end
            return #Predicate<Receipt> { receipt in
                receipt.capturedAt >= lower
                    && receipt.capturedAt < upper
                    && receipt.searchIndex.localizedStandardContains(query)
            }
        }
    }
}
