import Foundation

/// An immutable, `Sendable` copy of a `Receipt`'s persisted values.
///
/// Responsibilities:
/// - Carry receipt data across actor boundaries.
///
/// Why this exists: `Receipt` is a SwiftData `@Model` and is therefore bound to the
/// `ModelContext` that materialised it. Handing one to another actor (the PDF builder
/// running off the main actor, for instance) is a data race. Views read `Receipt`
/// directly from their own main-actor context; anything that leaves the main actor
/// travels as a snapshot.
struct ReceiptSnapshot: Sendable, Identifiable, Hashable {
    let id: UUID
    let capturedAt: Date
    let relativePath: String
    let merchant: String?
    let amount: Decimal?
    let currencyCode: String?
    let note: String?
    let ocrText: String?
    let groupID: UUID?
    let pageIndex: Int
}

extension ReceiptSnapshot {
    init(_ receipt: Receipt) {
        self.init(
            id: receipt.id,
            capturedAt: receipt.capturedAt,
            relativePath: receipt.relativePath,
            merchant: receipt.merchant,
            amount: receipt.amount,
            currencyCode: receipt.currencyCode,
            note: receipt.note,
            ocrText: receipt.ocrText,
            groupID: receipt.groupID,
            pageIndex: receipt.pageIndex
        )
    }
}
