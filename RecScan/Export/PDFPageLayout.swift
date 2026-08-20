import Foundation

/// How many receipts are placed on one PDF page.
enum PDFPageLayout: String, CaseIterable, Identifiable, Sendable {
    /// One receipt per page, image as large as the margins allow.
    case onePerPage
    /// Two receipts stacked vertically. Halves the page count for filing.
    case twoUp

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .onePerPage: "export.layout.onePerPage"
        case .twoUp: "export.layout.twoUp"
        }
    }

    /// Number of receipt slots on a single page.
    var slotsPerPage: Int {
        switch self {
        case .onePerPage: 1
        case .twoUp: 2
        }
    }
}
