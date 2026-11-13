import BrkBase
import Foundation
import XCTest
@testable import BrkCoreEngine

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

    /// Back from a #fragment (or a pushState address) to the document's first address: the pill, Copy URL and the saved
    /// tab kept the fragment address, because a return to the first address was taken for no change.
    func testBackToTheFirstAddressAfterAnInPageChangeCommitsIt() {
        var state = MainDocumentState(browser: token)
        _ = state.allowed(first, redirect: false); _ = state.started(first); _ = state.finished(first)
        let fragment = URL(string: first.absoluteString + "#section")!
        XCTAssertEqual(state.addressChanged(fragment, loading: false).last, .committed(fragment))
        state.prepareNavigation()
        XCTAssertEqual(state.addressChanged(first, loading: false).last, .committed(first))
    }
}
