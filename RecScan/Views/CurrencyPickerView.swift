import SwiftUI

/// A searchable currency list.
///
/// Responsibilities:
/// - Let a currency be found by typing rather than scrolled to.
///
/// Replaces `Picker(.navigationLink)`, which pushes its own list but cannot carry a
/// search field — leaving two hundred alphabetised codes to scroll through.
struct CurrencyPickerView: View {

    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty {
                Section("currency.section.common") { rows(for: CurrencyCatalog.pinned) }
                Section("currency.section.all") {
                    rows(for: CurrencyCatalog.others(including: selection))
                }
            } else {
                let matches = CurrencyCatalog.search(query, including: selection)
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    rows(for: matches)
                }
            }
        }
        .searchable(text: $query, prompt: Text("currency.search.prompt"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.characters)
        .navigationTitle("settings.currency.default")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rows(for codes: [String]) -> some View {
        ForEach(codes, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                LabeledContent {
                    if code == selection {
                        Image(systemName: SystemImage.checkmark)
                            .foregroundStyle(Color.accentColor)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code).monospaced()
                        Text(CurrencyCatalog.name(for: code))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Same reason as the category rows: the empty space either side of the
                // label is not hit-tested unless the row is given a shape.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("Currency picker") {
    @Previewable @State var selection = "ILS"
    return NavigationStack {
        CurrencyPickerView(selection: $selection)
    }
}
#endif
