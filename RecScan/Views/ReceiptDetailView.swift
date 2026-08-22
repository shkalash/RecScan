import SwiftUI
import UIKit

/// Full view of one receipt: image, editable metadata, delete.
///
/// Responsibilities:
/// - Show the full-resolution scan and let the user zoom it.
/// - Edit the receipt's date, merchant, amount, currency and note.
/// - Delete the receipt (row and file) and return to the library.
///
/// Edits are held in a local `ReceiptEdit` and committed explicitly. Binding the form
/// straight to the `@Model` would write a half-typed amount into the database on every
/// keystroke, and every one of those writes would ripple through the library's query.
struct ReceiptDetailView: View {

    let receipt: Receipt

    @Environment(\.receiptStore) private var receiptStore
    @Environment(\.imageFileStore) private var imageFileStore
    @Environment(\.dismiss) private var dismiss

    @State private var edit: ReceiptEdit
    @State private var committedEdit: ReceiptEdit
    @State private var amountText: String
    @State private var image: UIImage?
    @State private var isZooming = false
    @State private var isConfirmingDeletion = false
    @State private var presentedError: PresentableError?
    @State private var candidates: [AmountCandidate] = []
    @State private var dateCandidates: [DateCandidate] = []
    @State private var isConfirmingExit = false
    @State private var isOfferingAutoSave = false

    @AppStorage(AppSettings.Key.autoSaveOnDismiss)
    private var autoSaveOnDismiss = AppSettings.autoSaveOnDismissDefault
    @AppStorage(AppSettings.Key.hasOfferedAutoSave) private var hasOfferedAutoSave = false

    init(receipt: Receipt) {
        self.receipt = receipt
        let edit = ReceiptEdit(receipt)
        _edit = State(initialValue: edit)
        _committedEdit = State(initialValue: edit)
        _amountText = State(initialValue: DecimalParsing.editableText(from: edit.amount))
    }

