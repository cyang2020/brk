import BrkBase
import XCTest
@testable import BrkDomain

/// Issue #10: a page that quit Brk while it loaded was loaded again by every launch, so Brk quit on every launch.
/// After a run that did not finish its quit, the pages a launch would load stay held until the person asks for them.
final class HeldPagesTests: XCTestCase {
    private let chatGPT = URL(string: "https://chatgpt.com/")!

    private func savedWithChatGPTShown() -> (file: Data, tab: ItemID) {
        let d = Driver()
        let tab = d.todayIDs[0]
        d.page(tab, .committed(chatGPT))
        return (d.savedFile, tab)
    }

    /// After an unfinished quit the shown page is not loaded: the card says why, and Reload loads it at its address.
    func test_launchAfterUnfinishedQuitHoldsTheShownPageUntilReload() {
        let (file, tab) = savedWithChatGPTShown()
        let r = Driver(file: file, holdShownPages: true)
        let page = PageID(window: r.window, item: tab)
        XCTAssertEqual(r.view.content.panes.map(\.content), [.held(page)])
        XCTAssertFalse(r.snapshot.pages.contains { $0.id == page }, "a held page must not reach the engine")
        XCTAssertEqual(r.view.space.today.rows.count, 1, "the tab itself stays in the sidebar")

        r.user(.page(.reload(.item(tab), ignoringCache: false)))
        XCTAssertEqual(r.view.content.panes.map(\.content), [.page(page)])
        XCTAssertEqual(r.snapshot.pages.first { $0.id == page }?.initialURL, chatGPT)
    }

    /// After a normal quit the same file loads the shown page at once, as before.
    func test_launchAfterFinishedQuitLoadsTheShownPage() {
        let (file, tab) = savedWithChatGPTShown()
        let r = Driver(file: file)
        let page = PageID(window: r.window, item: tab)
        XCTAssertEqual(r.view.content.panes.map(\.content), [.page(page)])
        XCTAssertTrue(r.snapshot.pages.contains { $0.id == page })
    }

    /// Picking another tab loads that one; the held tab, picked again, loads like any other tab.
    func test_aHeldPageLoadsOnceItsTabIsPickedAgain() {
        let d = Driver()
        let held = d.todayIDs[0]
        d.page(held, .committed(chatGPT))
        let other = d.open("example.com")
        d.user(.tab(.focus(held)))
        let r = Driver(file: d.savedFile, holdShownPages: true)
        XCTAssertEqual(r.view.content.panes.map(\.content), [.held(PageID(window: r.window, item: held))])

        r.user(.tab(.focus(other)))
        XCTAssertEqual(r.view.content.panes.map(\.content), [.page(PageID(window: r.window, item: other))])
        r.user(.tab(.focus(held)))
        XCTAssertEqual(r.view.content.panes.map(\.content), [.page(PageID(window: r.window, item: held))])
        XCTAssertTrue(r.snapshot.pages.contains { $0.id == PageID(window: r.window, item: held) })
    }

    /// A split with a held pane: clicking the other pane loads only that one; the held pane loads when it is picked.
    func test_inASplitTheNeighbourOfAHeldPaneDoesNotLoadIt() {
        let d = Driver()
        let left = d.todayIDs[0]
        d.page(left, .committed(chatGPT))
        let right = d.open("example.com")
        d.user(.tab(.focus(left)))
        d.user(.split(.joinRow(right, onto: left)))
        XCTAssertEqual(d.view.content.panes.count, 2, "the fixture is a split of two pages")
        let r = Driver(file: d.savedFile, holdShownPages: true)
        let leftPage = PageID(window: r.window, item: left), rightPage = PageID(window: r.window, item: right)
        func content(_ tab: ItemID) -> PaneContent? { r.view.content.panes.first { $0.tab == tab }?.content }
        XCTAssertEqual(content(left), .held(leftPage))
        XCTAssertEqual(content(right), .held(rightPage))

        r.user(.page(.reload(.item(right), ignoringCache: false)))
        r.user(.tab(.focus(right)))
        XCTAssertEqual(content(left), .held(leftPage), "picking the right pane must not load the left one")
        XCTAssertEqual(content(right), .page(rightPage))
        r.user(.tab(.focus(left)))
        XCTAssertEqual(content(left), .page(leftPage))
    }

    /// Brk's own pages have no browser that could have quit Brk: History shows as usual after an unfinished quit.
    func test_brksOwnPagesAreNotHeld() {
        let d = Driver()
        let tab = d.todayIDs[0]
        d.page(tab, .committed(HistoryPage.url))
        let r = Driver(file: d.savedFile, holdShownPages: true)
        XCTAssertEqual(r.view.content.panes.map(\.content), [.history(PageID(window: r.window, item: tab))])
    }
}
