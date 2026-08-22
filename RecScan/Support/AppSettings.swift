import Foundation

/// User preferences that are not receipt data.
///
/// Responsibilities:
/// - Own the `UserDefaults` keys and resolve a preference to a usable value.
///
/// ## Why this is the boundary, not something formatting code reads
/// `ReceiptFormatting` and `PDFBuilder` are pure and run off the main actor. If they
/// reached into `UserDefaults` themselves they would be untestable without a defaults
/// suite and would silently couple rendering to global state. Instead this type resolves
/// the value and callers pass it down.
enum AppSettings {

    /// `UserDefaults` keys. Also the `@AppStorage` keys used by settings screens, so the
    /// two can never drift apart.
    enum Key {
        static let defaultCurrencyCode = "settings.defaultCurrencyCode"
    }

    /// Used only when neither the user nor the locale supplies a currency, which happens
    /// for a few region-less locales.
    static let fallbackCurrencyCode = "USD"

    /// The currency stamped onto receipts as they are created.
    ///
    /// Read once, at import, and written onto the receipt. Changing the setting affects
    /// what arrives next and never rewrites history: a receipt paid in shekels stays in
    /// shekels when the default later moves to euros. The fallback at render time exists
    /// only for rows created before currency was stamped.
    static func defaultCurrencyCode(
        defaults: UserDefaults = .standard,
        locale: Locale = .current
    ) -> String {
        defaults.string(forKey: Key.defaultCurrencyCode)
            ?? locale.currency?.identifier
            ?? fallbackCurrencyCode
    }
}
