import SwiftData
import SwiftUI

/// Date-range and text filters for the library.
///
/// Responsibilities:
/// - Edit the shared `ReceiptFilter`.
///
/// Bindings write straight through to the library's filter so the grid updates live
/// behind the sheet; there is no separate "apply" step to get out of sync.
struct FilterView: View {

    @Binding var filter: ReceiptFilter

    @Query(sort: \ReceiptCategory.name) private var categories: [ReceiptCategory]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("filter.section.dateRange") {
                    Picker("filter.section.dateRange", selection: $filter.preset) {
                        ForEach(DateRangePreset.allCases) { preset in
                            Text(String(localized: preset.titleKey)).tag(preset)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if filter.preset.usesCustomBounds {
                    Section("filter.section.customRange") {
                        DatePicker(
                            "filter.custom.start",
                            selection: $filter.customStart,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "filter.custom.end",
                            selection: $filter.customEnd,
                            displayedComponents: .date
                        )
                    }
                }

                if !categories.isEmpty {
                    Section("filter.section.category") {
                        Picker("filter.section.category", selection: $filter.categoryID) {
                            Text("filter.category.all").tag(UUID?.none)
                            ForEach(categories) { category in
                                Text(category.name).tag(UUID?.some(category.id))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    TextField("filter.search.placeholder", text: $filter.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("filter.section.search")
                } footer: {
                    Text("filter.search.footer")
                }
            }
            .navigationTitle("filter.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("filter.action.reset") { filter = ReceiptFilter() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Filter") {
    @Previewable @State var filter = ReceiptFilter()
    return FilterView(filter: $filter).previewLibrary()
}

#Preview("Filter — active") {
    @Previewable @State var filter = ReceiptFilter(
        preset: .thisQuarter,
        searchText: "coffee",
        categoryID: PreviewFixture.primaryCategoryID
    )
    return FilterView(filter: $filter).previewLibrary()
}
#endif
