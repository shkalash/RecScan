import Foundation
import Observation

/// Drives archive creation for the export sheet.
///
/// Responsibilities:
/// - Hold the chosen scope and produce the zip off the main actor.
@MainActor
@Observable
final class ArchiveExportViewModel {

    /// Defaults to the whole library: an archive is a backup, and a filtered one that
    /// looks complete is the failure worth designing against.
    var scope: ArchiveScope = .entireLibrary {
        didSet {
            guard scope != oldValue else { return }
            discardGeneratedFile()
        }
    }

    private(set) var generatedURL: URL?
    private(set) var isGenerating = false
    var presentedError: PresentableError?

    func generate(
        selection: [ReceiptSnapshot],
        store: any ReceiptStoring,
        fileStore: any ImageFileStoring
    ) async {
        guard !isGenerating else { return }
        discardGeneratedFile()
        isGenerating = true
        defer { isGenerating = false }

        do {
            let receipts = switch scope {
            case .entireLibrary: try await store.allReceipts()
            case .currentSelection: selection
            }
            let categories = try await store.allCategories()
            generatedURL = try await Task.detached(priority: .userInitiated) {
                try ArchiveExporter(fileStore: fileStore)
                    .makeArchive(receipts: receipts, categories: categories)
            }.value
        } catch {
            presentedError = PresentableError(titleKey: "error.archive.export.title", error: error)
        }
    }

    /// Removes a previously generated archive.
    ///
    /// Unlike the PDF sheet this is safe to call on scope changes, but deliberately not
    /// on disappear — a share extension may still be reading the file.
    func discardGeneratedFile() {
        guard let url = generatedURL else { return }
        generatedURL = nil
        try? FileManager.default.removeItem(at: url)
    }
}
