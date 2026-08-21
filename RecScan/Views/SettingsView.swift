import SwiftUI

/// App preferences.
///
/// Responsibilities:
/// - Edit settings that are not receipt data.
///
/// Currently the default currency; categories join it in the next change.
struct SettingsView: View {

    @AppStorage(AppSettings.Key.defaultCurrencyCode) private var defaultCurrencyCode = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CurrencyPickerView(selection: currencyBinding)
                    } label: {
                        LabeledContent("settings.currency.default") {
                            Text(currencyBinding.wrappedValue).monospaced()
                        }
                    }
                } header: {
                    Text("settings.section.currency")
                } footer: {
                    Text("settings.currency.footer")
                }

                Section("settings.section.categories") {
                    NavigationLink {
                        CategoryListView()
                    } label: {
                        Label("settings.categories.manage", systemImage: SystemImage.category)
                    }
                }
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Bindings

    /// Empty storage means "never chosen", which resolves to the locale's currency.
    /// Surfacing that as the resolved value keeps the picker from showing a blank row.
    private var currencyBinding: Binding<String> {
        Binding(
            get: { defaultCurrencyCode.isEmpty ? AppSettings.defaultCurrencyCode() : defaultCurrencyCode },
            set: { defaultCurrencyCode = $0 }
        )
    }

}

#if DEBUG
#Preview("Settings") {
    SettingsView()
}
#endif
