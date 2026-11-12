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

    func testAnInterveningUserFileIsPreservedAndOutputRemainsRecoverable() throws {
        let f = Fixture(); defer { f.dispose() }
        f.start(); f.accept()
        let original = Data("user file".utf8)
        try original.write(to: f.destination)
        try f.render()
        XCTAssertEqual(try Data(contentsOf: f.destination), original)
        guard case .failed(_, .retained(let directory, _))? = f.terminals.first else { return XCTFail("Missing recovery result") }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("file").appendingPathComponent(f.destination.lastPathComponent)), Fixture.bytes)
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

    /// Save Page As checked the saved MHTML by reading, decoding and lowercasing the whole file on the main thread, so a
    /// page of tens of MB stalled the app (0.98 s for 512 MB). The MIME header at the top is enough: nothing past the
    /// first megabyte is read, so a header that only comes after it is not found.
    func testMHTMLCheckReadsOnlyTheHeader() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-output-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let late = root.appendingPathComponent("late.mhtml")
        try (Data(repeating: 0x20, count: 1_048_576) + Fixture.bytes).write(to: late)
        XCTAssertThrowsError(try DocumentOutputs.validate(late, intent: .mhtml), "the check read past the first megabyte")
        // A saved page with its header at the top passes, however long it is (sparse: 512 MB long, no disk used).
        let large = root.appendingPathComponent("large.mhtml")
        try Fixture.bytes.write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 512 * 1_048_576)
        try handle.close()
        XCTAssertNoThrow(try DocumentOutputs.validate(large, intent: .mhtml))
    }

    /// The time limit ran from the command, so a person still choosing a folder in the save panel had the panel closed
    /// under them and the save reported failed. Only the native rendering is timed.
    func testTimeLimitDoesNotRunWhileTheSavePanelIsOpen() throws {
        let f = Fixture(); defer { f.dispose() }
        var dismissals = 0
        f.outputs.dismiss = { _ in dismissals += 1 }
        f.outputs.timeLimit = 0.05
        f.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(dismissals, 0, "the save panel stays open")
        guard f.terminals.isEmpty else { return XCTFail("the save was reported failed while its panel was open: \(f.terminals)") }
        f.accept(); try f.render()
        XCTAssertEqual(f.terminals, [.saved(FileReceipt(url: f.destination, bytes: Int64(Fixture.bytes.count)))])
    }

    /// A print whose rendering passed the time limit kept the page's PDF in the temporary folder for good, private
    /// windows too. Print output is never recovered: once the renderer has answered, its folder goes.
    func testTimedOutPrintLeavesNoPDFBehind() throws {
        let f = Fixture(); defer { f.dispose() }
        f.outputs.timeLimit = 0.05
        let request = OutputRequest(id: OutputID("print"), document: f.request.document, intent: .print, suggestedName: "Fixture")
        f.outputs.start(request, context: f.context)
        let staging = try XCTUnwrap(f.renderings.first?.0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard case .failed(_, let named)? = f.terminals.first else { return XCTFail("the rendering was not timed") }
        XCTAssertEqual(named, .absent, "the failure named a recovery folder that is deleted once the renderer answers")
        try Data("%PDF-1.4".utf8).write(to: staging)
        f.renderings[0].1(.success(()))
        let folder = staging.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("brk-output-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "the page's PDF stayed in \(folder.path)")
        XCTAssertTrue(f.outputs.isEmpty)
    }
}
