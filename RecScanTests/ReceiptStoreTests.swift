import Foundation
import SwiftData
import Testing
import UIKit
@testable import RecScan

/// Nested inside `ImagePipelineSuite` so it inherits `.serialized`.
extension ImagePipelineSuite {

    @Suite("Receipt persistence")
    struct ReceiptStoreTests {

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

        @Test("A single-page scan creates one row with its image on disk and no group")
        func importsSinglePage() async throws {
            let ids = try await store.importScan(pages: [TestImage.solid(width: 400, height: 600)], capturedAt: .now)

            #expect(ids.count == 1)

            let receipts = try fetchAll()
            let receipt = try #require(receipts.first)
            #expect(receipt.groupID == nil)
            #expect(receipt.pageIndex == 0)
            #expect(directory.fileExists(atRelativePath: receipt.relativePath))
        }

        @Test("A multi-page scan shares one group, one capture date and sequential page indexes")
        func importsMultiplePagesAsAGroup() async throws {
            let capturedAt = TestCalendar.date(year: 2026, month: 3, day: 4)
            let pages = (0..<3).map { _ in TestImage.solid(width: 300, height: 400) }

            _ = try await store.importScan(pages: pages, capturedAt: capturedAt)

            let receipts = try fetchAll().sorted { $0.pageIndex < $1.pageIndex }
            #expect(receipts.count == 3)

            let groupID = try #require(receipts.first?.groupID)
            #expect(receipts.allSatisfy { $0.groupID == groupID })
            #expect(receipts.allSatisfy { $0.capturedAt == capturedAt })
            #expect(receipts.map(\.pageIndex) == [0, 1, 2])
        }

        @Test("Every imported page gets its own distinct file")
        func eachPageGetsItsOwnFile() async throws {
            _ = try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300), TestImage.solid(width: 200, height: 300)],
                capturedAt: .now
            )

            let paths = try fetchAll().map(\.relativePath)
            #expect(Set(paths).count == 2)
            #expect(paths.allSatisfy { directory.fileExists(atRelativePath: $0) })
        }

        @Test("A new receipt starts flagged for review")
        func newReceiptNeedsReview() async throws {
            _ = try await store.importScan(pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now)

            #expect(try fetchAll().first?.needsReview == true)
        }

        @Test("Confirming a receipt's details clears the flag")
        func editingClearsNeedsReview() async throws {
            let id = try #require(try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now
            ).first)

            try await store.apply(
                ReceiptEdit(
                    capturedAt: .now, merchant: "Corner Store", amount: nil,
                    currencyCode: nil, note: nil, categoryID: nil
                ),
                toReceiptWithID: id
            )

            // Editing is the act of confirming, so the badge clears here as well as from
            // the review sheet -- a flag with only one way out is a flag that sticks.
            #expect(try fetchAll().first?.needsReview == false)
        }

        @Test("An empty scan is rejected")
        func rejectsEmptyImports() async {
            await #expect(throws: ReceiptStoreError.emptyImportRequest) {
                try await store.importScan(pages: [], capturedAt: .now)
            }
        }

        @Test("Edits are persisted and the search column is rebuilt")
        func appliesEdits() async throws {
            let id = try #require(try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300)],
                capturedAt: .now
            ).first)
            let newDate = TestCalendar.date(year: 2025, month: 11, day: 2)

            try await store.apply(
                ReceiptEdit(
                    capturedAt: newDate,
                    merchant: "  Corner Store  ",
                    amount: Decimal(string: "42.50"),
                    currencyCode: "EUR",
                    note: "Team lunch"
                ),
                toReceiptWithID: id
            )

            let receipt = try #require(try fetchAll().first)
            #expect(receipt.capturedAt == newDate)
            #expect(receipt.merchant == "Corner Store")
            #expect(receipt.amount == Decimal(string: "42.50"))
            #expect(receipt.currencyCode == "EUR")
            #expect(receipt.searchIndex.contains("Corner Store"))
            #expect(receipt.searchIndex.contains("Team lunch"))
        }

        @Test("Whitespace-only text is normalised to nil so 'unset' has one representation")
        func normalisesBlankText() async throws {
            let id = try #require(try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300)],
                capturedAt: .now
            ).first)

            try await store.apply(
                ReceiptEdit(capturedAt: .now, merchant: "   ", amount: nil, currencyCode: nil, note: "\n "),
                toReceiptWithID: id
            )

            let receipt = try #require(try fetchAll().first)
            #expect(receipt.merchant == nil)
            #expect(receipt.note == nil)
        }

        @Test("Editing an unknown receipt reports it")
        func rejectsUnknownEdits() async {
            let id = UUID()

            await #expect(throws: ReceiptStoreError.receiptNotFound(id: id)) {
                try await store.apply(
                    ReceiptEdit(capturedAt: .now, merchant: nil, amount: nil, currencyCode: nil, note: nil),
                    toReceiptWithID: id
                )
            }
        }

        @Test("Deleting removes the row and the backing file together")
        func deleteRemovesRowAndFile() async throws {
            let ids = try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300), TestImage.solid(width: 200, height: 300)],
                capturedAt: .now
            )
            let paths = try fetchAll().map(\.relativePath)

            try await store.delete(receiptsWithIDs: ids)

            #expect(try fetchAll().isEmpty)
            #expect(paths.allSatisfy { !directory.fileExists(atRelativePath: $0) })
        }

        @Test("Deleting only the requested receipts leaves the rest intact")
        func deleteIsScoped() async throws {
            let ids = try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300), TestImage.solid(width: 200, height: 300)],
                capturedAt: .now
            )

            try await store.delete(receiptsWithIDs: [ids[0]])

            let remaining = try fetchAll()
            #expect(remaining.count == 1)
            #expect(remaining.first?.id == ids[1])
            #expect(directory.fileExists(atRelativePath: remaining[0].relativePath))
        }

        @Test("Deleting nothing is a no-op")
        func deleteEmptyIsHarmless() async throws {
            _ = try await store.importScan(pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now)

            try await store.delete(receiptsWithIDs: [])

            #expect(try fetchAll().count == 1)
        }

        // MARK: - Helpers

        /// Reads through a fresh context so assertions see what was actually saved rather
        /// than the store's own in-memory state.
        private func fetchAll() throws -> [Receipt] {
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<Receipt>())
        }
    }
}
