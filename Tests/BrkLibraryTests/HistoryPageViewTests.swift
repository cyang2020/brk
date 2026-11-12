import AppKit
import BrkBase
@testable import BrkDomain
import XCTest
@testable import BrkLibrary

/// Owner: F5. The History page in its card (Q05-a): the navigation, the day cards with their visits, the search, the
/// checks and what each control dispatches.
@MainActor
final class HistoryPageViewTests: XCTestCase {
    private var sent: [Command] = []
    /// Fri 30 Oct 2026 15:05 UTC.
    private let now = Instant(milliseconds: 1_793_372_700_000)
    private let card = CGRect(x: 238, y: 10, width: 1032, height: 756)
    private let page = PageID(window: WindowID("w"), item: ItemID("h"))
    private let minute: Int64 = 60_000

    private func makeView() -> HistoryPageView {
        let view = HistoryPageView(dispatch: { [unowned self] in self.sent.append($0) })
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        view.calendar = utc
        return view
    }

    private var visits: [HistoryRow] {
        [
            HistoryRow(url: URL(string: "http://127.0.0.1:9/page2.html")!, title: "Fixture Page 2", visitedAt: now),
            HistoryRow(url: URL(string: "http://127.0.0.1:9/index.html")!, title: "Fixture Home", visitedAt: Instant(milliseconds: now.milliseconds - 5 * minute)),
            HistoryRow(url: URL(string: "https://swift.org/blog/")!, title: "", visitedAt: Instant(milliseconds: now.milliseconds - 40 * minute)),
            HistoryRow(url: URL(string: "https://resources.arc.net/notes")!, title: "Release notes", visitedAt: Instant(milliseconds: now.milliseconds - 26 * 60 * minute)),
        ]
    }

