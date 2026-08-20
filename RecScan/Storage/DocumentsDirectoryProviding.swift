import Foundation

/// Supplies the root directory that relative receipt paths resolve against.
///
/// Responsibilities:
/// - Abstract the Documents directory lookup.
///
/// Why it is a protocol: tests must not write into the real Documents directory, and
/// resolving the root at call time (rather than caching a URL at launch) is what keeps
/// the app correct across restores — see `Receipt.relativePath`.
protocol DocumentsDirectoryProviding: Sendable {
    var documentsDirectory: URL { get }
}

/// Production implementation backed by `FileManager`.
struct DocumentsDirectoryProvider: DocumentsDirectoryProviding {
    var documentsDirectory: URL {
        // `.userDomainMask` Documents is the backed-up, user-owned container.
        // The plan deliberately keeps receipts inside iCloud/iTunes backup.
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
