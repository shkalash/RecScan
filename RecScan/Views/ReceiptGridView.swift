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
            searchText: filter.searchText,
            categoryID: filter.categoryID
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
        // The tile size is computed here rather than left to `.adaptive` columns.
        // A LazyVGrid proposes an unspecified height to its cells, so anything that
        // relies on `.aspectRatio` to derive a square has nothing to resolve against
        // and silently collapses. A fixed column width removes the guesswork.
        GeometryReader { proxy in
            let side = Self.tileSide(forAvailableWidth: proxy.size.width)
            gridContent(tileSide: side)
        }
    }

    /// Largest tile that fits a whole number of columns, never below the minimum.
    static func tileSide(forAvailableWidth width: CGFloat) -> CGFloat {
        let spacing = LayoutMetrics.Grid.itemSpacing
        let usable = width - LayoutMetrics.Grid.horizontalPadding * 2
        guard usable > 0 else { return LayoutMetrics.Grid.minimumItemWidth }

        let columns = max(1, Int((usable + spacing) / (LayoutMetrics.Grid.minimumItemWidth + spacing)))
        return (usable - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func gridContent(tileSide: CGFloat) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: LayoutMetrics.Grid.sectionSpacing,
                pinnedViews: [.sectionHeaders]
            ) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: tileSide), spacing: LayoutMetrics.Grid.itemSpacing)],
                            spacing: LayoutMetrics.Grid.itemSpacing
                        ) {
                            ForEach(section.items) { receipt in
                                cell(for: receipt, tileSide: tileSide)
                            }
                        }
                        .padding(.horizontal, LayoutMetrics.Grid.horizontalPadding)
                    } header: {
                        monthHeader(for: section.id)
                    }
                }
            }
            .padding(.vertical, LayoutMetrics.Grid.itemSpacing)
        }
    }

    @ViewBuilder
    private func cell(for receipt: Receipt, tileSide: CGFloat) -> some View {
        let thumbnail = ReceiptThumbnailView(
            receipt: receipt,
            isSelectionActive: model.isSelecting,
            isSelected: model.selection.contains(receipt.id),
            side: tileSide
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

    private var sections: [MonthSection<Receipt>] {
        MonthGrouper.group(receipts) { $0.capturedAt }
    }
}

#if DEBUG
#Preview("Grid") {
    NavigationStack {
        ReceiptGridView(filter: ReceiptFilter(), model: PreviewFixture.libraryModel())
            .navigationTitle("library.title")
    }
    .previewLibrary()
}

#Preview("Grid — selecting") {
    NavigationStack {
        ReceiptGridView(filter: ReceiptFilter(), model: PreviewFixture.libraryModel(selecting: true))
            .navigationTitle("library.title")
    }
    .previewLibrary()
}
#endif
