import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Round 4, R4-9: the branches of the sidebar rows the R4-6 review found without a unit test (REVIEW.md, "证据不足").
/// The native side is in Sources/BrkE2E/SidebarEvidenceScenarios.swift and LittlePeekEvidenceScenarios.swift.
final class SidebarReviewEvidenceTests: XCTestCase {
    private func folder(_ id: ItemID, in rows: [Row]) -> FolderRow? {
        for row in rows {
            if case .folder(let f) = row { if f.id == id { return f }; if let inner = folder(id, in: f.children) { return inner } }
        }
        return nil
    }
    private func shown(_ d: Driver, in window: WindowID? = nil) -> ItemID? {
        let v = window.map { d.view(of: $0) } ?? d.view
        return v.content.split ?? v.content.panes.first?.tab
    }
    private func newWindow(_ d: Driver) throws -> WindowID {
        let before = Set(d.snapshot.windows.keys)
        d.user(.window(.new))
        return try XCTUnwrap(d.snapshot.windows.keys.first { !before.contains($0) })
    }

    // A011: every pinned tab, in nested folders and split panes, loaded or not, goes back to its pinned address.
    func testResetPinnedReachesNestedFoldersSplitPanesAndUnloadedTabs() throws {
        let d = Driver()
        let top = d.open("https://example.com/top")
        let nested = d.open("https://example.com/nested")
        let unloaded = d.open("https://example.com/unloaded")
        let left = d.open("https://example.com/left")
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://example.com/right")))
        let split = try XCTUnwrap(d.view.content.split)
        let right = try XCTUnwrap(d.paneIDs.first { $0 != left })
        d.page(right, .committed(url("https://example.com/right")))
        d.user(.item(.newFolder))
        let outer = d.pinnedIDs[0]
        d.user(.tabTools(.newNestedFolder(outer)))
        let inner = try XCTUnwrap(folder(outer, in: d.view.space.pinned.rows)?.children.first?.id)
        let root = d.view.space.pinned.root
        for (id, parent) in [(top, root), (split, root), (unloaded, root), (nested, inner)] { d.user(.item(.move(id, to: .into(parent: parent, index: 0)))) }
        for id in [top, nested, unloaded, left, right] {
            d.user(.tab(.focus(id)))
            d.user(.commandBar(.open(.editCurrent))); d.user(.commandBar(.submit("https://example.org/away")))
            d.page(id, .committed(url("https://example.org/away")))
        }
        d.user(.tab(.close(.item(unloaded))))
        XCTAssertFalse(d.loadedIDs.contains(unloaded))
        d.user(.tabTools(.resetPinned))
        for (id, address) in [(top, "https://example.com/top"), (nested, "https://example.com/nested"), (left, "https://example.com/left"), (right, "https://example.com/right")] {
            XCTAssertEqual(d.state.session.live[PageID(window: d.window, item: id)]?.requestedURL, url(address), "\(address) was not requested again")
        }
        XCTAssertEqual(d.row(unloaded)?.url, url("https://example.com/unloaded"), "the unloaded tab's row shows its pinned address")
        XCTAssertFalse(d.loadedIDs.contains(unloaded), "Reset does not load an unloaded tab")
    }

