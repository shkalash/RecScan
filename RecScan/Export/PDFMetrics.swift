import CoreGraphics
import UIKit

/// Layout constants for the generated PDF.
///
/// Responsibilities:
/// - Hold every point value and font size the PDF renderer uses.
///
/// Why not literals at the draw sites: page geometry is the one thing most likely to
/// be retuned after seeing a printed page, and it must stay internally consistent.
enum PDFMetrics {

    /// US Letter at 72 dpi, the unit PDF contexts work in.
    static let pageSize = CGSize(width: 612, height: 792)

    static var pageRect: CGRect { CGRect(origin: .zero, size: pageSize) }

    static let margin: CGFloat = 36
    static let footerHeight: CGFloat = 18
    static let headerHeight: CGFloat = 22
    static let slotSpacing: CGFloat = 16
    static let headerImageSpacing: CGFloat = 8

    enum FontSize {
        static let header: CGFloat = 11
        static let footer: CGFloat = 9
        static let summaryTitle: CGFloat = 20
        static let summaryBody: CGFloat = 11
        static let summaryTotal: CGFloat = 13
    }

    enum Summary {
        static let titleBottomSpacing: CGFloat = 20
        static let rowHeight: CGFloat = 20
        static let sectionSpacing: CGFloat = 12
        static let rulerThickness: CGFloat = 0.5
        /// Column split, expressed as fractions of the content width.
        static let monthColumnFraction: CGFloat = 0.5
        static let countColumnFraction: CGFloat = 0.2
    }

    /// Point size used for the invisible searchable-text layer. It is never seen, but
    /// it must be small enough that the whole OCR string fits over the image.
    static let searchableTextFontSize: CGFloat = 8
}
