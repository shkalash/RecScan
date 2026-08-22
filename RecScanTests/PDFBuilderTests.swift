import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import RecScan

/// Nested inside `ImagePipelineSuite` so it inherits `.serialized`.
extension ImagePipelineSuite {

    @Suite("PDF export")
    struct PDFBuilderTests {

        private let directory = TemporaryDirectory()
        private let fileStore: ImageFileStore
        private let builder: PDFBuilder

        init() {
            let fileStore = ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache())
            self.fileStore = fileStore
            builder = PDFBuilder(fileStore: fileStore)
        }

        // MARK: - Fixtures

        @discardableResult
        private func storedSnapshot(
            day: Int,
            amount: Decimal? = nil,
            ocrText: String? = nil
        ) throws -> ReceiptSnapshot {
            let id = UUID()
            let path = try fileStore.write(TestImage.solid(width: 600, height: 900), for: id)
            return ReceiptSnapshot(
                id: id,
                capturedAt: TestCalendar.date(year: 2026, month: 4, day: day),
                createdAt: TestCalendar.date(year: 2026, month: 4, day: day),
                modifiedAt: TestCalendar.date(year: 2026, month: 4, day: day),
                relativePath: path,
                merchant: "Merchant \(day)",
                amount: amount,
                currencyCode: "USD",
                note: nil,
                ocrText: ocrText,
                categoryID: nil,
                needsReview: false
            )
        }

        /// `ExportSummary` derives its rows from receipts; this rebuilds one carrying a
        /// chosen set of month totals so pagination can be tested without writing
        /// hundreds of image files.
        private func summaryWith(
            _ summary: ExportSummary,
            monthTotals: [ExportSummary.MonthTotal]
        ) -> ExportSummary {
            ExportSummary(
                receiptCount: monthTotals.reduce(0) { $0 + $1.count },
                monthTotals: monthTotals,
                grandTotal: monthTotals.reduce(Decimal.zero) { $0 + $1.total },
                currencyCode: "USD",
                hasExcludedCurrencies: false
            )
        }

        private func pageCount(of url: URL) throws -> Int {
            let document = try #require(CGPDFDocument(url as CFURL))
            return document.numberOfPages
        }

        private var noSummaryOptions: ExportOptions {
            ExportOptions(
                layout: .onePerPage, includeHeader: true, includeSummaryPage: false,
                includeCategoryBreakdown: false, includeSearchableText: false
            )
        }

        // MARK: - Tests

