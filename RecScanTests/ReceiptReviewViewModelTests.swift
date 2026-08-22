import Foundation
import Testing
@testable import RecScan

@MainActor
@Suite("Review sheet state")
struct ReceiptReviewViewModelTests {

    private func snapshot(
        capturedAt: Date = Date(),
        merchant: String? = nil,
        amount: Decimal? = nil,
        categoryID: UUID? = nil
    ) -> ReceiptSnapshot {
        let id = UUID()
        return ReceiptSnapshot(
            id: id,
            capturedAt: capturedAt,
            createdAt: capturedAt,
            modifiedAt: capturedAt,
            relativePath: "Receipts/\(id.uuidString).heic",
            merchant: merchant,
            amount: amount,
            currencyCode: nil,
            note: nil,
            ocrText: nil,
            categoryID: categoryID,
            needsReview: true
        )
    }

    @Test("A single receipt is not treated as a batch")
    func singleIsNotBatch() {
        let model = ReceiptReviewViewModel(receipts: [snapshot()])

        #expect(!model.isBatch)
        #expect(model.entries.count == 1)
    }

    @Test("Existing values are carried into the form")
    func seedsFromSnapshot() {
        let category = UUID()
        let model = ReceiptReviewViewModel(receipts: [
            snapshot(merchant: "Blue Bottle", amount: Decimal(string: "12.5"), categoryID: category)
        ])

        let entry = model.entries[0]
        #expect(entry.edit.merchant == "Blue Bottle")
        #expect(entry.edit.categoryID == category)
        // The text field starts populated, not blank, or an existing amount looks lost.
        #expect(entry.amountText == "12.5")
    }

    @Test("Typing an amount keeps text and parsed value in step")
    func amountTracksTyping() {
        let model = ReceiptReviewViewModel(receipts: [snapshot()])

        model.updateAmountText("42.50", at: 0)

        #expect(model.entries[0].amountText == "42.50")
        #expect(model.entries[0].edit.amount == Decimal(string: "42.50"))
    }

    @Test("A half-typed amount does not throw away what was typed")
    func partialAmountIsKept() {
        let model = ReceiptReviewViewModel(receipts: [snapshot()])

        model.updateAmountText("12.", at: 0)

        // The text survives even though it is not yet a number; reformatting mid-entry
        // would fight the user.
        #expect(model.entries[0].amountText == "12.")
    }

    @Test("Apply-to-all sets the date on every receipt")
    func appliesSharedDate() {
        let model = ReceiptReviewViewModel(receipts: [snapshot(), snapshot(), snapshot()])
        let target = TestCalendar.date(year: 2026, month: 8, day: 12)
        model.sharedDate = target

        model.applySharedDate()

        #expect(model.entries.allSatisfy { $0.edit.capturedAt == target })
    }

    @Test("Apply-to-all sets the category on every receipt")
    func appliesSharedCategory() {
        let model = ReceiptReviewViewModel(receipts: [snapshot(), snapshot()])
        let category = UUID()
        model.sharedCategoryID = category

        model.applySharedCategory()

        #expect(model.entries.allSatisfy { $0.edit.categoryID == category })
    }

    @Test("Applying a shared value overwrites a per-receipt edit")
    func sharedValueOverwrites() {
        let model = ReceiptReviewViewModel(receipts: [snapshot(), snapshot()])
        model.setMerchant("Kept", at: 0)
        let category = UUID()
        model.sharedCategoryID = category

        model.applySharedCategory()

        // Documented in the sheet's footer: apply-to-all is destructive by design.
        #expect(model.entries.allSatisfy { $0.edit.categoryID == category })
        #expect(model.entries[0].edit.merchant == "Kept")
    }

    @Test("Several receipts read as a batch")
    func manyIsBatch() {
        let model = ReceiptReviewViewModel(receipts: [snapshot(), snapshot(), snapshot()])

        #expect(model.isBatch)
        #expect(model.entries.count == 3)
    }

    // MARK: - Recognised amounts

    /// The verbatim output of recognising a real Hebrew receipt, garbage included.
    private static let recognizedReceipt =
        "n7H 790 | 12.90 | 7.50 | 24.30 | a70 | naaa | 7.60 | N52.30 | 17%nAN"

