import Foundation
import UIKit

/// Mutating operations on the receipt library.
///
/// Responsibilities:
/// - Own every write that touches both the database and the file system, so the two
///   can never drift apart.
///
/// Why a protocol: views depend on this, not on `ModelContext`. That keeps SwiftData
/// out of the UI layer and lets tests substitute an in-memory store.
///
/// Every member is `async` because the implementation runs on its own actor — bulk
/// imports must not encode HEIC on the main actor.
protocol ReceiptStoring: Sendable {

    /// Persists one scan session.
    ///
    /// A session of more than one page produces sibling rows sharing a `groupID`,
    /// an identical `capturedAt`, and sequential `pageIndex` values.
    /// - Returns: the identifiers of the created receipts, in page order.
    @discardableResult
    func importScan(pages: [UIImage], capturedAt: Date) async throws -> [UUID]

    /// Commits edited metadata to the receipt with the given identifier.
    func apply(_ edit: ReceiptEdit, toReceiptWithID id: UUID) async throws

    /// Deletes rows *and* their backing image files.
    func delete(receiptsWithIDs ids: [UUID]) async throws
}
