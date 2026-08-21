import Foundation
import SwiftData
import Testing
import UIKit
@testable import RecScan

/// Nested inside `ImagePipelineSuite` so it inherits `.serialized` — these write images.
extension ImagePipelineSuite {

    @Suite("Archive round trip")
    struct ArchiveRoundTripTests {

        /// One self-contained library: its own container, its own image directory.
        private struct Library {
            let directory = TemporaryDirectory()
            let container: ModelContainer
            let fileStore: ImageFileStore
            let store: ReceiptStore

            init() throws {
                container = try ModelContainerFactory.makeInMemoryContainer()
                fileStore = ImageFileStore(
                    directoryProvider: directory,
                    thumbnailCache: ThumbnailCache()
                )
                store = ReceiptStore(modelContainer: container, fileStore: fileStore)
            }

            func count() throws -> Int {
                try ModelContext(container).fetchCount(FetchDescriptor<Receipt>())
            }

            func receipts() throws -> [Receipt] {
                try ModelContext(container).fetch(FetchDescriptor<Receipt>())
            }
        }

        private func page() -> UIImage { TestImage.solid(width: 320, height: 440) }

        // MARK: - Export

        @Test("An archive contains a manifest and one image per receipt")
        func archiveContents() async throws {
            let library = try Library()
            _ = try await library.store.importScan(pages: [page(), page()], capturedAt: .now)
            let receipts = try await library.store.allReceipts()

            let url = try ArchiveExporter(fileStore: library.fileStore).makeArchive(receipts: receipts)
            let (manifest, staged) = try ArchiveImporter().read(archiveAt: url)

            #expect(manifest.entries.count == 2)
            #expect(staged.count == 2)
            #expect(staged.allSatisfy { $0.imageData != nil })
            #expect(staged.allSatisfy { $0.entry.fileName.hasPrefix("Receipts/") })
        }

        @Test("Exporting an empty library is rejected")
        func emptyExportIsRejected() {
            #expect(throws: ArchiveError.nothingToExport) {
                try ArchiveExporter().makeArchive(receipts: [])
            }
        }

