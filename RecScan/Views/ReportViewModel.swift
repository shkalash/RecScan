import Foundation
import Observation

/// Builds the category report for the chosen period.
///
/// Responsibilities:
/// - Hold the date range and produce the report from the library.
@MainActor
@Observable
final class ReportViewModel {

    /// Defaults to this year: the period most often asked for, and wide enough that a new
    /// user sees something rather than an empty screen.
    var preset: DateRangePreset = .thisYear
    var customStart: Date = Date()
    var customEnd: Date = Date()

    private(set) var report: CategoryReport?
    private(set) var isLoading = false
    var presentedError: PresentableError?

    /// The resolved window, reusing the library's own preset maths so the report and the
    /// filter can never disagree about what "this quarter" means.
    func interval(calendar: Calendar = .current) -> DateInterval? {
        ReceiptFilter(
            preset: preset,
            customStart: customStart,
            customEnd: customEnd
        ).resolvedInterval(calendar: calendar)
    }

    var usesCustomRange: Bool { preset.usesCustomBounds }

    func load(store: any ReceiptStoring, names: [UUID: String]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let receipts = try await store.allReceipts()
            report = CategoryReport.make(
                allReceipts: receipts,
                names: names,
                interval: interval(),
                defaultCurrencyCode: AppSettings.defaultCurrencyCode(),
                uncategorisedLabel: String(localized: "report.uncategorised")
            )
        } catch {
            presentedError = PresentableError(titleKey: ErrorTitle.loadFailed, error: error)
        }
    }

    private enum ErrorTitle {
        static let loadFailed: String.LocalizationValue = "error.report.title"
    }
}
