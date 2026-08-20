import Foundation

/// Builds the denormalised text blob that backs receipt search.
///
/// Responsibilities:
/// - Combine every searchable field into a single string.
///
/// ## Why a derived column exists at all
/// The natural predicate — date bounds AND (merchant OR note OR OCR text), each of the
/// three an optional string — expands into a `PredicateExpressions` tree the Swift type
/// checker cannot resolve in reasonable time. Collapsing the three optionals into one
/// non-optional column makes the predicate three flat terms, and it turns a
/// three-column scan into one. The cost is that the column must be rewritten whenever
/// any contributing field changes, which is why `ReceiptStore` is the only writer.
enum ReceiptSearchIndex {

    /// Separator between fields. A newline keeps two adjacent fields from forming a
    /// spurious match across their boundary (e.g. "Acme" + "Rent" matching "mere").
    private static let separator = "\n"

    static func make(merchant: String?, note: String?, ocrText: String?) -> String {
        [merchant, note, ocrText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}
