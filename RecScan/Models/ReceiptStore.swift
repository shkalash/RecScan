import Foundation
import SwiftData
import UIKit

/// SwiftData-backed implementation of `ReceiptStoring`.
///
/// Responsibilities:
/// - Perform every receipt write on a background actor with its own `ModelContext`.
/// - Keep the database row and the image file on disk in lockstep.
///
/// ## Why `ModelActor` is conformed to by hand rather than via the `@ModelActor` macro
/// The macro synthesises `init(modelContainer:)` and nothing else, which leaves no way
/// to inject `ImageFileStoring`. Writing the two stored properties out costs four lines
/// and buys constructor injection, which the tests depend on.
///
/// ## Why writes do not happen on the main actor
/// Importing a multi-page scan encodes several HEIC images and inserts several rows.
/// Doing that on the main actor drops frames on the capture dismissal animation, and at
/// bulk-import scale it stalls the UI outright.
actor ReceiptStore: ReceiptStoring, ModelActor {

    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor

    private let fileStore: any ImageFileStoring
    private let logger = LogCategory.persistence.logger

    init(modelContainer: ModelContainer, fileStore: any ImageFileStoring = ImageFileStore()) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.fileStore = fileStore
    }

    // MARK: - Import

    @discardableResult
    func importScan(pages: [UIImage], capturedAt: Date = Date()) async throws -> [UUID] {
        guard !pages.isEmpty else { throw ReceiptStoreError.emptyImportRequest }

        // A single-page scan is not a "group"; only multi-page sessions get an identity.
        let groupID: UUID? = pages.count > 1 ? UUID() : nil
        var createdIDs: [UUID] = []
        createdIDs.reserveCapacity(pages.count)

        for (index, page) in pages.enumerated() {
            let id = UUID()
            // The file is written first. If the save below throws, the worst case is a
            // stray file with no row — invisible and harmless. The reverse order would
            // leave a row pointing at nothing, which the library cannot render.
            let relativePath = try fileStore.write(page, for: id)

            let receipt = Receipt(
                id: id,
                capturedAt: capturedAt,
                relativePath: relativePath,
                groupID: groupID,
                pageIndex: index
            )
            modelContext.insert(receipt)
            createdIDs.append(id)
        }

        try modelContext.save()
        logger.info("Imported \(createdIDs.count, privacy: .public) receipt page(s).")
        return createdIDs
    }

    // MARK: - Edit

    func apply(_ edit: ReceiptEdit, toReceiptWithID id: UUID) async throws {
        guard let receipt = try fetchReceipt(id: id) else {
            throw ReceiptStoreError.receiptNotFound(id: id)
        }

        receipt.capturedAt = edit.capturedAt
        receipt.merchant = edit.merchant?.normalisedOrNil
        receipt.amount = edit.amount
        receipt.currencyCode = edit.currencyCode
        receipt.note = edit.note?.normalisedOrNil
        // The derived search column is rewritten here and nowhere else, so it cannot
        // drift out of step with the fields it is built from.
        receipt.searchIndex = ReceiptSearchIndex.make(
            merchant: receipt.merchant,
            note: receipt.note,
            ocrText: receipt.ocrText
        )

        try modelContext.save()
    }

    // MARK: - Delete

    /// Deletes rows and files together.
    ///
    /// This is the *only* deletion entry point on purpose: splitting it into "delete
    /// row" and "delete file" is how image files get orphaned.
    func delete(receiptsWithIDs ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }

        for id in ids {
            guard let receipt = try fetchReceipt(id: id) else { continue }
            let relativePath = receipt.relativePath
            modelContext.delete(receipt)
            do {
                try fileStore.delete(relativePath: relativePath, id: id)
            } catch {
                // A missing or unreadable file must not block the row deletion —
                // leaving the row behind would show an unopenable receipt forever.
                logger.error("Failed to delete image for \(id, privacy: .public): \(error)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Private

    private func fetchReceipt(id: UUID) throws -> Receipt? {
        // Bound captured outside the macro: `#Predicate` cannot call arbitrary code.
        let target = id
        var descriptor = FetchDescriptor<Receipt>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

private extension String {
    /// Trimmed, or `nil` when nothing but whitespace remains.
    ///
    /// Stored as `nil` rather than `""` so that "no merchant" has exactly one
    /// representation in the database and predicates need only test for nil.
    var normalisedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
