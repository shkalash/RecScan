import SwiftData
import SwiftUI

/// Spend by category over a chosen period.
///
/// Responsibilities:
/// - Pick a period and show what was spent in each category.
struct ReportView: View {

    @Query(sort: \ReceiptCategory.name) private var categories: [ReceiptCategory]
    @Environment(\.receiptStore) private var receiptStore
    @Environment(\.dismiss) private var dismiss

    @State private var model = ReportViewModel()

    var body: some View {
        NavigationStack {
            Form {
                periodSection

                if let report = model.report {
                    if report.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("report.empty.title", systemImage: SystemImage.report)
                            } description: {
                                Text("report.empty.message")
                            }
                        }
                    } else {
                        breakdownSection(report)
                        totalSection(report)
                    }
                } else if model.isLoading {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle("report.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
            .errorAlert($model.presentedError)
            .task(id: reloadKey) { await model.load(store: receiptStore, names: names) }
        }
    }

    /// Changing any of these rebuilds the report; folding them into one key keeps that in
    /// a single `task` rather than several observers that could fire out of order.
    private var reloadKey: String {
        "\(model.preset.rawValue)-\(model.customStart.timeIntervalSince1970)-\(model.customEnd.timeIntervalSince1970)-\(categories.count)"
    }

    private var names: [UUID: String] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
    }

    // MARK: - Sections

    private var periodSection: some View {
        Section("report.section.period") {
            Picker("report.section.period", selection: $model.preset) {
                ForEach(DateRangePreset.allCases) { preset in
                    Text(String(localized: preset.titleKey)).tag(preset)
                }
            }
            .pickerStyle(.menu)

            if model.usesCustomRange {
                DatePicker("filter.custom.start", selection: $model.customStart, displayedComponents: .date)
                DatePicker("filter.custom.end", selection: $model.customEnd, displayedComponents: .date)
            }
        }
    }

    private func breakdownSection(_ report: CategoryReport) -> some View {
        Section("report.section.breakdown") {
            ForEach(report.lines) { line in
                LabeledContent {
                    Text(amount(line.total, in: report))
                        .monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .foregroundStyle(line.isUncategorised ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        Text("report.line.count \(line.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func totalSection(_ report: CategoryReport) -> some View {
        Section {
            LabeledContent {
                Text(amount(report.grandTotal, in: report))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            } label: {
                Text("report.total").fontWeight(.semibold)
            }
        } footer: {
            if report.hasExcludedCurrencies {
                Text("report.mixedCurrencies")
            }
        }
    }

    private func amount(_ value: Decimal, in report: CategoryReport) -> String {
        ReceiptFormatting.amount(
            value,
            currencyCode: report.currencyCode,
            defaultCode: AppSettings.defaultCurrencyCode()
        ) ?? ""
    }
}

#if DEBUG
#Preview("Report") {
    ReportView().previewLibrary()
}
#endif
