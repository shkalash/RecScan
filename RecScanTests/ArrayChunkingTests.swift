import Foundation
import Testing
@testable import RecScan

@Suite("Page chunking")
struct ArrayChunkingTests {

    @Test("An exact multiple splits evenly")
    func exactMultiple() {
        #expect([1, 2, 3, 4].chunked(into: 2) == [[1, 2], [3, 4]])
    }

    @Test("A remainder forms a short final chunk")
    func remainder() {
        #expect([1, 2, 3, 4, 5].chunked(into: 2) == [[1, 2], [3, 4], [5]])
    }

    @Test("A chunk larger than the array yields one chunk")
    func oversizedChunk() {
        #expect([1, 2].chunked(into: 10) == [[1, 2]])
    }

    @Test("An empty array yields no chunks")
    func empty() {
        #expect([Int]().chunked(into: 3).isEmpty)
    }

    @Test("A non-positive size degrades to a single chunk rather than trapping")
    func nonPositiveSize() {
        #expect([1, 2, 3].chunked(into: 0) == [[1, 2, 3]])
        #expect([Int]().chunked(into: 0).isEmpty)
    }
}
