import Foundation

/// One printed line of a currency-split table.
///
/// Responsibilities:
/// - Flatten currency sections into a single sequence that can be split across pages.
///
/// ## Why the table is flattened before paginating
/// Sections cannot each start a new page: a report with five currencies and two
/// categories apiece would print five near-empty sheets. Flattening to rows means the
/// page break falls wherever the page happens to run out, and a section that spans a
/// break simply continues — which is how a printed ledger behaves.
enum TotalsTableRow<Section: CurrencySection>: Sendable {

    /// Names the currency the following rows are in.
    case currencyHeader(Section)
    /// One line under the current currency.
    case row(Section.Row, currencyCode: String)
    /// Closes a currency with its total.
    case total(Section)

    /// Flattens sections in order, each as header, rows, total.
    static func rows(for sections: [Section]) -> [TotalsTableRow<Section>] {
        sections.flatMap { section in
            [.currencyHeader(section)]
                + section.rows.map { .row($0, currencyCode: section.currencyCode) }
                + [.total(section)]
        }
    }
}
