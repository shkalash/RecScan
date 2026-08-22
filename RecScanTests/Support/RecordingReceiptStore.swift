import Foundation
import UIKit
@testable import RecScan

/// A `ReceiptStoring` that records what it was asked to write.
///
/// Responsibilities:
/// - Capture every `apply` so a test can assert on what reached the store, and on whether
///   the save was meant to confirm the receipt.
///
/// Why it exists: the review sheet's whole contract is *which* edits are written and
/// whether they clear the review flag. A real store would prove the writes landed but
/// makes it awkward to ask what was never written at all — which is the more important
/// half of the promise here.
actor RecordingReceiptStore: ReceiptStoring {

    /// One recorded write.
    struct Applied: Equatable {
        let id: UUID
        let edit: ReceiptEdit
        /// `false` when the save deliberately left the review flag standing.
        let confirming: Bool
    }

    private(set) var applied: [Applied] = []

    var appliedIDs: [UUID] { applied.map(\.id) }

    func edit(for id: UUID) -> ReceiptEdit? {
        applied.first { $0.id == id }?.edit
    }

    // MARK: - ReceiptStoring

    func apply(_ edit: ReceiptEdit, toReceiptWithID id: UUID, confirming: Bool) async throws {
        applied.append(Applied(id: id, edit: edit, confirming: confirming))
    }

    // MARK: - Unused by these tests

    @discardableResult
    func importScan(pages: [UIImage], capturedAt: Date) async throws -> [UUID] { [] }

    @discardableResult
    func importItems(_ items: [ReceiptImportItem]) async throws -> [UUID] { [] }

    func attachRecognizedText(_ text: String, toReceiptWithID id: UUID) async throws {}

    func delete(receiptsWithIDs ids: [UUID]) async throws {}

    @discardableResult
    func createCategory(named name: String) async throws -> UUID { UUID() }

    func renameCategory(id: UUID, to name: String) async throws {}

    func deleteCategory(id: UUID) async throws {}

    @discardableResult
    func stampMissingCurrency() async throws -> Int { 0 }

    func allReceipts() async throws -> [ReceiptSnapshot] { [] }

    @discardableResult
    func importArchived(
        _ receipts: [ArchiveImporter.StagedReceipt],
        categories: [ArchiveManifest.Category]
    ) async throws -> ArchiveImportResult {
        ArchiveImportResult()
    }

    func allCategories() async throws -> [ArchiveManifest.Category] { [] }
}