    private func shown(_ root: NSView) -> [NSView] { root.descendants.filter { !$0.isHiddenOrHasHiddenAncestor } }
    private func texts(_ root: NSView) -> [String] { shown(root).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty } }
    private func rows(_ root: NSView) -> [HistoryVisitRow] { shown(root).compactMap { $0 as? HistoryVisitRow } }

    /// a click opens the visit in a new tab; ⋮ offers More from this site and Remove from history; checked visits
    /// delete together; the search narrows and keeps each visit's index
    func testVisitActionsSearchAndChecks() throws {
        let view = makeView()
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        rows(view)[0].click()
        XCTAssertEqual(sent, [.library(.openHistoryVisit(URL(string: "http://127.0.0.1:9/page2.html")!))])
        let menu = rows(view)[3].actions()
        XCTAssertEqual(menu.items.map(\.title), ["More from this site", "Remove from history"])
        let remove = menu.items[1]
        _ = (remove.target as? NSObject)?.perform(remove.action!, with: remove)
        XCTAssertEqual(sent.last, .library(.removeHistory(URL(string: "https://resources.arc.net/notes")!)))
        view.toggle(0)
        view.toggle(2)
        XCTAssertTrue(texts(view).contains("2 selected"))
        sent = []
        view.deleteSelected()
        XCTAssertEqual(sent, [.library(.removeHistory(URL(string: "http://127.0.0.1:9/page2.html")!)),
                              .library(.removeHistory(URL(string: "https://swift.org/blog/")!))])
        view.searchField.stringValue = "release"
        view.rebuild()
        XCTAssertEqual(rows(view).map { $0.accessibilityIdentifier() }, ["history-3"])
        // The same page keeps the search; another clears it.
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        XCTAssertEqual(view.searchField.stringValue, "release")
        view.render(visits, page: PageID(window: WindowID("w"), item: ItemID("other")), in: card, scheme: .light, now: now)
        XCTAssertEqual(view.searchField.stringValue, "")
    }

    /// like Chromium's page (Q05-a), a page shows once a day at its latest visit; removing that row removes the day's
    /// other visits to it, not other days'
    func testAPageShowsOnceADayAtItsLatestVisit() throws {
        let view = makeView()
        let home = URL(string: "http://127.0.0.1:9/index.html")!, other = URL(string: "http://127.0.0.1:9/page2.html")!
        let ago = { (m: Int64) in Instant(milliseconds: self.now.milliseconds - m * self.minute) }
        let visits = [
            HistoryRow(id: HistoryVisitID("v0"), url: other, title: "Fixture Page 2", visitedAt: ago(1)),
            HistoryRow(id: HistoryVisitID("v1"), url: home, title: "Fixture Home", visitedAt: ago(0)),   // newest, not first
            HistoryRow(id: HistoryVisitID("v2"), url: home, title: "Fixture Home", visitedAt: ago(3)),
            HistoryRow(id: HistoryVisitID("v3"), url: other, title: "Fixture Page 2", visitedAt: ago(4)),
            HistoryRow(id: HistoryVisitID("v4"), url: home, title: "Fixture Home", visitedAt: ago(26 * 60)),
        ]
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        XCTAssertEqual(rows(view).map { $0.accessibilityIdentifier() }, ["history-1", "history-0", "history-4"])
        XCTAssertEqual(rows(view).map { $0.texts[0] }, ["3:05 PM", "3:04 PM", "1:05 PM"])
        let menu = rows(view)[0].actions()
        let remove = menu.items[1]
        _ = (remove.target as? NSObject)?.perform(remove.action!, with: remove)
        XCTAssertEqual(sent, [.library(.removeHistoryVisit(HistoryVisitID("v1"))), .library(.removeHistoryVisit(HistoryVisitID("v2")))])
        sent = []
        view.toggle(0)
        view.deleteSelected()
        XCTAssertEqual(sent, [.library(.removeHistoryVisit(HistoryVisitID("v0"))), .library(.removeHistoryVisit(HistoryVisitID("v3")))])
    }

    /// a check follows its visit: a visit recorded before Delete does not move the check to a neighbour, and a checked
    /// visit that goes away is no longer checked (checks were list positions, so Delete removed other visits)
    func testChecksFollowTheirVisitWhenTheListChanges() throws {
        let view = makeView()
        let swift = URL(string: "https://swift.org/blog/")!
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        view.toggle(2)
        let newer = [HistoryRow(url: URL(string: "https://new.example/")!, title: "New", visitedAt: now)] + visits
        view.render(newer, page: page, in: card, scheme: .light, now: now)
        XCTAssertEqual(rows(view).filter(\.isChecked).map { $0.accessibilityIdentifier() }, ["history-3"])
        view.deleteSelected()
        XCTAssertEqual(sent, [.library(.removeHistory(swift))])
        sent = []
        view.toggle(3)
        view.render(newer.filter { $0.url != swift }, page: page, in: card, scheme: .light, now: now)
        XCTAssertFalse(texts(view).contains("1 selected"))
        view.deleteSelected()
        XCTAssertEqual(sent, [])
    }

    /// a visit opened from the page is a link, not a typed visit: the command bar counts typed visits four times over
    func testOpeningAVisitIsNotATypedVisit() throws {
        let size = CGSize(width: 1280, height: 776)
        let ctx = { Context(now: self.now, newID: { UUID().uuidString }) }
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: size), ctx: ctx()).state
        let window = project(state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows.keys.sorted()[0]
        let view = HistoryPageView(dispatch: { state = reduce(state, .user(window, $0), ctx()).state })
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        rows(view)[0].click()
        let focused = try XCTUnwrap(state.resolveTab(.focused, in: window))
        XCTAssertEqual(state.address(of: focused, in: window, for: .visible), URL(string: "http://127.0.0.1:9/page2.html"), "opens in a new focused tab")
        XCTAssertEqual(state.session.typedPending, [])
    }

    /// a long history builds its first 150 visits (Chromium's history page asks for 150 at a time) and the next 150 as
    /// the list scrolls to its end; the search still looks through every visit. Every keystroke, check and new visit
    /// rebuilt a row for each visit in the profile's history.
    func testALongHistoryBuildsItsRowsAPageAtATime() throws {
        let view = makeView()
        let many = (0..<1000).map {
            HistoryRow(url: URL(string: "https://site\($0).example/")!, title: "Page \($0)", visitedAt: Instant(milliseconds: now.milliseconds - Int64($0) * minute))
        }
        view.render(many, page: page, in: card, scheme: .light, now: now)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(rows(view).count, 150)
        let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
        let list = try XCTUnwrap(scroll.documentView)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: list.frame.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(rows(view).count, 300)
        view.searchField.stringValue = "Page 999"
        view.searchField.onChange()
        XCTAssertEqual(rows(view).map { $0.texts[1] }, ["Page 999"])
    }

    /// Delete browsing data asks first, then clears this profile's history; Tabs from other devices says Brk has none
    func testDeleteBrowsingDataAsksFirstAndOtherDevicesIsEmpty() throws {
        let view = makeView()
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        let items = shown(view).compactMap { $0 as? HistoryNavItem }
        XCTAssertEqual(items.map(\.text), ["Brk history", "Tabs from other devices", "Delete browsing data"])
        items[2].performClick(nil)
        XCTAssertTrue(texts(view).contains("Clear this profile's browsing history?"))
        XCTAssertEqual(sent, [])
        view.confirmCancel.performClick(nil)
        XCTAssertFalse(texts(view).contains("Clear this profile's browsing history?"))
        items[2].performClick(nil)
        view.confirmClear.performClick(nil)
        XCTAssertEqual(sent, [.library(.clearHistory)])
        items[1].performClick(nil)
        XCTAssertTrue(rows(view).isEmpty)
        XCTAssertTrue(texts(view).contains(LibraryCopy.otherDevicesEmpty))
    }
}
