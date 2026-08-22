import SwiftUI

/// Dates found on the receipt, offered as one tap each.
///
/// Responsibilities:
/// - Show what was printed and let one be chosen.
///
/// ## Why alternatives are shown
/// `05/06/2026` is 5 June or 6 May depending on where the receipt was printed, and the
/// page itself does not say. The parser picks the likelier reading from the document's
/// own language, but "likelier" is not "right" — so the other reading sits next to it
/// rather than being silently discarded. Ambiguous readings are marked, because a date
/// that might be a month out is worth a second look in a way a certain one is not.
struct DateSuggestionRow: View {

    let candidates: [DateCandidate]
    let onSelect: (Date) -> Void

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: LayoutMetrics.Suggestions.spacing) {
                Text("date.suggestions.title")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: LayoutMetrics.Suggestions.spacing) {
                        ForEach(candidates) { candidate in
                            Button {
                                onSelect(candidate.date)
                            } label: {
                                chip(for: candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                // Scrolls rather than wraps, for the same reason as the amounts: a
                // receipt can print several dates and the fields must stay on screen.
                .scrollIndicators(.hidden)
            }
        }
    }

    private func chip(for candidate: DateCandidate) -> some View {
        HStack(spacing: LayoutMetrics.Suggestions.chipIconSpacing) {
            if candidate.confidence != .unambiguous {
                Image(systemName: SystemImage.ambiguousDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(ReceiptFormatting.receiptDate(for: candidate.date))
                .font(.callout)
        }
        .padding(.horizontal, LayoutMetrics.Suggestions.chipPaddingX)
        .padding(.vertical, LayoutMetrics.Suggestions.chipPaddingY)
        .background(.quaternary, in: Capsule())
    }
}

#if DEBUG
#Preview("Date suggestions") {
    Form {
        DateSuggestionRow(
            candidates: ReceiptDateParser.candidates(
                in: "Issued 21/08/2026  Due 05/06/2026",
                order: .dayFirst,
                now: TestPreviewDate.now
            ),
            onSelect: { _ in }
        )
    }
}

/// Fixed so the preview does not reshuffle as real dates age past the plausibility check.
private enum TestPreviewDate {
    static let now = Date(timeIntervalSince1970: 1_788_000_000)
}
#endif
