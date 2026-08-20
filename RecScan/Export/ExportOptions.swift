import Foundation

/// User choices that govern PDF generation.
///
/// Responsibilities:
/// - Carry the export sheet's settings to `PDFBuilder`.
struct ExportOptions: Sendable, Equatable {
    var layout: PDFPageLayout
    var includeHeader: Bool
    var includeSummaryPage: Bool
    var includeSearchableText: Bool

    init(
        layout: PDFPageLayout = .onePerPage,
        includeHeader: Bool = true,
        includeSummaryPage: Bool = true,
        includeSearchableText: Bool = true
    ) {
        self.layout = layout
        self.includeHeader = includeHeader
        self.includeSummaryPage = includeSummaryPage
        self.includeSearchableText = includeSearchableText
    }
}
