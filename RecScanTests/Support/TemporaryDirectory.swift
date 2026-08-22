import Foundation
import UIKit
@testable import RecScan

/// A throwaway directory that stands in for the app's Documents directory.
///
/// Responsibilities:
/// - Give each test an isolated file-system root.
/// - Delete that root when the test finishes.
///
/// Why it exists: `ImageFileStore` resolves every path against a
/// `DocumentsDirectoryProviding`, so pointing that at a temporary directory keeps the
/// suite from touching the real container.
final class TemporaryDirectory: DocumentsDirectoryProviding, @unchecked Sendable {

    let documentsDirectory: URL

    init() {
        documentsDirectory = FileManager.default.temporaryDirectory
            .appending(path: "RecScanTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: documentsDirectory)
    }

    func fileExists(atRelativePath relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: documentsDirectory.appending(path: relativePath).path(percentEncoded: false)
        )
    }

    /// Decodes a stored image, for tests that care about what was actually written.
    func image(atRelativePath relativePath: String) throws -> UIImage {
        try ImageCodec.decodeImage(at: documentsDirectory.appending(path: relativePath))
    }
}
