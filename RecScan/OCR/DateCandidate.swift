import Foundation

/// A date found in a receipt's text.
///
/// Responsibilities:
/// - Pair a parsed date with the text it came from and how certain the reading is.
///
/// The original text is kept for the same reason as `AmountCandidate`: `05/06/2026` is
/// two different dates depending on where the receipt was printed, and showing what was
/// actually on the page is what lets the right one be picked.
struct DateCandidate: Sendable, Equatable, Identifiable {

    /// How much the reading can be trusted, which is also the ranking.
    ///
    /// Ambiguity here is a property of the receipt, not of the parser: a purely numeric
    /// `05/06/2026` genuinely is both 5 June and 6 May, and no amount of cleverness
    /// settles it from the page alone.
    enum Confidence: Int, Sendable, Comparable {
        /// A month name, an ISO date, or a component over 12 — only one reading exists.
        case unambiguous = 0
        /// Day-first or month-first was decided by the document's language or the locale.
        case inferredOrder = 1
        /// The other reading of the same ambiguous date, offered so it is one tap away.
        case alternativeOrder = 2

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let date: Date
    /// The matched substring, exactly as printed.
    let text: String
    let confidence: Confidence

    var id: String { "\(text)-\(date.timeIntervalSince1970)" }
}
