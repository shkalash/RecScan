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
    /// A session of more than one page becomes a single receipt: the pages are stacked
    /// into one tall image, because a receipt that spans pages is still one purchase.
    /// - Returns: the identifiers of the created receipts, in page order.
    @discardableResult
    func importScan(pages: [UIImage], capturedAt: Date) async throws -> [UUID]

    /// Persists images brought in from Photos, Files or a shared document.
    ///
    /// Unlike a scan, each item carries its own date, so a batch keeps the dates its
    /// sources knew rather than all landing on today.
    /// - Returns: the identifiers of the created receipts, in order.
    @discardableResult
    func importItems(_ items: [ReceiptImportItem]) async throws -> [UUID]

    /// Stores text recognised from a receipt's image.
    ///
    /// Deliberately does **not** clear `needsReview`: reading a receipt is not confirming
    /// it, and `apply` stays the only thing that does.
    func attachRecognizedText(_ text: String, toReceiptWithID id: UUID) async throws

    /// Commits edited metadata to the receipt with the given identifier.
    ///
    /// A receipt with no amount stays flagged for review however it is saved: an amount
    /// is what the library is for, so one without is never finished.
    ///
    /// - Parameter confirming: whether the save may clear the review flag. Pass `false`
    ///   to keep edits without marking the receipt as done with.
    func apply(_ edit: ReceiptEdit, toReceiptWithID id: UUID, confirming: Bool) async throws

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
    /// Stamps a currency onto receipts stored before currency became per-receipt.
    @discardableResult
    func stampMissingCurrency() async throws -> Int

    func allReceipts() async throws -> [ReceiptSnapshot]

    /// Merges archived receipts into the library.
    ///
    /// Identity is the receipt's `UUID`, so importing the same archive twice changes
    /// nothing the second time. See `ArchiveMergePolicy` for the rules.
    @discardableResult
    func importArchived(
        _ receipts: [ArchiveImporter.StagedReceipt],
        categories: [ArchiveManifest.Category]
    ) async throws -> ArchiveImportResult

    /// Every category, for export.
    func allCategories() async throws -> [ArchiveManifest.Category]
}

extension ReceiptStoring {

    /// Commits edits and confirms the receipt, which is what editing normally means.
    ///
    /// A convenience rather than a defaulted parameter on the requirement: defaults on a
    /// protocol requirement do not reach calls made through `any ReceiptStoring`, which
    /// is how every view holds the store.
    func apply(_ edit: ReceiptEdit, toReceiptWithID id: UUID) async throws {
        try await apply(edit, toReceiptWithID: id, confirming: true)
    }
}
