import Foundation
import ZIPFoundation

/// Reads an archive and reports what it contains.
///
/// Responsibilities:
/// - Open the zip, validate the manifest, and pair each entry with its image bytes.
///
/// Merging into the library is `ReceiptStore`'s job: it owns both the database and the
/// image directory, and those two have to move together or rows end up orphaned.
struct ArchiveImporter: Sendable {

    /// A manifest entry paired with the image found for it, if any.
    struct StagedReceipt: Sendable, Equatable {
        let entry: ArchiveManifest.Entry
        /// `nil` when the manifest listed an image the archive does not actually contain.
        let imageData: Data?
    }

    /// Opens `url` and returns everything it holds.
    ///
    /// - Note: a URL from the document picker is security-scoped. The caller must have
    ///   started access before calling this and must stop it afterwards.
    func read(archiveAt url: URL) throws -> (manifest: ArchiveManifest, receipts: [StagedReceipt]) {
        // ZIPFoundation's underlying error is deliberately dropped: "not a readable zip"
        // is the only thing the user can act on, and picking the wrong file is the only
        // way to get here.
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ArchiveError.unreadableArchive
        }

        guard let manifestEntry = archive[ArchiveManifest.Layout.manifestFileName] else {
            throw ArchiveError.manifestMissing
        }

        let manifestData = try extract(manifestEntry, from: archive)
        guard let manifest = try? ArchiveManifest.makeDecoder()
            .decode(ArchiveManifest.self, from: manifestData) else {
            throw ArchiveError.manifestUnreadable
        }
        // Older archives are read, not refused: v1 simply lacks categories and the
        // review flag, and its optional keys decode as absent.
        guard manifest.formatVersion <= ArchiveManifest.currentFormatVersion else {
            throw ArchiveError.unsupportedFormatVersion(
                found: manifest.formatVersion,
                supported: ArchiveManifest.currentFormatVersion
            )
        }

        let staged = manifest.entries.map { entry in
            let imageData = archive[entry.fileName].flatMap { try? extract($0, from: archive) }
            return StagedReceipt(entry: entry, imageData: imageData)
        }

        return (manifest, staged)
    }

    // MARK: - Private

    /// `Archive.extract` delivers the entry in chunks; this reassembles them.
    private func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return data
    }
}
