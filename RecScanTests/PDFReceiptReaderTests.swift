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

    // MARK: - Which date wins

    private var fallbackDate: Date { TestCalendar.date(year: 2026, month: 2, day: 9) }
    private var reference: Date { TestCalendar.date(year: 2026, month: 9, day: 1) }

    /// The whole point: an emailed receipt carries its date on the page, and that beats
    /// every guess about when the file was handled.
    @Test("A date printed on the receipt beats everything else")
    func printedDateWins() {
        let chosen = PDFReceiptReader.captureDate(
            printedIn: "Invoice 21/08/2026  Total 52.30",
            documentCreated: TestCalendar.date(year: 2026, month: 8, day: 30),
            fallback: fallbackDate,
            now: reference,
            calendar: TestCalendar.utcGregorian
        )

        #expect(chosen == TestCalendar.date(year: 2026, month: 8, day: 21, hour: 12))
    }

    @Test("With no printed date, the PDF's own creation date is used")
    func documentDateIsTheFirstFallback() {
        let created = TestCalendar.date(year: 2026, month: 8, day: 30)

        let chosen = PDFReceiptReader.captureDate(
            printedIn: "Thank you for your custom",
            documentCreated: created,
            fallback: fallbackDate,
            now: reference
        )

        #expect(chosen == created)
    }

    /// Printing an email to PDF stamps it with today, which says nothing — and would
    /// beat a genuinely older file date if it were trusted.
    @Test("A PDF created today is ignored in favour of the file's own date")
    func sameDayCreationIsIgnored() {
        let chosen = PDFReceiptReader.captureDate(
            printedIn: "Thank you for your custom",
            documentCreated: TestCalendar.date(year: 2026, month: 9, day: 1, hour: 9),
            fallback: fallbackDate,
            now: reference
        )

        #expect(chosen == fallbackDate)
    }

    @Test("A creation date in the future is ignored")
    func futureCreationIgnored() {
        let chosen = PDFReceiptReader.captureDate(
            printedIn: nil,
            documentCreated: TestCalendar.date(year: 2027, month: 1, day: 1),
            fallback: fallbackDate,
            now: reference
        )

        #expect(chosen == fallbackDate)
    }

    @Test("With nothing to go on, the fallback stands")
    func fallbackStands() {
        let chosen = PDFReceiptReader.captureDate(
            printedIn: nil, documentCreated: nil, fallback: fallbackDate, now: reference
        )

        #expect(chosen == fallbackDate)
    }

    /// A bare time used to resolve to today via NSDataDetector, which is the exact
    /// failure this feature exists to remove.
    @Test("A printed time is not mistaken for a date")
    func printedTimeIsNotADate() {
        let chosen = PDFReceiptReader.captureDate(
            printedIn: "Printed 14:32", documentCreated: nil, fallback: fallbackDate, now: reference
        )

        #expect(chosen == fallbackDate)
    }

}
