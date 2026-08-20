import SwiftData
import SwiftUI

/// The filtered, month-sectioned grid of receipts.
///
/// Responsibilities:
/// - Own the `@Query` for the current filter.
/// - Group results into month sections and render the cells.
/// - Publish the visible results back to `LibraryViewModel`.
///
/// ## Why the query lives here and not in `LibraryView`
/// `@Query` is configured in `init`, so the predicate must be known when the view is
/// constructed. Isolating it in a child view means changing the filter rebuilds only
/// this subtree, and `LibraryView` keeps its own state across the change.
struct ReceiptGridView: View {

    @Query private var receipts: [Receipt]

    private let model: LibraryViewModel

    init(filter: ReceiptFilter, model: LibraryViewModel) {
        self.model = model

        // Calendar arithmetic is resolved here, on the Swift side. The predicate below
        // only ever captures finished `Date` values.
        let interval = filter.resolvedInterval()
        let predicate = ReceiptPredicateFactory.makePredicate(
            interval: interval,
            searchText: filter.searchText
        )
        _receipts = Query(
            filter: predicate,
            sort: [
                SortDescriptor(\Receipt.capturedAt, order: .reverse),
                SortDescriptor(\Receipt.pageIndex, order: .forward)
            ]
        )
    }

    var body: some View {
        Group {
            if receipts.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .onChange(of: receipts, initial: true) { _, current in
            model.visibleReceipts = current.map(ReceiptSnapshot.init)
            model.pruneSelection()
        }
    }

    // MARK: - Content

    private var grid: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: LayoutMetrics.Grid.sectionSpacing,
                pinnedViews: [.sectionHeaders]
            ) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: LayoutMetrics.Grid.itemSpacing) {
                            ForEach(section.items) { receipt in
                                cell(for: receipt)
                            }
                        }
                        .padding(.horizontal)
                    } header: {
                        monthHeader(for: section.id)
                    }
                }
            }
            .padding(.vertical, LayoutMetrics.Grid.itemSpacing)
        }
    }

    @ViewBuilder
    private func cell(for receipt: Receipt) -> some View {
        let thumbnail = ReceiptThumbnailView(
            receipt: receipt,
            isSelectionActive: model.isSelecting,
            isSelected: model.selection.contains(receipt.id)
        )

        if model.isSelecting {
            Button {
                model.toggleSelection(of: receipt.id)
            } label: {
                thumbnail
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: receipt) {
                thumbnail
            }
            .buttonStyle(.plain)
        }
    }

    private func monthHeader(for month: Date) -> some View {
        Text(ReceiptFormatting.monthTitle(for: month))
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, LayoutMetrics.Grid.itemSpacing / 2)
            .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.filter.isActive ? "library.empty.filtered.title" : "library.empty.title",
                systemImage: SystemImage.emptyLibrary
            )
        } description: {
            Text(model.filter.isActive ? "library.empty.filtered.message" : "library.empty.message")
        }
    }

    // MARK: - Layout

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: LayoutMetrics.Grid.minimumItemWidth),
                spacing: LayoutMetrics.Grid.itemSpacing
            )
        ]
    }

    private var sections: [MonthSection<Receipt>] {
        MonthGrouper.group(receipts) { $0.capturedAt }
    }
}
