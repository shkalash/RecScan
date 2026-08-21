import Foundation

/// What an archive export covers.
enum ArchiveScope: String, CaseIterable, Identifiable, Sendable {
    /// Every receipt, ignoring the active filter and selection.
    case entireLibrary
    /// Only what is currently selected.
    case currentSelection

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .entireLibrary: "archive.scope.entireLibrary"
        case .currentSelection: "archive.scope.currentSelection"
        }
    }
}
