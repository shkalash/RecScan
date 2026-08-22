import Foundation
import PDFKit
import Testing
import UIKit
@testable import RecScan

@Suite("PDF import")
struct PDFReceiptReaderTests {

    /// A PDF with `pageCount` pages, each carrying real text.
    private func pdfData(pageCount: Int, text: String = "TOTAL 42.50") -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18)
                ]
                "\(text) page \(page + 1)".draw(at: CGPoint(x: 20, y: 20), withAttributes: attributes)
            }
        }
    }

    private var certainDate: ImportDateReader.Result {
        ImportDateReader.Result(date: TestCalendar.date(year: 2026, month: 7, day: 4), isCertain: true)
    }

    /// A multi-page PDF is one long receipt, not several.
    @Test("A multi-page PDF becomes a single item")
    func onePDFIsOneReceipt() {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 3), capturedAt: certainDate)

        #expect(items.count == 1)
    }

    @Test("The pages are stacked, so the image is as tall as all of them together")
    func stacksPages() throws {
        let one = try #require(PDFReceiptReader.items(from: pdfData(pageCount: 1), capturedAt: certainDate).first)
        let three = try #require(PDFReceiptReader.items(from: pdfData(pageCount: 3), capturedAt: certainDate).first)

        #expect(three.image.size.width == one.image.size.width)
        #expect(three.image.size.height == one.image.size.height * 3)
    }

    @Test("A single-page PDF still produces one item")
    func singlePage() {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 1), capturedAt: certainDate)

        #expect(items.count == 1)
    }

    @Test("Embedded text is lifted into ocrText")
    func liftsEmbeddedText() throws {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 1), capturedAt: certainDate)

        // A PDF receipt has real text; using it beats running OCR over a rasterisation
        // of that same text.
        let text = try #require(items.first?.ocrText)
        #expect(text.contains("TOTAL 42.50"))
    }

    @Test("Pages rasterise to a usable image")
    func rasterisesPages() throws {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 1), capturedAt: certainDate)

        let image = try #require(items.first?.image)
        #expect(image.size.width > 0)
        #expect(image.size.height > image.size.width)
    }

    @Test("The capture date carries onto the item")
    func carriesDate() throws {
        let date = TestCalendar.date(year: 2026, month: 2, day: 9)
        let result = ImportDateReader.Result(date: date, isCertain: false)

        let item = try #require(PDFReceiptReader.items(from: pdfData(pageCount: 2), capturedAt: result).first)

        #expect(item.capturedAt == date)
    }

    @Test("Data that is not a PDF yields nothing rather than crashing")
    func handlesGarbage() {
        #expect(PDFReceiptReader.items(from: Data("nope".utf8), capturedAt: certainDate).isEmpty)
    }
}
