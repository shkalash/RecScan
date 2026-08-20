import Foundation

/// Failures raised by the receipt persistence layer.
enum ReceiptStoreError: Error, Equatable {
    /// No `Receipt` row exists with the given identifier.
    case receiptNotFound(id: UUID)
    /// A scan session produced no usable pages.
    case emptyImportRequest
}
