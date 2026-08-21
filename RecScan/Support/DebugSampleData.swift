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
            _ = try? await store.importScan(pages: [SampleReceiptImage.make(index: index)], capturedAt: capturedAt)
        }
    }

}
#endif
