import Foundation
import Observation
import UIKit

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
    var isPresentingSettings = false
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
