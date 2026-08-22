import CoreGraphics
import Foundation
import UIKit

/// Renders selected receipts into a single PDF file.
///
/// Responsibilities:
/// - Lay out one or two receipts per page with an optional header and page footer.
/// - Optionally append a summary page.
/// - Optionally embed an invisible text layer so the PDF is searchable.
///
/// ## Why `UIGraphicsPDFRenderer` and not `PDFKit`
/// `PDFPage(image:)` produces a page and nothing else — no header line, no page
/// numbers, no two-up layout. Every one of those is a stated requirement, and PDFKit
/// exposes no layout control to add them.
///
/// ## Memory
/// Each page is rendered inside its own `autoreleasepool` and its full-resolution
/// image is loaded *inside* the loop. Preloading the images, or omitting the pool,
/// keeps every decoded bitmap resident and the app is jetsammed part-way through a
/// hundred-receipt export.
struct PDFBuilder: Sendable {

    private let fileStore: any ImageFileStoring
    /// Currency assumed for receipts carrying none. Injected so the renderer stays pure
    /// and does not reach into `UserDefaults` from a background task.
    private let defaultCurrencyCode: String
    private let logger = LogCategory.export.logger

    /// Category names, for the breakdown page. Passed in because the renderer has no
    /// access to the store and must not acquire one — it runs off the main actor.
    private let categoryNames: [UUID: String]

    init(
        fileStore: any ImageFileStoring = ImageFileStore(),
        defaultCurrencyCode: String = AppSettings.fallbackCurrencyCode,
        categoryNames: [UUID: String] = [:]
    ) {
        self.fileStore = fileStore
        self.defaultCurrencyCode = defaultCurrencyCode
        self.categoryNames = categoryNames
    }

    /// Generates the PDF and returns the URL it was written to.
    ///
    /// The file is written into the temporary directory and must stay alive until the
    /// share sheet has been dismissed — hand over the URL, never in-memory `Data`.
    func buildPDF(
        receipts: [ReceiptSnapshot],
        options: ExportOptions,
        generatedAt: Date = Date()
    ) throws -> URL {
        guard !receipts.isEmpty else { throw PDFBuildError.noReceiptsSelected }

        // `createdAt` breaks ties so a batch captured with one timestamp still lands in
        // the order it was added, rather than an order the sort does not define.
        let ordered = receipts.sorted { lhs, rhs in
            lhs.capturedAt == rhs.capturedAt
                ? lhs.createdAt < rhs.createdAt
                : lhs.capturedAt < rhs.capturedAt
        }
        let pages = ordered.chunked(into: options.layout.slotsPerPage)
        let summary = options.includeSummaryPage
            ? ExportSummary(receipts: ordered, defaultCurrencyCode: defaultCurrencyCode)
            : nil
        let summaryPages = summary.map { Self.summaryPages(for: $0) } ?? []

        // The report covers exactly what is being exported, so its period is the span of
        // the selection rather than a separately chosen range.
        let report: CategoryReport? = options.includeCategoryBreakdown && options.includeSummaryPage
            ? CategoryReport(
                receipts: ordered,
                names: categoryNames,
                interval: Self.span(of: ordered),
                defaultCurrencyCode: defaultCurrencyCode,
                uncategorisedLabel: String(localized: "report.uncategorised")
            )
            : nil
        let reportPages = report.map { Self.reportPages(for: $0) } ?? []
        let totalPageCount = pages.count + summaryPages.count + reportPages.count

        let url = FileManager.default.temporaryDirectory
            .appending(path: Self.fileName(generatedAt: generatedAt))
        let renderer = UIGraphicsPDFRenderer(bounds: PDFMetrics.pageRect, format: Self.documentFormat)

        try renderer.writePDF(to: url) { context in
            for (pageIndex, slotContents) in pages.enumerated() {
                // Non-negotiable: without this pool every decoded receipt stays
                // resident for the whole render.
                autoreleasepool {
                    context.beginPage()
                    let slots = Self.slotRects(for: options.layout)
                    for (slotIndex, receipt) in slotContents.enumerated() {
                        draw(receipt: receipt, in: slots[slotIndex], options: options)
                    }
                    drawFooter(pageNumber: pageIndex + 1, of: totalPageCount)
                }
            }

            if let summary {
                for (index, months) in summaryPages.enumerated() {
                    autoreleasepool {
                        context.beginPage()
                        drawSummary(summary, months: months, isFinalPage: index == summaryPages.count - 1)
                        drawFooter(pageNumber: pages.count + index + 1, of: totalPageCount)
                    }
                }
            }

            if let report {
                for (index, lines) in reportPages.enumerated() {
                    autoreleasepool {
                        context.beginPage()
                        drawReport(report, lines: lines, isFinalPage: index == reportPages.count - 1)
                        drawFooter(
                            pageNumber: pages.count + summaryPages.count + index + 1,
                            of: totalPageCount
                        )
                    }
                }
            }
        }

        logger.info("Exported \(ordered.count, privacy: .public) receipt(s) to PDF.")
        return url
    }

