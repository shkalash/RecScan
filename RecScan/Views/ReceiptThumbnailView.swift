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

    @Environment(\.imageFileStore) private var imageFileStore
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailContent
                .frame(maxWidth: .infinity)
                .aspectRatio(LayoutMetrics.Grid.itemAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.Grid.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutMetrics.Grid.cornerRadius)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: LayoutMetrics.Grid.selectionBorderWidth
                        )
                }

            if isSelectionActive {
                Image(systemName: isSelected ? SystemImage.selectionOn : SystemImage.selectionOff)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(LayoutMetrics.Grid.selectionBadgePadding)
            }
        }
        .task(id: receipt.id) { await loadThumbnail() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
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
        guard let merchant = receipt.merchant, !merchant.isEmpty else {
            return Text("library.item.accessibility.dateOnly \(date)")
        }
        return Text("library.item.accessibility.merchant \(merchant) \(date)")
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
