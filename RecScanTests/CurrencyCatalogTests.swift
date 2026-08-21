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
