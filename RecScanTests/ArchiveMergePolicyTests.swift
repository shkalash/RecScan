import Foundation
import Testing
@testable import RecScan

@Suite("Archive merge policy")
struct ArchiveMergePolicyTests {

    private let earlier = TestCalendar.date(year: 2026, month: 8, day: 1)
    private let later = TestCalendar.date(year: 2026, month: 9, day: 1)

    @Test("An unknown receipt is inserted")
    func unknownIsInserted() {
        #expect(ArchiveMergePolicy.decide(local: nil, archivedModifiedAt: earlier) == .insert)
    }

    @Test("A newer archived copy overwrites the local one")
    func newerArchiveWins() {
        let local = ArchiveMergePolicy.LocalState(modifiedAt: earlier, hasImageFile: true)

        #expect(ArchiveMergePolicy.decide(local: local, archivedModifiedAt: later) == .update)
    }

    @Test("A newer local copy is left alone")
    func newerLocalWins() {
        let local = ArchiveMergePolicy.LocalState(modifiedAt: later, hasImageFile: true)

        #expect(ArchiveMergePolicy.decide(local: local, archivedModifiedAt: earlier) == .skip)
    }

    @Test("An identical timestamp is a no-op, so re-importing an archive changes nothing")
    func equalTimestampsSkip() {
        let local = ArchiveMergePolicy.LocalState(modifiedAt: earlier, hasImageFile: true)

        #expect(ArchiveMergePolicy.decide(local: local, archivedModifiedAt: earlier) == .skip)
    }

    @Test("A missing image is restored even when the local metadata is newer")
    func missingImageIsRestoredRegardlessOfDates() {
        // The row is current but unopenable, and the archive holds the only copy of the
        // image. Dates are the wrong question here.
        let local = ArchiveMergePolicy.LocalState(modifiedAt: later, hasImageFile: false)

        #expect(ArchiveMergePolicy.decide(local: local, archivedModifiedAt: earlier) == .update)
    }
}
