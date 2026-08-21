import Foundation

/// Failures raised while producing or reading an archive.
enum ArchiveError: Error, Equatable {
    /// Export was asked for an empty library.
    case nothingToExport
    /// The chosen file is not a readable zip.
    case unreadableArchive
    /// The zip contains no `manifest.json` at its root.
    case manifestMissing
    /// The manifest parsed but came from a newer, incompatible export.
    case unsupportedFormatVersion(found: Int, supported: Int)
    /// The manifest is present but malformed.
    case manifestUnreadable
    /// The system refused access to the picked file.
    case fileAccessDenied
}
