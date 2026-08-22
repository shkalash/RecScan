import Foundation

/// Pulls currency-shaped numbers out of a receipt's text.
///
/// Responsibilities:
/// - Find every plausible amount and rank them.
///
/// ## Why this is purely numeric
/// Vision cannot recognise Hebrew, so a Hebrew receipt yields correct digits and unusable
/// words — there is no `סה"כ` to anchor on. Digits, though, are the same glyphs in every
/// script, so a numeric approach works for Hebrew, English and anything else without
/// knowing which it is looking at.
///
/// Taking plain text rather than Vision observations means PDF-imported receipts, whose
/// `ocrText` is already real text, get the same treatment for free.
///
/// ## The ranking is a heuristic
/// Largest wins, which is right on an ordinary receipt and wrong when a bigger number
/// appears — cash tendered, a pre-discount subtotal, an account number with two decimals.
/// The rest are offered as alternatives rather than discarded, because there is no reliable
/// way to tell those cases apart without reading the labels.
enum ReceiptAmountParser {

    /// Digits with a two-digit fraction, optionally grouped: `52.30`, `1,234.56`, `1.234,56`.
    private static let pattern = #"\d+(?:[.,]\d{3})*[.,]\d{2}"#

    /// Every amount found, largest first, without duplicates.
    static func candidates(in text: String?) -> [AmountCandidate] {
        guard let text, !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern)
        else { return [] }

        let full = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: full.length))

        var seen = Set<Decimal>()
        var found: [AmountCandidate] = []

        for match in matches where isStandalone(match.range, in: full) {
            let matched = full.substring(with: match.range)
            guard let value = decimal(from: matched), value > 0, !seen.contains(value) else { continue }
            seen.insert(value)
            found.append(AmountCandidate(value: value, text: matched))
        }

        return found.sorted { $0.value > $1.value }
    }

    /// The value to offer first.
    static func bestGuess(in text: String?) -> AmountCandidate? {
        candidates(in: text).first
    }

    // MARK: - Private

    /// Rejects matches that are a fragment of a longer run of digits and separators.
    ///
    /// A date like `21.08.26` otherwise yields `21.08`, and part numbers do the same. A
    /// real amount is bounded by something that is not a digit and not a separator glued to
    /// more digits.
    private static func isStandalone(_ range: NSRange, in text: NSString) -> Bool {
        let before = range.location - 1
        if before >= 0 {
            let character = text.substring(with: NSRange(location: before, length: 1))
            if character.rangeOfCharacter(from: .decimalDigits) != nil { return false }
            if character == "." || character == "," { return false }
        }

        let after = range.location + range.length
        guard after < text.length else { return true }
        let character = text.substring(with: NSRange(location: after, length: 1))
        if character.rangeOfCharacter(from: .decimalDigits) != nil { return false }

        // A trailing separator only disqualifies the match when more digits follow it,
        // which is what makes `21.08.26` a date rather than an amount.
        if character == "." || character == "," {
            let next = after + 1
            guard next < text.length else { return true }
            return text.substring(with: NSRange(location: next, length: 1))
                .rangeOfCharacter(from: .decimalDigits) == nil
        }
        return true
    }

    /// Reads a value by the shape of its separators rather than by locale.
    ///
    /// `1.234,56` and `1,234.56` are both 1234.56, and a receipt does not say which
    /// convention it used. The rule: the last separator followed by exactly two digits is
    /// the decimal point, everything earlier is grouping. Trusting `Locale.current` instead
    /// would misread a German receipt on an English phone.
    static func decimal(from matched: String) -> Decimal? {
        guard let separatorIndex = matched.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return Decimal(string: matched)
        }

        let whole = matched[matched.startIndex..<separatorIndex]
            .filter { $0.isNumber }
        let fraction = matched[matched.index(after: separatorIndex)...]

        guard !whole.isEmpty || !fraction.isEmpty else { return nil }
        return Decimal(string: "\(whole.isEmpty ? "0" : whole).\(fraction)")
    }
}
