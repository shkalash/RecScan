import CoreGraphics
import Foundation
import PDFKit
import UIKit

/// Turns a PDF into a receipt.
///
/// Responsibilities:
/// - Rasterise every page and join them into one image.
/// - Lift any embedded text out of the document.
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
///
/// ## Why a multi-page PDF is one receipt
/// A receipt long enough to need a second page is still one purchase. Splitting it per page
/// produced a tile, a review entry and a report line for each — one shop billed several
/// times over. The pages are stacked into a single tall image instead.
enum PDFReceiptReader {

    /// Rendered at twice the page's natural size so text stays legible when zoomed.
    private static let renderScale: CGFloat = 2

    /// One item for the whole document.
    ///
    /// - Returns: a single-element array, or empty when the data is not a readable PDF.
    ///   An array rather than an optional so the import routes stay uniform.
    static func items(from data: Data, capturedAt: ImportDateReader.Result) -> [ReceiptImportItem] {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return [] }

        var images: [UIImage] = []
        images.reserveCapacity(document.pageCount)
        var text: [String] = []

        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                images.append(render(page))
                if let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !pageText.isEmpty {
                    text.append(pageText)
                }
            }
        }

        guard let merged = ImageStitcher.stack(images) else { return [] }

        let joined = text.isEmpty ? nil : text.joined(separator: "\n")

        return [
            ReceiptImportItem(
                image: merged,
                capturedAt: Self.captureDate(
                    printedIn: joined,
                    documentCreated: document.documentAttributes?[
                        PDFDocumentAttribute.creationDateAttribute
                    ] as? Date,
                    fallback: capturedAt.date
                ),
                // Joined in page order, so an amount on the last page is still found and
                // the search index covers the whole document.
                ocrText: joined
            )
        ]
    }

    /// When the receipt was actually issued.
    ///
    /// **The date printed on the receipt always wins.** Everything below it is a guess
    /// about when a file was handled, not about when money was spent.
    ///
    /// A PDF's `CreationDate` is only consulted when the page prints no date, and then
    /// only if it is not from today: printing an email to PDF stamps it with the moment
    /// you pressed print, which is the very answer this exists to avoid and is
    /// indistinguishable from a real one. A same-day stamp is therefore treated as no
    /// information at all — it says nothing the fallback does not already say, and the
    /// fallback may hold a genuinely older file date.
    static func captureDate(
        printedIn text: String?,
        documentCreated: Date?,
        fallback: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        if let printed = ReceiptDateParser.bestGuess(in: text, now: now, calendar: calendar)?.date {
            return printed
        }
        if let documentCreated,
           documentCreated <= now,
           !calendar.isDate(documentCreated, inSameDayAs: now) {
            return documentCreated
        }
        return fallback
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
