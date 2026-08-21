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

    @State private var model: ReceiptReviewViewModel
    @Environment(\.receiptStore) private var receiptStore
    @Environment(\.imageFileStore) private var imageFileStore
    @Environment(\.dismiss) private var dismiss

    init(receipts: [ReceiptSnapshot]) {
        self.receipts = receipts
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
                    Button("review.action.later") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") { Task { await save() } }
                        .disabled(model.isSaving)
                }
            }
            .errorAlert($model.presentedError)
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
            ReceiptReviewThumbnail(relativePath: entry.relativePath)

            DatePicker(
                "detail.field.date",
                selection: bindingForDate(at: index),
                displayedComponents: .date
            )
            TextField("detail.field.merchant", text: bindingForMerchant(at: index))
                .textInputAutocapitalization(.words)
            TextField("detail.field.amount", text: bindingForAmount(at: index))
                .keyboardType(.decimalPad)
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
/// sheet exists to fill below the fold.
private struct ReceiptReviewThumbnail: View {

    let relativePath: String

    @Environment(\.imageFileStore) private var imageFileStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: LayoutMetrics.Review.thumbnailHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.Grid.cornerRadius))
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
