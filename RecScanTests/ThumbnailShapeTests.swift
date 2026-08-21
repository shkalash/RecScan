import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import RecScan

/// Nested under `ImagePipelineSuite` so it inherits `.serialized` — these write images.
extension ImagePipelineSuite {

    @Suite("Grid thumbnails")
    struct ThumbnailShapeTests {

        private let directory = TemporaryDirectory()
        private let store: ImageFileStore

        init() {
            store = ImageFileStore(directoryProvider: directory, thumbnailCache: ThumbnailCache())
        }

        @Test("A tall receipt yields a square thumbnail")
        func thumbnailIsSquare() throws {
            let id = UUID()
            let path = try store.write(TestImage.solid(width: 620, height: 1000), for: id)
            let url = store.absoluteURL(forRelativePath: path)

            let thumbnail = try ImageCodec.squareThumbnail(
                at: url, maxEdge: StorageConstants.thumbnailEdgePixels
            )

            print("DIAG square thumbnail size=\(thumbnail.size) scale=\(thumbnail.scale)")
            #expect(thumbnail.size.width == thumbnail.size.height)
        }

        @Test("The square is as large as the receipt's width allows")
        func thumbnailUsesFullWidth() throws {
            let id = UUID()
            let path = try store.write(TestImage.solid(width: 620, height: 1000), for: id)
            let url = store.absoluteURL(forRelativePath: path)

            let full = try ImageCodec.thumbnail(at: url, maxEdge: 300)
            let square = try ImageCodec.squareThumbnail(at: url, maxEdge: 300)

            print("DIAG full=\(full.size) square=\(square.size)")
            // The crop must keep the receipt's full width -- cropping narrower would
            // zoom into a sliver instead of showing the top of the receipt.
            #expect(square.size.width == full.size.width)
            #expect(square.size.height == full.size.width)
        }

        @Test("The square spans the receipt, not just its top-left corner")
        func squareSpansProportionally() throws {
            // The regression this exists for: `CGImage.cropping(to:)` against a lazily
            // backed thumbnail cut a 186x186 rect out of the *original* 620x1000 buffer
            // instead of the 186x300 thumbnail, yielding a magnified top-left sliver.
            //
            // A top-only check cannot tell the two apart -- both are red at the top. The
            // square must cover the receipt's top ~62%, so its lower rows land in the
            // blue half. The buggy crop was entirely red.
            let id = UUID()
            let path = try store.write(
                TestImage.twoTone(width: 620, height: 1000, top: .red, bottom: .blue), for: id
            )
            let url = store.absoluteURL(forRelativePath: path)

            let square = try ImageCodec.squareThumbnail(at: url, maxEdge: 300)
            let cgImage = try #require(square.cgImage)
            let x = cgImage.width / 2
            let top = try #require(TestImage.pixel(in: cgImage, x: x, y: 4))
            let bottom = try #require(TestImage.pixel(in: cgImage, x: x, y: cgImage.height - 5))

            #expect(top.r > top.b, "top of the square should be the receipt's red half")
            #expect(bottom.b > bottom.r, "bottom of the square should reach the blue half")
        }

        @Test("The crop keeps the top of the receipt, not the middle")
        func cropIsTopBiased() throws {
            // Top half red, bottom half blue: a top-biased square crop of a 620x1000
            // receipt covers y 0..620, so it must be predominantly red.
            let id = UUID()
            let path = try store.write(
                TestImage.twoTone(width: 620, height: 1000, top: .red, bottom: .blue), for: id
            )
            let url = store.absoluteURL(forRelativePath: path)

            let square = try ImageCodec.squareThumbnail(at: url, maxEdge: 300)
            let cgImage = try #require(square.cgImage)
            let pixel = try #require(TestImage.pixel(in: cgImage, x: cgImage.width / 2, y: 4))

            #expect(pixel.r > pixel.b)
        }
    }
}
