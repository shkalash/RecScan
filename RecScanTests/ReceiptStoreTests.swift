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

        @Test("A single-page scan creates one row with its image on disk")
        func importsSinglePage() async throws {
            let ids = try await store.importScan(pages: [TestImage.solid(width: 400, height: 600)], capturedAt: .now)

            #expect(ids.count == 1)

            let receipts = try fetchAll()
            let receipt = try #require(receipts.first)
            #expect(directory.fileExists(atRelativePath: receipt.relativePath))
        }

        /// A receipt long enough to need three frames is still one purchase.
        @Test("A multi-page scan becomes a single receipt")
        func importsMultiplePagesAsOneReceipt() async throws {
            let capturedAt = TestCalendar.date(year: 2026, month: 3, day: 4)
            let pages = (0..<3).map { _ in TestImage.solid(width: 300, height: 400) }

            let ids = try await store.importScan(pages: pages, capturedAt: capturedAt)

            #expect(ids.count == 1)
            let receipts = try fetchAll()
            #expect(receipts.count == 1)
            #expect(receipts.first?.capturedAt == capturedAt)
        }

        @Test("The pages of a scan are stacked into one taller image")
        func stacksPagesVertically() async throws {
            let pages = (0..<3).map { _ in TestImage.solid(width: 300, height: 400) }

            _ = try await store.importScan(pages: pages, capturedAt: .now)

            let receipt = try #require(try fetchAll().first)
            let image = try directory.image(atRelativePath: receipt.relativePath)
            #expect(image.size.width == 300)
            #expect(image.size.height == 1200)
        }

        @Test("Every imported receipt gets its own distinct file")
        func eachReceiptGetsItsOwnFile() async throws {
            for _ in 0..<2 {
                _ = try await store.importScan(
                    pages: [TestImage.solid(width: 200, height: 300)],
                    capturedAt: .now
                )
            }

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
            let id = try await newReceiptID()

            try await store.apply(edit(amount: Decimal(12)), toReceiptWithID: id)

            // Editing is the act of confirming, so the badge clears here as well as from
            // the review sheet -- a flag with only one way out is a flag that sticks.
            #expect(try fetchAll().first?.needsReview == false)
        }

        // MARK: - No amount means unfinished

        /// The flag means "not yet accounted for", not merely "not yet opened". An amount
        /// is the point of the library, so a receipt without one is never done -- which is
        /// what lets the review filter alone find everything that was missed.
        @Test("Saving a receipt with no amount leaves it flagged")
        func noAmountStaysFlagged() async throws {
            let id = try await newReceiptID()

            try await store.apply(edit(merchant: "Corner Store", amount: nil), toReceiptWithID: id)

            #expect(try fetchAll().first?.needsReview == true)
            // The rest of the edit still lands; only the flag is withheld.
            #expect(try fetchAll().first?.merchant == "Corner Store")
        }

        @Test("Clearing the amount off a confirmed receipt flags it again")
        func clearingTheAmountReflagsIt() async throws {
            let id = try await newReceiptID()
            try await store.apply(edit(amount: Decimal(12)), toReceiptWithID: id)
            #expect(try fetchAll().first?.needsReview == false)

            try await store.apply(edit(amount: nil), toReceiptWithID: id)

            #expect(try fetchAll().first?.needsReview == true)
        }

        @Test("Parking edits never clears the flag, amount or not")
        func parkingNeverConfirms() async throws {
            let id = try await newReceiptID()

            try await store.apply(edit(amount: Decimal(12)), toReceiptWithID: id, confirming: false)

            #expect(try fetchAll().first?.needsReview == true)
            #expect(try fetchAll().first?.amount == Decimal(12))
        }

        // MARK: - Helpers

        /// Imports one receipt and returns its identifier. Imports arrive flagged.
        private func newReceiptID() async throws -> UUID {
            try #require(try await store.importScan(
                pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now
            ).first)
        }

        private func edit(merchant: String? = nil, amount: Decimal?) -> ReceiptEdit {
            ReceiptEdit(
                capturedAt: .now, merchant: merchant, amount: amount,
                currencyCode: nil, note: nil, categoryID: nil
            )
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
            var ids: [UUID] = []
            for _ in 0..<2 {
                ids += try await store.importScan(
                    pages: [TestImage.solid(width: 200, height: 300)],
                    capturedAt: .now
                )
            }

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

        // MARK: - Currency

        /// A receipt is stamped with the default in force when it arrived, so changing
        /// the setting later cannot rewrite what was already captured.
        @Test("An imported receipt is stamped with the current default currency")
        func stampsCurrencyAtImport() async throws {
            let store = ReceiptStore(
                modelContainer: container,
                fileStore: ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache()),
                currentDefaultCurrency: { "ILS" }
            )

            _ = try await store.importScan(pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now)

            #expect(try fetchAll().first?.currencyCode == "ILS")
        }

        @Test("Changing the default currency leaves existing receipts alone")
        func defaultChangeDoesNotRewriteHistory() async throws {
            let fileStore = ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache())
            let shekels = ReceiptStore(
                modelContainer: container, fileStore: fileStore, currentDefaultCurrency: { "ILS" }
            )
            _ = try await shekels.importScan(pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now)

            // The user switches the default, then captures another receipt.
            let euros = ReceiptStore(
                modelContainer: container, fileStore: fileStore, currentDefaultCurrency: { "EUR" }
            )
            _ = try await euros.importScan(pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now)

            let codes = try fetchAll().map(\.currencyCode)
            #expect(Set(codes) == ["ILS", "EUR"])
        }

        @Test("Receipts stored before currency was stamped get the current default")
        func backfillsMissingCurrency() async throws {
            let context = ModelContext(container)
            context.insert(Receipt(id: UUID(), relativePath: "Receipts/legacy.heic"))
            try context.save()

            let store = ReceiptStore(
                modelContainer: container,
                fileStore: ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache()),
                currentDefaultCurrency: { "USD" }
            )
            let stamped = try await store.stampMissingCurrency()

            #expect(stamped == 1)
            #expect(try fetchAll().first?.currencyCode == "USD")
        }

        @Test("A backfill does not make a receipt look edited")
        func backfillLeavesModifiedAtAlone() async throws {
            let modifiedAt = TestCalendar.date(year: 2026, month: 1, day: 2)
            let context = ModelContext(container)
            context.insert(
                Receipt(id: UUID(), modifiedAt: modifiedAt, relativePath: "Receipts/legacy.heic")
            )
            try context.save()

            let store = ReceiptStore(
                modelContainer: container,
                fileStore: ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache()),
                currentDefaultCurrency: { "USD" }
            )
            _ = try await store.stampMissingCurrency()

            // Bumping it would make every receipt beat its archived copy on merge.
            #expect(try fetchAll().first?.modifiedAt == modifiedAt)
        }

        @Test("A second backfill has nothing left to do")
        func backfillIsIdempotent() async throws {
            let store = ReceiptStore(
                modelContainer: container,
                fileStore: ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache()),
                currentDefaultCurrency: { "USD" }
            )
            _ = try await store.importScan(pages: [TestImage.solid(width: 200, height: 300)], capturedAt: .now)

            #expect(try await store.stampMissingCurrency() == 0)
        }

    }
}
