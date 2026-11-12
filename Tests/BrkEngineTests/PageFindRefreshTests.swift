import BrkBase
import Foundation
import XCTest
@testable import BrkEngine

@MainActor final class PageFindRefreshTests: XCTestCase {
    final class Host: FindHost {
        let frame = FindFrame(frame: "main", document: "doc")
        var finds: [Bool] = []
        var stops: [Bool] = []
        var revisionRequests: [String] = []
        func startFinding(_ text: String, forward: Bool, matchCase: Bool) { finds.append(forward) }
        func stopFinding(clearSelection: Bool) { stops.append(clearSelection) }
        var findFrames: [FindFrame] { [frame] }
        func focusedFindFrame() -> FindFrame? { frame }
        func isCurrent(_ frame: FindFrame) -> Bool { frame == self.frame }
        func sendEditor(to frame: FindFrame, request: String, payload: String) -> Bool {
            if payload.contains("revision") { revisionRequests.append(request) }
            return true
        }
    }

    /// Waits for what PageFind's own timers (the 350 ms page poll, the 80 ms refresh) bring, without a fixed sleep a
    /// loaded machine could outrun.
    private func wait(_ what: String, until done: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !done() {
            guard ContinuousClock.now < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// On a page that keeps changing (a ticker, a chat), every change searched again from the top: the 3rd match went
    /// back to the 1st and the count went blank each time. A recount keeps the active match and the count it shows.
    func testAPageChangeRecountsWithoutMovingTheActiveMatchOrBlankingTheCount() async throws {
        let host = Host()
        var updates: [FindUpdate] = []
        let find = PageFind(host: host) { updates.append($0) }
        defer { find.invalidate() }
        let doc = DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("w"), item: ItemID("p")), generation: 1), sequence: 1)
        find.observe(.documentChanged(.ready(doc)))
        let search = SearchToken(id: SearchID("search"), document: doc)
        func revision(_ request: String, _ value: Int) {
            find.receive(FindEditorMessage(frame: "main", document: "doc", kind: "result", request: request, payload: #"{"status":"revision","revision":\#(value)}"#))
        }
        find.perform(.search(FindRequestID("first"), search, FindQuery(text: "apple"), .page))
        try await wait("the first poll") { !host.revisionRequests.isEmpty }
        let first = try XCTUnwrap(host.revisionRequests.last)
        revision(first, 0)
        try await wait("the first search") { !host.finds.isEmpty }
        XCTAssertEqual(host.finds.count, 1)
        find.nativeResult(id: 1, count: 5, ordinal: 1, final: true)
        find.perform(.step(FindRequestID("second"), search, .next))
        find.nativeResult(id: 2, count: 5, ordinal: 2, final: true)
        find.perform(.step(FindRequestID("third"), search, .next))
        find.nativeResult(id: 3, count: 5, ordinal: 3, final: true)
        // The next poll of the page sees that it changed.
        try await wait("the next poll") { host.revisionRequests.last != first }
        let later = try XCTUnwrap(host.revisionRequests.last)
        host.stops.removeAll(); updates.removeAll()
        revision(later, 1)
        try await wait("the recount") { host.finds.count >= 4 }
        XCTAssertEqual(host.finds.count, 4, "the change was searched again")
        XCTAssertEqual(host.stops, [false], "Chromium keeps the active match as the selection, so the new search starts at it")
        XCTAssertFalse(updates.contains { if case .matches(_, _, count: 0, ordinal: nil, passComplete: false) = $0 { true } else { false } },
                       "the count went blank while it recounted")
    }
}
