import Foundation

/// One month's worth of items in the library grid.
///
/// Responsibilities:
/// - Pair a month boundary with the items that fall inside it.
struct MonthSection<Item>: Identifiable {
    /// Start of the month, which is both the sort key and a stable identity.
    let id: Date
    let items: [Item]
}
