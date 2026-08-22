import Foundation
import Observation

/// Edits for a batch of newly added receipts.
///
/// Responsibilities:
/// - Hold one scratch edit per receipt.
/// - Apply a shared date or category across the whole batch.
/// - Commit everything in one pass.
@MainActor
@Observable
final class ReceiptReviewViewModel {

    /// One receipt's in-progress edit.
    ///
    /// The amount travels as text alongside the parsed value: a half-typed "12." is not a
    /// `Decimal` yet, and reformatting the field on every keystroke fights the user.
    struct Entry: Identifiable {
        let id: UUID
        let relativePath: String
        var edit: ReceiptEdit
        var amountText: String
        /// Amounts read off the image, largest first. Empty until recognition lands.
        var candidates: [AmountCandidate] = []
        /// Set once the field has been typed in or a chip tapped, after which an arriving
        /// suggestion must not overwrite it.
        var isAmountUserSet = false
        /// Whether the user has changed anything on this entry.
        ///
        /// Distinct from "the edit differs from the receipt": recognition pre-fills an
        /// amount without anyone touching it, and that must not count as work worth
        /// keeping. Only the user's own actions set this.
        var isUserEdited = false
        /// The amount the receipt arrived with, so a pre-fill can be undone when parking.
        let originalAmount: Decimal?

        /// The edit as it should be stored when leaving without confirming.
        ///
        /// An amount that was only ever suggested is put back to what it was: parking a
        /// batch keeps the user's work, and a guess nobody looked at is not their work.
        /// Writing it would let an unconfirmed number reach a total, an export or the
        /// expense report -- and, worse, make it look saved rather than suggested.
        var parkedEdit: ReceiptEdit {
            guard !isAmountUserSet else { return edit }
            var parked = edit
            parked.amount = originalAmount
            return parked
        }
    }

    private(set) var entries: [Entry]

    /// Values for the apply-to-all controls. Separate from the entries so pressing apply
    /// is an explicit act rather than a side effect of scrolling past a field.
    var sharedDate: Date
    var sharedCategoryID: UUID?

    /// The receipt currently open full-screen, if any.
    ///
    /// Lives here rather than in the thumbnail row because the row is inside a `Form` and
    /// is destroyed as it scrolls. A presentation owned by the row went down with it and
    /// took the whole sheet -- and every unsaved edit -- with it.
    var zoomedImage: ZoomCover.Target?

    private(set) var isSaving = false
    var presentedError: PresentableError?

    init(receipts: [ReceiptSnapshot]) {
        entries = receipts.map { receipt in
            Entry(
                id: receipt.id,
                relativePath: receipt.relativePath,
                edit: ReceiptEdit(
                    capturedAt: receipt.capturedAt,
                    merchant: receipt.merchant,
                    amount: receipt.amount,
                    currencyCode: receipt.currencyCode,
                    note: receipt.note,
                    categoryID: receipt.categoryID
                ),
                amountText: DecimalParsing.editableText(from: receipt.amount),
                candidates: ReceiptAmountParser.candidates(in: receipt.ocrText),
                // An amount that already exists came from the file, not from a guess, and
                // outranks anything recognition finds.
                isAmountUserSet: receipt.amount != nil,
                originalAmount: receipt.amount
            )
        }
        sharedDate = receipts.first?.capturedAt ?? Date()
        sharedCategoryID = receipts.first?.categoryID
    }

    var isBatch: Bool { entries.count > 1 }

    // MARK: - Editing

    func setDate(_ date: Date, at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries[index].edit.capturedAt = date
        entries[index].isUserEdited = true
    }

    func setMerchant(_ merchant: String, at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries[index].edit.merchant = merchant
        entries[index].isUserEdited = true
    }

    func setCategory(_ categoryID: UUID?, at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries[index].edit.categoryID = categoryID
        entries[index].isUserEdited = true
    }

    /// Keeps the parsed amount in step with what has been typed.
    func updateAmountText(_ text: String, at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries[index].amountText = text
        entries[index].edit.amount = DecimalParsing.decimal(from: text)
        entries[index].isAmountUserSet = true
        entries[index].isUserEdited = true
    }

    /// Chooses one of the recognised amounts.
    func chooseAmount(_ value: Decimal, at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries[index].amountText = DecimalParsing.editableText(from: value)
        entries[index].edit.amount = value
        entries[index].isAmountUserSet = true
        entries[index].isUserEdited = true
    }

    // MARK: - Recognised amounts

    /// Takes recognised text for one receipt and pre-fills the largest amount found.
    ///
    /// Only the form is touched. Nothing reaches the database until save, so a wrong guess
    /// can never end up in a total, an export or the expense report.
    ///
    /// Recognition finishes one receipt at a time and arrives while the sheet is already
    /// open and possibly already being typed into, so a suggestion never overwrites a
    /// value the user put there.
    func applyRecognizedText(_ text: String, forReceiptWithID id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let candidates = ReceiptAmountParser.candidates(in: text)
        guard !candidates.isEmpty else { return }

        entries[index].candidates = candidates
        guard !entries[index].isAmountUserSet, entries[index].amountText.isEmpty else { return }

        let best = candidates[0].value
        entries[index].amountText = DecimalParsing.editableText(from: best)
        entries[index].edit.amount = best
    }

    // MARK: - Apply to all

    func applySharedDate() {
        for index in entries.indices {
            entries[index].edit.capturedAt = sharedDate
            entries[index].isUserEdited = true
        }
    }

    func applySharedCategory() {
        for index in entries.indices {
            entries[index].edit.categoryID = sharedCategoryID
            entries[index].isUserEdited = true
        }
    }

    // MARK: - Saving

    /// Commits every entry.
    ///
    /// Each `apply` clears that receipt's review flag, which is what makes finishing this
    /// sheet the act of confirming the batch.
    /// - Returns: `true` when everything saved.
    @discardableResult
    func save(using store: any ReceiptStoring) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        do {
            for entry in entries {
                try await store.apply(entry.edit, toReceiptWithID: entry.id)
            }
            return true
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.saveFailed, error: error)
            return false
        }
    }

    /// Keeps what the user typed without confirming any of it.
    ///
    /// Dismissing with "Later" used to write nothing, so a batch someone had worked
    /// through was lost the moment the sheet closed. Their edits are now stored and the
    /// receipts stay flagged, which is exactly what "later" means: the work is kept, the
    /// question is still open.
    ///
    /// Only entries the user actually touched are written. An untouched entry has nothing
    /// worth saving, and writing it would clear nothing but cost a `modifiedAt` bump --
    /// which would make it beat its own archived copy on the next merge.
    ///
    /// Errors are swallowed. This runs as the sheet is going away, so there is no longer
    /// a screen to show an alert on, and the receipts keep their flag either way.
    func park(using store: any ReceiptStoring) async {
        let parked = entries.filter(\.isUserEdited)
        guard !parked.isEmpty else { return }

        for entry in parked {
            do {
                try await store.apply(entry.parkedEdit, toReceiptWithID: entry.id, confirming: false)
            } catch {
                LogCategory.persistence.logger.error(
                    "Could not keep edits for \(entry.id, privacy: .public): \(error)"
                )
            }
        }
    }

    private enum ErrorTitle {
        static let saveFailed: String.LocalizationValue = "error.save.title"
    }
}
