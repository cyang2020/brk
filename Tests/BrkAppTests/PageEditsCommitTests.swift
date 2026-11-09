import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// While Brk quits, user input is dropped, except what a page saves of itself: the quit makes pages commit their edits
/// first, and those saves must reach the page's record before the state is written.
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
        harness.store.dispatch(.user(harness.window, .assist(.inTab(conversation, .pageSave(page, #"{"note":"from the tab"}"#)))))
        XCTAssertEqual(harness.store.state.savedPages[page]?.saved, #"{"note":"from the tab"}"#)
        XCTAssertTrue(AppStore.isPageSave(.assist(.pageSave(page, "{}"))))
        XCTAssertFalse(AppStore.isPageSave(.assist(.keepPage(page))))
    }
}
