import BrkBase
import Foundation
import XCTest
@testable import BrkCEF

final class MainDocumentStateTests: XCTestCase {
    private let token = BrowserToken(page: PageID(window: WindowID("window"), item: ItemID("tab")), generation: 1)
    private let first = URL(string: "https://example.com/first")!
    private let next = URL(string: "https://example.com/next")!

    func testOlderAbortCannotFailReplacementBeforeOrAfterItStarts() {
        for abortAfterStart in [false, true] {
            var state = MainDocumentState(browser: token)
            _ = state.allowed(first, redirect: false)
            _ = state.started(first)
            state.prepareNavigation()
            _ = state.allowed(next, redirect: false)
            if abortAfterStart { _ = state.started(next) }
            XCTAssertTrue(state.loadFailed(code: -3, description: "ERR_ABORTED", url: first.absoluteString).isEmpty)
            if !abortAfterStart { _ = state.started(next) }
            _ = state.addressChanged(next, loading: true)
            XCTAssertEqual(state.finished(next), [.committed(next), .documentChanged(.ready(DocumentToken(browser: token, sequence: 2)))])
        }
    }

    func testOlderFailureCannotFailADifferentAcceptedNavigation() {
        var state = MainDocumentState(browser: token)
        _ = state.allowed(first, redirect: false); _ = state.started(first)
        _ = state.allowed(next, redirect: false)
        XCTAssertTrue(state.loadFailed(code: -2, description: "old failure", url: first.absoluteString).isEmpty)
        _ = state.started(next)
        XCTAssertTrue(state.finished(next).contains(.committed(next)))
    }

    func testFailedCurrentNavigationCannotCommitItsErrorDocument() {
        var state = MainDocumentState(browser: token)
        _ = state.allowed(first, redirect: false); _ = state.started(first)
        XCTAssertTrue(state.loadFailed(code: -2, description: "failure", url: first.absoluteString).contains(.documentChanged(.unavailable)))
        _ = state.started(first)
        XCTAssertTrue(state.finished(first).isEmpty)
        state.prepareNavigation()
        _ = state.started(next)
        XCTAssertTrue(state.finished(next).contains(.committed(next)))
    }

    func testCancelledAttachmentKeepsTheOriginalDocumentAndSafeAddress() {
        var state = MainDocumentState(browser: token)
        _ = state.allowed(first, redirect: false); _ = state.started(first); _ = state.finished(first)
        _ = state.allowed(next, redirect: false); _ = state.addressChanged(next, loading: true)
        XCTAssertTrue(state.loadFailed(code: -3, description: "attachment", url: next.absoluteString).isEmpty)
        XCTAssertTrue(state.loadingChanged(false).isEmpty)
        let fragment = URL(string: first.absoluteString + "#fragment")!
        XCTAssertEqual(state.addressChanged(fragment, loading: false).last, .committed(fragment))
    }

    func testStopPreventsLateFinishButAllowsANewAttempt() {
        var state = MainDocumentState(browser: token)
        _ = state.allowed(first, redirect: false); _ = state.started(first)
        XCTAssertEqual(state.stopped(), [.documentChanged(.unavailable)])
        XCTAssertTrue(state.finished(first).isEmpty)
        state.prepareNavigation(); _ = state.allowed(next, redirect: false); _ = state.started(next)
        XCTAssertTrue(state.finished(next).contains(.committed(next)))
    }
}