    @Test("The largest recognised amount is pre-filled")
    func largestIsPreFilled() {
        let receipt = snapshot()
        let model = ReceiptReviewViewModel(receipts: [receipt])

        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipt.id)

        #expect(model.entries[0].edit.amount == Decimal(string: "52.30"))
        #expect(model.entries[0].amountText == "52.3")
    }

    @Test("Every recognised amount is offered, largest first")
    func allAmountsOffered() {
        let receipt = snapshot()
        let model = ReceiptReviewViewModel(receipts: [receipt])

        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipt.id)

        let values = model.entries[0].candidates.map(\.value)
        #expect(values == ["52.30", "24.30", "12.90", "7.60", "7.50"].map { Decimal(string: $0) })
    }

    @Test("An amount already on the receipt is never overwritten by a guess")
    func existingAmountWins() {
        let receipt = snapshot(amount: Decimal(string: "9.99"))
        let model = ReceiptReviewViewModel(receipts: [receipt])

        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipt.id)

        #expect(model.entries[0].edit.amount == Decimal(string: "9.99"))
        // The suggestions still appear -- the guess is refused, not hidden.
        #expect(!model.entries[0].candidates.isEmpty)
    }

    /// Recognition finishes while the sheet is open, so this races real typing.
    @Test("A typed amount is never overwritten by a guess that lands later")
    func typedAmountWins() {
        let receipt = snapshot()
        let model = ReceiptReviewViewModel(receipts: [receipt])

        model.updateAmountText("40", at: 0)
        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipt.id)

        #expect(model.entries[0].edit.amount == Decimal(40))
        #expect(model.entries[0].amountText == "40")
    }

    @Test("Clearing the field and re-recognising still does not re-fill it")
    func clearedFieldStaysCleared() {
        let receipt = snapshot()
        let model = ReceiptReviewViewModel(receipts: [receipt])

        model.updateAmountText("", at: 0)
        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipt.id)

        #expect(model.entries[0].edit.amount == nil)
        #expect(model.entries[0].amountText.isEmpty)
    }

    @Test("Tapping a suggestion fills the field")
    func choosingASuggestion() {
        let receipt = snapshot()
        let model = ReceiptReviewViewModel(receipts: [receipt])
        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipt.id)

        model.chooseAmount(Decimal(string: "24.30")!, at: 0)

        #expect(model.entries[0].edit.amount == Decimal(string: "24.30"))
        #expect(model.entries[0].amountText == "24.3")
    }

    @Test("Text with no amounts in it changes nothing")
    func nothingFound() {
        let receipt = snapshot()
        let model = ReceiptReviewViewModel(receipts: [receipt])

        model.applyRecognizedText("n7H naaa a70", forReceiptWithID: receipt.id)

        #expect(model.entries[0].edit.amount == nil)
        #expect(model.entries[0].amountText.isEmpty)
        #expect(model.entries[0].candidates.isEmpty)
    }

    @Test("Recognised text lands on its own receipt only")
    func routedByIdentifier() {
        let first = snapshot()
        let second = snapshot()
        let model = ReceiptReviewViewModel(receipts: [first, second])

        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: second.id)

        #expect(model.entries[0].edit.amount == nil)
        #expect(model.entries[1].edit.amount == Decimal(string: "52.30"))
    }

    @Test("A receipt imported with text already attached is suggested immediately")
    func textFromImportIsParsedUpFront() {
        var receipt = snapshot()
        receipt = ReceiptSnapshot(
            id: receipt.id,
            capturedAt: receipt.capturedAt,
            createdAt: receipt.createdAt,
            modifiedAt: receipt.modifiedAt,
            relativePath: receipt.relativePath,
            merchant: nil,
            amount: nil,
            currencyCode: nil,
            note: nil,
            ocrText: Self.recognizedReceipt,
            categoryID: nil,
            needsReview: true
        )

        let model = ReceiptReviewViewModel(receipts: [receipt])

        #expect(model.entries[0].candidates.count == 5)
    }
}

