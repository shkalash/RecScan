import Foundation

/// Failures raised by the image storage layer.
///
/// Responsibilities:
/// - Describe, in domain terms, every way a receipt image operation can fail.
enum StorageError: Error, Equatable {
    /// The `UIImage` handed in had no backing `CGImage` (e.g. a pure `CIImage`).
    case imageHasNoBitmap
    /// ImageIO refused to create a HEIC destination or finalise it.
    case encodingFailed
    /// The file exists but could not be decoded into an image.
    case decodingFailed(relativePath: String)
    /// No file at the resolved path — typically an orphaned row.
    case fileMissing(relativePath: String)
}