        @Test("A file that is not a zip is reported, not crashed on")
        func nonArchiveIsRejected() throws {
            let bogus = FileManager.default.temporaryDirectory
                .appending(path: "not-an-archive-\(UUID().uuidString).zip")
            try Data("hello".utf8).write(to: bogus)
            defer { try? FileManager.default.removeItem(at: bogus) }

            #expect(throws: (any Error).self) {
                try ArchiveImporter().read(archiveAt: bogus)
            }
        }

        // MARK: - The scenario

        @Test("August export restores alongside September scans without duplicating")
        func augustArchiveMergesIntoSeptemberLibrary() async throws {
            // August: two receipts, exported.
            let august = try Library()
            _ = try await august.store.importScan(
                pages: [page(), page()],
                capturedAt: TestCalendar.date(year: 2026, month: 8, day: 12)
            )
            let archive = try ArchiveExporter(fileStore: august.fileStore)
                .makeArchive(receipts: try await august.store.allReceipts())

            // The app is deleted and reinstalled, then a September receipt is taken.
            let september = try Library()
            _ = try await september.store.importScan(
                pages: [page()],
                capturedAt: TestCalendar.date(year: 2026, month: 9, day: 3)
            )

            let staged = try ArchiveImporter().read(archiveAt: archive).receipts
            let result = try await september.store.importArchived(staged, categories: [])

            #expect(result.inserted == 2)
            #expect(result.skipped == 0)
            #expect(try september.count() == 3)
        }

        @Test("Importing the same archive twice changes nothing the second time")
        func doubleImportIsIdempotent() async throws {
            let source = try Library()
            _ = try await source.store.importScan(pages: [page(), page()], capturedAt: .now)
            let archive = try ArchiveExporter(fileStore: source.fileStore)
                .makeArchive(receipts: try await source.store.allReceipts())

            let target = try Library()
            let staged = try ArchiveImporter().read(archiveAt: archive).receipts

            let first = try await target.store.importArchived(staged, categories: [])
            let second = try await target.store.importArchived(staged, categories: [])

            #expect(first.inserted == 2)
            #expect(second.inserted == 0)
            #expect(second.skipped == 2)
            #expect(try target.count() == 2)
        }

        @Test("Restored receipts keep their identity, metadata and image")
        func restoredReceiptsSurviveIntact() async throws {
            let source = try Library()
            let ids = try await source.store.importScan(pages: [page()], capturedAt: .now)
            let id = try #require(ids.first)
            try await source.store.apply(
                ReceiptEdit(
                    capturedAt: TestCalendar.date(year: 2026, month: 8, day: 9),
                    merchant: "Blue Bottle",
                    amount: Decimal(string: "12.50"),
                    currencyCode: "ILS",
                    note: "team lunch"
                ),
                toReceiptWithID: id
            )
            let archive = try ArchiveExporter(fileStore: source.fileStore)
                .makeArchive(receipts: try await source.store.allReceipts())

            let target = try Library()
            let staged = try ArchiveImporter().read(archiveAt: archive).receipts
            _ = try await target.store.importArchived(staged, categories: [])

            let restored = try #require(try target.receipts().first)
            #expect(restored.id == id)
            #expect(restored.merchant == "Blue Bottle")
            #expect(restored.amount == Decimal(string: "12.50"))
            #expect(restored.currencyCode == "ILS")
            #expect(restored.note == "team lunch")
            #expect(restored.capturedAt == TestCalendar.date(year: 2026, month: 8, day: 9))
            // Search must work on a restored library, which means the derived column
            // has to be rebuilt rather than restored blank.
            #expect(restored.searchIndex.contains("Blue Bottle"))
            #expect(try target.fileStore.fullResolutionImage(atRelativePath: restored.relativePath).size.width > 0)
        }

        @Test("A newer local edit survives an older archive")
        func newerLocalEditIsNotClobbered() async throws {
            let source = try Library()
            let ids = try await source.store.importScan(pages: [page()], capturedAt: .now)
            let id = try #require(ids.first)
            let archive = try ArchiveExporter(fileStore: source.fileStore)
                .makeArchive(receipts: try await source.store.allReceipts())

            // The same receipt is edited after the archive was taken.
            try await source.store.apply(
                ReceiptEdit(
                    capturedAt: .now, merchant: "Edited After Export",
                    amount: nil, currencyCode: nil, note: nil
                ),
                toReceiptWithID: id
            )

            let staged = try ArchiveImporter().read(archiveAt: archive).receipts
            let result = try await source.store.importArchived(staged, categories: [])

            #expect(result.skipped == 1)
            #expect(result.updated == 0)
            #expect(try source.receipts().first?.merchant == "Edited After Export")
        }

        @Test("A missing image is restored from the archive")
        func missingImageIsRestored() async throws {
            let library = try Library()
            let ids = try await library.store.importScan(pages: [page()], capturedAt: .now)
            let id = try #require(ids.first)
            let archive = try ArchiveExporter(fileStore: library.fileStore)
                .makeArchive(receipts: try await library.store.allReceipts())

            // Simulate the file being deleted out from under the row -- exactly what
            // Finder file sharing now makes possible.
            let path = try #require(try library.receipts().first?.relativePath)
            try library.fileStore.delete(relativePath: path, id: id)
            #expect(throws: (any Error).self) {
                try library.fileStore.fullResolutionImage(atRelativePath: path)
            }

            let staged = try ArchiveImporter().read(archiveAt: archive).receipts
            let result = try await library.store.importArchived(staged, categories: [])

            #expect(result.updated == 1)
            #expect(try library.fileStore.fullResolutionImage(atRelativePath: path).size.width > 0)
        }

        @Test("A manifest entry whose image is absent is reported, not half-imported")
        func missingImageDataIsReported() async throws {
            let library = try Library()
            let entry = ArchiveManifest.Entry(
                id: UUID(),
                capturedAt: .now, createdAt: .now, modifiedAt: .now,
                fileName: "Receipts/gone.heic",
                merchant: nil, amount: nil, currencyCode: nil,
                note: nil, ocrText: nil, groupID: nil, pageIndex: 0,
                categoryID: nil, needsReview: nil
            )

            let result = try await library.store.importArchived(
                [ArchiveImporter.StagedReceipt(entry: entry, imageData: nil)], categories: []
            )

            #expect(result.missingImages == 1)
            #expect(result.inserted == 0)
            // A row with no image would render as a permanently broken receipt.
            #expect(try library.count() == 0)
        }

        @Test("Categories survive into a library that has none")
        func categoriesAreRecreated() async throws {
            let source = try Library()
            let categoryID = try await source.store.createCategory(named: "Fuel")
            let receiptID = try #require(try await source.store.importScan(pages: [page()], capturedAt: .now).first)
            try await source.store.apply(
                ReceiptEdit(capturedAt: .now, merchant: nil, amount: nil,
                            currencyCode: nil, note: nil, categoryID: categoryID),
                toReceiptWithID: receiptID
            )
            let archive = try ArchiveExporter(fileStore: source.fileStore).makeArchive(
                receipts: try await source.store.allReceipts(),
                categories: try await source.store.allCategories()
            )

            let target = try Library()
            let read = try ArchiveImporter().read(archiveAt: archive)
            _ = try await target.store.importArchived(read.receipts, categories: read.manifest.categoryList)

            let restored = try #require(try target.receipts().first)
            let categories = try ModelContext(target.container).fetch(FetchDescriptor<ReceiptCategory>())
            #expect(categories.map(\.name) == ["Fuel"])
            #expect(restored.categoryID == categories.first?.id)
        }

        @Test("An archived category matching an existing name is merged, not duplicated")
        func categoriesMergeByName() async throws {
            let source = try Library()
            let sourceCategory = try await source.store.createCategory(named: "Fuel")
            let receiptID = try #require(try await source.store.importScan(pages: [page()], capturedAt: .now).first)
            try await source.store.apply(
                ReceiptEdit(capturedAt: .now, merchant: nil, amount: nil,
                            currencyCode: nil, note: nil, categoryID: sourceCategory),
                toReceiptWithID: receiptID
            )
            let archive = try ArchiveExporter(fileStore: source.fileStore).makeArchive(
                receipts: try await source.store.allReceipts(),
                categories: try await source.store.allCategories()
            )

            // A different device already has its own "Fuel" -- same name, different id.
            let target = try Library()
            let localCategory = try await target.store.createCategory(named: "fuel")

            let read = try ArchiveImporter().read(archiveAt: archive)
            _ = try await target.store.importArchived(read.receipts, categories: read.manifest.categoryList)

            let categories = try ModelContext(target.container).fetch(FetchDescriptor<ReceiptCategory>())
            #expect(categories.count == 1)
            #expect(try target.receipts().first?.categoryID == localCategory)
        }

        @Test("Only categories the exported receipts actually use are written")
        func unusedCategoriesAreNotExported() async throws {
            let source = try Library()
            _ = try await source.store.createCategory(named: "Unused")
            _ = try await source.store.importScan(pages: [page()], capturedAt: .now)

            let archive = try ArchiveExporter(fileStore: source.fileStore).makeArchive(
                receipts: try await source.store.allReceipts(),
                categories: try await source.store.allCategories()
            )

            let read = try ArchiveImporter().read(archiveAt: archive)
            #expect(read.manifest.categoryList.isEmpty)
        }

        @Test("The review flag survives the round trip")
        func needsReviewSurvives() async throws {
            let source = try Library()
            _ = try await source.store.importScan(pages: [page()], capturedAt: .now)
            let archive = try ArchiveExporter(fileStore: source.fileStore).makeArchive(
                receipts: try await source.store.allReceipts(),
                categories: []
            )

            let target = try Library()
            let read = try ArchiveImporter().read(archiveAt: archive)
            _ = try await target.store.importArchived(read.receipts, categories: [])

            #expect(try target.receipts().first?.needsReview == true)
        }

        @Test("Multi-page groups survive the round trip")
        func groupsSurvive() async throws {
            let source = try Library()
            _ = try await source.store.importScan(pages: [page(), page(), page()], capturedAt: .now)
            let archive = try ArchiveExporter(fileStore: source.fileStore)
                .makeArchive(receipts: try await source.store.allReceipts())

            let target = try Library()
            _ = try await target.store.importArchived(
                try ArchiveImporter().read(archiveAt: archive).receipts, categories: []
            )

            let restored = try target.receipts().sorted { $0.pageIndex < $1.pageIndex }
            let groupID = try #require(restored.first?.groupID)
            #expect(restored.count == 3)
            #expect(restored.allSatisfy { $0.groupID == groupID })
            #expect(restored.map(\.pageIndex) == [0, 1, 2])
        }
    }
}
