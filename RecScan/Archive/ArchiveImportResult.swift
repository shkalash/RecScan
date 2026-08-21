import Foundation

/// What an archive import actually did.
///
/// Responsibilities:
/// - Report the outcome in the terms the user cares about, so a merge is never silent.
///
/// A restore that says only "done" is untrustworthy: the interesting cases are the ones
/// it skipped and the images it could not find.
struct ArchiveImportResult: Sendable, Equatable, Identifiable {

    /// Fresh per import, so presenting two results in a row re-renders the sheet rather
    /// than reusing the first one's identity.
    let id = UUID()

    /// Receipts that did not exist locally and were added.
    var inserted: Int = 0
    /// Existing receipts the archive was newer than, or whose missing image it restored.
    var updated: Int = 0
    /// Existing receipts left alone because the local copy was the same age or newer.
    var skipped: Int = 0
    /// Manifest entries whose image was absent from the archive.
    var missingImages: Int = 0

    var total: Int { inserted + updated + skipped + missingImages }
    var changedAnything: Bool { inserted > 0 || updated > 0 }
}
