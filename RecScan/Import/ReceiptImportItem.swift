import Foundation
import UIKit

/// One image on its way into the library.
///
/// Responsibilities:
/// - Carry an image with whatever the source could tell us about it.
///
/// Produced by every import route — Photos, Files, a shared document — so the store has a
/// single shape to accept regardless of where a receipt came from.
///
/// One item is one receipt. A multi-page document is stitched into a single image before
/// it gets here (see `ImageStitcher`), so nothing downstream has to know about pages.
struct ReceiptImportItem: Sendable {

    let image: UIImage
    let capturedAt: Date
    /// Text already present in the source, for PDFs. Real text beats OCR.
    let ocrText: String?

    init(image: UIImage, capturedAt: Date, ocrText: String? = nil) {
        self.image = image
        self.capturedAt = capturedAt
        self.ocrText = ocrText
    }
}
