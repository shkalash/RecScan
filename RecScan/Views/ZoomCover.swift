import SwiftUI
import UIKit

/// Full-screen reader for one receipt image.
///
/// Responsibilities:
/// - Load an image by relative path and present it zoomable, with a way out.
///
/// ## Where this may be attached
/// **Never inside a `Form`, `List` or any other lazy container.** Rows there are created
/// and destroyed as they scroll, and a presentation owned by a row goes down with it —
/// in a sheet that took the whole sheet with it, losing everything the user had typed.
/// Attach it to the screen's root instead, driven by state that outlives any single row.
struct ZoomCover: View {

    /// The receipt open in the reader.
    ///
    /// A wrapper rather than a bare `String` because `fullScreenCover(item:)` needs
    /// `Identifiable`, and conforming `String` to it retroactively would apply to every
    /// string in the app.
    struct Target: Identifiable, Hashable {
        /// The image's path relative to the Documents directory.
        let id: String
        var relativePath: String { id }
    }

    let relativePath: String

    @Environment(\.imageFileStore) private var imageFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
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
                    Button("common.done") { dismiss() }
                }
            }
        }
        // Loaded here rather than handed in, so the presenting screen does not have to
        // keep a full-resolution image alive just in case this is opened.
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
#Preview("Zoom") {
    ZoomCover(relativePath: PreviewFixture.receipt.relativePath)
        .previewLibrary()
}
#endif
