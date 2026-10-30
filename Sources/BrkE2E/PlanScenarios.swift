import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Scenarios 0 to 9: the Electron plan's done predicate (electron-v1:e2e/arc.spec.ts) on the control socket.
enum PlanScenarios {
    static let inset = Metrics.content.inset.value
    static let radius = Metrics.content.cornerRadius.value
    static let sidebarWidth = Metrics.sidebar.defaultWidth.value

    /// 0: one window; one dock item and one current Today row; `sidebar` and `card-0` on screen; a full-size capture.
    @Sendable static func launchSmoke(_ app: AppUnderTest) throws {
        let windows = app.hello?.windows.count ?? 0
        try expect(windows == 1, "hello lists \(windows) windows, expected 1")
        let v = try app.view()
        try expect(v.dock.count == 1, "the dock has \(v.dock.count) items, expected 1")
        try expect(v.space.today.rows.count == 1, "Today has \(v.space.today.rows.count) rows, expected 1")
        guard case .tab(let row) = v.space.today.rows[0] else { throw Check(description: "the Today row is not a tab") }
        try expect(row.status == .current, "the Today row's status is \(row.status), expected current")
        let n = try app.native()
        _ = try visible(n, .sidebar)
        _ = try visible(n, .card(0))
        let shot = try app.screenshot("launch-smoke")
        try expect(Double(shot.width) >= n.contentSize.width && Double(shot.height) >= n.contentSize.height,
                   "the capture is \(shot.width)x\(shot.height) px, smaller than the \(n.contentSize) pt content")
    }

    /// 1: card-0 inset 10 from the sidebar and the window, radius 6, the corner shows the background, the page is white;
    /// the page's surface holds Chromium's two views (CEF only).
    @Sendable static func oneCard(_ app: AppUnderTest) throws {
        try app.settle()
        let v = try app.view()
        let n = try app.native()
        let size = n.contentSize
        try expect(v.sidebar.width == sidebarWidth, "sidebar width \(v.sidebar.width), expected \(sidebarWidth)")
        let card = try visible(n, .card(0))
        let expected = CGRect(x: sidebarWidth + inset, y: inset, width: size.width - sidebarWidth - 2 * inset, height: size.height - 2 * inset)
        try expect(near(card.frame, expected), "card-0 is at \(card.frame), expected \(expected)")
        try expect(card.cornerRadius == radius, "card-0 radius \(card.cornerRadius), expected \(radius)")
        let computed = n.computed.cards.first?.rect
        try expect(computed.map { near($0, card.frame) } == true, "computed card \(computed.map { "\($0)" } ?? "none") differs from actual \(card.frame)")

        let corner = try app.pixel(CGPoint(x: card.frame.minX + 1, y: card.frame.minY + 1))
        let outside = try app.pixel(CGPoint(x: card.frame.minX + 1, y: card.frame.minY - 3))
        try expect(distance(outside, white) > 24, "the background next to the card is \(outside), too close to white for the corner check")
        try expect(distance(corner, outside) <= 24,
                   "pixel 1 pt inside the card corner is \(corner), the background just outside is \(outside): the corner is not cut")
        let mid = try app.pixel(cardProbe(card.frame))
        try expect(distance(mid, white) <= 3, "the card's page area is \(mid), expected white")
        app.passed("card frame, radius, cut corner and white page")
        try app.screenshot("one-card")

        try app.requireCEF("PageFacts.embeddedViews lists Chromium's two views")
        guard let page = currentTab(v).map({ PageID($0.id) }), let facts = n.pages[page] else {
            throw Check(description: "native().pages has no facts for the current page")
        }
        try expect(facts.embeddedViews.count == 2, "embedded views \(facts.embeddedViews), expected Chromium's two")
    }

