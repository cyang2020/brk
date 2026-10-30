import BrkBase
import CefKit
import Foundation
import XCTest
@testable import BrkCEF

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
                  interrupted: Bool = false, named: Bool = true) -> CefDownload {
            CefDownload(id: id, url: named ? URL(string: "https://example.com/file") : nil,
                        receivedBytes: received, totalBytes: 100, isComplete: complete, isCanceled: cancelled, fullPath: nil,
                        isInterrupted: interrupted, isInProgress: !complete && !cancelled && !interrupted,
                        interruptionReason: interrupted ? 9 : 0, suggestedName: named ? "file.bin" : "")
        }
        func update(_ item: CefDownload, _ control: Control? = nil, owner: DownloadOwner? = nil) {
            transfers.update(item, owner: owner ?? self.owner, available: { [unowned self] in available }, control: control)
        }
        @discardableResult func decide(_ item: CefDownload, owner: DownloadOwner? = nil) -> Decision {
            let d = Decision()
            transfers.decision(item, name: "file.bin", owner: owner ?? self.owner, available: { [unowned self] in available }, callback: d)
            return d
        }
    }

    func testEarlyUpdateBuffersDetailsAndFreezesOriginalPolicy() throws {
        let f = Fixture(); defer { f.dispose() }
        let first = Control(), next = Control()
        f.update(f.item(named: false), first)
        XCTAssertTrue(f.updates.isEmpty)
        let changed = DownloadOwner(browser: f.owner.browser, context: ContextEpoch(context: .profile(ProfileID("new")), generation: 2),
                                    policy: .directory(f.directory.appendingPathComponent("wrong")))
        let decision = f.decide(f.item(received: 0), owner: changed)
        let path = try XCTUnwrap(decision.resolutions.first!)
        XCTAssertEqual(path.deletingLastPathComponent().deletingLastPathComponent().path, f.directory.path)
        XCTAssertEqual(f.updates.last?.owner, f.owner)
        XCTAssertEqual(f.updates.last?.stage, .receiving(TransferProgress(received: 10, total: 100)))
        f.update(f.item(received: 20), next)
        XCTAssertEqual(first.releases, 1)
        f.update(f.item(received: 0, cancelled: true))
        XCTAssertEqual(next.releases, 1)
        XCTAssertEqual(decision.resolutions.count, 1)
        XCTAssertTrue(f.leases.isEmpty)
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

    func testPendingSheetSourceGoneRejectsStaleAndDuplicateAnswers() throws {
        let f = Fixture(); defer { f.dispose() }
        let owner = DownloadOwner(browser: f.owner.browser, context: f.owner.context, policy: .ask(startingAt: f.directory))
        let decision = f.decide(f.item(), owner: owner)
        let reply = try XCTUnwrap(f.replies.first)
        f.available = false; f.transfers.sourceGone(owner.browser)
        reply.1(.accepted(f.directory.appendingPathComponent("late")))
        reply.1(.accepted(f.directory.appendingPathComponent("later")))
        XCTAssertEqual(decision.resolutions.count, 1); XCTAssertNil(decision.resolutions[0])
        XCTAssertEqual(f.dismissals, [reply.0.ticket])
        f.update(f.item(cancelled: true), owner: owner)
        XCTAssertTrue(f.leases.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.path))
    }

    func testAcceptedAnswerIsOneShotAndNativeOwnerAvailabilityIsRequired() throws {
        let f = Fixture(); defer { f.dispose() }
        let owner = DownloadOwner(browser: f.owner.browser, context: f.owner.context, policy: .ask(startingAt: f.directory))
        let decision = f.decide(f.item(), owner: owner)
        f.replies[0].1(.accepted(f.directory.appendingPathComponent("chosen")))
        f.replies[0].1(.cancelled)
        XCTAssertEqual(decision.resolutions.count, 1)
        XCTAssertFalse(f.transfers.operations.values.first!.cancelling)
        f.update(f.item(cancelled: true))
        f.available = false
        let denied = f.decide(f.item(2))
        XCTAssertEqual(denied.resolutions.count, 1); XCTAssertNil(denied.resolutions[0])
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

    func testInterruptedIsDistinctAndTimeoutRetainsWriterOwnership() throws {
        let f = Fixture(); defer { f.dispose() }
        f.decide(f.item()); f.update(f.item(interrupted: true))
        XCTAssertEqual(f.updates.last?.stage, .terminal(.interrupted(reason: "CEF interruption 9", .removed)))
        let d = f.decide(f.item(2)); let c = Control(); f.update(f.item(2), c)
        f.transfers.reportTimeout()
        guard case .terminal(.failed(_, .retained(let directory, _))) = f.updates.last?.stage else { return XCTFail("timeout erased file ownership") }
        XCTAssertEqual(directory, d.resolutions[0]!.deletingLastPathComponent())
        XCTAssertEqual(c.releases, 0); XCTAssertEqual(f.leases.count, 1)
        f.transfers.browserClosed(f.owner.browser)
        XCTAssertEqual(c.releases, 1); XCTAssertTrue(f.leases.isEmpty)
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
    func testLateTerminalAfterTimeoutReleasesWriterWithoutPublishingASecondTerminal() throws {
        let f = Fixture(); defer { f.dispose() }
        f.decide(f.item()); let c = Control(); f.update(f.item(), c)
        f.transfers.reportTimeout()
        let published = f.updates.count
        f.update(f.item(cancelled: true))
        XCTAssertEqual(f.updates.count, published)
        XCTAssertEqual(c.releases, 1)
        XCTAssertTrue(f.leases.isEmpty)
    }
    func testDestinationCreationFailureIsReportedAsFailureAfterNativeCancellation() throws {
        let f = Fixture(); defer { f.dispose() }
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: true)
        let file = f.directory.appendingPathComponent("not-a-directory")
        try Data("user".utf8).write(to: file)
        let owner = DownloadOwner(browser: f.owner.browser, context: f.owner.context, policy: .directory(file))
        let d = f.decide(f.item(), owner: owner)
        XCTAssertNil(d.resolutions[0])
        f.update(f.item(cancelled: true), owner: owner)
        guard case .terminal(.failed(_, .absent)) = f.updates.last?.stage else { return XCTFail("destination error was labelled cancelled") }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "user")
    }

}
