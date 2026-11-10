import Foundation
@testable import BrkLocalModels
import XCTest

/// Vectors from a lookup table: a test's stand-in for the search model.
struct TableEmbedder: TextEmbedding {
    let table: [String: [Float]]
    let calls: LockedCounter

    func embed(_ texts: [EmbeddingText]) async throws -> [[Float]] {
        calls.increment()
        return texts.map { text in
            guard case .document(_, let body) = text else { return [1, 0, 0, 0] }
            let key = table.keys.first { body.hasPrefix($0) } ?? ""
            return VectorMath.normalized(table[key] ?? [0, 0, 0, 1])
        }
    }
}

final class IndexAndClusterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("brk-index-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private let table: [String: [Float]] = ["Redis": [1, 0.1, 0, 0], "MySQL": [0.9, 0.2, 0, 0], "东京": [0, 0, 1, 0.1], "Tokyo": [0, 0.3, 0.9, 0]]

    private func entries(_ titles: [(IndexEntry.Kind, String)]) -> [IndexEntry] {
        titles.enumerated().map { IndexEntry(kind: $0.element.0, id: "\($0.offset)", title: $0.element.1, url: "https://example.com/\($0.offset)") }
    }

    func testReconcileEmbedsNewDropsGoneAndPersists() async throws {
        let file = folder.appendingPathComponent("p.vectors")
        let calls = LockedCounter()
        let embedder = TableEmbedder(table: table, calls: calls)
        let index = SemanticIndex(file: file, dimensions: 4)
        let all = entries([(.tab, "Redis 持久化"), (.history, "MySQL 索引"), (.archive, "东京攻略")])
        let added = try await index.reconcile(all, embedder: embedder)
        XCTAssertEqual(added, 3)
        let hits = await index.search(VectorMath.normalized([1, 0, 0, 0]), limit: 2)
        XCTAssertEqual(hits.map(\.key), ["tab:0", "history:1"])
        let onlyTabs = await index.search(VectorMath.normalized([1, 0, 0, 0]), kinds: [.archive])
        XCTAssertEqual(onlyTabs.map(\.key), ["archive:2"])

        // Clearing history: the next reconcile drops the visit and rewrites the file, even with no model at hand.
        let removed = try await index.reconcile(all.filter { $0.kind != .history }, embedder: nil)
        XCTAssertEqual(removed, 0)
        let count = await index.count
        XCTAssertEqual(count, 2)
        let reopened = SemanticIndex(file: file, dimensions: 4)
        let after = await reopened.search(VectorMath.normalized([1, 0, 0, 0]), limit: 5)
        XCTAssertEqual(after.map(\.key), ["tab:0", "archive:2"])

        // Nothing new: no model call. A changed title is embedded again.
        let before = calls.value
        _ = try await reopened.reconcile(all.filter { $0.kind != .history }, embedder: embedder)
        XCTAssertEqual(calls.value, before)
        var renamed = all.filter { $0.kind != .history }
        renamed[0].title = "Tokyo hotels"
        _ = try await reopened.reconcile(renamed, embedder: embedder)
        XCTAssertEqual(calls.value, before + 1)
        let tokyo = await reopened.search(VectorMath.normalized([0, 0, 1, 0]), limit: 1)
        XCTAssertEqual(tokyo.map(\.key), ["archive:2"])

        await reopened.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFileRoundTripsAndRejectsAnotherSize() {
        let data = SemanticIndex.encode(keys: ["tab:1", "history:https://a/"], kinds: [.tab, .history], fingerprints: [7, 9], descriptions: [0, 11],
                                        vectors: [[0.5, -0.25, 1, 0], [0, 0, 0, 1]], dimensions: 4)
        let decoded = SemanticIndex.decode(data, dimensions: 4)
        XCTAssertEqual(decoded?.0, ["tab:1", "history:https://a/"])
        XCTAssertEqual(decoded?.1, [.tab, .history])
        XCTAssertEqual(decoded?.2, [7, 9])
        XCTAssertEqual(decoded?.3, [0, 11])
        XCTAssertEqual(decoded?.4.first, [0.5, -0.25, 1, 0])
        XCTAssertNil(SemanticIndex.decode(data, dimensions: 8))
        XCTAssertNil(SemanticIndex.decode(data.prefix(data.count - 1), dimensions: 4))
    }

    func testClustersMergeCloseVectorsOnly() {
        let vectors = [[1, 0, 0], [0.95, 0.1, 0], [0, 1, 0], [0.05, 0.98, 0], [0, 0, 1]].map { VectorMath.normalized($0.map(Float.init)) }
        XCTAssertEqual(EmbeddingGroups.clusters(vectors, threshold: 0.7), [[0, 1], [2, 3], [4]])
        XCTAssertEqual(EmbeddingGroups.clusters(vectors, threshold: -1, centred: -2).count, 1)
        XCTAssertEqual(EmbeddingGroups.clusters(vectors, threshold: 1.01).count, 5)
        XCTAssertEqual(EmbeddingGroups.clusters([], threshold: 0.7), [])
    }

    /// The README's failure: eight tabs of one broad subject sit above the similarity check together, so it alone made
    /// one group. Two clusters must also be more alike than the list as a whole.
    func testClustersSplitAListOfOneBroadSubject() {
        let shared: [Float] = [3, 0, 0, 0]
        let css = (0..<4).map { i in VectorMath.normalized(zip(shared, [0, 1, Float(i) * 0.05, 0]).map(+)) }
        let swift = (0..<4).map { i in VectorMath.normalized(zip(shared, [0, 0, Float(i) * 0.05, 1]).map(+)) }
        let vectors = css + swift
        XCTAssertEqual(EmbeddingGroups.clusters(vectors, threshold: 0.68, centred: -2), [Array(0..<8)], "the similarity check alone: one group")
        XCTAssertEqual(EmbeddingGroups.clusters(vectors), [[0, 1, 2, 3], [4, 5, 6, 7]])
    }

    /// A page read this session is embedded with its description; after a relaunch nothing is read until the page loads
    /// again, and its vector stays; a different description is embedded again.
    func testDescriptionsAreEmbeddedOnceAndKept() async throws {
        let calls = LockedCounter()
        let index = SemanticIndex(file: folder.appendingPathComponent("d.vectors"), dimensions: 4)
        let embedder = TableEmbedder(table: table, calls: calls)
        let plain = IndexEntry(kind: .tab, id: "1", title: "Perseverance (rover)", url: "https://en.wikipedia.org/wiki/Perseverance")
        XCTAssertEqual(plain.text, .document(title: nil, text: "Perseverance (rover) (en.wikipedia.org)"))
        var described = plain
        described.description = "Perseverance is a NASA rover exploring Mars."
        XCTAssertEqual(described.text, .document(title: nil, text: "Perseverance (rover) (en.wikipedia.org). Perseverance is a NASA rover exploring Mars."))
        _ = try await index.reconcile([plain], embedder: embedder)
        _ = try await index.reconcile([described], embedder: embedder)
        XCTAssertEqual(calls.value, 2, "the description arrived: embedded again")
        _ = try await index.reconcile([plain], embedder: embedder)
        XCTAssertEqual(calls.value, 2, "no description known: the described vector stays")
        described.description = "Another text."
        _ = try await index.reconcile([described], embedder: embedder)
        XCTAssertEqual(calls.value, 3)
    }

    /// A vague text is about as close to everything: nothing passes the lead over the query's median. A real one stands out.
    func testSearchNeedsALeadOverTheQuerysMedian() async throws {
        let index = SemanticIndex(file: folder.appendingPathComponent("s.vectors"), dimensions: 4)
        let table: [String: [Float]] = ["a": [1, 0, 0, 0], "b": [0, 1, 0, 0], "c": [0, 0, 1, 0], "d": [0, 0, 0, 1], "e": [0.7, 0.7, 0, 0]]
        let all = ["a", "b", "c", "d", "e"].map { IndexEntry(kind: .tab, id: $0, title: $0, url: "") }
        _ = try await index.reconcile(all, embedder: TableEmbedder(table: table, calls: LockedCounter()))
        let vague = await index.search(VectorMath.normalized([1, 1, 1, 1]), minimum: 0.3, lead: 0.25)
        XCTAssertEqual(vague.map(\.key), [], "0.5 against four of five, 0.71 against one: under the median plus 0.25")
        let real = await index.search(VectorMath.normalized([1, 0.1, 0, 0]), minimum: 0.3, lead: 0.25)
        XCTAssertEqual(real.map(\.key), ["tab:a", "tab:e"])
        let floor = await index.search(VectorMath.normalized([1, 0.1, 0, 0]), minimum: 0.9, lead: 0.25)
        XCTAssertEqual(floor.map(\.key), ["tab:a"])
    }

    func testNearestAndDuplicateCandidates() {
        let groups: [(id: String, vectors: [[Float]])] = [("db", [[1, 0], [0.9, 0.1]].map(VectorMath.normalized)), ("tokyo", [[0, 1]]), ("empty", [])]
        let nearest = EmbeddingGroups.nearest(VectorMath.normalized([0.8, 0.3]), groups: groups, limit: 5)
        XCTAssertEqual(nearest.map(\.id), ["db", "tokyo"])
        let pairs = EmbeddingGroups.duplicateCandidates([[1, 0], [0.999, 0.04], [0, 1]].map(VectorMath.normalized), threshold: 0.92)
        XCTAssertEqual(pairs.map { [$0.0, $0.1] }, [[0, 1]])
    }
}
