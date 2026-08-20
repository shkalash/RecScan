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
