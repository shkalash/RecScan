#if DEBUG
import CoreGraphics
import Foundation
import UIKit

/// Synthetic receipt imagery for previews and the debug seeder.
///
/// Responsibilities:
/// - Draw a believable, deterministic receipt so views can be exercised without a camera.
///
/// Shared by `DebugSampleData` and `PreviewFixture` so a change to what a sample receipt
/// looks like shows up in both the Simulator and the Xcode canvas.
enum SampleReceiptImage {

    static let merchants = [
        "BLUE BOTTLE", "SUPER YUDA", "PAZ FUEL", "OFFICE DEPOT",
        "CAFE LANDWER", "AM:PM", "IKEA", "STEIMATZKY"
    ]

    static func merchant(at index: Int) -> String {
        merchants[index % merchants.count]
    }

    private static let size = CGSize(width: 620, height: 1000)
    private static let lineCount = 14

    /// A tall receipt with a header and ruled lines.
    ///
    /// Deliberately taller than wide: the grid crops to a square, and a square sample
    /// would hide exactly the cropping behaviour a preview is meant to show.
    /// Line widths are derived from the index rather than random, so a preview does not
    /// change every time Xcode re-renders it.
    static func make(index: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let title = merchant(at: index)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 46, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let titleSize = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: 70), withAttributes: attributes)

            UIColor.black.withAlphaComponent(0.75).setFill()
            context.fill(CGRect(x: 90, y: 160, width: size.width - 180, height: 4))

            UIColor.black.withAlphaComponent(0.45).setFill()
            let usableWidth = size.width - 180
            for row in 0..<lineCount {
                // Deterministic pseudo-random widths: stable across renders.
                let fraction = 0.35 + 0.51 * abs(sin(Double(index * 31 + row * 7)))
                context.fill(CGRect(x: 90, y: 210 + Double(row) * 46, width: usableWidth * fraction, height: 12))
            }

            UIColor.black.setFill()
            context.fill(CGRect(x: 90, y: 880, width: size.width - 180, height: 18))
        }
    }
}
#endif
