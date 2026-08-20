import Foundation
import Testing
@testable import RecScan

@Suite("Search index")
struct ReceiptSearchIndexTests {

    @Test("All three source fields end up in the index")
    func includesEveryField() {
        let index = ReceiptSearchIndex.make(merchant: "Acme", note: "lunch", ocrText: "TOTAL 9.00")

        #expect(index.contains("Acme"))
        #expect(index.contains("lunch"))
        #expect(index.contains("TOTAL 9.00"))
    }

    @Test("Missing and empty fields are skipped")
    func skipsMissingFields() {
        #expect(ReceiptSearchIndex.make(merchant: nil, note: nil, ocrText: nil).isEmpty)
        #expect(ReceiptSearchIndex.make(merchant: "Acme", note: "", ocrText: nil) == "Acme")
    }

    @Test("Fields are separated so no match spans a boundary")
    func fieldsAreSeparated() {
        let index = ReceiptSearchIndex.make(merchant: "Acme", note: "Rent", ocrText: nil)

        #expect(!index.contains("AcmeRent"))
        #expect(index.contains("Acme"))
        #expect(index.contains("Rent"))
    }
}
