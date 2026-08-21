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

    @Test("Each page becomes its own receipt")
    func onePagePerReceipt() {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 3), capturedAt: certainDate)

        #expect(items.count == 3)
        #expect(items.map(\.pageIndex) == [0, 1, 2])
    }

    @Test("Pages of one document share a group")
    func pagesShareAGroup() throws {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 3), capturedAt: certainDate)

        let groupID = try #require(items.first?.groupID)
        #expect(items.allSatisfy { $0.groupID == groupID })
    }

    @Test("A single-page PDF is not given a group")
    func singlePageHasNoGroup() {
        let items = PDFReceiptReader.items(from: pdfData(pageCount: 1), capturedAt: certainDate)

        // A group means "these belong together"; one page belongs with nothing.
        #expect(items.count == 1)
        #expect(items[0].groupID == nil)
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

    @Test("The capture date and its certainty carry to every page")
    func carriesDate() {
        let uncertain = ImportDateReader.Result(date: Date(), isCertain: false)

        let items = PDFReceiptReader.items(from: pdfData(pageCount: 2), capturedAt: uncertain)

        #expect(items.allSatisfy { !$0.dateIsCertain })
    }

    @Test("Data that is not a PDF yields nothing rather than crashing")
    func handlesGarbage() {
        #expect(PDFReceiptReader.items(from: Data("nope".utf8), capturedAt: certainDate).isEmpty)
    }
}
