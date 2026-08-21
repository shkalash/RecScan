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
                    Picker("settings.currency.default", selection: currencyBinding) {
                        ForEach(Self.currencyCodes, id: \.self) { code in
                            Text(Self.label(for: code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("settings.section.currency")
                } footer: {
                    Text("settings.currency.footer")
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

    // MARK: - Currency list

    private static let currencyCodes: [String] = {
        let resolved = AppSettings.defaultCurrencyCode()
        // The active currency is guaranteed present, otherwise the Picker has no row
        // matching its selection and silently renders empty.
        return Array(Set(Locale.commonISOCurrencyCodes).union([resolved])).sorted()
    }()

    private static func label(for code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(code) — \(name)"
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView()
}
#endif