    /// 2: Cmd+T shows `command-bar` at `computed.commandBar` (766 wide, centred) with the input focused; the URL and
    /// Return add a current Today row; the bar closes; the page was created.
    @Sendable static func newTab(_ app: AppUnderTest) throws {
        let before = todayIDs(try app.view())
        try app.press("cmd+t")
        try app.waitUntil("Cmd+T to open the command bar") { isCommandBar(try app.view().overlay) }
        try app.waitUntil("command-bar on screen at computed.commandBar with its input focused") {
            let n = try app.native()
            guard let computed = n.computed.commandBar else { throw Check(description: "computed.commandBar is nil") }
            let bar = try visible(n, .commandBar)
            try expect(near(bar.frame, computed), "command-bar at \(bar.frame), computed \(computed)")
            try expect(computed.width == Metrics.commandBar.width.value, "command bar width \(computed.width), expected \(Metrics.commandBar.width.value)")
            try expect(abs(computed.midX - n.computed.contentArea.midX) <= 0.5 && abs(computed.midY - n.computed.contentArea.midY) <= 0.5,
                       "command bar \(computed) is not centred in the content area \(n.computed.contentArea)")
            try expect(n.firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier), "first responder is \(n.firstResponder)")
            return true
        }
        try app.screenshot("command-bar")
        let url = app.site.url("page2.html")
        try app.type(url.absoluteString)
        try app.press("return")
        var row: TabRow?
        try app.waitUntil("Today to gain one row") {
            let v = try app.view()
            row = tabRows(v.space.today.rows).first { !before.contains($0.id) }
            try expect(v.space.today.rows.count == before.count + 1 && row != nil,
                       "Today has \(v.space.today.rows.count) rows, expected \(before.count + 1)")
            return true
        }
        try expect(row!.status == .current, "the new row's status is \(row!.status), expected current")
        try expect(row!.url == url, "the new row's URL is \(row!.url?.absoluteString ?? "nil"), expected \(url.absoluteString)")
        try app.waitUntil("the command bar to close") {
            let v = try app.view(), n = try app.native()
            return v.overlay == nil && !isShown(n, .commandBar)
        }
        try app.onCEF("the title \"Fixture Page 2\"") { try waitForTitle(app, row!.id, "Fixture Page 2") }
        let log = try app.pageLog()
        try expect(log.contains { $0.page == PageID(row!.id) && $0.kind == .created }, "pageLog has no created entry for \(row!.id)")
        try app.screenshot("new-tab")
    }

    /// 3: Cmd+D moves the current Today tab to the end of Pinned (inside `section-pinned`, cannot reset); again back.
    @Sendable static func pinToggle(_ app: AppUnderTest) throws {
        guard let id = tabRows(try app.view().space.today.rows).first(where: { $0.status == .current })?.id else {
            throw Check(description: "no current Today tab at launch")
        }
        try app.press("cmd+d")
        try app.waitUntil("the tab to move to Pinned") {
            let v = try app.view()
            return pinnedIDs(v).last == id && !todayIDs(v).contains(id)
        }
        let pinned = tab(id, in: try app.view())
        try expect(pinned?.canReset == false, "the pinned tab's canReset is \(pinned.map { "\($0.canReset)" } ?? "absent"), expected false")
        try app.waitUntil("row-\(id) inside section-pinned") {
            let n = try app.native()
            let section = try visible(n, .section(.pinned)), row = try visible(n, .row(id))
            try expect(contains(section, row), "row \(row.frame) is outside section-pinned \(section.frame)")
            return true
        }
        try app.screenshot("pinned")
        try app.press("cmd+d")
        try app.waitUntil("the tab to move back to Today") {
            let v = try app.view()
            return todayIDs(v).contains(id) && !pinnedIDs(v).contains(id)
        }
        try app.waitUntil("row-\(id) inside section-today") {
            let n = try app.native()
            let section = try visible(n, .section(.today)), row = try visible(n, .row(id))
            try expect(contains(section, row), "row \(row.frame) is outside section-today \(section.frame)")
            return true
        }
    }

    /// 4: a second space with a Drab theme and a tab; a click on the first dock cell shows the first space's rows, hides
    /// the other's, and the background at (4, 200) moves by more than 24 per channel.
    @Sendable static func dockSwitch(_ app: AppUnderTest) throws {
        let start = try app.view()
        let first = start.dock[0].id
        guard let firstTab = start.space.today.rows.first?.id else { throw Check(description: "no Today row at launch") }
        try createSpace(app, title: "Work")
        let workTab = try openTab(app, app.site.url("page2.html"))
        try app.waitUntil("row-\(workTab.id) on screen") { isShown(try app.native(), .row(workTab.id)) }
        let probe = CGPoint(x: 4, y: 200)
        let before = try settledPixel(app, probe)
        try app.click(.dockSpace(first))
        try app.waitUntil("the window to show the first space") { try app.view().space.id == first }
        try app.waitUntil("the first space's row shown and the other's gone") {
            let n = try app.native()
            try expect(isShown(n, .row(firstTab)), "row-\(firstTab) is not on screen")
            try expect(!isShown(n, .row(workTab.id)), "row-\(workTab.id) of the other space is still on screen")
            return true
        }
        try app.waitUntil("the background at \(probe) to change by more than 24") {
            let after = try app.pixel(probe)
            try expect(distance(before, after) > 24, "background \(after) vs \(before) in Work")
            return true
        }
        try app.screenshot("space-switched")
    }

    /// 5: Cmd+S hides the sidebar and the card fills the window inset 10, radius 6; Cmd+S again restores x = width + 10.
    @Sendable static func sidebarToggle(_ app: AppUnderTest) throws {
        let size = try app.native().contentSize
        try app.press("cmd+s")
        try app.waitUntil("Cmd+S to hide the sidebar") { try !app.view().sidebar.visible }
        try app.waitUntil("card-0 to fill the window inset \(inset)") {
            let n = try app.native()
            let card = try visible(n, .card(0))
            let expected = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            try expect(near(card.frame, expected), "card-0 at \(card.frame), expected \(expected)")
            try expect(card.cornerRadius == radius, "card-0 radius \(card.cornerRadius), expected \(radius)")
            try expect(!isShown(n, .sidebar), "the sidebar is still on screen")
            return true
        }
        try app.screenshot("sidebar-hidden")
        try app.press("cmd+s")
        try app.waitUntil("Cmd+S again to show the sidebar") { try app.view().sidebar.visible }
        try app.waitUntil("card-0 back beside the sidebar") {
            let n = try app.native()
            let card = try visible(n, .card(0))
            try expect(card.frame.minX == sidebarWidth + inset, "card-0 x \(card.frame.minX), expected \(sidebarWidth + inset)")
            try expect(card.frame.maxX == size.width - inset, "card-0 right edge \(card.frame.maxX), expected \(size.width - inset)")
            try expect(card.cornerRadius == radius, "card-0 radius \(card.cornerRadius), expected \(radius)")
            _ = try visible(n, .sidebar)
            return true
        }
    }

    /// 6: Ctrl+Shift+= makes a split: two cards at the same y and height, 10 apart; one split row with two panes; the
    /// command bar is open for the empty pane, and the URL fills it.
    @Sendable static func split(_ app: AppUnderTest) throws {
        try app.press("ctrl+shift+=")
        try app.waitUntil("a second card") { isShown(try app.native(), .card(1)) }
        let n = try app.native()
        let left = try visible(n, .card(0)), right = try visible(n, .card(1))
        try expect(left.frame.minY == right.frame.minY && left.frame.height == right.frame.height,
                   "cards differ in y or height: \(left.frame) and \(right.frame)")
        try expect(left.frame.maxX + Metrics.content.splitGap.value == right.frame.minX,
                   "card-0 ends at \(left.frame.maxX), card-1 starts at \(right.frame.minX); expected a gap of \(Metrics.content.splitGap.value)")
        let v = try app.view()
        try expect(v.content.split != nil, "view().content.split is nil")
        let splits = v.space.today.rows.compactMap { if case .split(let s) = $0 { s } else { nil } }
        try expect(splits.count == 1, "Today has \(splits.count) split rows, expected 1")
        try expect(splits[0].panes.count == 2, "the split has \(splits[0].panes.count) panes, expected 2")
        try expect(isCommandBar(v.overlay), "the command bar is not open for the empty pane")
        let url = app.site.url("page2.html")
        try app.type(url.absoluteString)
        try app.press("return")
        var filled: ItemID?
        try app.waitUntil("the empty pane to load \(url.absoluteString)") {
            let v = try app.view()
            guard v.content.panes.count == 2, case .page(let page) = v.content.panes[1].content else {
                throw Check(description: "the second pane is not a page")
            }
            filled = page.item
            try expect(tab(page.item, in: v)?.url == url, "the second pane's URL is \(tab(page.item, in: v)?.url?.absoluteString ?? "nil")")
            return true
        }
        try app.onCEF("the second page's title \"Fixture Page 2\"") { try waitForTitle(app, filled!, "Fixture Page 2") }
        try app.screenshot("split")
    }

    /// 7: with B open, A goes idle; 13 h later A is archived (reason auto, in today's group) and B is not; the archive
    /// page fills the content area; restoring A brings it back to Today.
    @Sendable static func autoArchive(_ app: AppUnderTest) throws {
        guard let a = tabRows(try app.view().space.today.rows).first(where: { $0.status == .current }) else {
            throw Check(description: "no current Today tab at launch")
        }
        let b = try openTab(app, app.site.url("page2.html"))
        try app.advanceClock(seconds: 13 * hour)
        try app.waitUntil("A to be archived after 13 h") { try !todayIDs(app.view()).contains(a.id) }
        try expect(todayIDs(try app.view()).contains(b.id), "B (on screen) was archived too")
        try app.click(.dockLibrary)
        try app.waitUntil("the archive page to open") { isArchive(try app.view().overlay) }
        guard case .archive(let archive)? = try app.view().overlay else { throw Check(description: "the overlay is not the archive") }
        guard let entry = archive.groups.flatMap({ g in g.entries.map { (g.bucket, $0) } }).first(where: { $0.1.url == a.url }) else {
            throw Check(description: "no archive entry for A's URL \(a.url?.absoluteString ?? "nil")")
        }
        try expect(entry.1.reason == .auto, "A's entry has reason \(entry.1.reason), expected auto")
        try expect(entry.0 == .today, "A's entry is in group \(entry.0), expected today")
        try app.waitUntil("the archive page at computed.contentArea with A in archive-group-today") {
            let n = try app.native()
            let page = try visible(n, .archive)
            try expect(near(page.frame, n.computed.contentArea), "archive at \(page.frame), content area \(n.computed.contentArea)")
            let group = try visible(n, .archiveGroup(.today)), row = try visible(n, .archiveEntry(entry.1.id))
            try expect(contains(group, row), "archive-entry \(row.frame) is outside archive-group-today \(group.frame)")
            return true
        }
        try app.screenshot("archive")
        try app.click(.archiveRestore(entry.1.id))
        try app.waitUntil("A back in Today") { try todayIDs(app.view()).contains(a.id) }
    }

    /// 8: Cmd+W on a tab: the row leaves Today, its surface leaves the window, and the page log shows closeRequested
    /// then closed (OnBeforeClose; CEF only).
    @Sendable static func closeTab(_ app: AppUnderTest) throws {
        let t = try openTab(app, app.site.url("page2.html"))
        try app.settle()
        let page = PageID(t.id)
        try expect(try app.native().pages[page] != nil, "native().pages has no surface for the new tab")
        try app.press("cmd+w")
        try app.waitUntil("the row to leave Today") { try !todayIDs(app.view()).contains(t.id) }
        try app.waitUntil("the page's surface to leave the window") { try app.native().pages[page] == nil }
        try app.waitUntil("pageLog: closeRequested then closed for \(page)") {
            let entries = try app.pageLog().filter { $0.page == page }
            guard let generation = entries.map(\.generation).max() else { throw Check(description: "no pageLog entries") }
            let kinds = entries.filter { $0.generation == generation }.map(\.kind)
            try expect(kinds == [.created, .closeRequested, .closed], "pageLog kinds \(kinds)")
            return true
        }
        try app.requireCEF("OnBeforeClose for the closed browser")
    }

    /// 9: two spaces, a pinned tab, a failed load, page2 current, width 300; after flush and restart everything is the
    /// same, and only the current tab has a page (lazy restore).
    @Sendable static func restart(_ app: AppUnderTest) throws {
        try createSpace(app, title: "Work")
        let home = try openTab(app, app.site.url("index.html?home"))   // not the launch tab's URL
        let page2 = try openTab(app, app.site.url("page2.html"))
        try app.dispatch(.tab(.focus(home.id)))
        try app.waitUntil("home to be current") { try currentTab(app.view())?.id == home.id }
        try app.press("cmd+d")
        try app.waitUntil("home to be pinned") { try pinnedIDs(app.view()).contains(home.id) }
        let fail = try openTab(app, app.site.url("fail"))
        try app.waitUntil("the /fail tab to stop loading") { try tab(fail.id, in: app.view())?.loading == false }
        try app.dispatch(.tab(.focus(page2.id)))
        try app.waitUntil("page2 to be current") { try currentTab(app.view())?.id == page2.id }
        try app.dispatch(.sidebar(.resize(width: 300)))
        try app.waitUntil("the sidebar width to be 300") { try app.view().sidebar.width == 300 }
        try app.settle()

        let before = RestoreSummary(try app.view())
        try expect(before.dock.count == 2, "dock \(before.dock), expected two spaces")
        try expect(before.pinned.map(\.id) == [home.id.rawValue], "pinned \(before.pinned), expected only home")
        try expect(before.today.contains { $0.id == fail.id.rawValue }, "Today \(before.today) lacks the /fail tab")
        try expect(before.current == page2.id.rawValue, "current \(before.current ?? "nil"), expected page2")
        try app.flush()
        app.passed("two spaces, a pinned tab, a failed load, page2 current, width 300")
        try app.restart()

        try app.waitUntil("the restored window to equal the one before restart") {
            let after = RestoreSummary(try app.view())
            try expect(after == before, "after restart \(after), before \(before)")
            return true
        }
        let pages = Set(try app.native().pages.keys)
        try expect(pages == [PageID(page2.id)], "native().pages after restart is \(pages.map(\.description).sorted()), expected only page2")
        let created = Set(try app.pageLog().filter { $0.kind == .created }.map(\.page))
        try expect(created == [PageID(page2.id)], "pages created after restart: \(created.map(\.description).sorted()), expected only page2 (lazy restore)")
        if app.engine == .stub { app.note("the stub loads /fail like any URL and titles pages by host, so the failed load is not exercised") }
        try app.screenshot("restored")
    }

    /// What scenario 9 compares across a restart.
    struct RestoreSummary: Equatable, CustomStringConvertible {
        struct Tab: Equatable { let id: String, url: String, title: String }
        let dock: [String]
        let space: String
        let pinned: [Tab]
        let today: [Tab]
        let current: String?
        let width: Double

        init(_ v: WindowSnapshot) {
            func tabs(_ rows: [Row]) -> [Tab] {
                tabRows(rows).map { Tab(id: $0.id.rawValue, url: $0.url?.absoluteString ?? "", title: $0.title) }
            }
            dock = v.dock.map { "\($0.id):\($0.title)" }
            space = v.space.id.rawValue
            pinned = tabs(v.space.pinned.rows)
            today = tabs(v.space.today.rows)
            current = currentTab(v)?.id.rawValue
            width = v.sidebar.width
        }

        var description: String {
            "dock \(dock), space \(space), pinned \(pinned.map(\.id)), today \(today.map { "\($0.id) \($0.url) \"\($0.title)\"" }), current \(current ?? "nil"), width \(width)"
        }
    }
}
