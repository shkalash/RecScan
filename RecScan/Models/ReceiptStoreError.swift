import Foundation

/// Failures raised by the receipt persistence layer.
enum ReceiptStoreError: Error, Equatable {
    /// No `Receipt` row exists with the given identifier.
    case receiptNotFound(id: UUID)
    /// A scan session produced no usable pages.
    case emptyImportRequest
    /// No `ReceiptCategory` row exists with the given identifier.
    case categoryNotFound(id: UUID)
    /// A category name was blank once trimmed.
    case emptyCategoryName
}
