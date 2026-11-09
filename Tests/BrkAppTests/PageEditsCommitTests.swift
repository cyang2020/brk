import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// What a page saves of itself is applied as a system event, whatever window showed it: while Brk quits (user input is
/// dropped then) and after its window has gone from the state, a page committing its edits still saves.
@MainActor
final class PageEditsCommitTests: XCTestCase {
    func testAPagesSaveDuringTheQuitStillLands() throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let conversation = AIRequestID("c")
        let page = AIPageID("p")
        var stored = StoredConversation(id: conversation, profile: .default, title: "Notes", createdAt: Instant(milliseconds: 0), tabs: true)
        stored.agent = .claude
        let record = AIPageRecord(id: page, title: "Notes", html: harness.directory.appendingPathComponent("p.html"), height: 200, data: nil,
                                  conversation: conversation, profile: .default, createdAt: Instant(milliseconds: 0), readPages: false)
        harness.store.dispatch(.system(.conversationsLoaded([stored], [record])))
        harness.store.prepareForTermination()
        harness.store.dispatch(.user(harness.window, .commandBar(.open(.newTab))))
        XCTAssertNil(harness.store.snapshot.windows[harness.window]?.overlay, "other input is dropped while quitting")
        harness.store.dispatch(.user(harness.window, .assist(.pageSave(page, #"{"note":"wait for a sale"}"#))))
        XCTAssertEqual(harness.store.state.savedPages[page]?.saved, #"{"note":"wait for a sale"}"#)
        harness.store.dispatch(.user(WindowID("a window already gone"), .assist(.pageSave(page, #"{"note":"from a closed window"}"#))))
        XCTAssertEqual(harness.store.state.savedPages[page]?.saved, #"{"note":"from a closed window"}"#)
        XCTAssertNotNil(AppStore.pageSave(.assist(.pageSave(page, "{}"))))
        XCTAssertNil(AppStore.pageSave(.assist(.keepPage(page))))
    }
}
