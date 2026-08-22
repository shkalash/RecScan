import SwiftUI
import UIKit

/// One receipt cell in the library grid.
///
/// Responsibilities:
/// - Load and display the receipt's thumbnail.
/// - Show the selection state when the library is in selection mode.
///
/// Thumbnail loading runs in a `task` keyed on the receipt identifier so that cell
/// reuse during fast scrolling cancels the previous load instead of racing it.
struct ReceiptThumbnailView: View {

    let receipt: Receipt
    let isSelectionActive: Bool
    let isSelected: Bool
    /// Exact tile edge, computed by the grid. Passed in rather than derived so the cell
    /// never depends on an unspecified height proposal.
    let side: CGFloat

    @Environment(\.imageFileStore) private var imageFileStore
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The thumbnail is already square and top-cropped (see
            // `ImageCodec.squareThumbnail`), so the tile needs no aspect-ratio logic at
            // all: `resizable()` plus an exact frame scales it to the tile and nothing
            // has to be inferred. Every aspect-ratio-based version of this collapsed,
            // because a LazyVGrid proposes an unspecified height and the modifier has
            // nothing to resolve a square against.
            thumbnailContent
                .frame(width: side, height: side)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.Grid.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutMetrics.Grid.cornerRadius)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: LayoutMetrics.Grid.selectionBorderWidth
                        )
                }

            // Review badge leading, selection trailing: both can be visible at once, and
            // overlapping them would hide whichever drew first.
            if receipt.needsReview {
                Image(systemName: SystemImage.needsReview)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.orange)
                    .padding(LayoutMetrics.Grid.selectionBadgePadding)
                    .accessibilityHidden(true)
            }

            if isSelectionActive {
                Image(systemName: isSelected ? SystemImage.selectionOn : SystemImage.selectionOff)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(LayoutMetrics.Grid.selectionBadgePadding)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            detailPill
                .frame(width: side, height: side, alignment: .bottom)
                .allowsHitTesting(false)
        }
        .task(id: receipt.id) { await loadThumbnail() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // The amount rides as the element's value rather than being folded into the
        // label: the label already varies by merchant and review state, and adding
        // another axis would double a string table for no gain in what is spoken.
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Date and amount along the bottom of the tile.
    ///
    /// The library is already sectioned by month, so a numeric day-and-month date plus
    /// the amount turns the grid into something you can read a month's spending off
    /// without opening anything.
    ///
    /// Stacked rather than side by side: one line made the pill wide enough to run the
    /// width of the tile, which crowded the image it sits on. Two short lines keep it
    /// small enough to read past.
    ///
    /// A receipt with no amount shows a dash rather than dropping the pill: a missing
    /// amount is the thing worth spotting, and an absent pill looks the same as a tile
    /// you have not looked at yet.
    private var detailPill: some View {
        VStack(spacing: LayoutMetrics.Grid.Pill.spacing) {
            Text(ReceiptFormatting.tileDate(for: receipt.capturedAt))
                .foregroundStyle(.secondary)
            amountText
        }
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(LayoutMetrics.Grid.Pill.minimumScale)
        .padding(.horizontal, LayoutMetrics.Grid.Pill.horizontalInset)
        .padding(.vertical, LayoutMetrics.Grid.Pill.verticalInset)
        // A rounded rectangle, not a capsule: two lines through a capsule leaves ends so
        // round they read as a lozenge rather than a label.
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: LayoutMetrics.Grid.Pill.cornerRadius)
        )
        .padding(LayoutMetrics.Grid.Pill.padding)
    }

    @ViewBuilder
    private var amountText: some View {
        if let amount = ReceiptFormatting.amount(
            receipt.amount,
            currencyCode: receipt.currencyCode,
            defaultCode: AppSettings.defaultCurrencyCode()
        ) {
            Text(amount)
        } else {
            Text(verbatim: Self.missingAmountMark)
                .foregroundStyle(.secondary)
        }
    }

    /// An en dash, not a localised string: it is a typographic mark for "nothing here",
    /// and it reads the same in every language.
    private static let missingAmountMark = "–"

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: SystemImage.missingImage)
                        .font(.system(size: LayoutMetrics.Placeholder.iconSize))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var accessibilityLabel: Text {
        let date = ReceiptFormatting.receiptDate(for: receipt.capturedAt)
        if receipt.needsReview {
            guard let merchant = receipt.merchant, !merchant.isEmpty else {
                return Text("library.item.accessibility.needsReview.dateOnly \(date)")
            }
            return Text("library.item.accessibility.needsReview.merchant \(merchant) \(date)")
        }
        guard let merchant = receipt.merchant, !merchant.isEmpty else {
            return Text("library.item.accessibility.dateOnly \(date)")
        }
        return Text("library.item.accessibility.merchant \(merchant) \(date)")
    }

    private var accessibilityValue: Text {
        guard let amount = ReceiptFormatting.amount(
            receipt.amount,
            currencyCode: receipt.currencyCode,
            defaultCode: AppSettings.defaultCurrencyCode()
        ) else {
            return Text("library.item.accessibility.noAmount")
        }
        return Text(amount)
    }

    private func loadThumbnail() async {
        let relativePath = receipt.relativePath
        let id = receipt.id
        let store = imageFileStore

        // Decoding happens off the main actor; only the finished image comes back.
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            try? store.thumbnail(atRelativePath: relativePath, id: id)
        }.value

        guard !Task.isCancelled else { return }
        thumbnail = image
    }
}

#if DEBUG
#Preview("Tile") {
    ReceiptThumbnailView(
        receipt: PreviewFixture.receipt,
        isSelectionActive: false,
        isSelected: false,
        side: 96
    )
    .previewLibrary()
    .padding()
}

#Preview("Tile — needs review") {
    ReceiptThumbnailView(
        receipt: PreviewFixture.makeReceipt(index: 1, needsReview: true),
        isSelectionActive: false,
        isSelected: false,
        side: 96
    )
    .previewLibrary()
    .padding()
}

#Preview("Tile — no amount") {
    // The state the pill exists to make visible: an em dash where a figure should be.
    ReceiptThumbnailView(
        receipt: PreviewFixture.makeReceipt(index: 3, amount: nil, needsReview: true),
        isSelectionActive: false,
        isSelected: false,
        side: 96
    )
    .previewLibrary()
    .padding()
}

#Preview("Tile — smallest size") {
    // The narrowest tile the adaptive grid will produce, where the pill has least room.
    ReceiptThumbnailView(
        receipt: PreviewFixture.makeReceipt(index: 5, amount: Decimal(string: "1234.56")),
        isSelectionActive: false,
        isSelected: false,
        side: LayoutMetrics.Grid.minimumItemWidth
    )
    .previewLibrary()
    .padding()
}

#Preview("Tile — selected and unreviewed") {
    ReceiptThumbnailView(
        receipt: PreviewFixture.makeReceipt(index: 2, needsReview: true),
        isSelectionActive: true,
        isSelected: true,
        side: 96
    )
    .previewLibrary()
    .padding()
}
#endif
