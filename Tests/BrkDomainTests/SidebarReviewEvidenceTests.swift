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
        XCTAssertFalse(d.view.space.pinned.peeked, "a Today tab is shown: nothing peeks (the layout draws no pinned row)")
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

    // A025: Ctrl+Space reveals the shown item (ancestors open) and focuses the sidebar; arrows move and stop at ends.
    func testRevealOpensAncestorsFocusesTheSidebarAndArrowsMoveWithinRows() throws {
        let d = Driver()
        let inner = d.open("https://example.com/inner")
        d.user(.item(.newFolder))
        let box = d.pinnedIDs[0]
        d.user(.item(.rename(box, title: "Box")))
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
}
