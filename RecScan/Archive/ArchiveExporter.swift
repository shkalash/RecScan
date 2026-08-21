import Foundation
import ZIPFoundation

/// Writes a portable archive of receipts: the original images plus a JSON manifest.
///
/// Responsibilities:
/// - Copy each receipt's image into the archive under a predictable path.
/// - Write `manifest.json` describing every entry.
///
/// ## Why a zip of files rather than a copy of the database
/// A `default.store` copy only restores into this app at this schema version, and is
/// unreadable by anything else. It is also a trap: SwiftData runs SQLite in WAL mode, so
/// the `-wal` sidecar routinely holds more recent data than the `.store` itself and a
/// partial copy silently restores stale rows. An archive of image files and plain JSON
/// has neither problem and is still worth something when the app is gone.
struct ArchiveExporter: Sendable {

    private let fileStore: any ImageFileStoring
    private let logger = LogCategory.export.logger

    init(fileStore: any ImageFileStoring = ImageFileStore()) {
        self.fileStore = fileStore
    }

    /// Builds the archive and returns its location in the temporary directory.
    ///
    /// As with the PDF, the file must stay alive until the share sheet is done with it —
    /// hand over the URL, never in-memory `Data`.
    func makeArchive(receipts: [ReceiptSnapshot], exportedAt: Date = Date()) throws -> URL {
        guard !receipts.isEmpty else { throw ArchiveError.nothingToExport }

        let destination = FileManager.default.temporaryDirectory.appending(
            path: "\(ArchiveManifest.Layout.fileNamePrefix)"
                + "\(ReceiptFormatting.exportTimestamp(for: exportedAt))"
                + ".\(ArchiveManifest.Layout.archiveFileExtension)"
        )
        try? FileManager.default.removeItem(at: destination)

        let archive = try Archive(url: destination, accessMode: .create)
        var entries: [ArchiveManifest.Entry] = []
        entries.reserveCapacity(receipts.count)

        for receipt in receipts {
            let source = fileStore.absoluteURL(forRelativePath: receipt.relativePath)
            let imageName = URL(fileURLWithPath: receipt.relativePath).lastPathComponent
            let path = "\(ArchiveManifest.Layout.imagesDirectoryName)/\(imageName)"

            do {
                // Streamed from disk by ZIPFoundation, so a large library never has more
                // than one image resident at a time.
                try archive.addEntry(with: path, fileURL: source)
            } catch {
                // A receipt whose image has gone missing still has metadata worth keeping.
                // It stays out of the manifest rather than pointing at an absent file,
                // which would make every future import report it as damaged.
                logger.error("Archive: skipping \(receipt.id, privacy: .public), image unreadable")
                continue
            }

            entries.append(ArchiveManifest.Entry(receipt, fileName: path))
        }

        let manifest = ArchiveManifest(exportedAt: exportedAt, entries: entries)
        let manifestData = try ArchiveManifest.makeEncoder().encode(manifest)
        try archive.addEntry(
            with: ArchiveManifest.Layout.manifestFileName,
            type: .file,
            uncompressedSize: Int64(manifestData.count),
            provider: { position, size in
                let start = manifestData.startIndex + Int(position)
                return manifestData.subdata(in: start..<(start + size))
            }
        )

        logger.info("Archived \(entries.count, privacy: .public) receipt(s).")
        return destination
    }
}
