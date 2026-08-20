import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import RecScan

/// Nested inside `ImagePipelineSuite` so it inherits `.serialized`.
extension ImagePipelineSuite {

    @Suite("Image encoding and downscaling")
    struct ImageCodecTests {

        @Test("Encoding produces HEIC data that decodes back to an image")
        func heicRoundTrip() throws {
            let original = TestImage.solid(width: 400, height: 600)

            let data = try ImageCodec.encodeHEIC(original)
            #expect(!data.isEmpty)

            let decoded = UIImage(data: data)
            #expect(decoded != nil)
            #expect(decoded?.size == original.size)
        }

        @Test("Images larger than the limit are downscaled on the long edge")
        func downscalesOversizedImages() throws {
            let oversized = TestImage.solid(width: 4000, height: 3000)

            let bitmap = try ImageCodec.opaqueBitmap(from: oversized, maxEdge: 2400)

            #expect(bitmap.width == 2400)
            #expect(bitmap.height == 1800)
        }

        @Test("Portrait images are downscaled on their height")
        func downscalesPortraitOnHeight() throws {
            let oversized = TestImage.solid(width: 1500, height: 3000)

            let bitmap = try ImageCodec.opaqueBitmap(from: oversized, maxEdge: 2400)

            #expect(bitmap.height == 2400)
            #expect(bitmap.width == 1200)
        }

        @Test("Images already within the limit keep their pixel dimensions")
        func leavesSmallImagesAlone() {
            let small = TestImage.solid(width: 800, height: 600)

            let size = ImageCodec.fittedPixelSize(for: small, maxEdge: 2400)

            #expect(size == CGSize(width: 800, height: 600))
        }

        @Test("The rendered bitmap carries no alpha channel")
        func bitmapHasNoAlphaChannel() throws {
            // Regression guard. `UIGraphicsImageRendererFormat.opaque = true` was not
            // enough on device: ImageIO reported it was discarding an `AlphaLast`
            // channel, which doubles decode memory in the PDF export loop.
            let bitmap = try ImageCodec.opaqueBitmap(
                from: TestImage.solid(width: 600, height: 400),
                maxEdge: 2400
            )

            let alphaFree: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
            #expect(alphaFree.contains(bitmap.alphaInfo))
        }

        @Test("Encoded files decode without an alpha channel")
        func encodedFileHasNoAlphaChannel() throws {
            let data = try ImageCodec.encodeHEIC(TestImage.solid(width: 600, height: 400))

            let decoded = try #require(UIImage(data: data)?.cgImage)
            let alphaFree: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
            #expect(alphaFree.contains(decoded.alphaInfo))
        }

        @Test("The image is not flipped vertically by the raw drawing context")
        func preservesVerticalOrientation() throws {
            // `CGContext` origin is bottom-left, UIKit's is top-left. Without the
            // explicit flip every stored receipt would be upside down.
            let source = TestImage.twoTone(width: 200, height: 200, top: .red, bottom: .blue)

            let bitmap = try ImageCodec.opaqueBitmap(from: source, maxEdge: 2400)
            let top = try #require(TestImage.pixel(in: bitmap, x: 100, y: 20))
            let bottom = try #require(TestImage.pixel(in: bitmap, x: 100, y: 180))

            #expect(top.r > top.b)
            #expect(bottom.b > bottom.r)
        }

        @Test("Orientation survives a full encode and decode")
        func orientationSurvivesRoundTrip() throws {
            let source = TestImage.twoTone(width: 200, height: 200, top: .red, bottom: .blue)

            let data = try ImageCodec.encodeHEIC(source)
            let decoded = try #require(UIImage(data: data)?.cgImage)
            let top = try #require(TestImage.pixel(in: decoded, x: 100, y: 20))
            let bottom = try #require(TestImage.pixel(in: decoded, x: 100, y: 180))

            #expect(top.r > top.b)
            #expect(bottom.b > bottom.r)
        }

        @Test("Encoding respects the configured maximum edge")
        func encodingAppliesDownscale() throws {
            let oversized = TestImage.solid(width: 4000, height: 2000)

            let data = try ImageCodec.encodeHEIC(oversized, maxEdge: 1000)
            let decoded = try #require(UIImage(data: data))

            #expect(decoded.size.width == 1000)
            #expect(decoded.size.height == 500)
        }

        @Test("HEIC is materially smaller than an equivalent-quality JPEG")
        func heicBeatsJPEG() throws {
            let image = TestImage.solid(width: 1200, height: 1600, color: .systemTeal)

            let heic = try ImageCodec.encodeHEIC(image)
            let jpeg = try #require(image.jpegData(compressionQuality: StorageConstants.compressionQuality))

            #expect(heic.count < jpeg.count)
        }
    }
}
