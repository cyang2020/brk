import BrkBase
import XCTest
@testable import BrkDomain

/// Dragging a Cmd/Shift-click selection of several rows, as Arc 1.170 does (probed 2026-11-15,
/// ~/brk-evidence/multi-drag/README.md). The user's report: Shift-selected tabs could not be dragged together.
final class MultiDragTests: XCTestCase {
    /// A plain press on a row of a selection of several opens nothing and carries the whole selection; released without a
    /// drag it opens that row and the selection becomes the row alone. A press on a row outside the selection opens it at
    /// once and carries it alone.
    func testAPressOnASelectedRowCarriesTheSelectionAndOpensOnlyOnRelease() throws {
        let d = Driver()
        let a = d.todayIDs[0], b = d.open("127.0.0.1:9/b"), c = d.open("127.0.0.1:9/c")
        d.user(.tabTools(.select(a, .toggle)))
        let selection = d.view.tabTools.selected
        let rowA = try XCTUnwrap(d.view.space.today.rows.first { $0.id == a }), rowB = try XCTUnwrap(d.view.space.today.rows.first { $0.id == b })
        XCTAssertEqual(SidebarPress.carried(by: a, selection: selection), [c, a])
        XCTAssertEqual(SidebarPress.commands(for: rowA, command: false, shift: false, selection: selection), [], "the press opened the row")
        let release = SidebarPress.releaseCommands(for: rowA, selection: selection)
        XCTAssertEqual(release, [.tabTools(.select(a, .replace)), .tab(.focus(a))])
        for command in release { d.user(command) }
        XCTAssertEqual(d.current?.id, a)
        XCTAssertEqual(d.view.tabTools.selected, [a])

        XCTAssertEqual(SidebarPress.carried(by: b, selection: [c, a]), [b])
        XCTAssertEqual(SidebarPress.commands(for: rowB, command: false, shift: false, selection: [c, a]), [.tabTools(.select(b, .replace)), .tab(.focus(b))])
        XCTAssertEqual(SidebarPress.releaseCommands(for: rowB, selection: [c, a]), [])
    }

    /// Arc counts the tab on screen as selected: after a drop (which ends the selection) a Cmd-click still makes a
    /// selection of the current tab and the clicked row, and a Shift-click runs from the current tab. The drop itself put
    /// the rows together in sidebar order and left the current tab current.
    func testCmdClickAfterADropStillTakesTheCurrentTab() throws {
        let d = Driver()
        let a = d.todayIDs[0], b = d.open("127.0.0.1:9/b"), c = d.open("127.0.0.1:9/c")
        d.user(.tabTools(.select(b, .toggle)))
        XCTAssertEqual(d.view.tabTools.selected, [c, b])
        d.user(.tabTools(.bulk(.selected, .move(.into(parent: d.view.space.pinned.root, index: 0)))))
        XCTAssertEqual(d.pinnedIDs, [c, b])
        XCTAssertEqual(d.view.tabTools.selected, [])
        XCTAssertEqual(d.current?.id, c)
        d.user(.tabTools(.select(a, .toggle)))
        XCTAssertEqual(d.view.tabTools.selected, [c, a])
        d.user(.tabTools(.clearSelection))
        XCTAssertEqual(d.view.tabTools.selected, [])
        d.user(.tabTools(.select(a, .range)))
        XCTAssertEqual(d.view.tabTools.selected, [c, b, a])
    }

    /// Several tabs dropped on the half of another tab's row make one split with it, in sidebar order on that side, the
    /// last one focused, as one change; when any of them cannot join (the panes would not fit, a folder) nothing changes.
    func testSeveralTabsDroppedOnARowJoinItAsOneSplit() throws {
        let d = Driver()
        let start = d.paneIDs[0]
        let target = d.open("https://fixture.example/target"), b = d.open("https://fixture.example/b"), c = d.open("https://fixture.example/c")
        d.user(.tabTools(.select(b, .toggle)))
        d.user(.split(.joinRows([b, c], onto: target, at: 1)))
        let split = try XCTUnwrap(d.view.content.split)
        XCTAssertEqual(d.paneIDs, [target, c, b])
        XCTAssertEqual(d.todayIDs, [split, start])
        XCTAssertEqual(d.view.content.panes.first(where: \.focused)?.tab, b)
        XCTAssertEqual(d.view.tabTools.selected, [])

        let e = d.open("https://fixture.example/e"), f = d.open("https://fixture.example/f")
        assertUnchanged(d.state, d.user(.split(.joinRows([e, f], onto: split, at: 3))))
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        assertUnchanged(d.state, d.user(.split(.joinRows([e, folder], onto: start, at: 1))))
    }
}
