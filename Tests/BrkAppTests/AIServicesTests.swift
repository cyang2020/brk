import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class AIServicesTests: XCTestCase {
    func testQuitWaitsForAnAlreadyCancelledOperationToReleaseResources() async throws {
        let engine = FakeEngine(), gate = ReadGate()
        engine.onAIRead = { _ in try await gate.read() }
        var results: [SystemEvent] = []
        let services = AIServices(engine: engine, send: { results.append($0) })
        let page = PageID(window: WindowID("ai-window"), item: ItemID("ai-page"))
        services.read(AIRequestID("ai-request"), document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1))
        while !gate.started { await Task.yield() }
        services.cancel(AIRequestID("ai-request"))
        var enteredStop = false, stopped = false
        let shutdown = Task {
            enteredStop = true
            await services.stop()
            stopped = true
        }
        while !enteredStop { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(stopped, "quit lost ownership of an earlier cancelled operation before it released resources")
        gate.release()
        await shutdown.value
        XCTAssertTrue(stopped)
        XCTAssertTrue(results.isEmpty, "cancelled work delivered a late result")
    }
}

@MainActor
private final class ReadGate {
    private var continuation: CheckedContinuation<AIPageContent, any Error>?
    private(set) var started = false
    func read() async throws -> AIPageContent {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }
    func release() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
