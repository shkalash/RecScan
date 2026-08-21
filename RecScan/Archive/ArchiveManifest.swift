import Foundation

/// The metadata half of an exported archive, written as `manifest.json`.
///
/// Responsibilities:
/// - Describe every exported receipt in a form that outlives the app.
///
/// ## Why JSON and not the store file
/// A copy of `default.store` is only restorable into this app, at this schema version,
/// and is unreadable by anything else. The point of an archive is to still be worth
/// something when the app is gone, so the metadata travels as plain JSON beside the
/// original image files.
struct ArchiveManifest: Codable, Equatable {

    /// One receipt's metadata.
    struct Entry: Codable, Equatable {
        let id: UUID
        let capturedAt: Date
        let createdAt: Date
        let modifiedAt: Date
        /// Path of the image inside the archive, relative to its root.
        let fileName: String
        let merchant: String?
        /// Decimal encoded as a string.
        ///
        /// `Decimal` through `JSONEncoder` round-trips via `Double` and can come back
        /// as 12.499999999999998. Money does not survive that, so it travels as text.
        let amount: String?
        let currencyCode: String?
        let note: String?
        let ocrText: String?
        let groupID: UUID?
        let pageIndex: Int

        var decimalAmount: Decimal? {
            guard let amount else { return nil }
            return Decimal(string: amount)
        }
    }

    /// Bumped when the layout changes in a way an older importer could misread.
    let formatVersion: Int
    let application: String
    let exportedAt: Date
    let entries: [Entry]

    static let currentFormatVersion = 1
    static let applicationName = "RecScan"

    init(exportedAt: Date, entries: [Entry]) {
        formatVersion = Self.currentFormatVersion
        application = Self.applicationName
        self.exportedAt = exportedAt
        self.entries = entries
    }
}

extension ArchiveManifest {

    /// Names of the things inside an archive. Not user facing.
    enum Layout {
        static let manifestFileName = "manifest.json"
        static let imagesDirectoryName = "Receipts"
        static let archiveFileExtension = "zip"
        static let fileNamePrefix = "RecScan-Archive-"
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted keys keep two exports of the same library byte-comparable, which makes
        // "did anything actually change" answerable with a diff.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension ArchiveManifest.Entry {
    init(_ receipt: ReceiptSnapshot, fileName: String) {
        self.init(
            id: receipt.id,
            capturedAt: receipt.capturedAt,
            createdAt: receipt.createdAt,
            modifiedAt: receipt.modifiedAt,
            fileName: fileName,
            merchant: receipt.merchant,
            amount: receipt.amount.map { "\($0)" },
            currencyCode: receipt.currencyCode,
            note: receipt.note,
            ocrText: receipt.ocrText,
            groupID: receipt.groupID,
            pageIndex: receipt.pageIndex
        )
    }
}
