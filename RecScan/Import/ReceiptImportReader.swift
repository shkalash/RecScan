import Foundation
import UniformTypeIdentifiers
import UIKit

/// Turns files and picked photos into importable items.
///
/// Responsibilities:
/// - Decide whether a payload is an image or a PDF and produce items accordingly.
///
/// One entry point for every route, so Photos, the file picker and a shared document all
/// arrive at the store having been through the same date and rasterisation rules.
enum ReceiptImportReader {

    /// Items for a payload whose type is already known.
    static func items(from data: Data, isPDF: Bool, fileDate: Date? = nil) -> [ReceiptImportItem] {
        let captured = ImportDateReader.captureDate(from: data, fileDate: fileDate)

        guard !isPDF else {
            return PDFReceiptReader.items(from: data, capturedAt: captured)
        }
        guard let image = UIImage(data: data) else { return [] }
        return [
            ReceiptImportItem(
                image: image,
                capturedAt: captured.date,
                dateIsCertain: captured.isCertain
            )
        ]
    }

    /// Items for a file on disk, typed by its extension.
    ///
    /// - Note: a security-scoped URL must already be accessible; this does not claim it.
    static func items(atFileURL url: URL) -> [ReceiptImportItem] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let fileDate = attributes?[.creationDate] as? Date
        let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false

        return items(from: data, isPDF: isPDF, fileDate: fileDate)
    }
}
