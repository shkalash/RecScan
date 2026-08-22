import Foundation
import UniformTypeIdentifiers

/// What the file picker is currently being opened for.
///
/// Responsibilities:
/// - Name the two things that can be imported from a file, and what each accepts.
///
/// ## Why one picker rather than two
/// Two `.fileImporter` modifiers on the same view do not both work: they are presentation
/// modifiers, and the later one wins, leaving the earlier button doing nothing at all.
/// Driving a single importer from this mode makes the two routes mutually exclusive by
/// construction, which is what they always were in practice.
enum FileImportMode: Identifiable {

    /// A backup archive to merge into the library.
    case archive
    /// Images and PDFs to add as receipts.
    case receipts

    var id: Self { self }

    var contentTypes: [UTType] {
        switch self {
        case .archive: [.zip]
        case .receipts: [.image, .pdf]
        }
    }

    /// An archive is restored one at a time; receipts arrive in batches.
    var allowsMultipleSelection: Bool {
        switch self {
        case .archive: false
        case .receipts: true
        }
    }
}
