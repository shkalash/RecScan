import Foundation

/// A currency-shaped number found in a receipt's text.
///
/// Responsibilities:
/// - Pair a parsed value with the text it came from.
///
/// The original text is kept so the UI can show what was actually printed. That matters
/// because recognition can corrupt a value — `₪52.30` has been observed reading as
/// `152.30` — and seeing the source string is what lets the mistake be spotted.
struct AmountCandidate: Sendable, Equatable, Identifiable {

    let value: Decimal
    /// The matched substring, exactly as recognised.
    let text: String

    var id: String { "\(text)-\(value)" }
}
