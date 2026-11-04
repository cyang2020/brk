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

    /// the page fills its card: "History", the navigation with Brk history selected, one card per day titled like
    /// Chromium's ("Today - Friday, October 30, 2026"), each visit with its time, title and host; a break line marks
    /// visits more than 15 minutes apart; nil hides the page
    func testTheHistoryPageListsVisitsByDayInItsCard() throws {
        let view = makeView()
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.frame, card)
        XCTAssertEqual(view.accessibilityIdentifier(), "history-page")
        let all = texts(view)
        XCTAssertTrue(all.contains("History"))
        XCTAssertTrue(all.contains("Brk history") && all.contains("Tabs from other devices") && all.contains("Delete browsing data"))
        XCTAssertEqual(all.filter { $0.contains("October") }, ["Today - Friday, October 30, 2026", "Yesterday - Thursday, October 29, 2026"])
        let shownRows = rows(view)
        XCTAssertEqual(shownRows.map { $0.accessibilityIdentifier() }, ["history-0", "history-1", "history-2", "history-3"])
        XCTAssertEqual(shownRows[0].texts, ["3:05 PM", "Fixture Page 2", "127.0.0.1:9"])
        XCTAssertEqual(shownRows[2].texts, ["2:25 PM", "swift.org/blog", "swift.org"], "an untitled visit shows its address")
        let today = try XCTUnwrap(shown(view).compactMap { $0 as? HistoryDayCard }.first)
        XCTAssertEqual(today.height, 69 + 3 * 36 + 15 + 8, "a break between 3:00 PM and 2:25 PM")
        view.render(nil, page: nil, in: nil, scheme: .light, now: now)
        XCTAssertTrue(view.isHidden)
    }

    /// a click opens the visit in a new tab; ⋮ offers More from this site and Remove from history; checked visits
    /// delete together; the search narrows and keeps each visit's index
    func testVisitActionsSearchAndChecks() throws {
        let view = makeView()
        view.render(visits, page: page, in: card, scheme: .light, now: now)
        rows(view)[0].click()
        XCTAssertEqual(sent, [.commandBar(.submit("http://127.0.0.1:9/page2.html"))])
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
