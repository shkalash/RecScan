import CoreGraphics
import UIKit

/// Joins the pages of one document into a single tall image.
///
/// Responsibilities:
/// - Stack images vertically into one bitmap.
///
/// ## Why pages are merged rather than kept as separate receipts
/// A multi-page scan or PDF is almost always **one** long receipt that did not fit on a
/// single page — a supermarket till roll, a hotel folio. Storing a row per page split one
/// purchase into several, which then had to be re-assembled everywhere downstream: the
/// grid showed five tiles for one shop, the review sheet asked for five amounts, and the
/// expense report counted it five times. Merging at the point of import means the rest of
/// the app only ever deals with one image per receipt.
///
/// Pages are drawn at a common width so a mixed-size document does not produce a ragged
/// edge, and the tallest realistic receipt stays within one bitmap.
enum ImageStitcher {

    /// White, because a receipt is paper and a transparent gap would rasterise to black.
    private static let backgroundColor = UIColor.white

    /// Stacks `images` top to bottom.
    ///
    /// - Returns: the single image, or the only element when there is nothing to join.
    ///   `nil` only when handed an empty array.
    static func stack(_ images: [UIImage]) -> UIImage? {
        guard images.count > 1 else { return images.first }

        // Everything is scaled to the widest page: scaling up a narrow page is visually
        // kinder than pillar-boxing it, and keeps one consistent reading width.
        let width = images.map(\.size.width).max() ?? 0
        guard width > 0 else { return images.first }

        let heights = images.map { $0.size.height * (width / $0.size.width) }
        let totalHeight = heights.reduce(0, +)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let size = CGSize(width: width, height: totalHeight)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 0
            for (image, height) in zip(images, heights) {
                image.draw(in: CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
        }
    }
}
