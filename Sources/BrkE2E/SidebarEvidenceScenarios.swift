import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-9: native evidence for the sidebar rows the R4-6 review found short of it (REVIEW.md, "证据不足").
/// Setup (loading fixture pages, making folders) may use commands; each user-visible effect is reached at least once
/// through a real key, pointer or menu path, as the review's standard asks.
enum SidebarEvidenceScenarios {
    static let all = [
        Scenario("R49-Rename", "rename from the menu and the context menu: Return keeps, Escape restores, a Favorite and a folder rename, a collapsed folder opens", cefOnly: "native rename field", rename),
        Scenario("R49-Toasts", "a toast shows in the window that acted, a click dismisses it, it expires after 4 seconds", cefOnly: "two native windows", toasts),
    ]

    private typealias S = SidebarReviewScenarios
    static func shown(_ v: WindowSnapshot) -> ItemID? { v.content.split ?? v.content.panes.first?.tab }
    static func loadReady(_ app: AppUnderTest, _ path: String) throws -> ItemID {
        let url = app.site.url(path)
        let item = try app.load(url)
        try app.waitForPageInput(S.page(app, item), at: url)
        return item
    }
    static func committed(_ app: AppUnderTest, _ page: PageID) throws -> URL? {
        guard case .pageObservations(let values) = try app.send(.pageObservations) else { return nil }
        return values[page]?.committedURL
    }
    static func navigate(_ app: AppUnderTest, _ item: ItemID, to path: String) throws {
        try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.commandBar(.open(.editCurrent)))
        try app.dispatch(.commandBar(.submit(app.site.url(path).absoluteString)))
        try app.waitUntil("\(item) at \(path)") { try committed(app, S.page(app, item)) == app.site.url(path) }
    }
    static func folder(_ id: ItemID, in rows: [Row]) -> FolderRow? {
        for row in rows {
            if case .folder(let f) = row {
                if f.id == id { return f }
                if let inner = folder(id, in: f.children) { return inner }
            }
        }
        return nil
    }
    /// A new pinned folder named `title`, through New Folder and typing its name.
    static func newFolder(_ app: AppUnderTest, _ title: String) throws -> ItemID {
        let before = Set(try app.view().space.pinned.rows.map(\.id))
        try app.dispatch(.item(.newFolder))
        guard let id = try app.view().space.pinned.rows.first(where: { $0.kind == .folder && !before.contains($0.id) })?.id else { throw Check(description: "no new folder") }
        try app.waitUntil("the folder's name field") { try app.view().renaming == id }
        try app.press("cmd+a"); try app.type(title); try app.press("return")
        try app.waitUntil("the folder named \(title)") { folder(id, in: try app.view().space.pinned.rows)?.title == title }
        return id
    }
    static func pointer(_ app: AppUnderTest, _ phase: PointerPhase, _ point: CGPoint, window: WindowID? = nil) throws {
        _ = try app.send(.pointer(window: window ?? app.window, phase: phase, point: point))
    }
    /// A pointer drag as SidebarWindow1 does it: press, pass the drag threshold, travel, hold, release.
    static func drag(_ app: AppUnderTest, from: CGPoint, to: CGPoint, check: (() throws -> Void)? = nil) throws {
        try pointer(app, .down, from)
        try pointer(app, .dragged, CGPoint(x: from.x + 6, y: from.y + 4))
        try pointer(app, .dragged, CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2))
        try pointer(app, .dragged, to)
        app.sleep(0.15)
        try check?()
        try pointer(app, .up, to)
    }
    static func pageFocused(_ app: AppUnderTest, _ page: PageID) throws -> Bool {
        let facts = try app.native(page.window)
        return facts.focusedPage == page && facts.pages[page]?.hasKeyboardFocus == true
    }

    // MARK: A011


    // MARK: Q18: the hover button of a Pinned row (Arc: the x archives a row that is not current; the current row's
    // minus closes the page and keeps the row; Restore Last Closed Tab puts an archived Pinned tab back in its place)


    // MARK: A012


    // MARK: A016, A018


    // MARK: A019

    @Sendable static func numbers(_ app: AppUnderTest) throws {
        let favorite = try loadReady(app, "page2.html?number=favorite")
        try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().favorites.root, index: 0))))
        let pinnedTab = try loadReady(app, "page2.html?number=pinned")
        try app.dispatch(.item(.move(pinnedTab, to: .into(parent: try app.view().space.pinned.root, index: 0))))
        let newest = try loadReady(app, "red.html?number=newest")
        let home = tabRows(try app.view().space.today.rows).last!.id
        try expect(try app.view().tabTools.includeFavoritesInNumbers, "Favorites count in the numbers by default")
        try app.press("cmd+1")
        try app.waitUntil("Cmd+1 is the Favorite") { try shown(app.view()) == favorite }
        try app.press("cmd+2")
        try app.waitUntil("Cmd+2 is the pinned tab") { try shown(app.view()) == pinnedTab }
        try app.press("cmd+9")
        try app.waitUntil("Cmd+9 is the last item") { try shown(app.view()) == home }
        try app.dispatch(.tabTools(.preferences(includeFavorites: false, previews: false)))
        try app.press("cmd+1")
        try app.waitUntil("with Favorites left out, Cmd+1 is the pinned tab") { try shown(app.view()) == pinnedTab }
        try app.press("cmd+2")
        try app.waitUntil("and Cmd+2 the newest Today tab") { try shown(app.view()) == newest }
        _ = try app.screenshot("numbers-without-favorites")
        // Numbered spaces.
        let first = try app.view().space.id
        let second = try createSpace(app, title: "Second")
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("back in the first space") { try app.view().space.id == first }
        if WindowServerKeys.allowed { try WindowServerKeys.press(app, KeyChord([.control, .command], .two), window: app.window!) }
        else { try app.press("ctrl+cmd+2") }
        try app.waitUntil("Ctrl+Cmd+2 showed Space 2") { try app.view().space.id == second && app.view().dock.first { $0.active }?.id == second }
        try app.press("ctrl+cmd+1")
        try app.waitUntil("Ctrl+Cmd+1 showed Space 1") { try app.view().space.id == first }
        try app.press("ctrl+cmd+3")
        app.sleep(0.4)
        try expect(try app.view().space.id == first, "Ctrl+Cmd+3 with two spaces moved")
        _ = try app.screenshot("space-1")
    }

    // MARK: A020

    @Sendable static func rename(_ app: AppUnderTest) throws {
        let item = try loadReady(app, "page2.html?rename=tab")
        let original = try tab(item, in: app.view())!.title
        // Tabs > Rename Current Item (the real menu item), then Return.
        try app.perform(.menuAction("Rename Current Item"))
        try app.waitUntil("the rename field") { try app.view().renaming == item && isShown(app.native(), .renameField) }
        try app.press("cmd+a"); try app.type("Renamed tab"); try app.press("return")
        try app.waitUntil("Return kept the title") { try tab(item, in: app.view())?.title == "Renamed tab" && app.view().renaming == nil }
        // The row's menu Rename…, then Escape: the title stays as it was.
        let row = try visible(app.native(), .row(item)).frame
        try S.contextMenu(app, at: S.centre(row), choose: "Rename…")
        try app.waitUntil("the rename field again") { try app.view().renaming == item }
        try app.press("cmd+a"); try app.type("Discarded")
        try app.press("escape")
        try app.waitUntil("Escape left rename") { try app.view().renaming == nil }
        let kept = try tab(item, in: app.view())?.title
        try expect(kept == "Renamed tab", "Escape changed the title to \(String(describing: kept))")
        _ = original
        // A Favorite, from its tile's menu.
        let favorite = try loadReady(app, "page2.html?rename=favorite")
        try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().favorites.root, index: 0))))
        let tile = try visible(app.native(), .favorite(favorite)).frame
        try S.contextMenu(app, at: S.centre(tile), choose: "Rename…")
        try app.waitUntil("the Favorite's rename field") { try app.view().renaming == favorite }
        try app.press("cmd+a"); try app.type("Fav name"); try app.press("return")
        try app.waitUntil("the Favorite renamed") { try app.view().favorites.tiles.first { $0.id == favorite }?.title == "Fav name" }
        // A folder from its menu; then a tab inside it while it is collapsed.
        let box = try newFolder(app, "Box")
        try app.dispatch(.item(.move(item, to: .into(parent: box, index: 0))))
        let boxRow = try visible(app.native(), .row(box)).frame
        try S.contextMenu(app, at: S.centre(boxRow), choose: "Rename…")
        try app.waitUntil("the folder's rename field") { try app.view().renaming == box }
        try app.press("cmd+a"); try app.type("Crate"); try app.press("return")
        try app.waitUntil("the folder renamed") { folder(box, in: try app.view().space.pinned.rows)?.title == "Crate" }
        try app.click(.row(box))
        try app.waitUntil("the folder collapsed") { folder(box, in: try app.view().space.pinned.rows)?.collapsed == true }
        try app.dispatch(.tab(.focus(item)))
        try app.perform(.menuAction("Rename Current Item"))
        try app.waitUntil("renaming the tab inside the collapsed folder opens it") {
            try app.view().renaming == item && folder(box, in: app.view().space.pinned.rows)?.collapsed == false && isShown(app.native(), .renameField)
        }
        _ = try app.screenshot("rename-in-opened-folder")
        try app.press("escape")
        try app.flush(); try app.restart()
        try expect(try tab(item, in: app.view())?.title == "Renamed tab" && app.view().favorites.tiles.first { $0.id == favorite }?.title == "Fav name", "renames did not survive a restart")
    }

    // MARK: A022

    @Sendable static func drag(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        let a = try loadReady(app, "page2.html?drag=a")
        let b = try loadReady(app, "page2.html?drag=b")
        let c = try loadReady(app, "page2.html?drag=c")
        let box = try newFolder(app, "Drop box")
        // One Favorite already, so the tray has its tile row to drop beside.
        try app.dispatch(.item(.move(home, to: .into(parent: try app.view().favorites.root, index: 0))))
        let total = allTabs(try app.view()).count
        // Today is newest first: c, b, a. Drag a onto the top part of c: a goes first.
        let rowC = try visible(app.native(), .row(c)).frame, rowA = try visible(app.native(), .row(a)).frame
        try drag(app, from: S.centre(rowA), to: CGPoint(x: rowC.midX, y: rowC.minY + 6))
        try app.waitUntil("a reordered to the top of Today") { tabRows(try app.view().space.today.rows).first?.id == a }
        _ = try app.screenshot("reordered")
        // b onto the middle of the folder row: into the folder.
        let rowB = try visible(app.native(), .row(b)).frame, boxRow = try visible(app.native(), .row(box)).frame
        try drag(app, from: S.centre(rowB), to: S.centre(boxRow))
        try app.waitUntil("b in the folder") { folder(box, in: try app.view().space.pinned.rows)?.children.contains { $0.id == b } == true }
        // c onto the Favorites tray.
        let tray = try visible(app.native(), .favoritesTray).frame
        let rowC2 = try visible(app.native(), .row(c)).frame
        try drag(app, from: S.centre(rowC2), to: S.centre(tray))
        try app.waitUntil("c a Favorite") { try app.view().favorites.tiles.contains { $0.id == c } }
        _ = try app.screenshot("favorited")
        // a onto a dock space: it moves to that space's Today.
        let first = try app.view().space.id
        let second = try createSpace(app, title: "Drop target")
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("back in the first space") { try app.view().space.id == first }
        let rowA2 = try visible(app.native(), .row(a)).frame
        let cell = try visible(app.native(), .dockSpace(second)).frame
        try drag(app, from: S.centre(rowA2), to: S.centre(cell))
        try app.waitUntil("a left this space") { try tab(a, in: app.view()) == nil }
        try app.dispatch(.space(.focus(second)))
        try app.waitUntil("a at the top of the other space's Today") { try app.view().space.id == second && tabRows(app.view().space.today.rows).first?.id == a }
        try app.dispatch(.space(.focus(first)))
        // Nothing lost or doubled: the moved tab is in the other space.
        try app.waitUntil("first space shown") { try app.view().space.id == first }
        let here = allTabs(try app.view()).map(\.id)
        try expect(here.count == total - 1 && Set(here).count == here.count, "tabs lost or doubled: \(total) before, \(here.count) here plus a in the other space")
        // A folder dropped into its own child is refused: drag the folder onto b (inside it).
        if folder(box, in: try app.view().space.pinned.rows)?.collapsed == true { try app.dispatch(.item(.toggleFolder(box))) }
        let boxRow2 = try visible(app.native(), .row(box)).frame, inside = try visible(app.native(), .row(b)).frame
        try drag(app, from: S.centre(boxRow2), to: S.centre(inside))
        app.sleep(0.4)
        try expect(folder(box, in: try app.view().space.pinned.rows) != nil && folder(box, in: try app.view().space.pinned.rows)?.children.contains { $0.id == b } == true,
                   "a folder dropped into its own child moved")
    }

    // MARK: A024

    @Sendable static func duplicate(_ app: AppUnderTest) throws {
        let a = try loadReady(app, "page2.html?dup=a")
        let b = try loadReady(app, "page2.html?dup=b")
        let c = try loadReady(app, "page2.html?dup=c")
        _ = b
        try app.click(.row(a))
        try app.click(.row(c), modifiers: "cmd")
        try app.waitUntil("two rows selected") { Set(try app.view().tabTools.selected) == [a, c] }
        let before = tabRows(try app.view().space.today.rows).map(\.id)
        let row = try visible(app.native(), .row(c)).frame
        let items = try S.contextMenu(app, at: S.centre(row), choose: "Duplicate")
        try expect(items.contains("Share 2 Items…"), "not the selection's menu: \(items)")
        var after: [TabRow] = []
        try app.waitUntil("two copies") { after = tabRows(try app.view().space.today.rows); return after.count == before.count + 2 }
        let ids = after.map(\.id)
        let fresh = ids.filter { !before.contains($0) }
        try expect(fresh.count == 2, "copies reused identities: \(fresh)")
        for (original, copy) in zip([c, a], fresh) {
            guard let at = ids.firstIndex(of: original) else { throw Check(description: "original gone") }
            try expect(ids[at + 1] == copy, "the copy of \(original) is not right after it: \(ids)")
            try expect(after[at + 1].url == after[at].url, "the copy is at \(String(describing: after[at + 1].url))")
        }
        try app.waitUntil("a copy loads its page") { try committed(app, S.page(app, fresh[0])) == app.site.url("page2.html?dup=c") }
        _ = try app.screenshot("duplicated")
        // An explicit destination (the command the bar's Duplicate rows send; no menu row names one): the top of Pinned.
        let root = try app.view().space.pinned.root
        try app.dispatch(.tabTools(.bulk(.items([a]), .duplicate(.into(parent: root, index: 0)))))
        try app.waitUntil("a copy at the top of Pinned") { try app.view().space.pinned.rows.first.map { tab($0.id, in: try app.view())?.url == app.site.url("page2.html?dup=a") && $0.id != a } == true }
    }

    // MARK: A025


    // MARK: A026

    @Sendable static func clearToday(_ app: AppUnderTest) throws {
        let mine = try loadReady(app, "page2.html?clear=mine")
        let theirs = try loadReady(app, "page2.html?clear=theirs")
        let idle = try loadReady(app, "page2.html?clear=idle")
        let home = tabRows(try app.view().space.today.rows).last!.id
        try app.dispatch(.tab(.focus(mine)))
        let first = app.window!
        let other = try S.newWindow(app, "Cmd+N opens a second window", kind: .standard) { try app.press("cmd+n") }
        _ = try app.send(.dispatch(window: other, command: .tab(.focus(theirs))))
        try app.waitUntil("the second window shows its tab") { try shown(app.view(other)) == theirs }
        _ = try app.send(.activate(window: first))
        app.window = first
        try app.waitUntil("the first window key") { try app.native(first).isKey }
        // Clear sits on the Pinned/Today divider (drawn while Today has tabs) and shows on hover.
        _ = try newFolder(app, "Keeps the divider")
        guard let frames = try app.native().computed.sidebar, let divider = frames.rows.first(where: { $0.kind == .divider })?.rect else {
            throw Check(description: "no Pinned/Today divider")
        }
        let viewport = frames.tablistViewport
        try app.hover(CGPoint(x: viewport.minX + divider.midX, y: viewport.minY + divider.midY))
        try app.waitUntil("Clear on screen") { isShown(try app.native(), .todayClear) }
        try app.click(.todayClear)
        try app.waitUntil("the idle tabs archived") { let ids = todayIDs(try app.view()); return !ids.contains(idle) && !ids.contains(home) }
        let left = todayIDs(try app.view())
        try expect(left.contains(mine) && left.contains(theirs), "Clear archived a tab a window shows: \(left)")
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no archive") }
        let archived = library.archive?.groups.flatMap(\.entries).map(\.url) ?? []
        try expect(archived.contains(app.site.url("page2.html?clear=idle")) && !archived.contains(app.site.url("page2.html?clear=theirs")), "archive holds \(archived)")
        try app.dispatch(.library(.close))
        _ = try app.screenshot("cleared")
    }

    // MARK: A033

    @Sendable static func titles(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Skipped(description: "reading the row's text needs Accessibility for the runner") }
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        try app.dispatch(.tabTools(.site(.connectGitHub(favorite: nil))))
        try S.panel(app, .focus(identifier: ViewID.tabTool("repository").identifier))
        try app.type("fixture/titles")
        try S.panel(app, .button("Connect"))
        var pull: ItemID?
        try app.waitUntil("the Live Folder's pull request") {
            guard let folder = try app.view().space.pinned.rows.first(where: { $0.kind == .folder }), case .folder(let f) = folder,
                  case .tab(let row)? = f.children.first else { return false }
            pull = row.id
            return true
        }
        let row = try tab(pull!, in: app.view())!
        try expect(row.url == URL(string: "https://github.com/fixture/titles/pull/7")! && !row.loaded, "the pull request row: \(row)")
        try expect(row.title == "Shorten fixture titles", "the projected title is \(row.title)")
        func rowText() throws -> [String] { try S.texts(app, in: try visible(app.native(), .row(pull!)).frame) }
        try app.waitUntil("the row's text is the short title") { try rowText().contains("Shorten fixture titles") }
        try expect(!(try rowText()).contains { $0.contains("· GitHub") }, "the row shows GitHub's suffix")
        _ = try app.screenshot("short-title")
        // A title the user types is kept as typed, suffix and all.
        let frame = try visible(app.native(), .row(pull!)).frame
        try S.contextMenu(app, at: S.centre(frame), choose: "Rename…")
        try app.waitUntil("rename field") { try app.view().renaming == pull }
        try app.press("cmd+a"); try app.type("Mine · GitHub"); try app.press("return")
        try app.waitUntil("the user title shown as typed") { try rowText().contains("Mine · GitHub") }
        S.log(app, "row-texts.txt", try rowText().joined(separator: "\n"))
    }

    // MARK: A034

    @Sendable static func toasts(_ app: AppUnderTest) throws {
        let first = app.window!
        let other = try S.newWindow(app, "Cmd+N opens a second window", kind: .standard) { try app.press("cmd+n") }
        _ = try app.send(.activate(window: other))
        app.window = other
        try app.waitUntil("the second window key") { try app.native(other).isKey }
        try app.perform(.menuAction("Reset all tabs in this Space"))
        try app.waitUntil("the toast in the window that acted") { try S.toast(app, other) == "Pinned tabs reset" }
        try expect(try S.toast(app, first) == nil, "the other window shows the toast too")
        let toastFrame = try S.frame(app, ViewID.tabTool("toast").identifier, window: other)
        let area = try app.native(other).computed.contentArea
        try expect(toastFrame != nil && toastFrame!.maxX <= area.maxX + 0.5 && toastFrame!.minY < area.minY + 40, "the toast is not at the content area's top right: \(String(describing: toastFrame)) in \(area)")
        try expect(try S.frame(app, ViewID.tabTool("toast").identifier, window: first) == nil, "the first window draws a toast")
        _ = try app.screenshot("toast", window: other)
        // A click on it dismisses it.
        try app.click(.tabTool("toast"))
        try app.waitUntil("the click dismissed the toast") { try S.toast(app, other) == nil && S.frame(app, ViewID.tabTool("toast").identifier, window: other) == nil }
        // Expiry: shown at 3 s, gone by 5 s of real time.
        try app.perform(.menuAction("Reset all tabs in this Space"))
        try app.waitUntil("the toast again") { try S.toast(app, other) != nil }
        let shownAt = uptime()
        app.sleep(3)
        try expect(try S.toast(app, other) != nil, "the toast left before 3 s")
        try app.waitUntil("the toast expired", timeout: 3) { try S.toast(app, other) == nil }
        let lasted = uptime() - shownAt
        try expect(lasted >= 3.5 && lasted <= 5.5, "the toast lasted \(lasted) s, Brk's is 4 s")
        S.log(app, "expiry.txt", String(format: "toast shown for %.2f s (real time)\n", lasted))
        app.window = first
    }

    // MARK: A035

    @Sendable static func groups(_ app: AppUnderTest) throws {
        let a = try loadReady(app, "page2.html?group=a")
        let b = try loadReady(app, "page2.html?group=b")
        // Brk makes a group from a selection by command; Arc's groups come from Tidy Tabs (Arc Max), not a menu.
        try app.dispatch(.tabTools(.bulk(.items([a, b]), .newFolder(group: true))))
        guard let group = try app.view().space.pinned.rows.first(where: { if case .folder(let f) = $0 { return f.group } else { return false } })?.id else { throw Check(description: "no group") }
        if try app.view().renaming == group { try app.press("cmd+a"); try app.type("Fixture group"); try app.press("return") }
        let header = try visible(app.native(), .row(group)).frame
        try S.contextMenu(app, at: S.centre(header), choose: "Rename Group…")
        try app.waitUntil("the group's rename field") { try app.view().renaming == group }
        try app.press("cmd+a"); try app.type("Reading"); try app.press("return")
        try app.waitUntil("the group renamed") { folder(group, in: try app.view().space.pinned.rows)?.title == "Reading" }
        try app.perform(.pasteboard(nil))
        try S.contextMenu(app, at: S.centre(try visible(app.native(), .row(group)).frame), choose: "Copy All Links")
        try app.waitUntil("both links on the pasteboard") {
            guard case .text(let text) = try app.send(.readPasteboard) else { return false }
            return text.contains(app.site.url("page2.html?group=a").absoluteString) && text.contains(app.site.url("page2.html?group=b").absoluteString)
        }
        _ = try app.screenshot("group")
        // Arc's header (TabGroupHeaderCellView): the title starts 18 in from the sidebar's edge, where a tab's favicon starts.
        let groupRow = try visible(app.native(), .row(group)).frame
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        let screen = CGRect(x: facts.windowFrame.minX + groupRow.minX, y: top + groupRow.minY, width: groupRow.width, height: groupRow.height)
        guard let label = NativeSystemInput.staticTexts(pid: app.hello!.pid).first(where: { $0.text == "Reading" && screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }) else {
            throw Check(description: "no group title on screen")
        }
        let x = label.frame.minX - facts.windowFrame.minX
        try expect(abs(x - 18) <= 2, "the group's title starts at \(x), Arc's at 18")
        // A normal restart keeps the group, its title and its tabs.
        try app.flush(); try app.restart()
        guard let restored = folder(group, in: try app.view().space.pinned.rows) else { throw Check(description: "the group is gone after a restart") }
        try expect(restored.group && restored.title == "Reading" && Set(restored.children.map(\.id)) == [a, b], "after restart: \(restored)")
        try S.contextMenu(app, at: S.centre(try visible(app.native(), .row(group)).frame), choose: "Close Tab Group")
        try app.waitUntil("the group closed into the archive") { try folder(group, in: app.view().space.pinned.rows) == nil && tab(a, in: app.view()) == nil }
        try expect(try S.toast(app) == "Closed Tab Group! Use", "no close toast")
        try app.press("cmd+z")
        try app.waitUntil("Cmd+Z on the toast brought the group back") { try app.view().space.pinned.rows.contains { if case .folder(let f) = $0 { return f.group && f.title == "Reading" } else { return false } } }
    }

    // MARK: A053

    @Sendable static func windowMenu(_ app: AppUnderTest) throws {
        let item = try loadReady(app, "page2.html?window=menu")
        let page = S.page(app, item)
        try app.setWindowFrame(CGRect(x: 320, y: 200, width: 1000, height: 700))
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let start = try app.native().windowFrame
        // Window > Zoom, twice.
        try app.perform(.menuAction("Zoom"))
        try app.waitUntil("Zoom grew the window") { let f = try app.native().windowFrame; return f.width > start.width + 50 || f.height > start.height + 50 }
        try app.perform(.menuAction("Zoom"))
        try app.waitUntil("Zoom again restored it") { near(try app.native().windowFrame, start, tolerance: 2) }
        try app.waitUntil("the page kept focus through Zoom") { try pageFocused(app, page) }
        // Cmd+M minimizes; bringing it back keeps the page focus. The press goes to the key window of the active app, and
        // on this shared machine another task's app can take activation between steps, so the window is made frontmost
        // again right before the press (it was in the implementer's run, by timing).
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try app.press("cmd+m")
        try app.waitUntil("Cmd+M minimized the window") { try app.native().miniaturized }
        _ = try app.send(.activate(window: app.window!))
        try app.waitUntil("the window back from the Dock") { try !app.native().miniaturized && app.native().isKey }
        try app.waitUntil("the page kept focus through Minimize") { try pageFocused(app, page) }
        // Window > Bring All to Front with two windows: both on screen and in front of every other app's window.
        let first = app.window!
        let other = try S.newWindow(app, "a second window", kind: .standard) { try app.press("cmd+n") }
        _ = try app.send(.activate(window: first))
        try app.perform(.menuAction("Bring All to Front"))
        app.sleep(0.5)
        let numbers = try [first, other].map { try app.native($0).appWindows.first { $0.isKey }?.number ?? 0 }
        _ = numbers
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = app.hello!.pid
        let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
        let ours = normal.enumerated().filter { ($0.element[kCGWindowOwnerPID as String] as? Int32) == pid && (($0.element[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) > 400 }
        let firstOther = normal.firstIndex { ($0[kCGWindowOwnerPID as String] as? Int32) != pid } ?? normal.count
        try expect(ours.count >= 2 && ours.allSatisfy { $0.offset < firstOther }, "after Bring All to Front Brk's windows are at \(ours.map(\.offset)), another app's first window at \(firstOther)")
        try app.waitUntil("the first window kept the page focus") { try pageFocused(app, page) }
        _ = try app.send(.dispatch(window: other, command: .window(.close)))
        // Hide (Cmd+H), then Show All only when no other app is hidden, so it changes nothing outside Brk.
        try app.press("cmd+h")
        try app.waitUntil("Cmd+H hid Brk") { try app.native().appHidden }
        let otherHidden = hiddenApps(except: pid)
        if otherHidden.isEmpty {
            try app.perform(.menuAction("Show All"))
            try app.waitUntil("Show All showed Brk") { try !app.native().appHidden }
        } else {
            app.note("Show All not run: other apps are hidden (\(otherHidden.joined(separator: ", "))); it would show them. Brk was shown with activate.")
            _ = try app.send(.activate(window: first))
            try app.waitUntil("Brk shown") { try !app.native().appHidden }
        }
        try WindowServerKeys.ensureFrontmost(app, first)
        try app.waitUntil("the page kept focus through Hide") { try pageFocused(app, page) }
        app.note("Hide Others (Opt+Cmd+H) is not run: it hides every other application on this shared machine, other agents' windows and the user's Arc included.")
    }

    /// Foreground apps other than `pid` that are hidden now (Launch Services' own record, `lsappinfo`), so Show All
    /// is run only when it can change nothing outside Brk.
    static func hiddenApps(except pid: Int32) -> [String] {
        func run(_ arguments: [String]) -> String {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo"); process.arguments = arguments
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return text
        }
        var hidden: [String] = [], name = "", asn = ""
        for line in run(["list"]).components(separatedBy: "\n") {
            if let range = line.range(of: "\" ASN:"), let open = line.firstIndex(of: "\"") {
                name = String(line[line.index(after: open)..<range.lowerBound])
                asn = "ASN:" + line[range.upperBound...].prefix { $0 != ":" }
            }
            guard line.contains("type=\"Foreground\""), let range = line.range(of: "pid = "),
                  let appPid = Int32(line[range.upperBound...].prefix { $0.isNumber }), appPid != pid else { continue }
            if run(["info", "-only", "hidden", asn]).contains("\"Hidden\"=true") { hidden.append(name) }
        }
        return hidden
    }

    // MARK: A055

    @Sendable static func stayOnTop(_ app: AppUnderTest) throws {
        let item = try loadReady(app, "page2.html?top=1")
        let first = app.window!
        let other = try S.newWindow(app, "a second window", kind: .standard) { try app.press("cmd+n") }
        _ = try app.send(.activate(window: first))
        try app.waitUntil("the first window key") { try app.native(first).isKey }
        try app.perform(.menuAction("Stay on Top"))
        try app.waitUntil("the first window floats") { try app.native(first).windowLevel == 3 && app.view(first).stayOnTop }
        try expect(try app.native(other).windowLevel == 0 && !app.view(other).stayOnTop, "the other window floats too")
        try app.waitUntil("the page kept focus") { try pageFocused(app, S.page(app, item)) }
        // Full screen drops the level; leaving full screen puts it back.
        try app.press("ctrl+cmd+f")
        try app.waitUntil("full screen", timeout: 8) { let n = try app.native(first); return n.fullscreen && n.fullscreenTransitioning != true }
        try expect(try app.native(first).windowLevel == 0, "a full-screen window kept the floating level")
        try app.press("ctrl+cmd+f")
        try app.waitUntil("out of full screen", timeout: 8) { let n = try app.native(first); return !n.fullscreen && n.fullscreenTransitioning != true }
        try app.waitUntil("floating again") { try app.native(first).windowLevel == 3 }
        _ = try app.send(.dispatch(window: other, command: .window(.close)))
        // Restart: the window comes back floating; the menu item turns it off.
        try app.flush(); try app.restart()
        try app.waitUntil("floating after restart") { try app.native().windowLevel == 3 && app.view().stayOnTop }
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try app.perform(.menuAction("Stay on Top"))
        try app.waitUntil("Stay on Top off") { try app.native().windowLevel == 0 && !app.view().stayOnTop }
    }
}
