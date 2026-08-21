import Foundation

/// The currency list offered by pickers.
///
/// Responsibilities:
/// - Supply the codes, their localised names, and the search over both.
///
/// Kept out of the views so the pinned set and the matching rules live in one place
/// rather than being spelled inline wherever a currency is chosen.
enum CurrencyCatalog {

    /// Shown first, above the full list.
    ///
    /// Not alphabetical and not locale-derived: these are simply the ones reached for
    /// most often, and burying them behind two hundred alphabetised codes is the thing
    /// this list exists to avoid.
    static let pinned = ["USD", "EUR", "ILS"]

    /// Every remaining code, alphabetically.
    ///
    /// - Parameter including: a code to guarantee is present — a receipt may carry a
    ///   currency that is not in the common list, and it must still be selectable.
    static func others(including selection: String? = nil) -> [String] {
        var codes = Set(Locale.commonISOCurrencyCodes)
        if let selection, !selection.isEmpty { codes.insert(selection) }
        return codes.subtracting(pinned).sorted()
    }

    /// Localised currency name, e.g. "Israeli New Shekel".
    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// Codes matching `query` by code or by name, pinned ones first.
    ///
    /// Matching the name as well as the code matters: "shekel" and "ILS" should both
    /// find the same row, and only one of those is something you can be expected to know.
    static func search(_ query: String, including selection: String? = nil, locale: Locale = .current) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = pinned + others(including: selection)
        guard !trimmed.isEmpty else { return ordered }

        return ordered.filter { code in
            code.localizedCaseInsensitiveContains(trimmed)
                || name(for: code, locale: locale).localizedCaseInsensitiveContains(trimmed)
        }
    }
}
