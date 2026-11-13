import BrkBase
import Foundation
import XCTest
@testable import BrkCoreEngine

@MainActor final class TransferReentryReviewTests: XCTestCase {
    func testReentrantCancelDuringInitialPublishMustNotCreateAnUnanswerableSheet() throws {
        let f = TransfersTests.Fixture(); defer { f.transfers.publish = { _ in }; f.dispose() }
        f.transfers.publish = { update in
            f.updates.append(update)
            if case .choosingDestination = update.stage { f.transfers.cancel(update.id) }
        }
        let owner = DownloadOwner(browser: f.owner.browser, context: f.owner.context, policy: .ask(startingAt: f.directory))
        let decision = ReenteringDecision()
        decision.onResolve = { destination in
            if destination == nil { f.update(f.item(cancelled: true), owner: owner) }
        }
        f.transfers.decision(f.item(), name: "file.bin", owner: owner, available: { true }, callback: decision)
        XCTAssertEqual(decision.resolutions.count, 1)
        XCTAssertNil(decision.resolutions[0])
        print("REPRO prompts created after cancellation:", f.replies.count)
        print("REPRO operations remaining after synchronous cancellation:", f.transfers.operations.count)
        XCTAssertTrue(f.transfers.isEmpty)
        XCTAssertTrue(f.replies.isEmpty, "Cancelled operation must not issue a new destination prompt")
        if let reply = f.replies.first {
            reply.1(.cancelled)
            print("REPRO orphan sheet dismissed after user answers:", f.dismissals.contains(reply.0.ticket))
            XCTAssertTrue(f.dismissals.contains(reply.0.ticket), "No operation remains to dismiss this new sheet")
        }
        f.update(f.item(cancelled: true))
    }

    final class ReenteringDecision: TransferDecision {
        var onResolve: ((URL?) -> Void)?
        var resolutions: [URL?] = []
        func resolve(_ destination: URL?) { resolutions.append(destination); onResolve?(destination) }
    }

    func testSynchronousCompletionDuringContinueMustNotPublishTerminalTwice() throws {
        let f = TransfersTests.Fixture(); defer { f.dispose() }
        let decision = ReenteringDecision()
        decision.onResolve = { destination in
            guard let destination else { return }
            try! Data(repeating: 65, count: 100).write(to: destination)
            f.update(f.item(received: 100, complete: true))
        }
        f.transfers.decision(f.item(), name: "file.bin", owner: f.owner, available: { true }, callback: decision)
        let ends = f.updates.filter { if case .terminal = $0.stage { return true }; return false }
        print("REPRO terminal publications during synchronous continue:", ends.count)
        XCTAssertEqual(ends.count, 1)
        XCTAssertTrue(f.leases.isEmpty)
    }
}
