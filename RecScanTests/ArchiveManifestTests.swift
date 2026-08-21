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
            pageIndex: 0
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

    @Test("The manifest records its format version")
    func recordsFormatVersion() {
        let manifest = ArchiveManifest(exportedAt: .now, entries: [])

        #expect(manifest.formatVersion == ArchiveManifest.currentFormatVersion)
        #expect(manifest.application == "RecScan")
    }
}
