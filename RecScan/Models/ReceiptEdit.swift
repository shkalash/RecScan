import Foundation

/// The user-editable subset of a receipt's metadata.
///
/// Responsibilities:
/// - Move edited values from the detail view to the store as one atomic unit.
///
/// Why a dedicated type rather than mutating the `@Model` in place: the detail view
/// edits a scratch copy and commits on dismiss, so a half-typed amount never reaches
/// the database, and the commit can be performed off the main actor.
struct ReceiptEdit: Sendable, Equatable {
    var capturedAt: Date
    var merchant: String?
    var amount: Decimal?
    var currencyCode: String?
    var note: String?
    var categoryID: UUID?
}

extension ReceiptEdit {

    /// Whether saving this edit leaves the receipt still wanting review.
    ///
    /// The rule lives here rather than being restated at each call site: the store
    /// applies it when writing, and the detail view needs the same answer to decide
    /// whether to keep offering suggestions. Two copies would drift.
    var leavesReceiptUnreviewed: Bool { amount == nil }

    init(_ receipt: Receipt) {
        self.init(
            capturedAt: receipt.capturedAt,
            merchant: receipt.merchant,
            amount: receipt.amount,
            currencyCode: receipt.currencyCode,
            note: receipt.note,
            categoryID: receipt.categoryID
        )
    }
}
