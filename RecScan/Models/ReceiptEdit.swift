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
