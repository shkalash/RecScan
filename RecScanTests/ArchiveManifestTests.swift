import Foundation
import Testing
@testable import RecScan

@Suite("Archive manifest")
struct ArchiveManifestTests {

    private func entry(amount: String?) -> ArchiveManifest.Entry {
        ArchiveManifest.Entry(
            id: UUID(),
            capturedAt: TestCalendar.date(year: 2026, month: 8, day: 4),
            createdAt: TestCalendar.date(year: 2026, month: 8, day: 4),
            modifiedAt: TestCalendar.date(year: 2026, month: 8, day: 5),
            fileName: "Receipts/x.heic",
            merchant: "Corner Store",
            amount: amount,
            currencyCode: "ILS",
            note: "lunch",
            ocrText: "TOTAL 12.50",
            groupID: nil,
            pageIndex: 0,
            categoryID: nil,
            needsReview: true
        )
    }

    @Test("A manifest survives a JSON round trip unchanged")
    func roundTrips() throws {
        let manifest = ArchiveManifest(
            exportedAt: TestCalendar.date(year: 2026, month: 8, day: 21),
            entries: [entry(amount: "12.50")]
        )

        let data = try ArchiveManifest.makeEncoder().encode(manifest)
        let decoded = try ArchiveManifest.makeDecoder().decode(ArchiveManifest.self, from: data)

        #expect(decoded == manifest)
    }

    @Test("Money survives the round trip exactly")
    func decimalPrecisionSurvives() throws {
        // The reason amount is stored as a string: Decimal through JSONEncoder goes via
        // Double and comes back as 12.499999999999998.
        let original = entry(amount: "12.50")

        let data = try ArchiveManifest.makeEncoder().encode(original)
        let decoded = try ArchiveManifest.makeDecoder().decode(ArchiveManifest.Entry.self, from: data)

        #expect(decoded.decimalAmount == Decimal(string: "12.50"))
        #expect(decoded.decimalAmount?.description == "12.5")
    }

    @Test("A receipt with no amount stays absent rather than becoming zero")
    func missingAmountStaysNil() throws {
        let data = try ArchiveManifest.makeEncoder().encode(entry(amount: nil))
        let decoded = try ArchiveManifest.makeDecoder().decode(ArchiveManifest.Entry.self, from: data)

        #expect(decoded.decimalAmount == nil)
    }

    @Test("A v1 archive still decodes, without categories or review flags")
    func version1StillDecodes() throws {
        // Hand-written v1 JSON: no `categories`, no `categoryID`, no `needsReview`.
        // Anything that makes these required breaks every archive already on disk.
        let json = """
        {
          "application": "RecScan",
          "exportedAt": "2026-08-01T10:00:00Z",
          "formatVersion": 1,
          "entries": [
            {
              "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
              "capturedAt": "2026-07-04T10:00:00Z",
              "createdAt": "2026-07-04T10:00:00Z",
              "modifiedAt": "2026-07-04T10:00:00Z",
              "fileName": "Receipts/old.heic",
              "pageIndex": 0
            }
          ]
        }
        """

        let manifest = try ArchiveManifest.makeDecoder()
            .decode(ArchiveManifest.self, from: Data(json.utf8))

        #expect(manifest.formatVersion == 1)
        #expect(manifest.entries.count == 1)
        #expect(manifest.categoryList.isEmpty)
        #expect(manifest.entries[0].categoryID == nil)
        // Absent means "already reviewed" -- importing an old archive must not badge
        // every receipt it restores.
        #expect(manifest.entries[0].requiresReview == false)
    }

    @Test("Categories round trip in a v2 manifest")
    func categoriesRoundTrip() throws {
        let category = ArchiveManifest.Category(id: UUID(), name: "Fuel")
        let manifest = ArchiveManifest(
            exportedAt: TestCalendar.date(year: 2026, month: 8, day: 21),
            entries: [entry(amount: "10.00")],
            categories: [category]
        )

        let data = try ArchiveManifest.makeEncoder().encode(manifest)
        let decoded = try ArchiveManifest.makeDecoder().decode(ArchiveManifest.self, from: data)

        #expect(decoded.categoryList == [category])
        #expect(decoded.formatVersion == 2)
    }

    @Test("The manifest records its format version")
    func recordsFormatVersion() {
        let manifest = ArchiveManifest(exportedAt: .now, entries: [])

        #expect(manifest.formatVersion == ArchiveManifest.currentFormatVersion)
        #expect(manifest.application == "RecScan")
    }
}
