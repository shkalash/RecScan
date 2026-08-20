import SwiftUI

/// Dependency injection points exposed to the view layer.
///
/// Responsibilities:
/// - Let any view reach the receipt store and the image store without threading them
///   through every initialiser.
///
/// Why defaults exist at all: SwiftUI previews construct views without an app root.
/// The defaults are in-memory so a preview can never write into the real library.
extension EnvironmentValues {

    @Entry var receiptStore: any ReceiptStoring = ReceiptStore(
        modelContainer: ModelContainerFactory.preview
    )

    @Entry var imageFileStore: any ImageFileStoring = ImageFileStore()
}