    // A012: collapsed Pinned lists only the shown pinned item (peeked); nothing when a Today tab is shown.
    func testCollapsedPinnedPeeksOnlyTheShownPinnedItem() throws {
        let d = Driver()
        let first = d.open("https://example.com/first")
        let second = d.open("https://example.com/second")
        for id in [second, first] { d.user(.item(.move(id, to: .into(parent: d.view.space.pinned.root, index: 0)))) }
        let today = d.open("https://example.com/today")
        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertTrue(d.view.space.pinned.collapsed)
        XCTAssertFalse(d.view.space.pinned.peeked)
        XCTAssertTrue(d.view.space.pinned.rows.isEmpty, "a Today tab is shown: no pinned row")
        d.user(.tab(.focus(second)))
        XCTAssertTrue(d.view.space.pinned.peeked)
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), [second])
        d.user(.tab(.focus(today)))
        XCTAssertFalse(d.view.space.pinned.peeked)
        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertEqual(d.view.space.pinned.rows.map(\.id), [first, second])
    }

    // A016: Opt+Cmd+Down skips a collapsed folder's tabs and stops on a split once; no wrap.
    func testStepSkipsCollapsedChildrenTreatsASplitAsOneStopAndStopsAtTheEnds() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        let hidden = d.open("https://example.com/hidden")
        d.user(.item(.newFolder))
        let box = d.pinnedIDs[0]
        d.user(.item(.move(hidden, to: .into(parent: box, index: 0))))
        let left = d.open("https://example.com/left")
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://example.com/right")))
        let split = try XCTUnwrap(d.view.content.split)
        _ = left
        d.user(.item(.toggleFolder(box)))
        XCTAssertEqual(folder(box, in: d.view.space.pinned.rows)?.collapsed, true)
        d.user(.tab(.focus(home)))
        d.user(.tab(.step(.previous)))
        XCTAssertEqual(shown(d), split, "the split is one stop")
        d.user(.tab(.step(.previous)))
        XCTAssertEqual(shown(d), split, "the collapsed folder's tab is skipped and Up does not wrap")
        d.user(.tab(.step(.next)))
        XCTAssertEqual(shown(d), home)
        d.user(.tab(.step(.next)))
        XCTAssertEqual(shown(d), home, "Down does not wrap")
        d.user(.item(.toggleFolder(box)))
        d.user(.tab(.focus(split)))
        d.user(.tab(.step(.previous)))
        XCTAssertEqual(shown(d), hidden, "an open folder's tab is a stop")
    }

    // A018: Ctrl+Cmd+Right at the last unit wraps to the first; Left at the first wraps to the last.
    func testLinearCycleWrapsAtBothEnds() {
        let d = Driver()
        let home = d.todayIDs[0]
        let a = d.open("https://example.com/a")
        let order = d.todayIDs
        XCTAssertEqual(order, [a, home])
        d.user(.tab(.focus(home)))
        d.user(.tabTools(.cycleLinear(.next)))
        XCTAssertEqual(shown(d), a, "Right from the last unit wraps to the first")
        d.user(.tabTools(.cycleLinear(.previous)))
        XCTAssertEqual(shown(d), home, "Left from the first unit wraps to the last")
    }

    // A019: Favorites count in Cmd+1…8 only while the setting is on; Cmd+9 is always the last item.
    func testNumberJumpsFollowTheFavoritesSettingAndNineIsTheLast() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        let fav = d.open("https://example.com/fav")
        d.user(.item(.move(fav, to: .into(parent: try XCTUnwrap(d.state.doc.favorites[.default]), index: 0))))
        let newest = d.open("https://example.com/newest")
        d.user(.tabTools(.jumpItem(1)))
        XCTAssertEqual(shown(d), fav)
        d.user(.tabTools(.preferences(includeFavorites: false, previews: false)))
        d.user(.tabTools(.jumpItem(1)))
        XCTAssertEqual(shown(d), newest)
        d.user(.tabTools(.jumpItem(9)))
        XCTAssertEqual(shown(d), home)
        d.user(.tabTools(.jumpItem(5)))
        XCTAssertEqual(shown(d), home, "a number past the list changes nothing")
        XCTAssertFalse(Driver(file: d.savedFile).state.doc.tabPreferences.includeFavoritesInNumbers, "the setting is saved")
    }

    // A024: several rows, an explicit destination, order kept, fresh identities.
    func testDuplicateWithAnExplicitDestinationKeepsOrderAndMakesNewIdentities() throws {
        let d = Driver()
        let a = d.open("https://example.com/a")
        let b = d.open("https://example.com/b")
        let root = d.view.space.pinned.root
        d.user(.tabTools(.bulk(.items([a, b]), .duplicate(.into(parent: root, index: 0)))))
        let pinned = d.view.space.pinned.rows.compactMap { if case .tab(let t) = $0 { t } else { nil } }
        XCTAssertEqual(pinned.map(\.url), [url("https://example.com/a"), url("https://example.com/b")], "copies land at the destination in selection order")
        XCTAssertTrue(Set(pinned.map(\.id)).isDisjoint(with: [a, b]), "copies have new identities")
        XCTAssertEqual(d.todayIDs.filter { [a, b].contains($0) }.count, 2, "the originals stay")
        d.user(.tabTools(.bulk(.items([a, b]), .duplicate(nil))))
        let today = d.todayIDs
        XCTAssertEqual(today.count, 6)
        for original in [a, b] { let i = today.firstIndex(of: original)!; XCTAssertEqual(d.row(today[i + 1])?.url, d.row(original)?.url, "the copy sits right after its original") }
    }

    // A025: Ctrl+Space reveals the shown item (ancestors open) and focuses the sidebar; arrows move and stop at ends.
    func testRevealOpensAncestorsFocusesTheSidebarAndArrowsMoveWithinRows() throws {
        let d = Driver()
        let inner = d.open("https://example.com/inner")
        d.user(.item(.newFolder))
        let box = d.pinnedIDs[0]
        d.user(.item(.move(inner, to: .into(parent: box, index: 0))))
        d.user(.item(.toggleFolder(box)))
        d.user(.tab(.focus(inner)))
        d.user(.tabTools(.reveal))
        XCTAssertEqual(folder(box, in: d.view.space.pinned.rows)?.collapsed, false, "the folder opened to show the row")
        XCTAssertEqual(d.view.focus, .sidebar)
        XCTAssertEqual(d.view.tabTools.reveal, inner)
        let generation = d.view.tabTools.revealGeneration
        d.user(.tabTools(.sidebarStep(.next)))
        XCTAssertNotEqual(shown(d), inner, "Down moved to the next row")
        XCTAssertGreaterThan(d.view.tabTools.revealGeneration, generation, "each step asks the list to scroll")
        d.user(.tabTools(.sidebarStep(.previous)))
        XCTAssertEqual(shown(d), inner)
        for _ in 0..<5 { d.user(.tabTools(.sidebarStep(.previous))) }
        XCTAssertEqual(d.view.tabTools.reveal, box, "Up stops at the first row (the folder), which is selected, not shown")
        d.user(.tabTools(.leaveSidebar))
        XCTAssertNotEqual(d.view.focus, .sidebar)
    }

    // A026: Clear keeps a Today tab another window shows.
    func testClearTodayKeepsWhatAnyWindowShows() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        let mine = d.open("https://example.com/mine")
        let theirs = d.open("https://example.com/theirs")
        let idle = d.open("https://example.com/idle")
        d.user(.tab(.focus(mine)))
        let other = try newWindow(d)
        d.user(.tab(.focus(theirs)), in: other)
        d.user(.tab(.clearToday))
        XCTAssertEqual(Set(d.todayIDs), [mine, theirs])
        let archived = d.archive().map(\.url)
        XCTAssertTrue(archived.contains(url("https://example.com/idle")) && archived.contains(start))
        _ = (home, idle)
    }

    // A089: deleting a folder with a nested folder archives every tab at any depth.
    func testDeletingAFolderArchivesTabsInNestedFolders() throws {
        let d = Driver()
        let a = d.open("https://example.com/a")
        let b = d.open("https://example.com/b")
        d.user(.item(.newFolder))
        let outer = d.pinnedIDs[0]
        d.user(.tabTools(.newNestedFolder(outer)))
        let inner = try XCTUnwrap(folder(outer, in: d.view.space.pinned.rows)?.children.first?.id)
        d.user(.item(.move(a, to: .into(parent: outer, index: 0))))
        d.user(.item(.move(b, to: .into(parent: inner, index: 0))))
        d.user(.item(.deleteFolder(outer)))
        XCTAssertTrue(d.pinnedIDs.isEmpty)
        let archive = d.archive()
        for address in ["https://example.com/a", "https://example.com/b"] {
            XCTAssertTrue(archive.contains { $0.url == url(address) && $0.reason == .containerDeleted }, "\(address) not archived: \(archive.map(\.url))")
        }
        XCTAssertNil(d.state.doc.tree[inner], "the nested folder is gone too")
    }

    // A090: Collapse All acts on this window and this space; the hierarchy stays.
    func testCollapseAllIsThisWindowAndThisSpaceOnly() throws {
        let d = Driver()
        let a = d.open("https://example.com/a")
        d.user(.item(.newFolder))
        let outer = d.pinnedIDs[0]
        d.user(.tabTools(.newNestedFolder(outer)))
        let inner = try XCTUnwrap(folder(outer, in: d.view.space.pinned.rows)?.children.first?.id)
        d.user(.item(.move(a, to: .into(parent: inner, index: 0))))
        let tree = d.state.doc.tree
        let other = try newWindow(d)
        let first = d.view.space.id
        d.newSpace("Far")
        d.user(.item(.newFolder))
        let far = d.pinnedIDs[0]
        d.user(.space(.focus(first)))
        d.user(.tabTools(.folders(expanded: false)))
        XCTAssertEqual(folder(outer, in: d.view.space.pinned.rows)?.collapsed, true)
        XCTAssertEqual(d.state.doc.windows[d.window]?.folderExpansion[inner], false, "nested folders collapse too")
        XCTAssertEqual(folder(outer, in: d.view(of: other).space.pinned.rows)?.collapsed, false, "the other window is untouched")
        XCTAssertNil(d.state.doc.windows[d.window]?.folderExpansion[far], "the other space's folder is untouched")
        XCTAssertEqual(d.state.doc.tree.items.filter { tree.items[$0.key] != nil }.mapValues(\.parent), tree.items.mapValues(\.parent), "the hierarchy is unchanged")
        d.user(.tabTools(.folders(expanded: true)))
        XCTAssertEqual(folder(inner, in: d.view.space.pinned.rows)?.collapsed, false)
    }

    // A088: Shift+Cmd+E opens the Gmail Peek in the window's own profile.
    func testPeekEmailOpensInTheSpacesProfile() throws {
        let d = Driver()
        d.user(.peek(.email))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("no Peek") }
        XCTAssertEqual(peek.tab.url, url("https://mail.google.com/mail/u/0/"))
        d.user(.peek(.close))
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        d.user(.space(.create(title: "Work space", icon: .none, theme: SpaceTheme(colors: [ThemePresets.drab[8]], texture: .grain, intensity: 0.25, appearance: .auto), profile: work)))
        d.user(.peek(.email))
        guard case .peek(let workPeek)? = d.view.overlay, let page = workPeek.page ?? d.snapshot.pages.first(where: { $0.id.item == workPeek.tab.id })?.id else { return XCTFail("no Peek in the work space") }
        let spec = try XCTUnwrap(d.snapshot.pages.first { $0.id == page })
        XCTAssertEqual(spec.context, .profile(work), "the Peek page browses in the space's profile")
    }
}
