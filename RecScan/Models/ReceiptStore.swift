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

    /// Read at import time, not at init: the setting can change while the app runs, and
    /// each receipt should be stamped with whatever was current when it arrived.
    /// Injected so tests do not depend on `UserDefaults.standard`.
    private let currentDefaultCurrency: @Sendable () -> String

    init(
        modelContainer: ModelContainer,
        fileStore: any ImageFileStoring = ImageFileStore(),
        currentDefaultCurrency: @escaping @Sendable () -> String = { AppSettings.defaultCurrencyCode() }
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.fileStore = fileStore
        self.currentDefaultCurrency = currentDefaultCurrency
    }

    // MARK: - Import

    /// Stores one scan session as a single receipt.
    ///
    /// A multi-page session is one long receipt that did not fit the frame, so the pages
    /// are stacked into one image rather than becoming a row each.
    @discardableResult
    func importScan(pages: [UIImage], capturedAt: Date = Date()) async throws -> [UUID] {
        guard !pages.isEmpty else { throw ReceiptStoreError.emptyImportRequest }
        guard let merged = ImageStitcher.stack(pages) else {
            throw ReceiptStoreError.emptyImportRequest
        }

        let id = UUID()
        // The file is written first. If the save below throws, the worst case is a
        // stray file with no row — invisible and harmless. The reverse order would
        // leave a row pointing at nothing, which the library cannot render.
        let relativePath = try fileStore.write(merged, for: id)

        let now = Date()
        let receipt = Receipt(
            id: id,
            capturedAt: capturedAt,
            createdAt: now,
            modifiedAt: now,
            relativePath: relativePath,
            currencyCode: currentDefaultCurrency(),
            needsReview: true
        )
        modelContext.insert(receipt)

        try modelContext.save()
        logger.info("Imported a scan of \(pages.count, privacy: .public) page(s).")
        return [id]
    }

    // MARK: - Import from files

    @discardableResult
    func importItems(_ items: [ReceiptImportItem]) async throws -> [UUID] {
        guard !items.isEmpty else { throw ReceiptStoreError.emptyImportRequest }
        let defaultCurrency = currentDefaultCurrency()

        var createdIDs: [UUID] = []
        createdIDs.reserveCapacity(items.count)

        for item in items {
            let id = UUID()
            // Same order as capture: file first, so a failed save leaves a stray file
            // rather than a row pointing at nothing.
            let relativePath = try fileStore.write(item.image, for: id)
            let now = Date()

            let receipt = Receipt(
                id: id,
                capturedAt: item.capturedAt,
                createdAt: now,
                modifiedAt: now,
                relativePath: relativePath,
                currencyCode: defaultCurrency,
                ocrText: item.ocrText,
                // Everything imported is flagged until it has been through the review
                // sheet. A confident date does not make a receipt reviewed -- merchant,
                // amount and category are all still empty.
                needsReview: true,
                searchIndex: ReceiptSearchIndex.make(
                    merchant: nil, note: nil, ocrText: item.ocrText
                )
            )
            modelContext.insert(receipt)
            createdIDs.append(id)
        }

        try modelContext.save()
        logger.info("Imported \(createdIDs.count, privacy: .public) item(s) from files.")
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
        receipt.categoryID = edit.categoryID
        // The derived search column is rewritten here and nowhere else, so it cannot
        // drift out of step with the fields it is built from.
        receipt.searchIndex = ReceiptSearchIndex.make(
            merchant: receipt.merchant,
            note: receipt.note,
            ocrText: receipt.ocrText
        )
        receipt.modifiedAt = Date()
        // Editing a receipt is the act of confirming it, so the prompt clears here as
        // well as from the review sheet -- otherwise a badge could only be cleared one way.
        receipt.needsReview = false

        try modelContext.save()
    }

    func attachRecognizedText(_ text: String, toReceiptWithID id: UUID) async throws {
        guard let receipt = try fetchReceipt(id: id) else {
            throw ReceiptStoreError.receiptNotFound(id: id)
        }

        receipt.ocrText = text
        receipt.searchIndex = ReceiptSearchIndex.make(
            merchant: receipt.merchant, note: receipt.note, ocrText: text
        )
        receipt.modifiedAt = Date()
        // `needsReview` is untouched on purpose: the receipt has been read, not confirmed.

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

    // MARK: - Categories

    @discardableResult
    func createCategory(named name: String) async throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReceiptStoreError.emptyCategoryName }

        // Typing a name that already exists selects it rather than creating a twin.
        if let existing = try fetchCategory(matching: trimmed) { return existing.id }

        let category = ReceiptCategory(name: trimmed)
        modelContext.insert(category)
        try modelContext.save()
        return category.id
    }

    func renameCategory(id: UUID, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReceiptStoreError.emptyCategoryName }
        guard let category = try fetchCategory(id: id) else {
            throw ReceiptStoreError.categoryNotFound(id: id)
        }

        category.name = trimmed
        try modelContext.save()
    }

    func deleteCategory(id: UUID) async throws {
        guard let category = try fetchCategory(id: id) else { return }

        // Clear the id from its receipts first: a nil relationship would have been
        // nullified for us, but a denormalised column has to be swept by hand.
        let target = id
        let holders = try modelContext.fetch(
            FetchDescriptor<Receipt>(predicate: #Predicate { $0.categoryID == target })
        )
        for receipt in holders {
            receipt.categoryID = nil
            receipt.modifiedAt = Date()
        }

        modelContext.delete(category)
        try modelContext.save()
        logger.info("Deleted category, cleared from \(holders.count, privacy: .public) receipt(s).")
    }

    private func fetchCategory(id: UUID) throws -> ReceiptCategory? {
        let target = id
        var descriptor = FetchDescriptor<ReceiptCategory>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Case-insensitive lookup by name.
    ///
    /// Done in Swift rather than in the predicate: `#Predicate` has no case-insensitive
    /// equality, and the category list is small enough that fetching it is free.
    private func fetchCategory(matching name: String) throws -> ReceiptCategory? {
        let key = ReceiptCategory.matchingKey(for: name)
        return try modelContext.fetch(FetchDescriptor<ReceiptCategory>())
            .first { ReceiptCategory.matchingKey(for: $0.name) == key }
    }

    /// Stamps a currency onto receipts that predate per-receipt currency.
    ///
    /// Without this the setting would still rewrite history for existing rows: a `nil`
    /// currency falls back to the default at render time, so changing the default moves
    /// every unstamped receipt with it — the exact behaviour that per-receipt currency
    /// exists to stop. Run once at launch; a library with nothing to fix pays one query.
    ///
    /// - Returns: how many rows were stamped.
    @discardableResult
    func stampMissingCurrency() async throws -> Int {
        let descriptor = FetchDescriptor<Receipt>(
            predicate: #Predicate { $0.currencyCode == nil }
        )
        let unstamped = try modelContext.fetch(descriptor)
        guard !unstamped.isEmpty else { return 0 }

        let code = currentDefaultCurrency()
        for receipt in unstamped {
            receipt.currencyCode = code
            // `modifiedAt` is deliberately left alone: this is a backfill, not an edit,
            // and bumping it would make every receipt look newer than its archived copy
            // and win merges it should lose.
        }
        try modelContext.save()
        logger.info("Stamped \(unstamped.count, privacy: .public) receipt(s) with \(code, privacy: .public).")
        return unstamped.count
    }

    // MARK: - Reading

    func allReceipts() async throws -> [ReceiptSnapshot] {
        let descriptor = FetchDescriptor<Receipt>(
            sortBy: [SortDescriptor(\Receipt.capturedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(ReceiptSnapshot.init)
    }

    // MARK: - Archive import

    /// Merges archived receipts, deciding per receipt via `ArchiveMergePolicy`.
    ///
    /// Images are written before the row is touched, for the same reason capture does it
    /// that way: a stray file with no row is invisible, whereas a row pointing at a file
    /// that was never written renders as a permanently broken receipt.
    func allCategories() async throws -> [ArchiveManifest.Category] {
        try modelContext.fetch(FetchDescriptor<ReceiptCategory>())
            .map { ArchiveManifest.Category(id: $0.id, name: $0.name) }
    }

    /// Reconciles archived categories with the local ones.
    ///
    /// Matching is by **name**, not id: two devices that both created "Fuel" have two
    /// different ids for the same thing, and importing by id alone would leave a library
    /// with two identical-looking categories. An archived category whose name is already
    /// present is mapped onto the local one; anything genuinely new is created with the
    /// id it arrived with, so re-importing the same archive is still a no-op.
    ///
    /// - Returns: archived id → local id, for rewriting the receipts that follow.
    private func reconcile(_ categories: [ArchiveManifest.Category]) throws -> [UUID: UUID] {
        guard !categories.isEmpty else { return [:] }

        var existing = try modelContext.fetch(FetchDescriptor<ReceiptCategory>())
        var mapping: [UUID: UUID] = [:]

        for archived in categories {
            let key = ReceiptCategory.matchingKey(for: archived.name)
            if let match = existing.first(where: { ReceiptCategory.matchingKey(for: $0.name) == key }) {
                mapping[archived.id] = match.id
                continue
            }
            let created = ReceiptCategory(id: archived.id, name: archived.name)
            modelContext.insert(created)
            existing.append(created)
            mapping[archived.id] = created.id
        }

        return mapping
    }

    @discardableResult
    func importArchived(
        _ receipts: [ArchiveImporter.StagedReceipt],
        categories: [ArchiveManifest.Category] = []
    ) async throws -> ArchiveImportResult {
        var result = ArchiveImportResult()
        let categoryMapping = try reconcile(categories)

        for staged in receipts {
            let entry = staged.entry

            guard let imageData = staged.imageData else {
                // The manifest promised an image the archive does not hold. Importing the
                // metadata alone would create a receipt that can never be opened.
                result.missingImages += 1
                logger.error("Import: no image for \(entry.id, privacy: .public)")
                continue
            }

            let existing = try fetchReceipt(id: entry.id)
            let localState = existing.map { receipt in
                ArchiveMergePolicy.LocalState(
                    modifiedAt: receipt.modifiedAt,
                    hasImageFile: (try? fileStore.fullResolutionImage(
                        atRelativePath: receipt.relativePath
                    )) != nil
                )
            }

            switch ArchiveMergePolicy.decide(local: localState, archivedModifiedAt: entry.modifiedAt) {
            case .skip:
                result.skipped += 1

            case .insert:
                let relativePath = try fileStore.write(imageData, for: entry.id)
                modelContext.insert(
                    makeReceipt(from: entry, relativePath: relativePath, categoryMapping: categoryMapping)
                )
                result.inserted += 1

            case .update:
                let relativePath = try fileStore.write(imageData, for: entry.id)
                if let existing {
                    apply(entry, to: existing, relativePath: relativePath, categoryMapping: categoryMapping)
                } else {
                    modelContext.insert(
                        makeReceipt(from: entry, relativePath: relativePath, categoryMapping: categoryMapping)
                    )
                }
                result.updated += 1
            }
        }

        try modelContext.save()
        logger.info(
            """
            Import: \(result.inserted, privacy: .public) inserted, \
            \(result.updated, privacy: .public) updated, \
            \(result.skipped, privacy: .public) skipped.
            """
        )
        return result
    }

    /// Local id for an archived category reference.
    private func localCategoryID(for archived: UUID?, mapping: [UUID: UUID]) -> UUID? {
        guard let archived else { return nil }
        return mapping[archived] ?? archived
    }

    private func makeReceipt(
        from entry: ArchiveManifest.Entry,
        relativePath: String,
        categoryMapping: [UUID: UUID]
    ) -> Receipt {
        Receipt(
            id: entry.id,
            capturedAt: entry.capturedAt,
            createdAt: entry.createdAt,
            modifiedAt: entry.modifiedAt,
            relativePath: relativePath,
            merchant: entry.merchant,
            amount: entry.decimalAmount,
            currencyCode: entry.currencyCode,
            note: entry.note,
            ocrText: entry.ocrText,
            categoryID: localCategoryID(for: entry.categoryID, mapping: categoryMapping),
            needsReview: entry.requiresReview,
            searchIndex: ReceiptSearchIndex.make(
                merchant: entry.merchant,
                note: entry.note,
                ocrText: entry.ocrText
            )
        )
    }

    private func apply(
        _ entry: ArchiveManifest.Entry,
        to receipt: Receipt,
        relativePath: String,
        categoryMapping: [UUID: UUID]
    ) {
        receipt.capturedAt = entry.capturedAt
        receipt.createdAt = entry.createdAt
        receipt.modifiedAt = entry.modifiedAt
        receipt.relativePath = relativePath
        receipt.merchant = entry.merchant
        receipt.amount = entry.decimalAmount
        receipt.currencyCode = entry.currencyCode
        receipt.note = entry.note
        receipt.ocrText = entry.ocrText
        receipt.categoryID = localCategoryID(for: entry.categoryID, mapping: categoryMapping)
        receipt.needsReview = entry.requiresReview
        receipt.searchIndex = ReceiptSearchIndex.make(
            merchant: entry.merchant,
            note: entry.note,
            ocrText: entry.ocrText
        )
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
