import Foundation
import SwiftData

/// A user-defined grouping for receipts.
///
/// Responsibilities:
/// - Hold a category's identity and name.
///
/// ## Why receipts point at this by id rather than by relationship
/// `Receipt.categoryID` is a plain `UUID?`, not a SwiftData relationship. Predicates stay
/// flat that way — the library's filter has already hit the type checker's limit once, and
/// relationship traversal inside `#Predicate` is exactly the kind of thing that pushes it
/// over. It also sidesteps CloudKit's rules about relationships and inverses.
///
/// The cost is that deleting a category has to clear the id from its receipts explicitly,
/// which `ReceiptStore` does in one method — the same rule as deleting a receipt's row and
/// its file together.
@Model
final class ReceiptCategory {

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

extension ReceiptCategory {
    /// Case- and whitespace-insensitive key used to spot duplicates.
    ///
    /// Typing "fuel" when "Fuel" exists should pick the existing one rather than quietly
    /// creating a second category that looks identical in the list.
    static func matchingKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
