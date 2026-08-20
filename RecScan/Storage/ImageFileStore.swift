import Foundation
import UIKit

/// `FileManager`-backed implementation of `ImageFileStoring`.
///
/// Responsibilities:
/// - Create and protect the receipts directory.
/// - Encode to HEIC on write and decode on read.
/// - Serve thumbnails through `ThumbnailCache`.
struct ImageFileStore: ImageFileStoring {

    private let directoryProvider: any DocumentsDirectoryProviding
    private let thumbnailCache: ThumbnailCache

    init(
        directoryProvider: any DocumentsDirectoryProviding = DocumentsDirectoryProvider(),
        thumbnailCache: ThumbnailCache = ThumbnailCache()
    ) {
        self.directoryProvider = directoryProvider
        self.thumbnailCache = thumbnailCache
    }

    // MARK: - Paths

    func relativePath(for id: UUID) -> String {
        "\(StorageConstants.imageDirectoryName)/\(id.uuidString).\(StorageConstants.imageFileExtension)"
    }

    func absoluteURL(forRelativePath relativePath: String) -> URL {
        // Resolved on every call: the container prefix is not stable across installs.
        directoryProvider.documentsDirectory.appending(path: relativePath)
    }

    // MARK: - Write

    @discardableResult
    func write(_ image: UIImage, for id: UUID) throws -> String {
        let data = try ImageCodec.encodeHEIC(image)
        let path = relativePath(for: id)
        let url = absoluteURL(forRelativePath: path)

        try createImageDirectoryIfNeeded()
        // `.completeUnlessOpen` keeps receipts encrypted while the device is locked
        // but lets an in-flight export finish if the screen locks mid-write.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return path
    }

    // MARK: - Read

    func fullResolutionImage(atRelativePath relativePath: String) throws -> UIImage {
        let url = absoluteURL(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw StorageError.fileMissing(relativePath: relativePath)
        }
        return try ImageCodec.decodeImage(at: url)
    }

    func thumbnail(atRelativePath relativePath: String, id: UUID) throws -> UIImage {
        if let cached = thumbnailCache.image(for: id) { return cached }

        let url = absoluteURL(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw StorageError.fileMissing(relativePath: relativePath)
        }
        let image = try ImageCodec.thumbnail(at: url, maxEdge: StorageConstants.thumbnailEdgePixels)
        thumbnailCache.store(image, for: id)
        return image
    }

    // MARK: - Delete

    func delete(relativePath: String, id: UUID) throws {
        thumbnailCache.removeImage(for: id)
        let url = absoluteURL(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func createImageDirectoryIfNeeded() throws {
        let directory = directoryProvider.documentsDirectory
            .appending(path: StorageConstants.imageDirectoryName)
        guard !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
    }
}
