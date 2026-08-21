import CoreGraphics
import Foundation
import PDFKit
import UIKit

/// Turns a PDF into receipts.
///
/// Responsibilities:
/// - Rasterise each page to an image.
/// - Lift any embedded text out of the page.
///
/// ## Why pages become images
/// A PDF page could have been stored as-is, but the whole library — thumbnails, zoom, PDF
/// export, archiving — is built on one image per receipt. Rasterising means an e-receipt
/// behaves exactly like a scanned one everywhere, instead of every screen growing a second
/// media path.
///
/// The text is not thrown away though: a PDF receipt has real, selectable text, so it goes
/// straight into `ocrText`. That is strictly better than the OCR pass would produce, and it
/// makes the receipt searchable the moment it lands.
enum PDFReceiptReader {

    /// Rendered at twice the page's natural size so text stays legible when zoomed.
    private static let renderScale: CGFloat = 2

    /// One item per page, all sharing a group so they read as a single document.
    static func items(from data: Data, capturedAt: ImportDateReader.Result) -> [ReceiptImportItem] {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return [] }

        let groupID: UUID? = document.pageCount > 1 ? UUID() : nil
        var items: [ReceiptImportItem] = []
        items.reserveCapacity(document.pageCount)

        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                let image = render(page)
                items.append(
                    ReceiptImportItem(
                        image: image,
                        capturedAt: capturedAt.date,
                        dateIsCertain: capturedAt.isCertain,
                        ocrText: page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                        groupID: groupID,
                        pageIndex: index
                    )
                )
            }
        }
        return items
    }

    private static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // A PDF page is transparent; without a white ground it rasterises onto black.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let cgContext = context.cgContext
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: renderScale, y: -renderScale)
            page.draw(with: .mediaBox, to: cgContext)
        }
    }
}
