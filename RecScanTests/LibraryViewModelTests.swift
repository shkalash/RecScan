import Foundation
import UniformTypeIdentifiers
import Testing
import UIKit
@testable import RecScan

/// A store that records calls instead of touching disk.
///
/// Responsibilities:
/// - Let the selection and error paths be tested without a container or file system.
private actor SpyReceiptStore: ReceiptStoring {

    enum Behaviour: Sendable {
        case succeed
        case fail(ReceiptStoreError)
    }

    private let behaviour: Behaviour
    private(set) var importedPageCounts: [Int] = []
    private(set) var deletedIDs: [[UUID]] = []
    private(set) var attachedText: [UUID: String] = [:]

    init(behaviour: Behaviour = .succeed) {
        self.behaviour = behaviour
    }

    @discardableResult
    func importScan(pages: [UIImage], capturedAt: Date) async throws -> [UUID] {
        importedPageCounts.append(pages.count)
        if case .fail(let error) = behaviour { throw error }
        return pages.map { _ in UUID() }
    }

    @discardableResult
    func importItems(_ items: [ReceiptImportItem]) async throws -> [UUID] {
        importedPageCounts.append(items.count)
        if case .fail(let error) = behaviour { throw error }
        return items.map { _ in UUID() }
    }

    func apply(_ edit: ReceiptEdit, toReceiptWithID id: UUID, confirming: Bool) async throws {
        if case .fail(let error) = behaviour { throw error }
    }

    func attachRecognizedText(_ text: String, toReceiptWithID id: UUID) async throws {
        attachedText[id] = text
        if case .fail(let error) = behaviour { throw error }
    }

    func delete(receiptsWithIDs ids: [UUID]) async throws {
        deletedIDs.append(ids)
        if case .fail(let error) = behaviour { throw error }
    }

    @discardableResult
    func createCategory(named name: String) async throws -> UUID {
        if case .fail(let error) = behaviour { throw error }
        return UUID()
    }

    func renameCategory(id: UUID, to name: String) async throws {
        if case .fail(let error) = behaviour { throw error }
    }

    func deleteCategory(id: UUID) async throws {
        if case .fail(let error) = behaviour { throw error }
    }

    @discardableResult
    func stampMissingCurrency() async throws -> Int {
        if case .fail(let error) = behaviour { throw error }
        return 0
    }

    func allReceipts() async throws -> [ReceiptSnapshot] {
        if case .fail(let error) = behaviour { throw error }
        return []
    }

    @discardableResult
    func importArchived(
        _ receipts: [ArchiveImporter.StagedReceipt],
        categories: [ArchiveManifest.Category]
    ) async throws -> ArchiveImportResult {
        if case .fail(let error) = behaviour { throw error }
        return ArchiveImportResult(inserted: receipts.count)
    }

    func allCategories() async throws -> [ArchiveManifest.Category] {
        if case .fail(let error) = behaviour { throw error }
        return []
    }
}

@MainActor
@Suite("Library screen state")
struct LibraryViewModelTests {

    private func snapshot(id: UUID = UUID()) -> ReceiptSnapshot {
        ReceiptSnapshot(
            id: id,
            capturedAt: .now,
            createdAt: .now,
            modifiedAt: .now,
            relativePath: "Receipts/\(id.uuidString).heic",
            merchant: nil,
            amount: nil,
            currencyCode: nil,
            note: nil,
            ocrText: nil,
            categoryID: nil,
            needsReview: false
        )
    }

    private func model(with count: Int) -> LibraryViewModel {
        let model = LibraryViewModel()
        model.visibleReceipts = (0..<count).map { _ in snapshot() }
        return model
    }

    @Test("Entering selection mode starts with nothing selected")
    func beginSelectingClearsSelection() {
        let model = model(with: 3)
        model.selection = [model.visibleReceipts[0].id]

        model.beginSelecting()

        #expect(model.isSelecting)
        #expect(model.selection.isEmpty)
    }

    @Test("Leaving selection mode discards the selection")
    func endSelectingClearsSelection() {
        let model = model(with: 3)
        model.beginSelecting()
        model.toggleSelection(of: model.visibleReceipts[0].id)

        model.endSelecting()

        #expect(!model.isSelecting)
        #expect(!model.hasSelection)
    }

    @Test("Tapping a receipt toggles it")
    func toggleSelection() {
        let model = model(with: 2)
        let id = model.visibleReceipts[0].id

        model.toggleSelection(of: id)
        #expect(model.selection == [id])

        model.toggleSelection(of: id)
        #expect(model.selection.isEmpty)
    }

    @Test("Select All covers everything visible, and toggles back off")
    func selectAllToggles() {
        let model = model(with: 4)

        model.toggleSelectAll()
        #expect(model.isEverythingSelected)
        #expect(model.selection.count == 4)

        model.toggleSelectAll()
        #expect(model.selection.isEmpty)
    }

    @Test("An empty library is never reported as fully selected")
    func emptyLibraryIsNotFullySelected() {
        #expect(!LibraryViewModel().isEverythingSelected)
    }

