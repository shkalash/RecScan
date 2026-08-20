import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Pure image encoding / decoding helpers.
///
/// Responsibilities:
/// - Downscale a captured image to the stored size.
/// - Encode a `UIImage` to HEIC data.
/// - Produce a thumbnail from a file without decoding the full-resolution image.
///
/// Why a caseless `enum` of static methods: these are total functions with no state.
/// Giving them an instance would imply a lifetime they do not have.
enum ImageCodec {

    /// Encodes `image` as HEIC, downscaling so its longest edge is at most
    /// `maxEdge` pixels.
    ///
    /// - Note: the scanner already deskews, crops and de-shadows its output. No
    ///   additional `CIFilter` correction is applied here on purpose — re-processing
    ///   a corrected scan visibly degrades it.
    ///
    /// - Important: call this from one task at a time. The platform HEVC encoder is a
    ///   shared resource, and on the iOS Simulator a dozen concurrent
    ///   `CGImageDestinationFinalize` calls deadlock outright rather than queueing.
    ///   The app satisfies this by construction: `ReceiptStore` is a serial actor and
    ///   is the only caller that writes images. Any future parallel importer must keep
    ///   that guarantee.
    static func encodeHEIC(
        _ image: UIImage,
        maxEdge: CGFloat = StorageConstants.maxStoredEdgePixels,
        quality: Double = StorageConstants.compressionQuality
    ) throws -> Data {
        let cgImage = try opaqueBitmap(from: image, maxEdge: maxEdge)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw StorageError.encodingFailed
        }

        // No orientation tag: `opaqueBitmap` has already baked orientation into the
        // pixels, so the stored file is upright with no metadata to misinterpret.
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw StorageError.encodingFailed }
        return data as Data
    }

    /// Renders `image` into an **alpha-free** bitmap whose longest edge is at most
    /// `maxEdge`, with orientation baked into the pixels.
    ///
    /// ## Why this does not use `UIGraphicsImageRenderer`
    /// Setting `UIGraphicsImageRendererFormat.opaque = true` does not reliably produce
    /// an alpha-free bitmap — on device the renderer still hands back `AlphaLast`, and
    /// ImageIO then logs that it is discarding an alpha channel that "will double the
    /// required memory when decoding the image". Receipt scans are opaque by
    /// definition, and the PDF exporter decodes them one full-resolution page at a
    /// time, so that doubling is exactly the memory the export loop cannot spare.
    /// An explicit `CGContext` with `noneSkipLast` guarantees the channel is gone.
    static func opaqueBitmap(from image: UIImage, maxEdge: CGFloat) throws -> CGImage {
        let targetSize = fittedPixelSize(for: image, maxEdge: maxEdge)
        guard targetSize.width >= 1, targetSize.height >= 1 else {
            throw StorageError.imageHasNoBitmap
        }

        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw StorageError.imageHasNoBitmap
        }
        context.interpolationQuality = .high

        // A raw `CGContext` has its origin at the bottom left, while UIKit drawing
        // assumes the top left. Flipping here lets `UIImage.draw` run normally, which
        // is what applies the image's own orientation.
        context.translateBy(x: 0, y: targetSize.height)
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        UIGraphicsPopContext()

        guard let bitmap = context.makeImage() else { throw StorageError.imageHasNoBitmap }
        return bitmap
    }

    /// The pixel size `image` should occupy, clamped so its longest edge fits `maxEdge`.
    /// Images already within the limit keep their own pixel dimensions.
    static func fittedPixelSize(for image: UIImage, maxEdge: CGFloat) -> CGSize {
        let pixelSize = CGSize(
            width: (image.size.width * image.scale).rounded(),
            height: (image.size.height * image.scale).rounded()
        )
        let longestEdge = max(pixelSize.width, pixelSize.height)
        guard longestEdge > maxEdge, longestEdge > 0 else { return pixelSize }

        let ratio = maxEdge / longestEdge
        return CGSize(
            width: (pixelSize.width * ratio).rounded(),
            height: (pixelSize.height * ratio).rounded()
        )
    }

    /// 8 bits per channel: the only depth the HEIC path needs, and what
    /// `noneSkipLast` expects.
    private static let bitsPerComponent = 8

    /// Decodes the full-resolution image stored at `url`.
    static func decodeImage(at url: URL) throws -> UIImage {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else {
            throw StorageError.decodingFailed(relativePath: url.lastPathComponent)
        }
        return image
    }

    /// Produces a thumbnail directly from the file.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` decodes only what it needs, so the
    /// full-resolution bitmap never enters memory. This is why the app persists no
    /// second set of thumbnail files.
    static func thumbnail(at url: URL, maxEdge: CGFloat) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw StorageError.fileMissing(relativePath: url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StorageError.decodingFailed(relativePath: url.lastPathComponent)
        }
        return UIImage(cgImage: cgImage)
    }
}
