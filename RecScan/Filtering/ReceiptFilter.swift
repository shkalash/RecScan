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
    /// Categories to include. Empty means every category, which is also what the
    /// "All Categories" row selects — clearing rather than being a value of its own.
    var categoryIDs: Set<UUID>

    init(
        preset: DateRangePreset = .allTime,
        customStart: Date = Date(),
        customEnd: Date = Date(),
        searchText: String = "",
        categoryIDs: Set<UUID> = []
    ) {
        self.preset = preset
        self.customStart = customStart
        self.customEnd = customEnd
        self.searchText = searchText
        self.categoryIDs = categoryIDs
    }

    /// Whether the filter narrows the library at all. Drives the toolbar badge.
    var isActive: Bool {
        preset != .allTime || !trimmedSearchText.isEmpty || !categoryIDs.isEmpty
    }

    /// Whether `id` is included. An empty selection includes everything.
    func includes(categoryID id: UUID) -> Bool {
        categoryIDs.isEmpty || categoryIDs.contains(id)
    }

    /// Adds or removes `id`, leaving an empty set when the last one is removed — which
    /// reads as "all" rather than "none", the only sensible meaning for an empty filter.
    mutating func toggleCategory(_ id: UUID) {
        if categoryIDs.contains(id) {
            categoryIDs.remove(id)
        } else {
            categoryIDs.insert(id)
        }
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