        @Test("Exporting nothing is rejected")
        func rejectsEmptySelection() {
            #expect(throws: PDFBuildError.noReceiptsSelected) {
                try builder.buildPDF(receipts: [], options: ExportOptions())
            }
        }

        @Test("One-per-page produces one page per receipt")
        func onePagePerReceipt() throws {
            let receipts = try (1...5).map { try storedSnapshot(day: $0) }

            let url = try builder.buildPDF(receipts: receipts, options: noSummaryOptions)

            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            #expect(try pageCount(of: url) == 5)
        }

        @Test("Two-up halves the page count and rounds odd counts up")
        func twoUpHalvesPages() throws {
            let receipts = try (1...5).map { try storedSnapshot(day: $0) }
            var options = noSummaryOptions
            options.layout = .twoUp

            let url = try builder.buildPDF(receipts: receipts, options: options)

            #expect(try pageCount(of: url) == 3)
        }

        @Test("The summary page adds exactly one page")
        func summaryAddsOnePage() throws {
            let receipts = try (1...3).map { try storedSnapshot(day: $0, amount: 10) }
            var options = noSummaryOptions
            options.includeSummaryPage = true

            let url = try builder.buildPDF(receipts: receipts, options: options)

            #expect(try pageCount(of: url) == 4)
        }

        @Test("The category breakdown adds a page of its own")
        func categoryBreakdownAddsAPage() throws {
            let receipts = try (1...3).map { try storedSnapshot(day: $0, amount: 10) }
            var options = noSummaryOptions
            options.includeSummaryPage = true
            options.includeCategoryBreakdown = true

            let url = try builder.buildPDF(receipts: receipts, options: options)

            // 3 receipts + month summary + category breakdown.
            #expect(try pageCount(of: url) == 5)
        }

        @Test("Turning the breakdown off removes only that page")
        func breakdownCanBeTurnedOff() throws {
            let receipts = try (1...2).map { try storedSnapshot(day: $0, amount: 10) }
            var options = noSummaryOptions
            options.includeSummaryPage = true
            options.includeCategoryBreakdown = false

            let url = try builder.buildPDF(receipts: receipts, options: options)

            #expect(try pageCount(of: url) == 3)
        }

        @Test("The report's period is the span of what was exported")
        func reportSpansTheSelection() throws {
            let receipts = try (1...3).map { try storedSnapshot(day: $0) }

            let span = try #require(PDFBuilder.span(of: receipts))

            // Half-open like every other interval here, so the last receipt is inside.
            #expect(span.contains(receipts[0].capturedAt))
            #expect(span.contains(receipts[2].capturedAt))
        }

        @Test("Pages are US Letter at 72 dpi")
        func pageGeometry() throws {
            let url = try builder.buildPDF(receipts: [try storedSnapshot(day: 1)], options: noSummaryOptions)

            let document = try #require(CGPDFDocument(url as CFURL))
            let page = try #require(document.page(at: 1))
            let box = page.getBoxRect(.mediaBox)

            #expect(box.width == PDFMetrics.pageSize.width)
            #expect(box.height == PDFMetrics.pageSize.height)
        }

        @Test("A receipt whose image is missing still produces its page")
        func survivesMissingImages() throws {
            let receipt = try storedSnapshot(day: 1)
            try fileStore.delete(relativePath: receipt.relativePath, id: receipt.id)

            let url = try builder.buildPDF(receipts: [receipt], options: noSummaryOptions)

            #expect(try pageCount(of: url) == 1)
        }

        @Test("The searchable text layer does not change the page count")
        func searchableTextLayer() throws {
            let receipt = try storedSnapshot(day: 1, ocrText: "TOTAL 12.34")
            var options = noSummaryOptions
            options.includeSearchableText = true

            let url = try builder.buildPDF(receipts: [receipt], options: options)

            #expect(try pageCount(of: url) == 1)
        }

        @Test("Generated files are named distinctly per export")
        func fileNamesAreTimestamped() throws {
            let receipt = try storedSnapshot(day: 1)
            let early = TestCalendar.date(year: 2026, month: 4, day: 1, hour: 9)
            let later = TestCalendar.date(year: 2026, month: 4, day: 1, hour: 10)

            let first = try builder.buildPDF(receipts: [receipt], options: noSummaryOptions, generatedAt: early)
            let second = try builder.buildPDF(receipts: [receipt], options: noSummaryOptions, generatedAt: later)

            #expect(first.lastPathComponent != second.lastPathComponent)
            #expect(first.pathExtension == "pdf")
        }

        @Test("A summary that fits stays on one page")
        func shortSummaryIsOnePage() throws {
            let receipts = try (1...3).map { try storedSnapshot(day: $0, amount: 10) }
            var options = noSummaryOptions
            options.includeSummaryPage = true

            let url = try builder.buildPDF(receipts: receipts, options: options)

            #expect(try pageCount(of: url) == receipts.count + 1)
        }

        @Test("A summary spanning more months than fit on a page is paginated")
        func longSummaryPaginates() {
            // Rows used to be drawn straight past the bottom margin and disappear.
            let rowsPerPage = PDFBuilder.monthRowsPerSummaryPage
            let months = rowsPerPage * 2 + 1
            let totals = (0..<months).map { index in
                ExportSummary.MonthTotal(
                    id: TestCalendar.date(year: 2020 + index / 12, month: index % 12 + 1, day: 1),
                    count: 1,
                    total: 10
                )
            }
            let summary = ExportSummary(receipts: [], calendar: TestCalendar.utcGregorian)

            let pages = PDFBuilder.summaryPages(for: summaryWith(summary, monthTotals: totals))

            #expect(pages.count == 3)
            #expect(pages.flatMap(\.self).count == months)
            #expect(pages.allSatisfy { $0.count <= rowsPerPage })
        }

        @Test("A selection with no amounts still produces one summary page")
        func emptySummaryStillGetsAPage() {
            let summary = ExportSummary(receipts: [], calendar: TestCalendar.utcGregorian)

            let pages = PDFBuilder.summaryPages(for: summary)

            #expect(pages.count == 1)
            #expect(pages[0].isEmpty)
        }

        @Test("At least one month row always fits")
        func rowsPerPageIsPositive() {
            #expect(PDFBuilder.monthRowsPerSummaryPage >= 1)
        }

        @Test("Aspect-fit centres the image without distorting it")
        func aspectFitPreservesRatio() {
            let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

            let fitted = PDFBuilder.aspectFitRect(for: CGSize(width: 100, height: 200), in: bounds)

            #expect(fitted.height == 100)
            #expect(fitted.width == 50)
            #expect(fitted.midX == bounds.midX)
            #expect(fitted.midY == bounds.midY)
        }

        @Test("Aspect-fit tolerates a degenerate image size")
        func aspectFitHandlesZeroSize() {
            let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

            #expect(PDFBuilder.aspectFitRect(for: .zero, in: bounds) == bounds)
        }
    }
}
