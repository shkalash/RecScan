import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// State and actions for the receipt library screen.
///
/// Responsibilities:
/// - Hold filter, selection and sheet-presentation state.
/// - Drive imports and deletions through `ReceiptStoring`.
///
/// ## Why the store is passed per call rather than injected at init
/// SwiftUI builds `@State` objects before the environment is readable, so an
/// initialiser-injected store would have to be optional and set later — a lifecycle
/// trap that produces silent no-ops if the wiring is ever missed. Taking the store as
/// a parameter keeps every call site provably wired.
@MainActor
@Observable
final class LibraryViewModel {

    // MARK: - Filtering

    var filter = ReceiptFilter()

    // MARK: - Selection

    private(set) var isSelecting = false
    var selection: Set<UUID> = []

    /// Snapshots of everything currently passing the filter, newest first.
    ///
    /// Published by the grid, which owns the `@Query`. The library needs it for
    /// "select all" and to hand a concrete list to the exporter.
    var visibleReceipts: [ReceiptSnapshot] = []

    // MARK: - Presentation

    var isPresentingScanner = false
    var isPresentingFilter = false
    var isPresentingExport = false
    var isPresentingArchiveExport = false
    var isPresentingArchiveImporter = false
    var isPresentingPhotoPicker = false
    var isPresentingFileImporter = false
    var photoSelection: [PhotosPickerItem] = []

    /// Gathers `.onOpenURL` callbacks, which arrive one per file, into one batch.
    private let handoffQueue = ImportQueue()

    /// Recognition runs one receipt at a time in the background; a fifty-photo import must
    /// not start fifty at once.
    private let recognitionQueue = TextRecognitionQueue()

    /// Text read off each receipt, keyed by receipt id.
    ///
    /// Published rather than only persisted so the review sheet can show suggestions the
    /// moment each one lands, instead of opening empty and staying that way.
    private(set) var recognizedText: [UUID: String] = [:]
    var isPresentingSettings = false
    var isPresentingReport = false
    var importResult: ArchiveImportResult?
    /// Newly added receipts awaiting their details. Empty dismisses the sheet.
    var pendingReview: [ReceiptSnapshot] = []
    var isConfirmingDeletion = false
    var isImporting = false
    var presentedError: PresentableError?

    // MARK: - Derived state

    var hasSelection: Bool { !selection.isEmpty }

    var isEverythingSelected: Bool {
        !visibleReceipts.isEmpty && selection.count == visibleReceipts.count
    }

    /// The selected receipts, in the order they appear in the library.
    var selectedReceipts: [ReceiptSnapshot] {
        visibleReceipts.filter { selection.contains($0.id) }
    }

    // MARK: - Selection actions

    func beginSelecting() {
        isSelecting = true
        selection.removeAll()
    }

    func endSelecting() {
        isSelecting = false
        selection.removeAll()
    }

