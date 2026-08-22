import SwiftUI

/// Amounts read off the receipt, offered as one tap each.
///
/// Responsibilities:
/// - Show what was found and let one be chosen.
///
/// ## Why alternatives are shown rather than just the best guess
/// The ranking is "largest wins", which is right on an ordinary receipt and wrong when a
/// bigger number appears — cash tendered, a pre-discount subtotal. Recognition can also
/// corrupt a value: `₪52.30` has been observed reading as `152.30`, which looks entirely
/// plausible on its own. Seeing the alternatives is what makes both cases fixable in a tap
/// instead of invisible.
struct AmountSuggestionRow: View {

    let candidates: [AmountCandidate]
    let currencyCode: String?
    let onSelect: (Decimal) -> Void

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: LayoutMetrics.Suggestions.spacing) {
                Text("amount.suggestions.title")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: LayoutMetrics.Suggestions.spacing) {
                        ForEach(candidates) { candidate in
                            Button {
                                onSelect(candidate.value)
                            } label: {
                                Text(formatted(candidate.value))
                                    .font(.callout)
                                    .monospacedDigit()
                                    .padding(.horizontal, LayoutMetrics.Suggestions.chipPaddingX)
                                    .padding(.vertical, LayoutMetrics.Suggestions.chipPaddingY)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                // The row scrolls rather than wrapping: a long receipt can yield a dozen
                // numbers, and letting them wrap would push the form's fields off screen.
                .scrollIndicators(.hidden)
            }
        }
    }

    private func formatted(_ value: Decimal) -> String {
        ReceiptFormatting.amount(
            value,
            currencyCode: currencyCode,
            defaultCode: AppSettings.defaultCurrencyCode()
        ) ?? "\(value)"
    }
}

#if DEBUG
#Preview("Suggestions") {
    Form {
        AmountSuggestionRow(
            candidates: ReceiptAmountParser.candidates(
                in: "n7H 790 | 12.90 | 7.50 | 24.30 | a70 | naaa | 7.60 | N52.30 | 17%nAN"
            ),
            currencyCode: "ILS",
            onSelect: { _ in }
        )
    }
}
#endif
