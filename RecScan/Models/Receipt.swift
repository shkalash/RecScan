import Foundation
import SwiftData

/// A single captured receipt page.
///
/// Responsibilities:
/// - Hold the persisted metadata for one scanned page.
/// - Point at its backing image file by *relative* path.
///
/// ## Why every property has a default and every optional stays optional
/// CloudKit-backed `ModelConfiguration` rejects models with non-optional properties
/// that have no default value, and rejects unique constraints. Satisfying those rules
/// now means sync can be switched on later by changing the container configuration
/// alone — no schema migration. See the plan's "Optional / CloudKit sync" note.
///
/// ## Why `relativePath` and not a `URL`
/// The app container path changes across reinstall, device restore and some OS
/// updates. A persisted absolute URL silently rots. The path is stored relative to
/// the Documents directory and resolved at read time.
@Model
final class Receipt {

    /// Stable identity. Also names the backing image file.
    var id: UUID = UUID()

    /// When the receipt itself is dated. Editable, because receipts are frequently
    /// photographed days after the purchase and the capture time would be wrong.
    var capturedAt: Date = Date()

    /// When the row was created. Never edited — this is the audit trail.
    var createdAt: Date = Date()

    /// When any user-visible field last changed.
    ///
    /// Maintained by `ReceiptStore` on every write. This is the signal archive import
    /// uses to decide whether an incoming copy is newer than the local one; without it
    /// a merge can only guess, and guessing means either clobbering fresh edits or
    /// silently dropping restored ones.
    var modifiedAt: Date = Date()

    /// Path to the image relative to the Documents directory, e.g. `Receipts/<uuid>.heic`.
    var relativePath: String = ""

    var merchant: String?
    var amount: Decimal?
    var currencyCode: String?
    var note: String?

    /// Recognised text, populated asynchronously after capture. Drives search.
    var ocrText: String?

    /// Shared by every page of a multi-page scan session. `nil` for single-page receipts.
    var groupID: UUID?

    /// Position within a multi-page group. Always `0` for single-page receipts.
    var pageIndex: Int = 0

    /// Denormalised concatenation of `merchant`, `note` and `ocrText`.
    ///
    /// Written only by `ReceiptStore`. See `ReceiptSearchIndex` for why search does not
    /// query the three source columns directly.
    var searchIndex: String = ""

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        relativePath: String = "",
        merchant: String? = nil,
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        note: String? = nil,
        ocrText: String? = nil,
        groupID: UUID? = nil,
        pageIndex: Int = 0,
        searchIndex: String = ""
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.relativePath = relativePath
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.note = note
        self.ocrText = ocrText
        self.groupID = groupID
        self.pageIndex = pageIndex
        self.searchIndex = searchIndex
    }
}
