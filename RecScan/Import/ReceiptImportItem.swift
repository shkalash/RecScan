import Foundation
import UIKit

/// One image on its way into the library.
///
/// Responsibilities:
/// - Carry an image with whatever the source could tell us about it.
///
/// Produced by every import route — Photos, Files, a shared document — so the store has a
/// single shape to accept regardless of where a receipt came from.
struct ReceiptImportItem: Sendable {

    let image: UIImage
    let capturedAt: Date
    /// `false` when the date was inferred rather than read from the file.
    ///
    /// Drives the review flag: an import of fifty photos that all carry EXIF dates should
    /// leave nothing badged, while the handful that had to be guessed stay visible.
    let dateIsCertain: Bool
    /// Text already present in the source, for PDFs. Real text beats OCR.
    let ocrText: String?
    /// Shared by every page of a multi-page document.
    let groupID: UUID?
    let pageIndex: Int

    init(
        image: UIImage,
        capturedAt: Date,
        dateIsCertain: Bool,
        ocrText: String? = nil,
        groupID: UUID? = nil,
        pageIndex: Int = 0
    ) {
        self.image = image
        self.capturedAt = capturedAt
        self.dateIsCertain = dateIsCertain
        self.ocrText = ocrText
        self.groupID = groupID
        self.pageIndex = pageIndex
    }
}
