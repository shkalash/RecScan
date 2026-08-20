import Foundation

/// The canned date ranges offered by the filter sheet.
///
/// Responsibilities:
/// - Name each preset.
/// - Resolve a preset into concrete `Date` bounds.
///
/// ## Why resolution happens here and not in a predicate
/// `#Predicate` bodies are translated into a database query and cannot call
/// `Calendar`. Code that does so compiles cleanly and then traps at runtime. Every
/// calendar computation is therefore performed up front and only the resulting
/// `Date` values are captured by the predicate.
enum DateRangePreset: String, CaseIterable, Identifiable, Sendable {
    case allTime
    case thisMonth
    case lastMonth
    case thisQuarter
    case thisYear
    case custom

    var id: String { rawValue }

    /// Localisation key for this preset's label.
    var titleKey: String.LocalizationValue {
        switch self {
        case .allTime: "filter.preset.allTime"
        case .thisMonth: "filter.preset.thisMonth"
        case .lastMonth: "filter.preset.lastMonth"
        case .thisQuarter: "filter.preset.thisQuarter"
        case .thisYear: "filter.preset.thisYear"
        case .custom: "filter.preset.custom"
        }
    }

    /// Whether the preset draws its bounds from the user-supplied custom dates.
    var usesCustomBounds: Bool { self == .custom }

    /// The half-open interval `[start, end)` this preset covers.
    ///
    /// - Returns: `nil` for `.allTime` (no bound) and `.custom` (bounds come from the
    ///   filter, not from the preset).
    func dateInterval(reference: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .allTime, .custom:
            return nil

        case .thisMonth:
            return calendar.dateInterval(of: .month, for: reference)

        case .lastMonth:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: reference) else { return nil }
            return calendar.dateInterval(of: .month, for: previous)

        case .thisQuarter:
            // `Calendar.dateInterval(of: .quarter,…)` is not reliably implemented for
            // the Gregorian calendar, so the quarter is derived from the month index.
            return Self.quarterInterval(containing: reference, calendar: calendar)

        case .thisYear:
            return calendar.dateInterval(of: .year, for: reference)
        }
    }

    // MARK: - Private

    private static let monthsPerQuarter = 3

    private static func quarterInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }

        let zeroBasedMonth = month - 1
        let firstMonthOfQuarter = (zeroBasedMonth / monthsPerQuarter) * monthsPerQuarter + 1

        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = firstMonthOfQuarter
        startComponents.day = 1

        guard
            let start = calendar.date(from: startComponents),
            let end = calendar.date(byAdding: .month, value: monthsPerQuarter, to: start)
        else { return nil }

        return DateInterval(start: start, end: end)
    }
}
