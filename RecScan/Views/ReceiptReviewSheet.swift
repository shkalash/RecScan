import SwiftUI
import UIKit

/// Fills in details for newly added receipts, straight after capture or import.
///
/// Responsibilities:
/// - Edit every receipt in a batch without leaving the sheet.
/// - Offer a shared date and category so a batch is not retyped item by item.
///
/// ## Why one scrolling sheet rather than a wizard
/// A paged "1 of 8" flow forces every receipt to be visited in order and hides how much
/// is left. A single form degrades cleanly: one receipt looks like an ordinary form, and a
/// batch is a list you can skim, fix the two odd ones in, and finish.
///
/// Dismissing without saving loses nothing — the receipts are already stored, and their
/// review flag stays set so the library keeps showing which ones still want attention.
struct ReceiptReviewSheet: View {

    let receipts: [ReceiptSnapshot]
    /// Text recognised so far, keyed by receipt id. Grows while the sheet is open.
    let recognizedText: [UUID: String]

    @State private var model: ReceiptReviewViewModel
    @Environment(\.receiptStore) private var receiptStore
    @Environment(\.imageFileStore) private var imageFileStore
    @Environment(\.dismiss) private var dismiss

    init(receipts: [ReceiptSnapshot], recognizedText: [UUID: String] = [:]) {
        self.receipts = receipts
        self.recognizedText = recognizedText
        _model = State(initialValue: ReceiptReviewViewModel(receipts: receipts))
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.isBatch { applyToAllSection }

                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    section(for: entry, at: index)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Dismiss first, then write: the sheet should not hang on a disk
                    // round trip, and the receipts keep their review flag either way.
                    Button("review.action.later") {
                        let store = receiptStore
                        dismiss()
                        Task { await model.park(using: store) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") { Task { await save() } }
                        .disabled(model.isSaving)
                }
            }
            .errorAlert($model.presentedError)
            // Attached to the stack, never to a row inside the Form. See `ZoomCover`.
            .fullScreenCover(item: $model.zoomedImage) { target in
                ZoomCover(relativePath: target.relativePath)
            }
            // Recognition runs one receipt at a time behind this sheet, so suggestions
            // arrive in instalments rather than all at once.
            .onChange(of: recognizedText, initial: true) { _, texts in
                for (id, text) in texts {
                    model.applyRecognizedText(text, forReceiptWithID: id)
                }
            }
        }
    }

    private var title: Text {
        model.isBatch
            ? Text("review.title.batch \(model.entries.count)")
            : Text("review.title.single")
    }

    // MARK: - Apply to all

    private var applyToAllSection: some View {
        Section {
            DatePicker("review.shared.date", selection: $model.sharedDate, displayedComponents: .date)
            Button("review.shared.applyDate") { model.applySharedDate() }

            CategoryPicker(selection: $model.sharedCategoryID)
            Button("review.shared.applyCategory") { model.applySharedCategory() }
        } header: {
            Text("review.shared.title")
        } footer: {
            Text("review.shared.footer")
        }
    }

    // MARK: - Per receipt

    private func section(for entry: ReceiptReviewViewModel.Entry, at index: Int) -> some View {
        Section {
            ReceiptReviewThumbnail(relativePath: entry.relativePath) {
                model.zoomedImage = ZoomCover.Target(id: entry.relativePath)
            }

            DatePicker(
                "detail.field.date",
                selection: bindingForDate(at: index),
                displayedComponents: .date
            )
            DateSuggestionRow(
                candidates: entry.dateCandidates,
                onSelect: { model.chooseDate($0, at: index) }
            )
            TextField("detail.field.merchant", text: bindingForMerchant(at: index))
                .textInputAutocapitalization(.words)
            TextField("detail.field.amount", text: bindingForAmount(at: index))
                .keyboardType(.decimalPad)
            AmountSuggestionRow(
                candidates: entry.candidates,
                currencyCode: entry.edit.currencyCode,
                onSelect: { model.chooseAmount($0, at: index) }
            )
            CategoryPicker(selection: bindingForCategory(at: index))
        } header: {
            Text(model.isBatch ? "review.section.receipt \(index + 1)" : "detail.section.details")
        }
    }

    // MARK: - Bindings

    private func bindingForDate(at index: Int) -> Binding<Date> {
        Binding(
            get: { model.entries[index].edit.capturedAt },
            set: { model.setDate($0, at: index) }
        )
    }

    private func bindingForMerchant(at index: Int) -> Binding<String> {
        Binding(
            get: { model.entries[index].edit.merchant ?? "" },
            set: { model.setMerchant($0, at: index) }
        )
    }

    private func bindingForAmount(at index: Int) -> Binding<String> {
        Binding(
            get: { model.entries[index].amountText },
            set: { model.updateAmountText($0, at: index) }
        )
    }

    private func bindingForCategory(at index: Int) -> Binding<UUID?> {
        Binding(
            get: { model.entries[index].edit.categoryID },
            set: { model.setCategory($0, at: index) }
        )
    }

    // MARK: - Actions

    private func save() async {
        if await model.save(using: receiptStore) { dismiss() }
    }
}

/// The receipt being reviewed, at a glance.
///
/// Small on purpose: this is a form, and a full-height image would push every field the
/// sheet exists to fill below the fold. Filling in an amount means reading it off the
/// receipt first, so tapping hands off to the full-screen reader.
///
/// The reader itself is **not** presented from here. This view is a row in a `Form`, and a
/// presentation owned by a row is torn down when the row is — which took the enclosing
/// sheet with it and lost every edit in the batch. The row only reports the tap; the sheet
/// owns the presentation.
private struct ReceiptReviewThumbnail: View {

    let relativePath: String
    let onTap: () -> Void

    @Environment(\.imageFileStore) private var imageFileStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Button(action: onTap) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: LayoutMetrics.Review.thumbnailHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.Grid.cornerRadius))
                        .overlay(alignment: .bottomTrailing) {
                            // Nothing else in a form is tappable-to-enlarge, so the
                            // affordance has to be visible rather than discovered.
                            Image(systemName: SystemImage.zoom)
                                .font(.caption)
                                .padding(LayoutMetrics.Review.zoomBadgePadding)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(LayoutMetrics.Review.zoomBadgePadding)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("review.image.accessibility.zoom")
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: relativePath) {
            let store = imageFileStore
            let path = relativePath
            image = await Task.detached(priority: .userInitiated) {
                try? store.fullResolutionImage(atRelativePath: path)
            }.value
        }
    }
}

#if DEBUG
#Preview("Review — one receipt") {
    ReceiptReviewSheet(receipts: PreviewFixture.snapshots(count: 1))
        .previewLibrary()
}

#Preview("Review — batch") {
    ReceiptReviewSheet(receipts: PreviewFixture.snapshots(count: 4))
        .previewLibrary()
}
#endif
