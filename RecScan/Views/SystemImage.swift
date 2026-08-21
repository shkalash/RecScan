import Foundation

/// SF Symbol names used by the app.
///
/// Responsibilities:
/// - Keep symbol identifiers out of view bodies, where a typo becomes an invisible
///   blank image rather than a compile error.
enum SystemImage {
    static let scan = "doc.viewfinder"
    static let filter = "line.3.horizontal.decrease.circle"
    static let filterActive = "line.3.horizontal.decrease.circle.fill"
    static let export = "square.and.arrow.up"
    static let delete = "trash"
    static let selectionOn = "checkmark.circle.fill"
    static let selectionOff = "circle"
    static let missingImage = "doc.questionmark"
    static let emptyLibrary = "doc.text.image"
    static let pages = "doc.on.doc"
    static let more = "ellipsis.circle"
    static let archiveExport = "arrow.up.doc"
    static let archiveImport = "arrow.down.doc"
    static let settings = "gearshape"
    static let checkmark = "checkmark"
    static let addCategory = "plus.circle"
    static let category = "tag"
    static let chevron = "chevron.right"
}
