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

    /// Creates a category, or returns the existing one when the name already matches.
    ///
    /// - Returns: the identifier to select.
    @discardableResult
    func createCategory(named name: String) async throws -> UUID

    func renameCategory(id: UUID, to name: String) async throws

    /// Deletes a category and clears it from every receipt holding it.
    ///
    /// Both halves live here for the same reason row and file deletion do: split them and
    /// receipts end up pointing at a category that no longer exists.
    func deleteCategory(id: UUID) async throws

    /// Every receipt in the library, oldest first, ignoring any active filter.
    ///
    /// Archive export needs this: a backup taken through the library's filter would look
    /// complete while holding one month.
    func allReceipts() async throws -> [ReceiptSnapshot]

    /// Merges archived receipts into the library.
    ///
    /// Identity is the receipt's `UUID`, so importing the same archive twice changes
    /// nothing the second time. See `ArchiveMergePolicy` for the rules.
    @discardableResult
    func importArchived(_ receipts: [ArchiveImporter.StagedReceipt]) async throws -> ArchiveImportResult
}
