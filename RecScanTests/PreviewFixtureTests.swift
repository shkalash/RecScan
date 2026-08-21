import Foundation
import SwiftData
import Testing
@testable import RecScan

/// Nested under `ImagePipelineSuite` so it inherits `.serialized` — the fixture encodes
/// images when it is first touched.
extension ImagePipelineSuite {

    /// Guards the previews' data, not their appearance.
    ///
    /// A preview whose fixture yields no image still renders — as a placeholder square —
    /// so this failure is invisible in the canvas and would quietly make every
    /// data-backed preview useless for judging layout.
    @MainActor
    @Suite("Preview fixture")
    struct PreviewFixtureTests {

        @Test("A fixture receipt's image is actually on disk and loadable")
        func receiptImageLoads() throws {
            let receipt = PreviewFixture.makeReceipt(index: 0)

            #expect(!receipt.relativePath.isEmpty)
            let image = try PreviewFixture.imageFileStore
                .fullResolutionImage(atRelativePath: receipt.relativePath)
            #expect(image.size.width > 0)
        }

        @Test("Fixture receipts carry the metadata the previews are meant to show")
        func receiptsAreFurnished() {
            let receipt = PreviewFixture.makeReceipt(index: 0)

            #expect(receipt.merchant?.isEmpty == false)
            #expect(receipt.amount != nil)
            #expect(receipt.currencyCode != nil)
            // Search has to work in a preview too, and the column is derived.
            #expect(receipt.searchIndex.contains(receipt.merchant ?? ""))
        }

        @Test("The preview container is populated and spans several months")
        func containerIsSeeded() throws {
            let context = ModelContext(PreviewFixture.container)
            let receipts = try context.fetch(FetchDescriptor<Receipt>())

            #expect(receipts.count > 1)
            let months = Set(receipts.map { Calendar.current.dateInterval(of: .month, for: $0.capturedAt)?.start })
            // Month sectioning is a thing previews need to show, so the spread matters.
            #expect(months.count > 1)
        }

        @Test("Grid tiles come out square, which is what the tile preview shows")
        func fixtureThumbnailIsSquare() throws {
            let receipt = PreviewFixture.makeReceipt(index: 3)

            let thumbnail = try PreviewFixture.imageFileStore
                .thumbnail(atRelativePath: receipt.relativePath, id: receipt.id)

            #expect(thumbnail.size.width == thumbnail.size.height)
        }

        @Test("Sample imagery is deterministic, so a preview does not change every render")
        func sampleImageryIsStable() {
            let first = SampleReceiptImage.make(index: 2)
            let second = SampleReceiptImage.make(index: 2)

            #expect(first.pngData() == second.pngData())
        }
    }
}
