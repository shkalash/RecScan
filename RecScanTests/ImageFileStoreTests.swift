import Foundation
import Testing
import UIKit
@testable import RecScan

/// Nested inside `ImagePipelineSuite` so it inherits `.serialized`.
extension ImagePipelineSuite {

    @Suite("Receipt image files")
    struct ImageFileStoreTests {

        private let directory = TemporaryDirectory()
        private let store: ImageFileStore

        init() {
            store = ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache())
        }

        @Test("Relative paths are stable, scoped to the receipts directory and never absolute")
        func relativePathShape() {
            let id = UUID()

            let path = store.relativePath(for: id)

            #expect(path == "Receipts/\(id.uuidString).heic")
            #expect(!path.hasPrefix("/"))
        }

        @Test("Writing then reading returns an equivalent image")
        func writeReadRoundTrip() throws {
            let id = UUID()
            let image = TestImage.solid(width: 600, height: 900)

            let path = try store.write(image, for: id)
            let loaded = try store.fullResolutionImage(atRelativePath: path)

            #expect(directory.fileExists(atRelativePath: path))
            #expect(loaded.size == image.size)
        }

        @Test("Thumbnails are bounded by the configured edge")
        func thumbnailIsBounded() throws {
            let id = UUID()
            let path = try store.write(TestImage.solid(width: 1200, height: 1800), for: id)

            let thumbnail = try store.thumbnail(atRelativePath: path, id: id)

            #expect(max(thumbnail.size.width, thumbnail.size.height) <= StorageConstants.thumbnailEdgePixels)
        }

        @Test("Deleting removes the file and is safe to repeat")
        func deleteIsIdempotent() throws {
            let id = UUID()
            let path = try store.write(TestImage.solid(width: 300, height: 400), for: id)

            try store.delete(relativePath: path, id: id)
            #expect(!directory.fileExists(atRelativePath: path))

            // A second delete must not throw: the store is the sole cleanup path and is
            // called again whenever a row is removed after a partial failure.
            try store.delete(relativePath: path, id: id)
        }

        @Test("Reading a missing file reports it rather than crashing")
        func missingFileThrows() {
            let path = store.relativePath(for: UUID())

            #expect(throws: StorageError.fileMissing(relativePath: path)) {
                try store.fullResolutionImage(atRelativePath: path)
            }
        }

        @Test("Absolute URLs are rebuilt from the current container on every call")
        func absoluteURLTracksTheContainer() {
            let path = store.relativePath(for: UUID())

            let url = store.absoluteURL(forRelativePath: path)

            #expect(url.path(percentEncoded: false).hasPrefix(directory.documentsDirectory.path(percentEncoded: false)))
        }
    }
}
