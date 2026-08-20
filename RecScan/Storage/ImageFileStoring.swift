import Foundation
import UIKit

/// Reads and writes the image file that backs a receipt.
///
/// Responsibilities:
/// - Own the mapping between a receipt identifier and a file on disk.
/// - Resolve relative paths against the current container at every call.
///
/// Why a protocol: the persistence actor depends on this abstraction rather than on
/// `FileManager`, which is what makes the store unit-testable against a temporary
/// directory (Dependency Inversion).
protocol ImageFileStoring: Sendable {

    /// The relative path a receipt with this identifier will be stored at.
    func relativePath(for id: UUID) -> String

    /// Resolves a stored relative path to an absolute URL in the *current* container.
    func absoluteURL(forRelativePath relativePath: String) -> URL

    /// Encodes and writes `image`, returning the relative path it was written to.
    @discardableResult
    func write(_ image: UIImage, for id: UUID) throws -> String

    /// Decodes the full-resolution image. Callers must not hold onto the result.
    func fullResolutionImage(atRelativePath relativePath: String) throws -> UIImage

    /// Returns a cached or freshly generated thumbnail.
    func thumbnail(atRelativePath relativePath: String, id: UUID) throws -> UIImage

    /// Removes the backing file and any cached thumbnail. Succeeds if already absent.
    func delete(relativePath: String, id: UUID) throws
}
