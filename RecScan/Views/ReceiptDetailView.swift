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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.save") { Task { await save() } }
                    .disabled(!hasUnsavedChanges)
            }
        }
        .task { await loadImage() }
        .task { await loadAmountCandidates() }
        .fullScreenCover(isPresented: $isZooming) { zoomCover }
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

    private var zoomCover: some View {
        NavigationStack {
            Group {
                if let image {
                    ZoomableImageView(image: image)
                } else {
                    ProgressView()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { isZooming = false }
                }
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

    private func save() async {
        do {
            try await receiptStore.apply(edit, toReceiptWithID: receipt.id)
            committedEdit = edit
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
