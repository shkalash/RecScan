import Foundation
import Testing
@testable import RecScan

@Suite("Currency catalogue")
struct CurrencyCatalogTests {

    private let locale = Locale(identifier: "en_US")

    @Test("The common currencies come first, in the order given")
    func pinnedOrder() {
        #expect(CurrencyCatalog.pinned == ["USD", "EUR", "ILS"])
        #expect(Array(CurrencyCatalog.search("", locale: locale).prefix(3)) == ["USD", "EUR", "ILS"])
    }

    @Test("Pinned currencies are not repeated in the full list")
    func pinnedNotDuplicated() {
        let others = CurrencyCatalog.others()

        #expect(!others.contains("USD"))
        #expect(!others.contains("ILS"))
        #expect(others == others.sorted())
    }

    @Test("Searching by code finds the currency")
    func searchByCode() {
        #expect(CurrencyCatalog.search("ils", locale: locale).first == "ILS")
    }

    @Test("Searching by name finds it too")
    func searchByName() {
        // The reason names are searched at all: knowing the code is the hard part.
        let matches = CurrencyCatalog.search("shekel", locale: locale)

        #expect(matches.contains("ILS"))
    }

    @Test("A search matching nothing returns nothing rather than everything")
    func searchWithNoMatches() {
        #expect(CurrencyCatalog.search("zzzzz", locale: locale).isEmpty)
    }

    @Test("A currency outside the common list stays selectable")
    func unusualSelectionIsIncluded() {
        // A receipt can carry a code the common list omits; it must still appear, or the
        // picker silently cannot represent its own selection.
        let unusual = "XPT"

        #expect(CurrencyCatalog.others(including: unusual).contains(unusual))
        #expect(CurrencyCatalog.search(unusual, including: unusual, locale: locale).contains(unusual))
    }

    @Test("Names are localised, and fall back to the code when unknown")
    func nameFallback() {
        #expect(CurrencyCatalog.name(for: "ILS", locale: locale).localizedCaseInsensitiveContains("shekel"))
        #expect(CurrencyCatalog.name(for: "ZZZ", locale: locale) == "ZZZ")
    }
}


@Suite("Category picker sizing")
struct CategoryPickerSizingTests {

    /// Mirrors `CategoryPicker.popoverHeight`, which is private to the view.
    private func height(categoryCount: Int) -> CGFloat {
        let rows = CGFloat(categoryCount + 1)
        let content = rows * LayoutMetrics.CategoryPicker.rowHeight
            + LayoutMetrics.CategoryPicker.chromeHeight
        return min(
            max(content, LayoutMetrics.CategoryPicker.minimumHeight),
            LayoutMetrics.CategoryPicker.maximumHeight
        )
    }

    @Test("An empty list still opens at a usable size")
    func emptyListIsNotCollapsed() {
        // The bug this guards: a List has no intrinsic height, so the popover collapsed
        // to a single row and there was nothing to pick from.
        #expect(height(categoryCount: 0) == LayoutMetrics.CategoryPicker.minimumHeight)
        #expect(height(categoryCount: 0) >= 300)
    }

    @Test("The popover grows with the number of categories")
    func growsWithContent() {
        #expect(height(categoryCount: 8) > height(categoryCount: 2))
    }

    @Test("Growth is capped so it cannot run off screen")
    func heightIsCapped() {
        #expect(height(categoryCount: 200) == LayoutMetrics.CategoryPicker.maximumHeight)
    }

    @Test("The popover is wide enough for real category names")
    func widthFitsNames() {
        #expect(LayoutMetrics.CategoryPicker.width >= 300)
    }
}
