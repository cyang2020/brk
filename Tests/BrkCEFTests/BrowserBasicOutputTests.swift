import BrkBase
import Foundation
import XCTest
@testable import BrkCEF

@MainActor final class BrowserBasicOutputTests: XCTestCase {
    @MainActor final class Fixture {
        let outputs = DocumentOutputs()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-output-test-" + UUID().uuidString)
        var updates: [OutputUpdate] = []
        var prompts: [(OutputDestinationPrompt, @MainActor (DestinationAnswer) -> Void)] = []
        var renderings: [(URL, (Result<Void, Error>) -> Void)] = []
        var leases: Set<OutputID> = []
        var available = true
        var request: OutputRequest {
            OutputRequest(id: OutputID("output"), document: DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("owner"), item: ItemID("tab")), generation: 7), sequence: 3), intent: .mhtml, suggestedName: "Fixture")
        }
        var context: ContextEpoch { ContextEpoch(context: .profile(.default), generation: 1) }
        var destination: URL { root.appendingPathComponent("page.mhtml") }
        static let bytes = Data("MIME-Version: 1.0\r\nContent-Type: multipart/related; boundary=fixture\r\n\r\n--fixture\r\nContent-Type: text/html\r\nContent-Location: https://fixture.example/\r\n\r\n<html>Fixture</html>\r\n--fixture--\r\n".utf8)
        init() {
            outputs.available = { [unowned self] _, _ in available }
            outputs.acquire = { [unowned self] id, _ in leases.insert(id); return true }
            outputs.release = { [unowned self] id, _ in leases.remove(id) }
            outputs.publish = { [unowned self] in updates.append($0) }
            outputs.destination = { [unowned self] in prompts.append(($0, $1)) }
            outputs.render = { [unowned self] _, path, done in renderings.append((path, done)) }
        }
        func start() { outputs.start(request, context: context) }
        func accept() { prompts[0].1(.accepted(destination)) }
        func render() throws {
            try Self.bytes.write(to: renderings[0].0)
            renderings[0].1(.success(()))
        }
        func dispose() { try? FileManager.default.removeItem(at: root) }
        var terminals: [OutputResult] { updates.compactMap { if case .terminal(let result) = $0.stage { result } else { nil } } }
    }

    func testRealFileCommitAndLateCancellationPreserveCompletedBytes() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.accept(); try f.render()
        XCTAssertEqual(try Data(contentsOf: f.destination), Fixture.bytes)
        XCTAssertEqual(f.terminals, [.saved(FileReceipt(url: f.destination, bytes: Int64(Fixture.bytes.count)))])
        f.outputs.cancel(f.request.id)
        f.renderings[0].1(.failure(CocoaError(.userCancelled)))
        XCTAssertEqual(f.terminals.count, 1)
        XCTAssertEqual(try Data(contentsOf: f.destination), Fixture.bytes)
        XCTAssertTrue(f.leases.isEmpty)
    }

    func testDuplicateLateDestinationAndDuplicateStartCannotGenerateTwice() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.start()
        XCTAssertEqual(f.prompts.count, 1)
        f.accept(); f.accept()
        XCTAssertEqual(f.renderings.count, 1)
        try f.render()
        XCTAssertEqual(f.terminals.count, 1)
    }

    func testCancellationRetainsWriterLeaseUntilItsActualCallback() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.accept()
        f.outputs.cancel(f.request.id)
        XCTAssertEqual(f.leases, [f.request.id])
        XCTAssertTrue(f.terminals.isEmpty)
        try f.render()
        XCTAssertEqual(f.terminals, [.cancelled(.removed)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
        XCTAssertTrue(f.outputs.isEmpty)
        XCTAssertTrue(f.leases.isEmpty)
    }

    func testRetiredDocumentCancelsPendingPromptAndRejectsDelayedAnswers() {
        let f = Fixture(); defer { f.dispose() }
        f.start()
        f.outputs.sourceGone(f.request.document.browser)
        f.accept()
        XCTAssertTrue(f.renderings.isEmpty)
        XCTAssertEqual(f.terminals, [.cancelled(.absent)])
        XCTAssertTrue(f.leases.isEmpty)
    }

    func testReentryDuringPublicationCreatesNoOrphanDialogOrWriter() {
        for stage in [OutputStage.choosingDestination, .rendering] {
            let f = Fixture(); defer { f.dispose() }
            f.outputs.publish = { [unowned f] update in
                f.updates.append(update)
                if update.stage == stage { f.outputs.cancel(update.id) }
            }
            f.start()
            if stage == .rendering { f.accept() }
            XCTAssertTrue(f.renderings.isEmpty)
            XCTAssertTrue(f.leases.isEmpty)
            XCTAssertEqual(f.terminals.count, 1)
            if stage == .choosingDestination { XCTAssertTrue(f.prompts.isEmpty) }
        }
    }

    func testAnInterveningUserFileIsPreservedAndOutputRemainsRecoverable() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.accept()
        let original = Data("user file".utf8)
        try original.write(to: f.destination)
        try f.render()
        XCTAssertEqual(try Data(contentsOf: f.destination), original)
        guard case .failed(_, .retained(let directory, _))? = f.terminals.first else { return XCTFail("Missing recovery result") }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("payload")), Fixture.bytes)
    }

    func testTimeoutDoesNotInventAWriterBarrierOrPublishTwoTerminals() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.accept()
        f.outputs.reportTimeout()
        XCTAssertEqual(f.terminals.count, 1)
        XCTAssertEqual(f.leases, [f.request.id])
        try f.render()
        XCTAssertEqual(f.terminals.count, 1)
        XCTAssertTrue(f.leases.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.renderings[0].0.path))
    }

    func testContextRevocationDrainsWithoutWritingDestination() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.accept()
        f.outputs.revoke(.profile(.default))
        f.available = false
        XCTAssertTrue(f.outputs.contains(context: .profile(.default)))
        try f.render()
        XCTAssertFalse(f.outputs.contains(context: .profile(.default)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }
}
