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
        Scenario("R49-PinnedReset", "Reset all tabs in this Space (menu) resets top-level, nested-folder, split and unloaded pinned tabs", cefOnly: "real navigation", pinnedReset),
        Scenario("R49-PinnedPeek", "Collapse Pinned Section hides Pinned rows; the shown pinned tab stays peeked; Expand restores", cefOnly: "native sidebar rows", pinnedPeek),
        Scenario("R49-StepKeys", "Opt+Cmd+Down/Up skip a collapsed folder and stop on a split once, no wrap; Ctrl+Cmd+Left/Right wrap at both ends", cefOnly: "native key routing", stepKeys),
        Scenario("R49-Numbers", "Cmd+1 follows the Favorites-in-numbers setting, Cmd+9 is the last item, Ctrl+Cmd+2 jumps to Space 2", cefOnly: "native key routing", numbers),
        Scenario("R49-Rename", "rename from the menu and the context menu: Return keeps, Escape restores, a Favorite and a folder rename, a collapsed folder opens", cefOnly: "native rename field", rename),
        Scenario("R49-Drag", "pointer drags reorder Today, nest into a folder, add a Favorite and move to a dock space; no tab lost", cefOnly: "native pointer drags", drag),
        Scenario("R49-Duplicate", "two selected rows duplicate from their context menu right after each original with fresh identity", cefOnly: "native selection and menu", duplicate),
        Scenario("R49-Reveal", "Ctrl+Space scrolls to the current row and focuses the sidebar; arrow keys move, Return returns to the page", cefOnly: "native sidebar focus", reveal),
        Scenario("R49-ClearToday", "Clear keeps the Today tabs any window shows and archives the rest", cefOnly: "two native windows", clearToday),
        Scenario("R49-Titles", "a GitHub Live Folder row shows the shortened title; a user title is kept as typed", cefOnly: "native sidebar row text", titles),
        Scenario("R49-Toasts", "a toast shows in the window that acted, a click dismisses it, it expires after 4 seconds", cefOnly: "two native windows", toasts),
        Scenario("R49-Groups", "a tab group's menu renames it, copies its links and closes it; the group survives a restart", cefOnly: "native group header menu", groups),
        Scenario("R49-WindowMenu", "Zoom, Minimize, Bring All to Front, Hide and Show All act on Brk's own windows and keep page focus", cefOnly: "native window states", windowMenu),
        Scenario("R49-StayOnTop", "Stay on Top raises one window, drops while full screen, comes back after, and survives a restart", cefOnly: "native window level", stayOnTop),
        Scenario("R55-PinnedButton", "a Pinned row that is not current is archived by its x and comes back to its place; the current one's minus closes the page and keeps the row", cefOnly: "native sidebar rows", pinnedButton),
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

    @Sendable static func pinnedReset(_ app: AppUnderTest) throws {
        let top = try loadReady(app, "page2.html?reset=top")
        let nested = try loadReady(app, "page2.html?reset=nested")
        let unloaded = try loadReady(app, "page2.html?reset=unloaded")
        let left = try loadReady(app, "split-tools.html?reset=left")
        try app.press("ctrl+shift+=")
        try app.dispatch(.commandBar(.submit(app.site.url("split-tools.html?reset=right").absoluteString)))
        guard let split = try app.view().content.split else { throw Check(description: "no split") }
        let right = try app.view().content.panes.first { $0.tab != left }!.tab
        try app.waitUntil("the right pane loaded") { try committed(app, S.page(app, right)) == app.site.url("split-tools.html?reset=right") }
        let outer = try newFolder(app, "Outer")
        try app.dispatch(.tabTools(.newNestedFolder(outer)))
        try app.press("cmd+a"); try app.type("Inner"); try app.press("return")
        guard case .folder(let o)? = try app.view().space.pinned.rows.first(where: { $0.id == outer }), let inner = o.children.first?.id else { throw Check(description: "no nested folder") }
        let pinnedRoot = try app.view().space.pinned.root
        for (id, parent) in [(top, pinnedRoot), (split, pinnedRoot), (unloaded, pinnedRoot), (nested, inner)] {
            try app.dispatch(.item(.move(id, to: .into(parent: parent, index: 0))))
        }
        // Every pinned tab leaves its saved page; the unloaded one is then closed and kept pinned.
        for id in [top, nested, unloaded, left, right] { try navigate(app, id, to: "red.html?reset=away-\(id.rawValue)") }
        try app.dispatch(.tab(.close(.item(unloaded))))
        try app.waitUntil("the unloaded pinned tab has no page") { try tab(unloaded, in: app.view())?.loaded == false }
        try expect(try tab(unloaded, in: app.view())?.url?.query?.hasPrefix("reset=away") == true, "the closed pinned tab kept its away address")
        try app.dispatch(.tab(.focus(top)))
        try app.perform(.menuAction("Reset all tabs in this Space"))
        let homes: [(ItemID, String)] = [(top, "page2.html?reset=top"), (nested, "page2.html?reset=nested"), (left, "split-tools.html?reset=left"), (right, "split-tools.html?reset=right")]
        for (id, path) in homes {
            try app.waitUntil("\(path) back") { try committed(app, S.page(app, id)) == app.site.url(path) }
        }
        try expect(try tab(unloaded, in: app.view())?.url == app.site.url("page2.html?reset=unloaded"), "the unloaded tab's row did not go back to its pinned address")
        try expect(try tab(unloaded, in: app.view())?.loaded == false, "Reset loaded an unloaded tab")
        try expect(try S.toast(app) == "Pinned tabs reset", "no Reset toast")
        _ = try app.screenshot("after-reset")
        try app.click(.row(unloaded))
        try app.waitUntil("the unloaded tab opens at its pinned address") { try committed(app, S.page(app, unloaded)) == app.site.url("page2.html?reset=unloaded") }
        app.passed("Tabs > Reset all tabs in this Space: top, nested folder, both split panes, unloaded (row, then on click)")
    }

    // MARK: Q18: the hover button of a Pinned row (Arc: the x archives a row that is not current; the current row's
    // minus closes the page and keeps the row; Restore Last Closed Tab puts an archived Pinned tab back in its place)

    @Sendable static func pinnedButton(_ app: AppUnderTest) throws {
        let first = try loadReady(app, "page2.html?pinned=first")
        let second = try loadReady(app, "page2.html?pinned=second")
        let third = try loadReady(app, "page2.html?pinned=third")
        for id in [third, second, first] { try app.dispatch(.item(.move(id, to: .into(parent: try app.view().space.pinned.root, index: 0)))) }
        let today = try loadReady(app, "red.html?pinned=today")
        func pinned() throws -> [ItemID] { try app.view().space.pinned.rows.map(\.id) }
        try expect(try pinned() == [first, second, third] && shown(app.view()) == today, "setup: \(try pinned())")
        func pressButton(_ id: ItemID) throws {
            let row = try app.native().actual[ViewID.row(id).identifier]!.frame
            try app.hover(CGPoint(x: row.midX, y: row.midY))
            try app.waitUntil("the row's button") { isShown(try app.native(), .rowClose(id)) }
            try app.click(.rowClose(id))
        }
        try pressButton(second)
        try app.waitUntil("the Pinned row that was not current is archived") { try pinned() == [first, third] }
        try expect(try shown(app.view()) == today, "archiving another row changed what is shown")
        _ = try app.screenshot("archived")
        try app.press("cmd+shift+t")
        try app.waitUntil("the restored tab is back between its neighbours") { let p = try pinned(); return p.count == 3 && p.first == first && p.last == third }
        let restored = try pinned()[1]
        try app.waitUntil("the restored tab is shown and loaded") { try shown(app.view()) == restored && tab(restored, in: app.view())?.loaded == true }
        _ = try app.screenshot("restored")
        try pressButton(restored)
        try app.waitUntil("the current Pinned row stays, without its page") { try pinned().count == 3 && tab(restored, in: app.view())?.loaded == false }
        try expect(try shown(app.view()) != restored, "the closed pinned tab is still shown")
        _ = try app.screenshot("closed-and-kept")
        try app.perform(.menuAction("Collapse Pinned Section"))
        try app.waitUntil("Pinned collapsed") { try app.view().space.pinned.collapsed }
        _ = try app.screenshot("collapsed-pointer-away")
        try app.perform(.menuAction("Expand Pinned Section"))
        try app.waitUntil("Pinned expanded") { try !app.view().space.pinned.collapsed }
    }

    // MARK: A012

    @Sendable static func pinnedPeek(_ app: AppUnderTest) throws {
        let first = try loadReady(app, "page2.html?peek=first")
        let second = try loadReady(app, "page2.html?peek=second")
        for id in [second, first] { try app.dispatch(.item(.move(id, to: .into(parent: try app.view().space.pinned.root, index: 0)))) }
        let today = try loadReady(app, "red.html?peek=today")
        try expect(isShown(try app.native(), .row(first)) && isShown(try app.native(), .row(second)), "pinned rows not drawn before collapsing")
        try app.perform(.menuAction("Collapse Pinned Section"))
        try app.waitUntil("Pinned collapsed") { try app.view().space.pinned.collapsed }
        try app.waitUntil("no pinned row drawn") { let n = try app.native(); return !isShown(n, .row(first)) && !isShown(n, .row(second)) }
        try expect(try shown(app.view()) == today, "collapsing changed what is shown")
        _ = try app.screenshot("collapsed")
        // The shown pinned tab stays in view (peeked): Cmd+1 picks the first pinned tab while the section is collapsed.
        try app.press("cmd+1")
        try app.waitUntil("Cmd+1 showed the first pinned tab") { try shown(app.view()) == first }
        let peeked = try app.view().space.pinned
        try expect(peeked.collapsed && peeked.peeked && peeked.rows.map(\.id) == [first], "the peeked section lists \(peeked.rows.map(\.id))")
        try app.waitUntil("only the shown pinned row drawn") { let n = try app.native(); return isShown(n, .row(first)) && !isShown(n, .row(second)) }
        _ = try app.screenshot("peeked")
        try app.click(.row(today))
        try app.waitUntil("back on Today, the peeked row goes") { try !app.view().space.pinned.peeked && !isShown(app.native(), .row(first)) }
        try app.perform(.menuAction("Expand Pinned Section"))
        try app.waitUntil("Pinned expanded") { try !app.view().space.pinned.collapsed }
        try app.waitUntil("both pinned rows drawn") { let n = try app.native(); return isShown(n, .row(first)) && isShown(n, .row(second)) }
        try app.flush(); try app.restart()
        try expect(try !app.view().space.pinned.collapsed, "the expanded state was not kept")
    }

    // MARK: A016, A018

    @Sendable static func stepKeys(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        let hidden = try loadReady(app, "page2.html?step=hidden")
        let pinnedTab = try loadReady(app, "page2.html?step=pinned")
        let outer = try newFolder(app, "Steps")
        try app.dispatch(.item(.move(hidden, to: .into(parent: outer, index: 0))))
        try app.dispatch(.item(.move(pinnedTab, to: .into(parent: try app.view().space.pinned.root, index: Int.max))))
        let left = try loadReady(app, "split-tools.html?step=left")
        try app.press("ctrl+shift+=")
        try app.dispatch(.commandBar(.submit(app.site.url("split-tools.html?step=right").absoluteString)))
        guard let split = try app.view().content.split else { throw Check(description: "no split") }
        _ = left
        let last = try loadReady(app, "red.html?step=last")
        // The folder is collapsed with a real click on its row.
        try app.click(.row(outer))
        try app.waitUntil("the folder collapsed") { folder(outer, in: try app.view().space.pinned.rows)?.collapsed == true }
        // Expected stops: Pinned in order without the collapsed folder's tab, then Today, the split once.
        func stops(_ rows: [Row]) -> [ItemID] {
            rows.flatMap { row -> [ItemID] in
                switch row {
                case .tab(let t): [t.id]
                case .split(let s): [s.id]
                case .folder(let f): f.collapsed ? [] : stops(f.children)
                }
            }
        }
        let v = try app.view()
        let order = stops(v.space.pinned.rows) + stops(v.space.today.rows)
        try expect(!order.contains(hidden) && order.contains(split) && order.contains(home), "fixture order \(order)")
        try app.dispatch(.tab(.focus(order[0])))
        var seen: [ItemID] = [order[0]]
        for i in 1..<order.count {
            if i == 1, WindowServerKeys.allowed { try WindowServerKeys.press(app, KeyChord([.option, .command], .downArrow), window: app.window!) }
            else { try app.press("alt+cmd+down") }
            try app.waitUntil("Opt+Cmd+Down step \(i)") { try shown(app.view()) == order[i] }
            seen.append(order[i])
        }
        try app.press("alt+cmd+down")
        app.sleep(0.4)
        try expect(try shown(app.view()) == order.last, "Opt+Cmd+Down wrapped past the last stop")
        for i in stride(from: order.count - 2, through: 0, by: -1) {
            try app.press("alt+cmd+up")
            try app.waitUntil("Opt+Cmd+Up back to stop \(i)") { try shown(app.view()) == order[i] }
        }
        try app.press("alt+cmd+up")
        app.sleep(0.4)
        try expect(try shown(app.view()) == order.first, "Opt+Cmd+Up wrapped past the first stop")
        try expect(!seen.contains(hidden), "Opt+Cmd+Down stopped on a collapsed folder's tab")
        app.passed("Opt+Cmd+Down/Up: \(order.count) stops, split once, collapsed child skipped, no wrap at either end")

        // Ctrl+Cmd+Left/Right: the linear order of every unit (a collapsed folder's tab included), wrapping at both ends.
        func units(_ rows: [Row]) -> [ItemID] {
            rows.flatMap { row -> [ItemID] in
                switch row {
                case .tab(let t): [t.id]
                case .split(let s): [s.id]
                case .folder(let f): units(f.children)
                }
            }
        }
        // The folder (first in Pinned) holds `hidden`; a collapsed folder may list no children in the view.
        var linear = units(v.space.pinned.rows) + units(v.space.today.rows)
        if !linear.contains(hidden) { linear.insert(hidden, at: 0) }
        try app.dispatch(.tab(.focus(linear.last!)))
        try app.waitUntil("the last unit shown") { try shown(app.view()) == linear.last }
        try app.press("ctrl+cmd+right")
        try app.waitUntil("Ctrl+Cmd+Right from the last unit wraps to the first") { try shown(app.view()) == linear.first }
        try app.press("ctrl+cmd+left")
        try app.waitUntil("Ctrl+Cmd+Left from the first unit wraps to the last") { try shown(app.view()) == linear.last }
        app.passed("Ctrl+Cmd+Right at the end went to the first unit (inside the collapsed folder); Ctrl+Cmd+Left at the start came back to the end")
    }

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

    @Sendable static func reveal(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        for i in 0..<22 { _ = try app.load(app.site.url("page2.html?reveal=\(i)")) }
        try app.settle()
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        // Scroll the list to its top so the current (bottom) row is off screen.
        guard let viewport = try app.native().computed.sidebar?.tablistViewport else { throw Check(description: "no sidebar frames") }
        func onScreen(_ id: ItemID) throws -> Bool {
            guard let f = try S.frame(app, ViewID.row(id).identifier) else { return false }
            return viewport.insetBy(dx: -1, dy: -1).contains(f)
        }
        for delta in [4000.0, -4000.0] where try onScreen(home) {
            _ = try app.send(.scrollGesture(at: CGPoint(x: viewport.midX, y: viewport.midY), horizontal: 0, vertical: delta, cancel: false))
            app.sleep(0.6)
        }
        try expect(try !onScreen(home), "the current row is still on screen after scrolling up")
        try app.press("ctrl+space")
        try app.waitUntil("Ctrl+Space scrolled to the current row") { try onScreen(home) }
        try app.waitUntil("the sidebar has focus") { try app.view().focus == .sidebar && app.native().firstResponder.contains("ListDocumentView") }
        _ = try app.screenshot("revealed")
        let rows = tabRows(try app.view().space.today.rows).map(\.id)
        guard let at = rows.firstIndex(of: home), at > 0 else { throw Check(description: "home is not below another Today row: \(rows)") }
        let above = rows[at - 1]
        try app.press("up")
        try app.waitUntil("Up moved to the row above") { try shown(app.view()) == above }
        try app.press("down")
        try app.waitUntil("Down moved back") { try shown(app.view()) == home }
        try app.press("return")
        try app.waitUntil("Return gave the page its focus") { try pageFocused(app, S.page(app, home)) }
    }

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
        // Clear sits on the Pinned/Today divider (drawn only while Pinned has something) and shows on hover.
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
