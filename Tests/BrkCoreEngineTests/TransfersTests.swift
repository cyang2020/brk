import BrkBase
import Foundation
import XCTest
@testable import BrkCoreEngine

struct FixtureDownload: TransferItem {
    var id: UInt32
    var url: URL?
    var receivedBytes: Int64
    var totalBytes: Int64
    var isComplete: Bool
    var isCanceled: Bool
    var fullPath: String?
    var isInterrupted: Bool
    var isInProgress: Bool
    var interruptionReason: Int
    var suggestedName: String
}

@MainActor final class TransfersTests: XCTestCase {
    final class Decision: TransferDecision {
        var resolutions: [URL?] = []
        func resolve(_ destination: URL?) { resolutions.append(destination) }
    }
    final class Control: TransferControl {
        var cancellations = 0
        var releases = 0
        func cancel() { cancellations += 1 }
        func release() { releases += 1 }
    }
    @MainActor final class Fixture {
        let transfers = Transfers()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-transfers-test-" + UUID().uuidString)
        var updates: [DownloadUpdate] = []
        var replies: [(DownloadDestinationPrompt, @MainActor (DestinationAnswer) -> Void)] = []
        var dismissals: [DestinationTicket] = []
        var leases: Set<DownloadID> = []
        var available = true
        var owner: DownloadOwner {
            DownloadOwner(browser: BrowserToken(page: PageID(window: WindowID("w"), item: ItemID("tab")), generation: 1),
                          context: ContextEpoch(context: .profile(.default), generation: 1), policy: .directory(directory))
        }
        init() {
            transfers.publish = { [unowned self] in updates.append($0) }
            transfers.prompt = { [unowned self] in replies.append(($0, $1)) }
            transfers.dismiss = { [unowned self] in dismissals.append($0) }
            transfers.acquire = { [unowned self] id, _ in leases.insert(id); return true }
            transfers.release = { [unowned self] id, _ in leases.remove(id) }
        }
        func dispose() { try? FileManager.default.removeItem(at: directory) }
        func item(_ id: UInt32 = 1, received: Int64 = 10, complete: Bool = false, cancelled: Bool = false,
                  interrupted: Bool = false, named: Bool = true) -> FixtureDownload {
            FixtureDownload(id: id, url: named ? URL(string: "https://example.com/file") : nil,
                        receivedBytes: received, totalBytes: 100, isComplete: complete, isCanceled: cancelled, fullPath: nil,
                        isInterrupted: interrupted, isInProgress: !complete && !cancelled && !interrupted,
                        interruptionReason: interrupted ? 9 : 0, suggestedName: named ? "file.bin" : "")
        }
        func update(_ item: FixtureDownload, _ control: Control? = nil, owner: DownloadOwner? = nil) {
            transfers.update(item, owner: owner ?? self.owner, available: { [unowned self] in available }, control: control)
        }
        @discardableResult func decide(_ item: FixtureDownload, owner: DownloadOwner? = nil) -> Decision {
            let d = Decision()
            transfers.decision(item, name: "file.bin", owner: owner ?? self.owner, available: { [unowned self] in available }, callback: d)
            return d
        }
    }

    func testCancelBeforeControlRetainsIntentAndUsefulBytes() throws {
        let f = Fixture(); defer { f.dispose() }
        let decision = f.decide(f.item(received: 28))
        let id = try XCTUnwrap(f.updates.last?.id)
        f.transfers.cancel(id)
        XCTAssertEqual(f.updates.last?.stage, .cancelling(TransferProgress(received: 28, total: 100)))
        XCTAssertFalse(f.leases.isEmpty)
        let control = Control(); f.update(f.item(received: 0), control)
        XCTAssertEqual(control.cancellations, 1)
        f.update(f.item(received: 0, cancelled: true))
        XCTAssertEqual(control.releases, 1)
        XCTAssertEqual(f.updates.last?.stage, .terminal(.cancelled(.removed)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: decision.resolutions[0]!.path))
    }

