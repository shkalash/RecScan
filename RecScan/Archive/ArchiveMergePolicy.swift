import Foundation

/// Decides what to do with one incoming archived receipt.
///
/// Responsibilities:
/// - Compare an archived receipt against whatever the library already holds and
///   choose insert, update, or skip.
///
/// ## Identity
/// A receipt is identified by its `UUID`, assigned once at capture and carried through
/// export and back. It is deliberately *not* content-based: two scans of the same paper
/// receipt are two different receipts, and no amount of image comparison should merge
/// them. Equally, the same receipt exported twice keeps one identity, so re-importing
/// an archive is a no-op rather than a way to double your library.
///
/// The `id` carries no `@Attribute(.unique)` — a unique constraint would block the
/// CloudKit-backed configuration the model is shaped for — so uniqueness is enforced
/// here, at the point of import, instead of by the store.
///
/// ## Conflict resolution
/// Last writer wins, per receipt, compared on `modifiedAt`. Field-level merging would
/// mean reconciling a merchant edited in one place against a note edited in another,
/// which is a lot of machinery for a single-user app that will almost never hit it.
enum ArchiveMergePolicy {

    /// What importing one archived receipt should do.
    enum Decision: Equatable {
        /// Nothing local has this identity — add it.
        case insert
        /// A local row exists and the archived copy is newer — overwrite its fields.
        case update
        /// A local row exists and is the same age or newer — leave it alone.
        case skip
    }

    /// The parts of a local receipt the decision depends on.
    struct LocalState: Equatable {
        let modifiedAt: Date
        /// Whether the backing image is actually present on disk. A row whose file has
        /// gone missing is repairable from an archive even when the metadata is current.
        let hasImageFile: Bool
    }

    /// - Parameters:
    ///   - local: the matching local receipt, or `nil` if none exists.
    ///   - archivedModifiedAt: the archived copy's last-modified stamp.
    /// - Returns: the action to take.
    static func decide(local: LocalState?, archivedModifiedAt: Date) -> Decision {
        guard let local else { return .insert }

        // A restored file is strictly a gain: the row is already there but unopenable,
        // and the archive is the only place the image still exists.
        if !local.hasImageFile { return .update }

        return archivedModifiedAt > local.modifiedAt ? .update : .skip
    }
}
