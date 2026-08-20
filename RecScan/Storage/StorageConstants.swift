import Foundation
import CoreGraphics

/// Tuning values and non user facing strings for the image storage layer.
///
/// Responsibilities:
/// - Centralise every literal that governs how receipt images are written and read,
///   so a change of quality, size or directory happens in exactly one place.
enum StorageConstants {

    /// Subdirectory of `Documents` that holds every receipt image.
    static let imageDirectoryName = "Receipts"

    /// File extension for stored receipt images.
    static let imageFileExtension = "heic"

    /// HEIC lossy quality. 0.85 is visually lossless for document scans and lands at
    /// roughly half the byte size of an equivalent-quality JPEG.
    static let compressionQuality: Double = 0.85

    /// Longest edge, in pixels, that a stored image is downscaled to on write.
    /// Receipts carry no detail beyond this, and it keeps generated PDFs small enough
    /// to send by email.
    static let maxStoredEdgePixels: CGFloat = 2400

    /// Longest edge, in pixels, of a generated grid thumbnail.
    static let thumbnailEdgePixels: CGFloat = 300

    /// Upper bound on the in-memory thumbnail cache, expressed as an object count.
    /// Thumbnails are regenerated on demand, so eviction is cheap.
    static let thumbnailCacheCountLimit = 300

    /// Scale factor used when rasterising a downscaled image. `1` means "pixels are
    /// pixels" — the source is already at device resolution and re-applying the
    /// screen scale would inflate the file.
    static let rasterisationScale: CGFloat = 1
}
