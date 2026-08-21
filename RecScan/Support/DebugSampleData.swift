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

    /// Pass `-seedSampleData` in the scheme, optionally followed by a count.
    private static let flag = "-seedSampleData"
    private static let defaultCount = 7

    /// The requested receipt count, or `nil` when seeding was not asked for.
    ///
    /// Simulator-only, and deliberately so: seeding **replaces** the library, and a
    /// scheme argument left ticked while running on a phone would destroy real receipts.
    /// The guard makes that impossible rather than merely unlikely.
    static var requestedCount: Int? {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments

        // Xcode may deliver "-seedSampleData 7" as one token or two depending on how the
        // scheme argument was entered, so both forms are accepted.
        if let combined = arguments.first(where: { $0.hasPrefix(flag + " ") }) {
            return Int(combined.dropFirst(flag.count + 1).trimmingCharacters(in: .whitespaces))
                ?? defaultCount
        }
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        if index + 1 < arguments.count, let count = Int(arguments[index + 1]) { return count }
        return defaultCount
        #else
        return nil
        #endif
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
