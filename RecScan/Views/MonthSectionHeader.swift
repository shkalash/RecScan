import SwiftUI

/// The pinned header above one month of receipts in the library grid.
///
/// Responsibilities:
/// - Name the month.
/// - While selecting, offer to select or deselect that month's receipts in one tap.
///
/// ## Why the month gets its own select control
/// An export is almost always one month's receipts, and the two existing routes both miss
/// that: the toolbar export takes everything the filter shows, and Select All takes the
/// whole library. Picking a month by hand means tapping every tile in it. Narrowing the
/// date filter would work but then has to be undone afterwards, so the quickest path sits
/// where the month is already named.
///
/// ## Why one button rather than a checkbox
/// A checkbox implies a third, indeterminate state to render and explain. What the header
/// actually needs is a verb: with nothing in the month picked it offers to take the lot,
/// and with anything picked it offers to drop the lot. Partial selections therefore read
/// as "deselect", because that is the only useful thing left to offer.
///
/// It is styled as a bordered capsule rather than bare text so it reads as a control
/// sitting next to a headline instead of a second, smaller heading. `.bordered` with a
/// capsule shape is what the system draws for the toolbar's own Select, and unlike the
/// iOS 26 glass styles it needs no availability gate against the iOS 18 floor.
struct MonthSectionHeader: View {

    /// Start of the month, used for the title.
    let month: Date
    /// Whether the library is in selection mode. The control is hidden otherwise.
    let isSelectionActive: Bool
    /// Whether any receipt in *this month* is selected, which flips the verb.
    let isAnySelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack {
            Text(ReceiptFormatting.monthTitle(for: month))
                .font(.headline)

            Spacer(minLength: LayoutMetrics.Grid.itemSpacing)

            if isSelectionActive {
                Button(action: onToggleSelection) {
                    Text(isAnySelected ? "library.month.deselect" : "library.month.select")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                // "Select" on its own is ambiguous when several months are on screen, so
                // the spoken label names the month the button acts on.
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, LayoutMetrics.Grid.itemSpacing / 2)
        .background(.bar)
    }

    private var accessibilityLabel: Text {
        let title = ReceiptFormatting.monthTitle(for: month)
        return isAnySelected
            ? Text("library.month.deselect.accessibility \(title)")
            : Text("library.month.select.accessibility \(title)")
    }
}

#if DEBUG
/// A fixed month rather than one off the shared fixture: the fixture dates itself relative
/// to today, so the header's title would change every month and the preview would be
/// judging a different string each time.
private let previewMonth = Date(timeIntervalSince1970: 1_772_000_000)

#Preview("Header — not selecting") {
    MonthSectionHeader(
        month: previewMonth,
        isSelectionActive: false,
        isAnySelected: false,
        onToggleSelection: {}
    )
    .previewLibrary()
}

#Preview("Header — selecting, none picked") {
    MonthSectionHeader(
        month: previewMonth,
        isSelectionActive: true,
        isAnySelected: false,
        onToggleSelection: {}
    )
    .previewLibrary()
}

#Preview("Header — selecting, some picked") {
    MonthSectionHeader(
        month: previewMonth,
        isSelectionActive: true,
        isAnySelected: true,
        onToggleSelection: {}
    )
    .previewLibrary()
}

/// All three side by side, which is the quickest way to judge that the verb swap does not
/// shift the title or change the header's height.
#Preview("Header — all states") {
    VStack(spacing: 0) {
        MonthSectionHeader(
            month: previewMonth, isSelectionActive: false,
            isAnySelected: false, onToggleSelection: {}
        )
        MonthSectionHeader(
            month: previewMonth, isSelectionActive: true,
            isAnySelected: false, onToggleSelection: {}
        )
        MonthSectionHeader(
            month: previewMonth, isSelectionActive: true,
            isAnySelected: true, onToggleSelection: {}
        )
    }
    .previewLibrary()
}
#endif