    // MARK: - File naming

    private static let fileNamePrefix = "Receipts-"
    private static let fileExtension = "pdf"

    private static func fileName(generatedAt: Date) -> String {
        "\(fileNamePrefix)\(ReceiptFormatting.exportTimestamp(for: generatedAt)).\(fileExtension)"
    }

    /// Document-level metadata written into the PDF catalogue.
    private static var documentFormat: UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: String(localized: "pdf.document.creator"),
            kCGPDFContextTitle as String: String(localized: "pdf.document.title")
        ]
        return format
    }

    // MARK: - Page geometry

    /// The rect available to receipt content, with margins applied and the footer band
    /// reserved.
    private static var contentRect: CGRect {
        CGRect(
            x: PDFMetrics.margin,
            y: PDFMetrics.margin,
            width: PDFMetrics.pageSize.width - PDFMetrics.margin * 2,
            height: PDFMetrics.pageSize.height - PDFMetrics.margin * 2 - PDFMetrics.footerHeight
        )
    }

    private static func slotRects(for layout: PDFPageLayout) -> [CGRect] {
        let content = contentRect
        switch layout {
        case .onePerPage:
            return [content]
        case .twoUp:
            let slotHeight = (content.height - PDFMetrics.slotSpacing) / 2
            return [
                CGRect(x: content.minX, y: content.minY, width: content.width, height: slotHeight),
                CGRect(
                    x: content.minX,
                    y: content.minY + slotHeight + PDFMetrics.slotSpacing,
                    width: content.width,
                    height: slotHeight
                )
            ]
        }
    }

    // MARK: - Receipt drawing

    private func draw(receipt: ReceiptSnapshot, in slot: CGRect, options: ExportOptions) {
        var imageRect = slot

        if options.includeHeader {
            let headerRect = CGRect(
                x: slot.minX,
                y: slot.minY,
                width: slot.width,
                height: PDFMetrics.headerHeight
            )
            drawHeader(receipt: receipt, in: headerRect)

            let consumed = PDFMetrics.headerHeight + PDFMetrics.headerImageSpacing
            imageRect = CGRect(
                x: slot.minX,
                y: slot.minY + consumed,
                width: slot.width,
                height: slot.height - consumed
            )
        }

        // Loaded here, released at the end of the enclosing page's autoreleasepool.
        if let image = try? fileStore.fullResolutionImage(atRelativePath: receipt.relativePath) {
            let target = Self.aspectFitRect(for: image.size, in: imageRect)
            image.draw(in: target)
        } else {
            logger.error("Missing image for receipt \(receipt.id, privacy: .public); page left blank.")
            Self.drawText(
                String(localized: "pdf.image.missing"),
                in: imageRect,
                font: .systemFont(ofSize: PDFMetrics.FontSize.header),
                alignment: .center,
                color: PDFMetrics.Ink.secondary
            )
        }

        if options.includeSearchableText, let ocrText = receipt.ocrText, !ocrText.isEmpty {
            drawSearchableText(ocrText, in: imageRect)
        }
    }

    /// Header line: date on the left, merchant in the middle, amount on the right.
    ///
    /// Three independent text runs rather than one joined string — assembling a line
    /// by concatenation bakes in an English word order and cannot be translated.
    private func drawHeader(receipt: ReceiptSnapshot, in rect: CGRect) {
        let font = UIFont.systemFont(ofSize: PDFMetrics.FontSize.header, weight: .medium)
        let columnWidth = rect.width / 3

        Self.drawText(
            ReceiptFormatting.receiptDate(for: receipt.capturedAt),
            in: CGRect(x: rect.minX, y: rect.minY, width: columnWidth, height: rect.height),
            font: font,
            alignment: .left,
            color: PDFMetrics.Ink.primary
        )

        Self.drawText(
            receipt.merchant ?? String(localized: "pdf.header.untitled"),
            in: CGRect(x: rect.minX + columnWidth, y: rect.minY, width: columnWidth, height: rect.height),
            font: font,
            alignment: .center,
            color: PDFMetrics.Ink.primary
        )

        if let amount = ReceiptFormatting.amount(receipt.amount, currencyCode: receipt.currencyCode, defaultCode: defaultCurrencyCode) {
            Self.drawText(
                amount,
                in: CGRect(
                    x: rect.minX + columnWidth * 2,
                    y: rect.minY,
                    width: columnWidth,
                    height: rect.height
                ),
                font: font,
                alignment: .right,
                color: PDFMetrics.Ink.primary
            )
        }
    }

    /// Draws the recognised text in a fully transparent colour over the image.
    ///
    /// The glyphs are still real text in the PDF, so Spotlight and Preview can find
    /// them, while nothing about the page's appearance changes.
    private func drawSearchableText(_ text: String, in rect: CGRect) {
        Self.drawText(
            text,
            in: rect,
            font: .systemFont(ofSize: PDFMetrics.searchableTextFontSize),
            alignment: .left,
            color: .clear,
            lineBreakMode: .byWordWrapping
        )
    }

    private func drawFooter(pageNumber: Int, of pageCount: Int) {
        let rect = CGRect(
            x: PDFMetrics.margin,
            y: PDFMetrics.pageSize.height - PDFMetrics.margin - PDFMetrics.footerHeight,
            width: PDFMetrics.pageSize.width - PDFMetrics.margin * 2,
            height: PDFMetrics.footerHeight
        )
        Self.drawText(
            String(localized: "pdf.footer.page \(pageNumber) \(pageCount)"),
            in: rect,
            font: .systemFont(ofSize: PDFMetrics.FontSize.footer),
            alignment: .center,
            color: PDFMetrics.Ink.secondary
        )
    }

    // MARK: - Summary pagination

    /// Splits the month rows across as many summary pages as they need.
    ///
    /// Why this is not a single page: a year of receipts is twelve rows, but the app is
    /// meant to accumulate for years, and an export spanning three or four of them
    /// overruns the page. Rows were previously drawn straight past the bottom margin
    /// and simply vanished, silently understating nothing but losing the breakdown.
    ///
    /// - Returns: one entry per summary page. Always at least one, so a selection with
    ///   no amounts at all still gets its count page.
    static func summaryPages(for summary: ExportSummary) -> [[ExportSummary.MonthTotal]] {
        guard !summary.monthTotals.isEmpty else { return [[]] }
        return summary.monthTotals.chunked(into: monthRowsPerSummaryPage)
    }

    /// How many month rows fit on one summary page once the fixed furniture — title,
    /// column header, both rules, the grand total and the currency note — is reserved.
    static var monthRowsPerSummaryPage: Int {
        let ruleHeight = PDFMetrics.Summary.rulerThickness + PDFMetrics.Summary.sectionSpacing
        let reserved =
            PDFMetrics.FontSize.summaryTitle * summaryTitleLineHeightMultiple
            + PDFMetrics.Summary.titleBottomSpacing
            + PDFMetrics.Summary.rowHeight          // column header
            + ruleHeight * 2                        // above and below the rows
            + PDFMetrics.Summary.rowHeight          // grand total
            + PDFMetrics.Summary.sectionSpacing
            + PDFMetrics.Summary.rowHeight          // mixed-currency note

        let available = contentRect.height - reserved
        return max(1, Int(available / PDFMetrics.Summary.rowHeight))
    }

    /// Line box for the summary title, as a multiple of its point size.
    private static let summaryTitleLineHeightMultiple: CGFloat = 1.4

    // MARK: - Category report

    /// The window the exported receipts actually cover.
    static func span(of receipts: [ReceiptSnapshot]) -> DateInterval? {
        guard let first = receipts.first?.capturedAt, let last = receipts.last?.capturedAt else {
            return nil
        }
        // `ordered` is ascending, and the interval is half-open elsewhere, so the end is
        // nudged past the final receipt to keep it inside.
        return DateInterval(start: min(first, last), end: max(first, last).addingTimeInterval(1))
    }

    /// Splits category lines across pages, reusing the summary's row budget.
    static func reportPages(for report: CategoryReport) -> [[CategoryReport.Line]] {
        guard !report.lines.isEmpty else { return [[]] }
        return report.lines.chunked(into: monthRowsPerSummaryPage)
    }

    private func drawReport(
        _ report: CategoryReport,
        lines: [CategoryReport.Line],
        isFinalPage: Bool
    ) {
        let content = Self.contentRect
        var cursorY = content.minY

        Self.drawText(
            String(localized: "pdf.report.title"),
            in: CGRect(
                x: content.minX,
                y: cursorY,
                width: content.width,
                height: PDFMetrics.FontSize.summaryTitle * Self.summaryTitleLineHeightMultiple
            ),
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryTitle, weight: .semibold),
            alignment: .left,
            color: PDFMetrics.Ink.primary
        )
        cursorY += PDFMetrics.FontSize.summaryTitle * Self.summaryTitleLineHeightMultiple

        Self.drawText(
            String(localized: "pdf.report.period \(Self.periodDescription(report.interval))"),
            in: CGRect(x: content.minX, y: cursorY, width: content.width, height: PDFMetrics.Summary.rowHeight),
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryBody),
            alignment: .left,
            color: PDFMetrics.Ink.secondary
        )
        cursorY += PDFMetrics.Summary.rowHeight + PDFMetrics.Summary.sectionSpacing

        cursorY = drawSummaryRow(
            month: String(localized: "report.section.breakdown"),
            count: String(localized: "pdf.summary.column.count"),
            total: String(localized: "pdf.summary.column.total"),
            atY: cursorY,
            in: content,
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryBody, weight: .semibold)
        )
        cursorY = drawRule(atY: cursorY, in: content)

        for line in lines {
            cursorY = drawSummaryRow(
                month: line.name,
                count: line.count.formatted(),
                total: ReceiptFormatting.amount(
                    line.total, currencyCode: report.currencyCode, defaultCode: defaultCurrencyCode
                ) ?? "",
                atY: cursorY,
                in: content,
                font: .systemFont(ofSize: PDFMetrics.FontSize.summaryBody)
            )
        }

        guard isFinalPage else { return }

        cursorY = drawRule(atY: cursorY, in: content)
        cursorY = drawSummaryRow(
            month: String(localized: "report.total"),
            count: report.receiptCount.formatted(),
            total: ReceiptFormatting.amount(
                report.grandTotal, currencyCode: report.currencyCode, defaultCode: defaultCurrencyCode
            ) ?? "",
            atY: cursorY,
            in: content,
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryTotal, weight: .semibold)
        )

        // Mirrors the in-app report: a receipt with no amount is reported, not dropped,
        // so the exported copy cannot look complete when it is not.
        if report.missingAmountCount > 0 {
            cursorY += PDFMetrics.Summary.sectionSpacing
            Self.drawText(
                String(localized: "pdf.report.missingAmount \(report.missingAmountCount)"),
                in: CGRect(x: content.minX, y: cursorY, width: content.width, height: PDFMetrics.Summary.rowHeight),
                font: .italicSystemFont(ofSize: PDFMetrics.FontSize.summaryBody),
                alignment: .left,
                color: PDFMetrics.Ink.secondary
            )
            cursorY += PDFMetrics.Summary.rowHeight
        }

        if report.hasExcludedCurrencies {
            cursorY += PDFMetrics.Summary.sectionSpacing
            Self.drawText(
                String(localized: "pdf.summary.mixedCurrencies"),
                in: CGRect(x: content.minX, y: cursorY, width: content.width, height: PDFMetrics.Summary.rowHeight),
                font: .italicSystemFont(ofSize: PDFMetrics.FontSize.summaryBody),
                alignment: .left,
                color: PDFMetrics.Ink.secondary
            )
        }
    }

    private static func periodDescription(_ interval: DateInterval?) -> String {
        guard let interval else { return String(localized: "pdf.report.allTime") }
        let start = ReceiptFormatting.receiptDate(for: interval.start)
        let end = ReceiptFormatting.receiptDate(for: interval.end.addingTimeInterval(-1))
        return "\(start) – \(end)"
    }

    // MARK: - Summary drawing

    private func drawSummary(
        _ summary: ExportSummary,
        months: [ExportSummary.MonthTotal],
        isFinalPage: Bool
    ) {
        let content = Self.contentRect
        var cursorY = content.minY

        Self.drawText(
            String(localized: "pdf.summary.title"),
            in: CGRect(
                x: content.minX,
                y: cursorY,
                width: content.width,
                height: PDFMetrics.FontSize.summaryTitle * Self.summaryTitleLineHeightMultiple
            ),
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryTitle, weight: .semibold),
            alignment: .left,
            color: PDFMetrics.Ink.primary
        )
        cursorY += PDFMetrics.FontSize.summaryTitle * Self.summaryTitleLineHeightMultiple
            + PDFMetrics.Summary.titleBottomSpacing

        cursorY = drawSummaryRow(
            month: String(localized: "pdf.summary.column.month"),
            count: String(localized: "pdf.summary.column.count"),
            total: String(localized: "pdf.summary.column.total"),
            atY: cursorY,
            in: content,
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryBody, weight: .semibold)
        )
        cursorY = drawRule(atY: cursorY, in: content)

        for monthTotal in months {
            cursorY = drawSummaryRow(
                month: ReceiptFormatting.monthTitle(for: monthTotal.id),
                count: monthTotal.count.formatted(),
                total: ReceiptFormatting.amount(monthTotal.total, currencyCode: summary.currencyCode, defaultCode: defaultCurrencyCode) ?? "",
                atY: cursorY,
                in: content,
                font: .systemFont(ofSize: PDFMetrics.FontSize.summaryBody)
            )
        }

        guard isFinalPage else { return }

        cursorY = drawRule(atY: cursorY, in: content)
        cursorY = drawSummaryRow(
            month: String(localized: "pdf.summary.total"),
            count: summary.receiptCount.formatted(),
            total: ReceiptFormatting.amount(summary.grandTotal, currencyCode: summary.currencyCode, defaultCode: defaultCurrencyCode) ?? "",
            atY: cursorY,
            in: content,
            font: .systemFont(ofSize: PDFMetrics.FontSize.summaryTotal, weight: .semibold)
        )

        if summary.hasExcludedCurrencies {
            cursorY += PDFMetrics.Summary.sectionSpacing
            Self.drawText(
                String(localized: "pdf.summary.mixedCurrencies"),
                in: CGRect(x: content.minX, y: cursorY, width: content.width, height: PDFMetrics.Summary.rowHeight),
                font: .italicSystemFont(ofSize: PDFMetrics.FontSize.summaryBody),
                alignment: .left,
                color: PDFMetrics.Ink.secondary
            )
        }
    }

    /// Draws one summary table row and returns the Y coordinate below it.
    private func drawSummaryRow(
        month: String,
        count: String,
        total: String,
        atY y: CGFloat,
        in content: CGRect,
        font: UIFont
    ) -> CGFloat {
        let monthWidth = content.width * PDFMetrics.Summary.monthColumnFraction
        let countWidth = content.width * PDFMetrics.Summary.countColumnFraction
        let totalWidth = content.width - monthWidth - countWidth
        let height = PDFMetrics.Summary.rowHeight

        Self.drawText(
            month,
            in: CGRect(x: content.minX, y: y, width: monthWidth, height: height),
            font: font, alignment: .left, color: PDFMetrics.Ink.primary
        )
        Self.drawText(
            count,
            in: CGRect(x: content.minX + monthWidth, y: y, width: countWidth, height: height),
            font: font, alignment: .right, color: PDFMetrics.Ink.primary
        )
        Self.drawText(
            total,
            in: CGRect(x: content.minX + monthWidth + countWidth, y: y, width: totalWidth, height: height),
            font: font, alignment: .right, color: PDFMetrics.Ink.primary
        )

        return y + height
    }

    private func drawRule(atY y: CGFloat, in content: CGRect) -> CGFloat {
        let rect = CGRect(
            x: content.minX,
            y: y,
            width: content.width,
            height: PDFMetrics.Summary.rulerThickness
        )
        PDFMetrics.Ink.rule.setFill()
        UIRectFill(rect)
        return y + PDFMetrics.Summary.rulerThickness + PDFMetrics.Summary.sectionSpacing
    }

    // MARK: - Drawing primitives

    /// Scales `size` to fit inside `bounds` without distortion, centred.
    static func aspectFitRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        alignment: NSTextAlignment,
        color: UIColor,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(in: rect)
    }
}

extension Array {
    /// Splits the array into consecutive chunks of at most `size` elements.
    ///
    /// Used to turn a flat receipt list into pages. A non-positive `size` returns a
    /// single chunk rather than trapping, because a layout can never legitimately
    /// report zero slots.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
