import Foundation
import Testing
@testable import RecScan

@Suite("Amount parsing")
struct DecimalParsingTests {

    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test("Empty input means 'no amount', not zero")
    func emptyInputIsNil() {
        #expect(DecimalParsing.decimal(from: "", locale: us) == nil)
        #expect(DecimalParsing.decimal(from: "   ", locale: us) == nil)
    }

    @Test("A plain decimal parses in the current locale")
    func parsesLocaleDecimal() {
        #expect(DecimalParsing.decimal(from: "12.50", locale: us) == Decimal(string: "12.50"))
        #expect(DecimalParsing.decimal(from: "12,50", locale: german) == Decimal(string: "12.50"))
    }

    @Test("A dotted decimal still parses on a comma locale")
    func fallsBackToPOSIX() {
        // Someone typing on a hardware keypad gets a dot regardless of locale; the
        // value they meant is twelve fifty either way.
        #expect(DecimalParsing.decimal(from: "12.50", locale: german) == Decimal(string: "12.50"))
    }

    @Test("Grouped input parses")
    func parsesGroupedInput() {
        #expect(DecimalParsing.decimal(from: "1,234.56", locale: us) == Decimal(string: "1234.56"))
    }

    @Test("Nonsense input yields no amount")
    func rejectsNonsense() {
        #expect(DecimalParsing.decimal(from: "abc", locale: us) == nil)
    }

    @Test("Editable text is plain digits with no grouping or symbol")
    func editableTextIsPlain() {
        #expect(DecimalParsing.editableText(from: Decimal(string: "1234.5"), locale: us) == "1234.5")
        #expect(DecimalParsing.editableText(from: nil, locale: us) == "")
    }

    @Test("Rendering then parsing round-trips")
    func roundTrips() {
        let amount = Decimal(string: "987.65")

        let text = DecimalParsing.editableText(from: amount, locale: german)

        #expect(DecimalParsing.decimal(from: text, locale: german) == amount)
    }
}

@Suite("Default currency resolution")
struct AppSettingsTests {

    private func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        suite.removePersistentDomain(forName: suite.description)
        return suite
    }

    @Test("An explicit setting wins over the locale")
    func settingWins() {
        let store = defaults()
        store.set("ILS", forKey: AppSettings.Key.defaultCurrencyCode)

        let code = AppSettings.defaultCurrencyCode(defaults: store, locale: Locale(identifier: "en_US"))

        #expect(code == "ILS")
    }

    @Test("With no setting, the locale's currency is used")
    func localeFallback() {
        let code = AppSettings.defaultCurrencyCode(defaults: defaults(), locale: Locale(identifier: "en_US"))

        #expect(code == "USD")
    }

    @Test("A locale with no currency falls back rather than producing nothing")
    func finalFallback() {
        let code = AppSettings.defaultCurrencyCode(defaults: defaults(), locale: Locale(identifier: "en_001"))

        #expect(!code.isEmpty)
    }

    @Test("A receipt's own currency always beats the default")
    func receiptCurrencyWins() {
        let formatted = ReceiptFormatting.amount(
            Decimal(string: "12.50"), currencyCode: "EUR",
            defaultCode: "ILS", locale: Locale(identifier: "en_US")
        )

        #expect(formatted?.contains("€") == true)
    }

    @Test("A receipt with no currency renders in the default")
    func defaultAppliesRetroactively() {
        // The point of the setting: existing receipts stamped with no currency pick up
        // the new default without being edited.
        let formatted = ReceiptFormatting.amount(
            Decimal(string: "12.50"), currencyCode: nil,
            defaultCode: "ILS", locale: Locale(identifier: "en_US")
        )

        #expect(formatted?.contains("₪") == true)
    }
}
