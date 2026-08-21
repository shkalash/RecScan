#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Seeds synthetic receipts so the library can be exercised without a camera.
///
/// Responsibilities:
/// - Populate an empty library with believable receipts on demand.
///
/// ## Why this exists
/// `VNDocumentCameraViewController` does not run in the Simulator, so there is otherwise
/// no way to get a receipt into the app there — which makes every layout change in the
/// grid unverifiable. Guarded by `#if DEBUG` *and* a launch argument, so it cannot run in
/// a shipping build and does not run in a normal debug session either.
enum DebugSampleData {

    /// Pass `-seedSampleData <count>` in the scheme or via `simctl launch`.
    private static let flag = "-seedSampleData"

    static var requestedCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[index + 1])
    }

    /// Replaces the library with `count` synthetic receipts.
    static func seed(count: Int, store: any ReceiptStoring, calendar: Calendar = .current) async {
        let existing = (try? await store.allReceipts()) ?? []
        try? await store.delete(receiptsWithIDs: existing.map(\.id))

        for index in 0..<count {
            let capturedAt = calendar.date(byAdding: .day, value: -index * 9, to: Date()) ?? Date()
            _ = try? await store.importScan(pages: [makeReceiptImage(index: index)], capturedAt: capturedAt)
        }
    }

    // MARK: - Synthetic imagery

    private static let merchants = [
        "BLUE BOTTLE", "SUPER YUDA", "PAZ FUEL", "OFFICE DEPOT",
        "CAFE LANDWER", "AM:PM", "IKEA", "STEIMATZKY"
    ]

    /// A tall, receipt-shaped image with a header block and ruled lines.
    ///
    /// Deliberately taller than it is wide so that square-tile cropping is visible —
    /// a square placeholder would hide exactly the bug this is meant to expose.
    private static func makeReceiptImage(index: Int) -> UIImage {
        let size = CGSize(width: 620, height: 1000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let title = merchants[index % merchants.count]
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 46, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let titleSize = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: 70), withAttributes: attributes)

            UIColor.black.withAlphaComponent(0.75).setFill()
            context.fill(CGRect(x: 90, y: 160, width: size.width - 180, height: 4))

            UIColor.black.withAlphaComponent(0.45).setFill()
            for row in 0..<14 {
                let width = Double.random(in: 0.35...0.86) * (size.width - 180)
                context.fill(CGRect(x: 90, y: 210 + Double(row) * 46, width: width, height: 12))
            }

            UIColor.black.setFill()
            context.fill(CGRect(x: 90, y: 880, width: size.width - 180, height: 18))
        }
    }
}
#endif
