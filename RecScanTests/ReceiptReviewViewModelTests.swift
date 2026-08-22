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

    // MARK: - Reading a receipt full screen

    /// Opening the reader used to destroy the batch. The thumbnail owned the presentation,
    /// and it lives in a `Form` row -- a lazy container that discards rows as they scroll.
    /// Tearing the row down tore down the sheet, and the sheet owns these edits.
    ///
    /// Keeping the state on the model is what makes that impossible: it outlives any row.
    @Test("Opening and closing the reader leaves every edit intact")
    func zoomingPreservesEdits() {
        let receipts = [snapshot(), snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        model.setMerchant("Corner Store", at: 0)
        model.updateAmountText("18.40", at: 1)

        model.zoomedImage = ZoomCover.Target(id: receipts[0].relativePath)
        model.zoomedImage = nil

        #expect(model.entries.count == 2)
        #expect(model.entries[0].edit.merchant == "Corner Store")
        #expect(model.entries[1].edit.amount == Decimal(string: "18.40"))
    }

    @Test("The reader opens on the receipt that was tapped")
    func zoomTargetsItsOwnReceipt() {
        let receipts = [snapshot(), snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)

        model.zoomedImage = ZoomCover.Target(id: receipts[1].relativePath)

        #expect(model.zoomedImage?.relativePath == receipts[1].relativePath)
    }

    @Test("Nothing is open to begin with")
    func nothingZoomedInitially() {
        #expect(ReceiptReviewViewModel(receipts: [snapshot()]).zoomedImage == nil)
    }


    // MARK: - Parking edits with "Later"

    /// "Later" used to write nothing, so working through a batch and then dismissing it
    /// lost the lot. The work is kept; the question stays open.
    @Test("Later keeps what was typed")
    func parkKeepsEdits() async throws {
        let receipts = [snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()
        model.setMerchant("Corner Store", at: 0)

        await model.park(using: store)

        let edit = try #require(await store.edit(for: receipts[0].id))
        #expect(edit.merchant == "Corner Store")
    }

    @Test("Later does not confirm the receipt")
    func parkLeavesTheFlagStanding() async throws {
        let receipts = [snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()
        model.setMerchant("Corner Store", at: 0)

        await model.park(using: store)

        #expect(await store.applied.first?.confirming == false)
    }

    @Test("An entry nobody touched is not written at all")
    func parkSkipsUntouchedEntries() async throws {
        let receipts = [snapshot(), snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()
        model.setMerchant("Corner Store", at: 1)

        await model.park(using: store)

        #expect(await store.appliedIDs == [receipts[1].id])
    }

    @Test("Dismissing without touching anything writes nothing")
    func parkWithNoEditsIsANoOp() async throws {
        let model = ReceiptReviewViewModel(receipts: [snapshot()])
        let store = RecordingReceiptStore()

        await model.park(using: store)

        #expect(await store.applied.isEmpty)
    }

    /// The important half. Recognition pre-fills an amount nobody has looked at; parking
    /// must not turn that guess into a stored value, or it reaches totals and reports and
    /// stops looking like a suggestion.
    @Test("An untouched OCR guess is not written, even when the entry is dirty")
    func parkDropsUntouchedGuess() async throws {
        let receipts = [snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()

        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipts[0].id)
        // Dirty for an unrelated reason, so the entry is written at all.
        model.setMerchant("Corner Store", at: 0)
        #expect(model.entries[0].edit.amount == Decimal(string: "52.30"))

        await model.park(using: store)

        let edit = try #require(await store.edit(for: receipts[0].id))
        #expect(edit.merchant == "Corner Store")
        #expect(edit.amount == nil)
    }

    @Test("An amount the user chose from the chips is written")
    func parkKeepsChosenAmount() async throws {
        let receipts = [snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()

        model.applyRecognizedText(Self.recognizedReceipt, forReceiptWithID: receipts[0].id)
        model.chooseAmount(Decimal(string: "24.30")!, at: 0)

        await model.park(using: store)

        #expect(await store.edit(for: receipts[0].id)?.amount == Decimal(string: "24.30"))
    }

    @Test("A typed amount is written")
    func parkKeepsTypedAmount() async throws {
        let receipts = [snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()
        model.updateAmountText("18.40", at: 0)

        await model.park(using: store)

        #expect(await store.edit(for: receipts[0].id)?.amount == Decimal(string: "18.40"))
    }

    /// An amount already on the receipt is not a guess, so parking keeps it.
    @Test("An amount that arrived with the receipt survives parking")
    func parkKeepsPreexistingAmount() async throws {
        let receipts = [snapshot(amount: Decimal(string: "9.99"))]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()
        model.setMerchant("Corner Store", at: 0)

        await model.park(using: store)

        #expect(await store.edit(for: receipts[0].id)?.amount == Decimal(string: "9.99"))
    }

    @Test("Apply-to-all counts as the user editing every entry")
    func applyToAllMarksEveryEntry() async throws {
        let receipts = [snapshot(), snapshot()]
        let model = ReceiptReviewViewModel(receipts: receipts)
        let store = RecordingReceiptStore()
        model.sharedCategoryID = UUID()
        model.applySharedCategory()

        await model.park(using: store)

        #expect(await store.appliedIDs.count == 2)
    }

    /// Dropping the guess is only acceptable because it comes back. `ocrText` is stored
    /// by the recognition queue independently of the review sheet, so reopening the
    /// receipt still offers the same chips.
    @Test("The suggestions are still there after the guess is dropped")
    func suggestionsSurviveParking() {
        let candidates = ReceiptAmountParser.candidates(in: Self.recognizedReceipt)

        #expect(candidates.map(\.value.description).first == "52.3")
        #expect(candidates.count == 5)
    }

}
