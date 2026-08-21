import Foundation
import Testing
@testable import RecScan

@MainActor
@Suite("Import coalescing")
struct ImportQueueTests {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    /// Short window so the tests are quick; the behaviour under test is the grouping,
    /// not the exact duration.
    private func queue() -> ImportQueue {
        ImportQueue(window: .milliseconds(60))
    }

    @Test("Files arriving together are delivered as one batch")
    func coalescesBurst() async throws {
        // The bug this exists for: .onOpenURL fires once per file, so five shared files
        // would otherwise raise five review sheets, each replacing the last.
        let subject = queue()
        var batches: [[URL]] = []

        for name in ["a", "b", "c"] {
            subject.enqueue(url(name)) { batch in batches.append(batch) }
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(batches.count == 1)
        #expect(batches.first?.count == 3)
    }

    @Test("A single file is still delivered")
    func singleFileArrives() async throws {
        let subject = queue()
        var batches: [[URL]] = []

        subject.enqueue(url("only")) { batch in batches.append(batch) }
        try await Task.sleep(for: .milliseconds(200))

        #expect(batches == [[url("only")]])
    }

    @Test("Files arriving after the window are a separate batch")
    func separateBurstsStaySeparate() async throws {
        let subject = queue()
        var batches: [[URL]] = []

        subject.enqueue(url("first")) { batch in batches.append(batch) }
        try await Task.sleep(for: .milliseconds(200))
        subject.enqueue(url("second")) { batch in batches.append(batch) }
        try await Task.sleep(for: .milliseconds(200))

        #expect(batches.count == 2)
    }

    @Test("Nothing is delivered twice")
    func batchIsDrained() async throws {
        let subject = queue()
        var batches: [[URL]] = []

        subject.enqueue(url("a")) { batch in batches.append(batch) }
        try await Task.sleep(for: .milliseconds(200))

        #expect(subject.isEmpty)
        #expect(batches.flatMap(\.self).count == 1)
    }

    @Test("Flushing early delivers what is waiting")
    func flushNowDelivers() async {
        let subject = queue()
        var batches: [[URL]] = []

        subject.enqueue(url("a")) { _ in }
        subject.enqueue(url("b")) { _ in }
        await subject.flushNow { batch in batches.append(batch) }

        #expect(batches.first?.count == 2)
        #expect(subject.isEmpty)
    }

    @Test("Flushing an empty queue does nothing")
    func flushEmptyIsHarmless() async {
        let subject = queue()
        var called = false

        await subject.flushNow { _ in called = true }

        #expect(!called)
    }
}
