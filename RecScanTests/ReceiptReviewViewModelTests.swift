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
            groupID: nil,
            pageIndex: 0,
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
}
