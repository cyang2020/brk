import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class ImportSyncIOTests: XCTestCase {
    func testCredentialTransactionRollsBackOnlyItsOwnWritesAndCountsDuplicates() throws {
        let source = try SidebarImport.parse(Data("url,username,password\nhttps://example.test/,owned,fixture-secret\nhttps://example.test/other,owned,fixture-secret-2\n".utf8), format: .passwordsCSV)
        var created: [Data] = [], removed: [Data] = []
        var call = 0
        XCTAssertThrowsError(try ImportedPasswordTransaction.apply(source.passwords, stillValid: { true }, add: { _ in
            call += 1
            if call == 2 { throw SidebarDataError.invalid("Injected storage failure") }
            let reference = Data([1]); created.append(reference); return reference
        }, remove: { removed.append($0); return true }))
        XCTAssertEqual(removed, created)
        call = 0
        let count = try ImportedPasswordTransaction.apply(source.passwords, stillValid: { true }, add: { _ in
            call += 1; return call == 1 ? nil : Data([2])
        }, remove: { _ in XCTFail("Successful writes must remain"); return true })
        XCTAssertEqual(count, 1)
        var valid = true; removed = []
        XCTAssertThrowsError(try ImportedPasswordTransaction.apply(source.passwords, stillValid: { valid }, add: { _ in valid = false; return Data([3]) }, remove: { removed.append($0); return true }))
        XCTAssertEqual(removed, [Data([3])])
    }
    func testTwoOwnedReplicasRetryAndAtomicReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let a = SidebarSyncIO(), b = SidebarSyncIO()
        let one = SidebarSyncDocument(records: ["item-a": SidebarSyncRecord(stamp: SidebarSyncStamp(counter: 1, replica: "replica-a"),
            value: SidebarSyncValue(payload: .tab(title: "Owned A", url: URL(string: "https://example.test/a")!, icon: nil), parent: "favorites", order: 0))])
        let two = SidebarSyncDocument(records: ["item-b": SidebarSyncRecord(stamp: SidebarSyncStamp(counter: 1, replica: "replica-b"),
            value: SidebarSyncValue(payload: .tab(title: "Owned B", url: URL(string: "https://example.test/b")!, icon: nil), parent: "favorites", order: 1))])
        // Owned local checkpoints, independent of the shared transport files.
        for (device, document) in [("a", one), ("b", two)] {
            let path = root.appendingPathComponent(device)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try SidebarDataCodec.encodeSync(document).write(to: path.appendingPathComponent("outbox"), options: .atomic)
        }
        _ = try await a.exchange(folder: shared, replica: "replica-a", document: one)
        let receivedB = try await b.exchange(folder: shared, replica: "replica-b", document: two)
        let receivedA = try await a.exchange(folder: shared, replica: "replica-a", document: receivedB)
        XCTAssertEqual(receivedA.records.count, 2)
        XCTAssertEqual(receivedA, receivedB)
        let before = try Data(contentsOf: shared.appendingPathComponent("replica-a.brksync.json"))
        let retry = try await a.exchange(folder: shared, replica: "replica-a", document: receivedA)
        XCTAssertEqual(retry, receivedA)
        XCTAssertEqual(try Data(contentsOf: shared.appendingPathComponent("replica-a.brksync.json")), before)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: shared.path).contains { $0.hasSuffix(".tmp") })
        var deletion = receivedB
        deletion.records["item-a"] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: 2, replica: "replica-b"), value: nil)
        _ = try await b.exchange(folder: shared, replica: "replica-b", document: deletion)
        let stale = try await a.exchange(folder: shared, replica: "replica-a", document: one)
        XCTAssertNil(stale.records["item-a"]?.value)
        XCTAssertEqual(stale.records.count, 2)
    }

    func testInvalidPeerDoesNotOverwriteLastReplicaAndTemporaryFilesAreIgnored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = SidebarSyncIO(), document = SidebarSyncDocument()
        _ = try await io.exchange(folder: root, replica: "owned", document: document)
        let output = root.appendingPathComponent("owned.brksync.json"), before = try Data(contentsOf: output)
        try Data("unfinished".utf8).write(to: root.appendingPathComponent(".brksync-crash.tmp"))
        _ = try await io.exchange(folder: root, replica: "owned", document: document)
        try Data("not JSON".utf8).write(to: root.appendingPathComponent("bad.brksync.json"))
        do { _ = try await io.exchange(folder: root, replica: "owned", document: document); XCTFail("Accepted malformed peer") } catch {}
        XCTAssertEqual(try Data(contentsOf: output), before)
    }

    func testSymlinkReplicaIsRejectedAndMissingFolderIsAnError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("source")
        try SidebarDataCodec.encodeSync(SidebarSyncDocument()).write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.brksync.json"), withDestinationURL: target)
        let io = SidebarSyncIO()
        do { _ = try await io.exchange(folder: root, replica: "owned", document: SidebarSyncDocument()); XCTFail("Accepted symlink") } catch {}
        do { _ = try await io.exchange(folder: root.appendingPathComponent("missing"), replica: "owned", document: SidebarSyncDocument()); XCTFail("Accepted unavailable folder") } catch {}
        XCTAssertEqual(try Data(contentsOf: target), try SidebarDataCodec.encodeSync(SidebarSyncDocument()))
    }
}
