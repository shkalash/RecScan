import Foundation

/// An error prepared for display in an alert.
///
/// Responsibilities:
/// - Give a thrown error an identity so `.alert(item:)` can present it.
/// - Keep the underlying description out of the localisation catalogue while still
///   surfacing it, since these are diagnostics rather than designed copy.
struct PresentableError: Identifiable {
    let id = UUID()
    let titleKey: String.LocalizationValue
    let message: String

    init(titleKey: String.LocalizationValue, error: any Error) {
        self.titleKey = titleKey
        self.message = error.localizedDescription
    }
}
