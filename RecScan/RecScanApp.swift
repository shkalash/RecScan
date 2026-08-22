import SwiftData
import SwiftUI

/// Application entry point.
///
/// Responsibilities:
/// - Build the persistent `ModelContainer`.
/// - Construct the background `ReceiptStore` and publish both stores to the view tree.
@main
struct RecScanApp: App {

    private let modelContainer: ModelContainer
    private let receiptStore: any ReceiptStoring
    private let imageFileStore: any ImageFileStoring

    init() {
        do {
            modelContainer = try ModelContainerFactory.makeContainer()
        } catch {
            // There is no meaningful degraded mode: without a store there is no app.
            // Failing here surfaces the real error instead of an empty library.
            fatalError("Failed to open the receipts database: \(error)")
        }

        let imageFileStore = ImageFileStore()
        self.imageFileStore = imageFileStore
        // One store instance for the whole app: it owns a serial executor, and a second
        // instance would mean two contexts writing the same rows.
        receiptStore = ReceiptStore(modelContainer: modelContainer, fileStore: imageFileStore)
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(\.receiptStore, receiptStore)
                .environment(\.imageFileStore, imageFileStore)
                .task {
                    // Fire and forget: a failure here leaves the old fallback behaviour
                    // rather than blocking the library.
                    try? await receiptStore.stampMissingCurrency()
                }
        }
        .modelContainer(modelContainer)
    }
}
