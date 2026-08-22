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

    /// Whether the details still want confirming.
    ///
    /// Set when a receipt is created and cleared once its details are confirmed, so
    /// dismissing a review sheet leaves the prompt standing rather than losing it. Rows
    /// already in the library default to `false`, so adding this does not light up a
    /// library that was fine.
    ///
    /// A receipt with no `amount` always carries this flag: an amount is the point of the
    /// library, so one without it has not been accounted for yet. That makes the flag mean
    /// "unfinished" rather than merely "unvisited", and one filter finds everything that
    /// was missed.
    var needsReview: Bool = false

    /// The category this receipt belongs to, or `nil` for uncategorised.
    ///
    /// A plain identifier rather than a relationship — see `ReceiptCategory`.
    var categoryID: UUID?

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
        categoryID: UUID? = nil,
        needsReview: Bool = false,
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
        self.categoryID = categoryID
        self.needsReview = needsReview
        self.searchIndex = searchIndex
    }
}

/// Hashable on the receipt's own identifier.
///
/// `PersistentModel` already refines `Hashable`, so this is not strictly required to
/// satisfy `navigationDestination(for:)` — but that conformance arrives through the
/// `@Model` macro, which means it exists only once the macro has been expanded. Stating
/// it in source keeps the requirement visible without depending on expansion.
///
/// Identity is `id`, the UUID assigned at capture, rather than the object or its
/// `persistentModelID`. That is the identity the app already treats as the receipt's own
/// — it survives export and re-import (see `ArchiveMergePolicy`) — so two instances
/// fetched from different contexts for the same receipt compare equal, which is what a
/// navigation path needs when a view is popped and re-pushed.
extension Receipt: Hashable {

    static func == (lhs: Receipt, rhs: Receipt) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
