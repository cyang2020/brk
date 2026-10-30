import BrkBase
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor final class TransferOrderingTests: XCTestCase {
    func testPrivateDisposalIsSubmittedBeforeReconcile() throws {
        let h = Harness(); defer { h.cleanUp() }
        h.store.dispatch(.user(h.window, .window(.newIncognito)))
        let window = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let before = h.engine.calls.count
        h.store.dispatch(.user(window, .window(.close)))
        let calls = Array(h.engine.calls.dropFirst(before))
        XCTAssertEqual(calls.first, "forget")
        XCTAssertTrue(calls.dropFirst().contains("reconcile"))
        XCTAssertEqual(h.engine.forgotten.count, 1)
    }
}
