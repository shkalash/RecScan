import Foundation
import Observation

/// Drives PDF generation for the export sheet.
///
/// Responsibilities:
/// - Hold the export options.
/// - Generate the PDF off the main actor and publish the resulting file URL.
@MainActor
@Observable
final class ExportViewModel {

    var options = ExportOptions() {
        didSet {
            guard options != oldValue else { return }
            // The generated file no longer reflects the options on screen.
            discardGeneratedFile()
        }
    }

    private(set) var generatedURL: URL?
    private(set) var isGenerating = false
    var presentedError: PresentableError?

    /// Generates the PDF for `receipts`, replacing any previously generated file.
    func generate(receipts: [ReceiptSnapshot], fileStore: any ImageFileStoring) async {
        guard !receipts.isEmpty, !isGenerating else { return }

        discardGeneratedFile()
        isGenerating = true
        defer { isGenerating = false }

        let options = options
        // Resolved here, at the boundary, then passed down into pure rendering code.
        let currency = AppSettings.defaultCurrencyCode()
        do {
            // Rendering decodes full-resolution images; keeping it off the main actor
            // is what stops the sheet from freezing on a large selection.
            generatedURL = try await Task.detached(priority: .userInitiated) {
                try PDFBuilder(fileStore: fileStore, defaultCurrencyCode: currency).buildPDF(receipts: receipts, options: options)
            }.value
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.exportFailed, error: error)
        }
    }

    /// Removes the temporary file backing the previous share.
    ///
    /// The system eventually reclaims `temporaryDirectory`, but a session of repeated
    /// exports would otherwise leave a full-resolution PDF behind for every attempt.
    func discardGeneratedFile() {
        guard let url = generatedURL else { return }
        generatedURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    private enum ErrorTitle {
        static let exportFailed: String.LocalizationValue = "error.export.title"
    }
}