    func toggleSelection(of id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func toggleSelectAll() {
        if isEverythingSelected {
            selection.removeAll()
        } else {
            selection = Set(visibleReceipts.map(\.id))
        }
    }

    /// Drops identifiers that no longer exist, so a stale selection cannot resurrect
    /// a deleted receipt in the export sheet.
    func pruneSelection() {
        let available = Set(visibleReceipts.map(\.id))
        selection.formIntersection(available)
    }

    // MARK: - Store actions

    func importScannedPages(_ pages: [UIImage], using store: any ReceiptStoring) async {
        guard !pages.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            let created = try await store.importScan(pages: pages, capturedAt: Date())
            // Straight into review rather than saving silently: the details are easiest to
            // supply now, while the receipt is still in hand.
            let all = try await store.allReceipts()
            let ids = Set(created)
            pendingReview = all.filter { ids.contains($0.id) }
            await recognizeText(for: pendingReview, using: store, fileStore: ImageFileStore())
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.importFailed, error: error)
        }
    }

    func deleteSelectedReceipts(using store: any ReceiptStoring) async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }

        do {
            try await store.delete(receiptsWithIDs: ids)
            endSelecting()
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.deleteFailed, error: error)
        }
    }

    // MARK: - Text recognition

    /// Queues text recognition for newly added receipts.
    ///
    /// Fire and forget: the results land in `ocrText` and are parsed for amounts when a
    /// receipt is opened, so nothing here has to finish before the review sheet appears.
    func recognizeText(
        for receipts: [ReceiptSnapshot],
        using store: any ReceiptStoring,
        fileStore: any ImageFileStoring
    ) async {
        for receipt in receipts {
            // PDF imports already carry real extracted text -- far better than anything
            // recognition could produce -- so they are published straight through.
            if let existing = receipt.ocrText, !existing.isEmpty {
                recognizedText[receipt.id] = existing
                continue
            }

            let id = receipt.id
            let path = receipt.relativePath

            // Not awaited: enqueue returns as soon as the work is chained, so the review
            // sheet opens immediately and fills in behind it. The work outlives this
            // sheet, which is what keeps a dismissed batch from losing its search text.
            await recognitionQueue.enqueue { [weak self] in
                guard let image = try? fileStore.fullResolutionImage(atRelativePath: path),
                      let text = try? ReceiptTextRecognizer().recognizeText(in: image),
                      !text.isEmpty
                else { return }

                try? await store.attachRecognizedText(text, toReceiptWithID: id)
                await MainActor.run { self?.recognizedText[id] = text }
            }
        }
    }

    /// Waits for queued recognition to finish. Tests only -- the app never blocks on this.
    func drainRecognition() async {
        await recognitionQueue.drain()
    }

    // MARK: - Importing files and photos

    /// Imports photos chosen in the system picker.
    ///
    /// Loaded as `Data` rather than `Image` so the original bytes — and therefore the EXIF
    /// capture date — survive; a transferable `Image` arrives re-rendered and undated.
    func importPickedPhotos(_ selection: [PhotosPickerItem], using store: any ReceiptStoring) async {
        guard !selection.isEmpty else { return }
        isImporting = true
        defer {
            isImporting = false
            photoSelection = []
        }

        var items: [ReceiptImportItem] = []
        for picked in selection {
            guard let data = try? await picked.loadTransferable(type: Data.self) else { continue }
            items.append(contentsOf: ReceiptImportReader.items(from: data, isPDF: false))
        }
        await finishImport(of: items, using: store)
    }

    /// Imports files chosen in the document picker, or handed over by another app.
    func importFiles(at urls: [URL], using store: any ReceiptStoring, isInbox: Bool = false) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        var items: [ReceiptImportItem] = []
        for url in urls {
            // A picked URL is security-scoped and unreadable until access is started.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            items.append(contentsOf: ReceiptImportReader.items(atFileURL: url))
            if isInbox { try? FileManager.default.removeItem(at: url) }
        }
        await finishImport(of: items, using: store)
    }

    /// Saves the items and opens review over exactly what was created.
    private func finishImport(of items: [ReceiptImportItem], using store: any ReceiptStoring) async {
        guard !items.isEmpty else {
            presentedError = PresentableError(
                titleKey: ErrorTitle.importFailed, error: ReceiptStoreError.emptyImportRequest
            )
            return
        }

        do {
            let created = try await store.importItems(items)
            let all = try await store.allReceipts()
            let ids = Set(created)
            pendingReview = all.filter { ids.contains($0.id) }
            await recognizeText(for: pendingReview, using: store, fileStore: ImageFileStore())
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.importFailed, error: error)
        }
    }

    /// Imports anything the share extension left behind.
    ///
    /// Files are removed only after the import succeeds, so a failure means the next
    /// foreground tries again rather than quietly discarding what was shared.
    func drainSharedInbox(using store: any ReceiptStoring) async {
        let pending = SharedInbox.pendingURLs()
        guard !pending.isEmpty else { return }

        isImporting = true
        defer { isImporting = false }

        var items: [ReceiptImportItem] = []
        for url in pending {
            items.append(contentsOf: ReceiptImportReader.items(atFileURL: url))
        }
        guard !items.isEmpty else {
            SharedInbox.remove(pending)
            return
        }

        do {
            let created = try await store.importItems(items)
            let all = try await store.allReceipts()
            let ids = Set(created)
            pendingReview = all.filter { ids.contains($0.id) }
            SharedInbox.remove(pending)
            await recognizeText(for: pendingReview, using: store, fileStore: ImageFileStore())
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.importFailed, error: error)
        }
    }

    /// Accepts a file handed over by AirDrop or "Open with".
    ///
    /// Queued rather than imported immediately: these arrive one callback per file, and
    /// importing on each would raise a review sheet per file, each replacing the last.
    func acceptHandoff(of url: URL, using store: any ReceiptStoring) {
        guard canHandle(url) || canImport(url) else { return }

        handoffQueue.enqueue(url) { [weak self] batch in
            guard let self else { return }
            // Archives and receipts are different imports, so a mixed batch is split
            // rather than forced through one path.
            let archives = batch.filter { self.canHandle($0) }
            let receipts = batch.filter { !self.canHandle($0) && self.canImport($0) }

            for archive in archives {
                await self.importArchive(at: archive, using: store, isInbox: true)
            }
            if !receipts.isEmpty {
                await self.importFiles(at: receipts, using: store, isInbox: true)
            }
        }
    }

    /// Whether a handed-over file is something this app should act on.
    func canImport(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    // MARK: - Archive

    /// Reads an archive and merges it into the library.
    ///
    /// - Parameter isInbox: `true` when the file arrived via `.onOpenURL`, which copies
    ///   it into `Documents/Inbox`. Those copies are ours to delete; a file the user
    ///   picked from elsewhere is not.
    func importArchive(
        at url: URL,
        using store: any ReceiptStoring,
        isInbox: Bool = false
    ) async {
        isImporting = true
        defer { isImporting = false }

        // A picked URL is security-scoped and unreadable until access is started.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let contents = try await Task.detached(priority: .userInitiated) {
                let read = try ArchiveImporter().read(archiveAt: url)
                return (read.receipts, read.manifest.categoryList)
            }.value
            importResult = try await store.importArchived(contents.0, categories: contents.1)
            if isInbox { try? FileManager.default.removeItem(at: url) }
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.importArchiveFailed, error: error)
        }
    }

    /// Handles a file handed over by AirDrop or "Open with".
    ///
    /// - Returns: `true` when the URL was something this app should act on.
    func canHandle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == ArchiveManifest.Layout.archiveFileExtension
    }

    // MARK: - Constants

    private enum ErrorTitle {
        static let importFailed: String.LocalizationValue = "error.import.title"
        static let deleteFailed: String.LocalizationValue = "error.delete.title"
        static let importArchiveFailed: String.LocalizationValue = "error.archive.import.title"
    }
}
