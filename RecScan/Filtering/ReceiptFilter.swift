import Foundation

/// The complete state of the library filter.
///
/// Responsibilities:
/// - Carry the user's date-range and text-search choices.
/// - Resolve itself into the concrete bounds a predicate can capture.
struct ReceiptFilter: Hashable, Sendable {

    var preset: DateRangePreset
    var customStart: Date
    var customEnd: Date
    var searchText: String
    /// `nil` means every category, including uncategorised receipts.
    var categoryID: UUID?

    init(
        preset: DateRangePreset = .allTime,
        customStart: Date = Date(),
        customEnd: Date = Date(),
        searchText: String = "",
        categoryID: UUID? = nil
    ) {
        self.preset = preset
        self.customStart = customStart
        self.customEnd = customEnd
        self.searchText = searchText
        self.categoryID = categoryID
    }

    /// Whether the filter narrows the library at all. Drives the toolbar badge.
    var isActive: Bool {
        preset != .allTime || !trimmedSearchText.isEmpty || categoryID != nil
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The half-open date interval to match, or `nil` for "no date bound".
    ///
    /// The custom range is widened to whole days so that picking the same day for
    /// start and end matches that day rather than an empty instant.
    func resolvedInterval(reference: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        guard preset.usesCustomBounds else {
            return preset.dateInterval(reference: reference, calendar: calendar)
        }

        let start = calendar.startOfDay(for: min(customStart, customEnd))
        let lastDay = calendar.startOfDay(for: max(customStart, customEnd))
        guard let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        return DateInterval(start: start, end: end)
    }
}