    func testTwoOperationsCancelOnlyOneAndKeepBrowserUntilLastCompletion() throws {
        let f = Fixture(); defer { f.dispose() }
        let d1 = f.decide(f.item(1)), d2 = f.decide(f.item(2))
        let c1 = Control(), c2 = Control()
        f.update(f.item(1), c1); f.update(f.item(2), c2)
        let id = try XCTUnwrap(f.updates.first?.id)
        f.transfers.cancel(id)
        XCTAssertEqual(c1.cancellations, 1); XCTAssertEqual(c2.cancellations, 0)
        f.update(f.item(1, cancelled: true))
        XCTAssertEqual(f.leases.count, 1)
        f.available = false; f.transfers.sourceGone(f.owner.browser)
        try Data(repeating: 65, count: 100).write(to: d2.resolutions[0]!)
        f.update(f.item(2, received: 100, complete: true))
        guard case .terminal(.completed(let receipt)) = f.updates.last?.stage else { return XCTFail("not completed") }
        XCTAssertEqual(try Data(contentsOf: receipt.url).count, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: d1.resolutions[0]!.path))
        XCTAssertEqual(c1.releases, 1); XCTAssertEqual(c2.releases, 1)
        XCTAssertTrue(f.leases.isEmpty)
    }

    func testCompletionWinsCancelRaceAndTombstoneRejectsAllLateCallbacks() throws {
        let f = Fixture(); defer { f.dispose() }
        let decision = f.decide(f.item())
        try Data(repeating: 42, count: 100).write(to: decision.resolutions[0]!)
        f.transfers.cancel(f.updates.last!.id)
        f.update(f.item(received: 100, complete: true))
        let count = f.updates.count
        let late = Control(); f.update(f.item(), late)
        let duplicate = f.decide(f.item())
        XCTAssertEqual(f.updates.count, count)
        XCTAssertEqual(late.releases, 1); XCTAssertEqual(late.cancellations, 0)
        XCTAssertEqual(duplicate.resolutions.count, 1); XCTAssertNil(duplicate.resolutions[0])
        XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent("file.bin")).count, 100)
    }

    func testPrivateRevocationIsImmediateAndNewEpochIndependent() throws {
        let f = Fixture(); defer { f.dispose() }
        let old = DownloadOwner(browser: f.owner.browser, context: ContextEpoch(context: .incognito(PrivateSessionID("old")), generation: 1), policy: .ask(startingAt: f.directory))
        let d = f.decide(f.item(), owner: old)
        f.transfers.revoke(old.context.context)
        f.replies[0].1(.accepted(f.directory.appendingPathComponent("private-late")))
        XCTAssertNil(d.resolutions[0]); XCTAssertEqual(d.resolutions.count, 1)
        let next = DownloadOwner(browser: BrowserToken(page: old.browser.page, generation: 2),
                                 context: ContextEpoch(context: .incognito(PrivateSessionID("new")), generation: 2), policy: .directory(f.directory))
        let fresh = f.decide(f.item(), owner: next)
        XCTAssertNotNil(fresh.resolutions[0])
        let rejected = f.decide(f.item(2), owner: old)
        XCTAssertNil(rejected.resolutions[0])
        f.update(f.item(cancelled: true), owner: old)
        XCTAssertEqual(f.leases.count, 1)
        f.update(f.item(cancelled: true), owner: next)
        XCTAssertTrue(f.leases.isEmpty)
    }

    /// Chromium names a download after the path it writes to: a staging name ("payload") showed in Chromium's
    /// download card. The staged file carries the real name, shortened only past the file system's limit.
    func testStagedFileCarriesTheDestinationName() throws {
        let f = Fixture(); defer { f.dispose() }
        let staged = try XCTUnwrap(f.decide(f.item()).resolutions[0])
        XCTAssertEqual(staged.lastPathComponent, "file.bin")
        XCTAssertTrue(staged.path.contains("/.brk-transfer-"))
        let long = String(repeating: "é", count: 120) + ".txt"
        let short = TransferFiles.stagingName(long)
        XCTAssertLessThanOrEqual(short.utf8.count, 200)
        XCTAssertTrue(short.hasSuffix("é.txt"))
    }

    /// A download cut off by a crash or a force quit left its partial file in a hidden .brk-transfer-* folder beside the
    /// destination, and nothing ever removed it. The next download into that folder removes such leftovers; a folder
    /// that holds a person's replaced file is left alone.
    func testAbandonedPartialDownloadIsRemovedByTheNextDownload() throws {
        let f = Fixture(); defer { f.dispose() }
        let old = Date().addingTimeInterval(-2 * 3600)
        let abandoned = f.directory.appendingPathComponent(".brk-transfer-" + UUID().uuidString)
        let partial = abandoned.appendingPathComponent("file").appendingPathComponent("movie.mp4.crdownload")
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 1024).write(to: partial)
        for url in [partial, partial.deletingLastPathComponent(), abandoned] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
        let kept = f.directory.appendingPathComponent(".brk-transfer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: kept.appendingPathComponent("file"), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: kept.appendingPathComponent("replaced"))
        for url in [kept.appendingPathComponent("replaced"), kept.appendingPathComponent("file"), kept] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
        let staged = try XCTUnwrap(f.decide(f.item()).resolutions[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path), "the abandoned partial download is still there")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.appendingPathComponent("replaced").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
    }

    func testCollisionsAndConfirmedReplacementPreserveUnownedFiles() throws {
        let f = Fixture(); defer { f.dispose() }
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: true)
        let target = f.directory.appendingPathComponent("file.bin")
        try Data("original".utf8).write(to: target)
        let d = f.decide(f.item())
        try Data("new".utf8).write(to: d.resolutions[0]!)
        f.update(f.item(complete: true))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: f.directory.appendingPathComponent("file (1).bin"), encoding: .utf8), "new")
        let files = try TransferFiles(destination: target, chooseUnused: false)
        try Data("confirmed".utf8).write(to: files.staging)
        XCTAssertEqual(try files.commit().url, target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "confirmed")
        let racing = try TransferFiles(destination: target, chooseUnused: false)
        try Data("staged".utf8).write(to: racing.staging)
        try Data("collision created later".utf8).write(to: target, options: .atomic)
        XCTAssertThrowsError(try racing.commit())
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "collision created later")
        XCTAssertEqual(try String(contentsOf: racing.staging, encoding: .utf8), "staged")
    }

}
