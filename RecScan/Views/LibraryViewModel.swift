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
            try await store.importScan(pages: pages, capturedAt: Date())
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

    // MARK: - Constants

    private enum ErrorTitle {
        static let importFailed: String.LocalizationValue = "error.import.title"
        static let deleteFailed: String.LocalizationValue = "error.delete.title"
    }
}
