import Foundation

/// Groups dated items into descending month sections.
///
/// Responsibilities:
/// - Bucket items by the calendar month of a caller-supplied date.
///
/// Why it is generic and free of SwiftData: grouping is pure calendar logic and is
/// worth testing without a `ModelContainer` behind it.
enum MonthGrouper {

    /// - Parameters:
    ///   - items: the items to bucket, in any order.
    ///   - calendar: the calendar defining month boundaries.
    ///   - date: extracts the date each item should be filed under.
    /// - Returns: sections newest month first, items within a section newest first.
    static func group<Item>(
        _ items: [Item],
        calendar: Calendar = .current,
        date: (Item) -> Date
    ) -> [MonthSection<Item>] {
        let buckets = Dictionary(grouping: items) { item in
            calendar.dateInterval(of: .month, for: date(item))?.start
                ?? calendar.startOfDay(for: date(item))
        }

        return buckets
            .map { monthStart, contents in
                MonthSection(id: monthStart, items: contents.sorted { date($0) > date($1) })
            }
            .sorted { $0.id > $1.id }
    }
}
