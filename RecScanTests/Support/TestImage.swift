import UIKit

/// Builds deterministic images for the storage and export suites.
enum TestImage {

    /// A solid-colour image of an exact pixel size.
    ///
    /// The renderer scale is pinned to 1 so `size` is in pixels, which is what the
    /// downscaling assertions are written against.
    static func solid(
        width: CGFloat,
        height: CGFloat,
        color: UIColor = .systemBlue
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension TestImage {

    /// A two-tone image: `top` fills the upper half, `bottom` the lower half.
    ///
    /// Used to detect vertical flipping. `ImageCodec` draws into a raw `CGContext`,
    /// whose origin is bottom-left while UIKit's is top-left, so a missing flip is a
    /// real and easy regression.
    static func twoTone(
        width: CGFloat,
        height: CGFloat,
        top: UIColor = .red,
        bottom: UIColor = .blue
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            top.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            bottom.setFill()
            context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        }
    }

    /// Reads one pixel, in UIKit coordinates (y increasing downward).
    static func pixel(in cgImage: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        let bytesPerPixel = 4
        var buffer = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * bytesPerPixel)

        guard let context = CGContext(
            data: &buffer,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let offset = (y * cgImage.width + x) * bytesPerPixel
        guard offset + 2 < buffer.count else { return nil }
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2])
    }
}
