import Foundation
import SwiftData
import Testing
import UIKit
@testable import RecScan

/// Nested under `ImagePipelineSuite` so it inherits `.serialized` — receipts written here
/// encode images.
extension ImagePipelineSuite {

    @Suite("Categories")
    struct CategoryStoreTests {

        private let directory = TemporaryDirectory()
        private let container: ModelContainer
        private let store: ReceiptStore

        init() throws {
            container = try ModelContainerFactory.makeInMemoryContainer()
            store = ReceiptStore(
                modelContainer: container,
                fileStore: ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache())
            )
        }

        private func categories() throws -> [ReceiptCategory] {
            try ModelContext(container).fetch(FetchDescriptor<ReceiptCategory>())
        }

        private func receipts() throws -> [Receipt] {
            try ModelContext(container).fetch(FetchDescriptor<Receipt>())
        }

        private func page() -> UIImage { TestImage.solid(width: 200, height: 300) }

        @Test("Creating a category stores it under a trimmed name")
        func createsCategory() async throws {
            let id = try await store.createCategory(named: "  Groceries  ")

            let all = try categories()
            #expect(all.count == 1)
            #expect(all.first?.id == id)
            #expect(all.first?.name == "Groceries")
        }

        @Test("A name that already exists selects it instead of adding a twin")
        func doesNotDuplicate() async throws {
            let first = try await store.createCategory(named: "Fuel")
            let second = try await store.createCategory(named: "  fuel ")

            #expect(first == second)
            #expect(try categories().count == 1)
        }

        @Test("A blank name is rejected")
        func rejectsBlankName() async {
            await #expect(throws: ReceiptStoreError.emptyCategoryName) {
                try await store.createCategory(named: "   ")
            }
        }

        @Test("Renaming updates the stored name")
        func renames() async throws {
            let id = try await store.createCategory(named: "Feul")

            try await store.renameCategory(id: id, to: "Fuel")

            #expect(try categories().first?.name == "Fuel")
        }

        @Test("Renaming an unknown category reports it")
        func renameUnknown() async {
            let id = UUID()
            await #expect(throws: ReceiptStoreError.categoryNotFound(id: id)) {
                try await store.renameCategory(id: id, to: "Anything")
            }
        }

        @Test("A receipt keeps the category assigned to it")
        func assignsToReceipt() async throws {
            let categoryID = try await store.createCategory(named: "Office")
            let receiptID = try #require(try await store.importScan(pages: [page()], capturedAt: .now).first)

            try await store.apply(
                ReceiptEdit(
                    capturedAt: .now, merchant: nil, amount: nil,
                    currencyCode: nil, note: nil, categoryID: categoryID
                ),
                toReceiptWithID: receiptID
            )

            #expect(try receipts().first?.categoryID == categoryID)
        }

        @Test("Deleting a category keeps its receipts and clears the label")
        func deleteKeepsReceipts() async throws {
            let categoryID = try await store.createCategory(named: "Office")
            let receiptID = try #require(try await store.importScan(pages: [page()], capturedAt: .now).first)
            try await store.apply(
                ReceiptEdit(
                    capturedAt: .now, merchant: nil, amount: nil,
                    currencyCode: nil, note: nil, categoryID: categoryID
                ),
                toReceiptWithID: receiptID
            )

            try await store.deleteCategory(id: categoryID)

            // The destructive action removes a label, never the receipts behind it.
            #expect(try categories().isEmpty)
            #expect(try receipts().count == 1)
            #expect(try receipts().first?.categoryID == nil)
        }

        @Test("Deleting one category leaves other receipts' categories alone")
        func deleteIsScoped() async throws {
            let kept = try await store.createCategory(named: "Keep")
            let removed = try await store.createCategory(named: "Remove")
            var ids: [UUID] = []
            for _ in 0..<2 {
                ids += try await store.importScan(pages: [page()], capturedAt: .now)
            }

            for (id, category) in zip(ids, [kept, removed]) {
                try await store.apply(
                    ReceiptEdit(
                        capturedAt: .now, merchant: nil, amount: nil,
                        currencyCode: nil, note: nil, categoryID: category
                    ),
                    toReceiptWithID: id
                )
            }

            try await store.deleteCategory(id: removed)

            let assigned = try receipts().compactMap(\.categoryID)
            #expect(assigned == [kept])
        }

        @Test("Deleting an unknown category is a no-op")
        func deleteUnknownIsHarmless() async throws {
            try await store.createCategory(named: "Office")

            try await store.deleteCategory(id: UUID())

            #expect(try categories().count == 1)
        }
    }
}