    @Test("Selected receipts keep the library's order")
    func selectedReceiptsKeepOrder() {
        let model = model(with: 4)
        let expected = [model.visibleReceipts[0], model.visibleReceipts[2]]
        model.selection = Set(expected.map(\.id))

        #expect(model.selectedReceipts == expected)
    }

    // MARK: - What an export contains

    /// The toolbar export is a shortcut for "everything I have filtered down to", so it
    /// must not depend on anything having been selected.
    @Test("Exporting without selecting takes everything the filter left showing")
    func exportsEverythingVisible() {
        let model = model(with: 3)

        #expect(model.receiptsForExport.count == 3)
    }

    @Test("Exporting while selecting takes only the selection")
    func exportsSelectionWhenSelecting() {
        let model = model(with: 3)
        model.beginSelecting()
        model.toggleSelection(of: model.visibleReceipts[1].id)

        #expect(model.receiptsForExport.map(\.id) == [model.visibleReceipts[1].id])
    }

    /// Selection mode with nothing ticked must not quietly fall back to exporting the
    /// whole library -- the bottom-bar button is disabled there, and the scope has to
    /// agree with it.
    @Test("Selecting nothing exports nothing")
    func selectingNothingExportsNothing() {
        let model = model(with: 3)
        model.beginSelecting()

        #expect(model.receiptsForExport.isEmpty)
    }

    @Test("Leaving selection mode goes back to exporting everything visible")
    func exportScopeRestoredAfterSelecting() {
        let model = model(with: 3)
        model.beginSelecting()
        model.toggleSelection(of: model.visibleReceipts[0].id)
        model.endSelecting()

        #expect(model.receiptsForExport.count == 3)
    }

    @Test("An empty library exports nothing")
    func emptyLibraryExportsNothing() {
        #expect(LibraryViewModel().receiptsForExport.isEmpty)
    }

    // MARK: - File picking

    /// Two `.fileImporter` modifiers on one view cancel each other out, so the two routes
    /// share one picker and must stay mutually exclusive.
    @Test("Picking an archive and picking receipts ask for different file types")
    func fileImportModesDiffer() {
        #expect(FileImportMode.archive.contentTypes == [.zip])
        #expect(FileImportMode.receipts.contentTypes == [.image, .pdf])
        #expect(FileImportMode.archive.allowsMultipleSelection == false)
        #expect(FileImportMode.receipts.allowsMultipleSelection)
    }

    @Test("Choosing a route puts the picker into exactly that mode")
    func fileImportModeIsExclusive() {
        let model = LibraryViewModel()
        #expect(model.fileImportMode == nil)

        model.fileImportMode = .archive
        #expect(model.fileImportMode == .archive)

        model.fileImportMode = .receipts
        #expect(model.fileImportMode == .receipts)
    }

    @Test("Pruning drops identifiers that no longer exist")
    func pruneDropsStaleSelection() {
        let model = model(with: 3)
        let surviving = model.visibleReceipts[1].id
        model.selection = [model.visibleReceipts[0].id, surviving]

        model.visibleReceipts = model.visibleReceipts.filter { $0.id == surviving }
        model.pruneSelection()

        #expect(model.selection == [surviving])
    }

    @Test("A successful import raises no error")
    func importSucceeds() async {
        let model = LibraryViewModel()
        let store = SpyReceiptStore()

        await model.importScannedPages([TestImage.solid(width: 100, height: 100)], using: store)

        #expect(model.presentedError == nil)
        #expect(!model.isImporting)
        #expect(await store.importedPageCounts == [1])
    }

    @Test("An empty scan never reaches the store")
    func emptyImportIsIgnored() async {
        let model = LibraryViewModel()
        let store = SpyReceiptStore()

        await model.importScannedPages([], using: store)

        #expect(await store.importedPageCounts.isEmpty)
    }

    @Test("A failed import surfaces an alert")
    func importFailureIsSurfaced() async {
        let model = LibraryViewModel()
        let store = SpyReceiptStore(behaviour: .fail(.emptyImportRequest))

        await model.importScannedPages([TestImage.solid(width: 100, height: 100)], using: store)

        #expect(model.presentedError != nil)
        #expect(!model.isImporting)
    }

    @Test("Deleting the selection clears selection mode")
    func deleteClearsSelection() async {
        let model = model(with: 2)
        model.beginSelecting()
        model.toggleSelectAll()
        let selected = model.selection
        let store = SpyReceiptStore()

        await model.deleteSelectedReceipts(using: store)

        #expect(!model.isSelecting)
        #expect(model.selection.isEmpty)
        #expect(await Set(store.deletedIDs[0]) == selected)
    }

    @Test("A failed delete keeps the selection so the user can retry")
    func deleteFailureKeepsSelection() async {
        let model = model(with: 2)
        model.beginSelecting()
        model.toggleSelectAll()
        let store = SpyReceiptStore(behaviour: .fail(.receiptNotFound(id: UUID())))

        await model.deleteSelectedReceipts(using: store)

        #expect(model.presentedError != nil)
        #expect(model.selection.count == 2)
    }
}
