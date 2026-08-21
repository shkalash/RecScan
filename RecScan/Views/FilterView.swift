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

    /// A toggleable row. Uses a filled/empty circle rather than a checkmark so an
    /// unselected row still shows an affordance — with a bare checkmark, a section with
    /// nothing selected looks like plain text.
    private func categoryRow(title: Text, isOn: Bool, isMuted: Bool = false) -> some View {
        LabeledContent {
            Image(systemName: isOn ? SystemImage.selectionOn : SystemImage.selectionOff)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        } label: {
            title.foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

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
                    Section {
                        // "All Categories" clears rather than being a value of its own,
                        // so it reads as the off switch for the whole section.
                        Button {
                            filter.categoryIDs.removeAll()
                        } label: {
                            categoryRow(
                                title: Text("filter.category.all"),
                                isOn: filter.categoryIDs.isEmpty,
                                isMuted: true
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(categories) { category in
                            Button {
                                filter.toggleCategory(category.id)
                            } label: {
                                categoryRow(
                                    title: Text(category.name),
                                    isOn: filter.categoryIDs.contains(category.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("filter.section.category")
                    } footer: {
                        Text("filter.category.footer")
                    }
                }

                Section {
                    Toggle("filter.needsReview", isOn: $filter.needsReviewOnly)
                } footer: {
                    Text("filter.needsReview.footer")
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
        categoryIDs: [PreviewFixture.primaryCategoryID, PreviewFixture.categoryIDs[1]],
        needsReviewOnly: true
    )
    return FilterView(filter: $filter).previewLibrary()
}
#endif
