import Foundation
import Testing
@testable import RecScan

@Suite("Amount parsing")
struct ReceiptAmountParserTests {

    /// Verbatim output from running Vision over a synthetic Hebrew receipt. Using the real
    /// garbage rather than an imagined version is the point: the Hebrew words come back as
    /// Latin lookalikes, and the parser has to be unbothered by them.
    private let hebrewOCR = #"n7H 790 | 12.90 | 7.50 | 24.30 | a70 | naaa | 7.60 | N52.30 | 17%nAN"#

    @Test("Amounts are found among unrecognised Hebrew text")
    func findsAmountsInGarbage() {
        let values = ReceiptAmountParser.candidates(in: hebrewOCR).map(\.value)

        #expect(values == [
            Decimal(string: "52.30"), Decimal(string: "24.30"), Decimal(string: "12.90"),
            Decimal(string: "7.60"), Decimal(string: "7.50")
        ].compactMap { $0 })
    }

    @Test("A bare percentage is not an amount")
    func ignoresPercentages() {
        // "17%nAN" appears in the fixture and must not become 17.
        #expect(!ReceiptAmountParser.candidates(in: hebrewOCR).contains { $0.value == 17 })
    }

    @Test("The largest is offered first")
    func largestWins() {
        let guess = ReceiptAmountParser.bestGuess(in: hebrewOCR)

        #expect(guess?.value == Decimal(string: "52.30"))
    }

    @Test("The matched text is kept, so a corrupted value can be spotted")
    func keepsSourceText() throws {
        // `₪52.30` was observed reading as `N52.30`; showing the source is what makes that
        // visible rather than silently accepted.
        let candidate = try #require(ReceiptAmountParser.candidates(in: hebrewOCR).first)

        #expect(candidate.text == "52.30")
    }

    @Test("Both separator conventions give the same number")
    func separatorsByShape() {
        #expect(ReceiptAmountParser.decimal(from: "1.234,56") == Decimal(string: "1234.56"))
        #expect(ReceiptAmountParser.decimal(from: "1,234.56") == Decimal(string: "1234.56"))
        #expect(ReceiptAmountParser.decimal(from: "52,30") == Decimal(string: "52.30"))
        #expect(ReceiptAmountParser.decimal(from: "52.30") == Decimal(string: "52.30"))
    }

    @Test("A European receipt parses without knowing it is European")
    func europeanReceipt() {
        let values = ReceiptAmountParser.candidates(in: "SUPERMARKT Brot 1.234,56 GESAMT EUR 52,30").map(\.value)

        #expect(values == [Decimal(string: "1234.56"), Decimal(string: "52.30")].compactMap { $0 })
    }

    @Test("A dotted date is not mistaken for an amount")
    func ignoresDates() {
        // Without a boundary check `21.08.26` yields 21.08, which would outrank a small total.
        let values = ReceiptAmountParser.candidates(in: "21.08.26  total 9.05").map(\.value)

        #expect(values == [Decimal(string: "9.05")])
    }

    @Test("Currency symbols around a value do not prevent a match")
    func handlesCurrencySymbols() {
        let values = ReceiptAmountParser.candidates(in: "$4.50 and €3.80 and 12.00₪").map(\.value)

        #expect(values.count == 3)
    }

    @Test("Duplicates are offered once")
    func deduplicates() {
        let values = ReceiptAmountParser.candidates(in: "9.05 9.05 3.00").map(\.value)

        #expect(values == [Decimal(string: "9.05"), Decimal(string: "3.00")].compactMap { $0 })
    }

    @Test("Text with no amounts yields nothing rather than failing")
    func handlesNoAmounts() {
        #expect(ReceiptAmountParser.candidates(in: "no numbers here").isEmpty)
        #expect(ReceiptAmountParser.candidates(in: "").isEmpty)
        #expect(ReceiptAmountParser.candidates(in: nil).isEmpty)
        #expect(ReceiptAmountParser.bestGuess(in: nil) == nil)
    }

    @Test("An English receipt offers the total and its neighbours")
    func englishReceipt() {
        let text = "Latte $4.50 Pastry $3.80 Subtotal $8.30 Tax $0.75 TOTAL $9.05"

        let values = ReceiptAmountParser.candidates(in: text).map(\.value)

        // Largest is the total here; the rest stay available because on a receipt with a
        // cash line it would not be.
        #expect(values.first == Decimal(string: "9.05"))
        #expect(values.count == 5)
    }
}
