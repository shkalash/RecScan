import Foundation
import Testing
@testable import RecScan

/// The rule that decides whether a saved receipt is finished.
///
/// It lives on `ReceiptEdit` because two places need the same answer — the store, when
/// writing the review flag, and the detail view, when deciding whether to keep offering
/// date suggestions. These pin it so the two cannot drift apart.
@Suite("Receipt edits")
struct ReceiptEditTests {

    private func edit(amount: Decimal?) -> ReceiptEdit {
        ReceiptEdit(
            capturedAt: .now, merchant: "Corner Store", amount: amount,
            currencyCode: "ILS", note: nil, categoryID: nil
        )
    }

    @Test("An edit with no amount leaves the receipt wanting review")
    func noAmountLeavesItUnreviewed() {
        #expect(edit(amount: nil).leavesReceiptUnreviewed)
    }

    @Test("An edit with an amount finishes the receipt")
    func anAmountFinishesIt() {
        #expect(!edit(amount: Decimal(12)).leavesReceiptUnreviewed)
    }

    /// Zero is a real amount — a fully discounted receipt is still accounted for.
    @Test("A zero amount counts as recorded")
    func zeroIsAnAmount() {
        #expect(!edit(amount: .zero).leavesReceiptUnreviewed)
    }

    @Test("Filling in everything but the amount is not enough")
    func otherFieldsDoNotFinishIt() {
        var filled = edit(amount: nil)
        filled.note = "lunch with the team"
        filled.categoryID = UUID()

        #expect(filled.leavesReceiptUnreviewed)
    }
}