    var body: some View {
        Form {
            imageSection
            detailsSection
            noteSection
            deleteSection
        }
        .navigationTitle("detail.title")
        .navigationBarTitleDisplayMode(.inline)
        // The system back button pops immediately and cannot be intercepted, so leaving
        // has to go through a button of ours. Hiding it also disables the interactive
        // swipe-back, which would otherwise be a second unguarded way out.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    attemptToLeave()
                } label: {
                    Label("common.back", systemImage: SystemImage.back)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.save") { Task { await save() } }
                    .disabled(!hasUnsavedChanges)
            }
        }
        .task { await loadImage() }
        .task { await loadAmountCandidates() }
        .task { refreshDateSuggestions(unreviewed: receipt.needsReview) }
        .fullScreenCover(isPresented: $isZooming) { ZoomCover(relativePath: receipt.relativePath) }
        .confirmationDialog(
            "detail.delete.confirm.title",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("detail.delete.confirm.action", role: .destructive) {
                Task { await delete() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("detail.delete.confirm.message")
        }
        .alert("detail.unsaved.title", isPresented: $isConfirmingExit) {
            Button("common.save") {
                Task {
                    await save()
                    // Only leave if the write actually landed; otherwise the alert has
                    // closed over an error the user never sees and the edit is lost.
                    if presentedError == nil { finishLeaving() }
                }
            }
            Button("detail.unsaved.discard", role: .destructive) { finishLeaving() }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("detail.unsaved.message")
        }
        .alert("detail.autoSave.offer.title", isPresented: $isOfferingAutoSave) {
            Button("detail.autoSave.offer.enable") {
                autoSaveOnDismiss = true
                dismiss()
            }
            Button("detail.autoSave.offer.decline", role: .cancel) { dismiss() }
        } message: {
            Text("detail.autoSave.offer.message")
        }
        .errorAlert($presentedError)
    }

    // MARK: - Sections

    @ViewBuilder
    private var imageSection: some View {
        Section {
            if let image {
                Button {
                    isZooming = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.Detail.imageCornerRadius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("detail.image.accessibility")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var detailsSection: some View {
        Section("detail.section.details") {
            DatePicker("detail.field.date", selection: $edit.capturedAt, displayedComponents: .date)

            // Offered here too, not only at import: PDFs added before dates were read
            // off them are all sitting on the day they were imported, and this is the
            // only way to fix that batch without retyping each one.
            DateSuggestionRow(
                candidates: dateCandidates,
                onSelect: { edit.capturedAt = $0 }
            )

            TextField("detail.field.merchant", text: merchantBinding)
                .textInputAutocapitalization(.words)

            TextField("detail.field.amount", text: $amountText)
                .keyboardType(.decimalPad)
                .onChange(of: amountText) { _, text in
                    edit.amount = DecimalParsing.decimal(from: text)
                }

            AmountSuggestionRow(
                candidates: candidates,
                currencyCode: edit.currencyCode,
                onSelect: { value in
                    amountText = DecimalParsing.editableText(from: value)
                    edit.amount = value
                }
            )

            NavigationLink {
                CurrencyPickerView(selection: currencyBinding)
            } label: {
                LabeledContent("detail.field.currency") {
                    Text(currencyBinding.wrappedValue).monospaced()
                }
            }

            CategoryPicker(selection: $edit.categoryID)
        }
    }

    private var noteSection: some View {
        Section("detail.section.note") {
            TextEditor(text: noteBinding)
                .frame(minHeight: LayoutMetrics.Form.noteEditorMinimumHeight)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("detail.action.delete", role: .destructive) {
                isConfirmingDeletion = true
            }
        }
    }

    // MARK: - Bindings

    /// Optional strings are surfaced as non-optional text fields; empty text is
    /// normalised back to `nil` by the store so "" and nil never both mean "unset".
    private var merchantBinding: Binding<String> {
        Binding(get: { edit.merchant ?? "" }, set: { edit.merchant = $0 })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { edit.note ?? "" }, set: { edit.note = $0 })
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { edit.currencyCode ?? Self.defaultCurrencyCode },
            set: { edit.currencyCode = $0 }
        )
    }

    // MARK: - Derived state

    private var hasUnsavedChanges: Bool { edit != committedEdit }

    // MARK: - Leaving

    /// Decides what leaving the screen means for the edits in hand.
    private func attemptToLeave() {
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        guard !autoSaveOnDismiss else {
            Task {
                await save()
                if presentedError == nil { dismiss() }
            }
            return
        }
        isConfirmingExit = true
    }

    /// Runs once the save-or-discard question has been answered.
    ///
    /// The offer to turn auto-save on is made here rather than in Settings because this
    /// is the moment it means something — someone has just been asked a question they
    /// may not want asked again. It is shown once, ever: an offer that reappears every
    /// time is a nag, and the setting is in Settings for anyone who changes their mind.
    private func finishLeaving() {
        guard !autoSaveOnDismiss, !hasOfferedAutoSave else {
            dismiss()
            return
        }
        hasOfferedAutoSave = true
        isOfferingAutoSave = true
    }

    // MARK: - Actions

    /// Offers recognised amounts for a receipt whose amount is still blank.
    ///
    /// Unlike the review sheet, nothing is pre-filled here: this receipt has been seen
    /// before and left empty, so a number appearing on its own would look like a saved
    /// value rather than a guess. Every amount is a chip, and the field stays untouched
    /// until one is tapped.
    ///
    /// Recognition is only run when the receipt has never been through it -- normally the
    /// text is already there from import. This is deliberately not on the library's serial
    /// queue: one on-demand request should not wait behind a fifty-photo backlog, and two
    /// concurrent Vision requests is nowhere near the contention the queue guards against.
    private func loadAmountCandidates() async {
        guard edit.amount == nil else { return }

        if let existing = receipt.ocrText, !existing.isEmpty {
            candidates = ReceiptAmountParser.candidates(in: existing)
            return
        }

        let relativePath = receipt.relativePath
        let fileStore = imageFileStore
        let recognized = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let image = try? fileStore.fullResolutionImage(atRelativePath: relativePath)
            else { return nil }
            return try? ReceiptTextRecognizer().recognizeText(in: image)
        }.value

        guard !Task.isCancelled, let recognized, !recognized.isEmpty else { return }
        try? await receiptStore.attachRecognizedText(recognized, toReceiptWithID: receipt.id)
        candidates = ReceiptAmountParser.candidates(in: recognized)
    }

    private func loadImage() async {
        let relativePath = receipt.relativePath
        let store = imageFileStore

        // Full-resolution decode is expensive; it must not block the push animation.
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            try? store.fullResolutionImage(atRelativePath: relativePath)
        }.value

        guard !Task.isCancelled else { return }
        image = loaded
    }

    /// Dates printed on the receipt, offered only while it still wants review.
    ///
    /// A confirmed receipt has a date its owner accepted, and an ambiguous reading is a
    /// question about that — "did you mean 6 May?" is worth asking once and then never
    /// again. Amount suggestions need no such gate: they already only appear when the
    /// amount is empty, and an empty amount is itself what keeps a receipt unreviewed.
    private func refreshDateSuggestions(unreviewed: Bool) {
        dateCandidates = unreviewed ? ReceiptDateParser.candidates(in: receipt.ocrText) : []
    }

    private func save() async {
        do {
            try await receiptStore.apply(edit, toReceiptWithID: receipt.id)
            committedEdit = edit
            // Derived from the edit rather than re-read from the receipt: the store
            // writes on its own actor, so the model here has not necessarily caught up.
            refreshDateSuggestions(unreviewed: edit.leavesReceiptUnreviewed)
        } catch {
            presentedError = PresentableError(titleKey: "error.save.title", error: error)
        }
    }

    /// Leaves the screen first, then deletes.
    ///
    /// The other order is a latent crash: once the row is deleted, this view is still
    /// on screen holding the `Receipt`, and the next body evaluation reads properties
    /// off a model the context has already torn down. Dismissing first means nothing
    /// re-reads it. The error alert is intentionally sacrificed — by the time a delete
    /// fails there is no longer a screen to show it on, and the receipt simply stays
    /// in the library, which is the correct outcome anyway.
    private func delete() async {
        dismiss()
        do {
            try await receiptStore.delete(receiptsWithIDs: [receipt.id])
        } catch {
            LogCategory.persistence.logger.error("Failed to delete receipt: \(error)")
        }
    }

    // MARK: - Constants

    private static var defaultCurrencyCode: String {
        AppSettings.defaultCurrencyCode()
    }
}

#if DEBUG
#Preview("Detail — categorised") {
    NavigationStack {
        ReceiptDetailView(receipt: PreviewFixture.receipt)
    }
    .previewLibrary()
}

#Preview("Detail — uncategorised") {
    NavigationStack {
        ReceiptDetailView(receipt: PreviewFixture.makeReceipt(index: 4, amount: nil))
    }
    .previewLibrary()
}
#endif
