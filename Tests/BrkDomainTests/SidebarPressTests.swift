import BrkBase
@testable import BrkDomain
import XCTest

/// Arc opens a row or a Favorite on the press (Q13-press-*); Command and Shift stay multi-select clicks.
final class SidebarPressTests: XCTestCase {
    private func tab(_ id: String) -> TabRow {
        TabRow(id: ItemID(id), section: .today, title: id, url: nil, favicon: nil, icon: nil, status: .idle, loading: false, loaded: false, canReset: false)
    }

    func testAPressOpensATabARowsPaneAndAFavorite() {
        let a = ItemID("a")
        XCTAssertEqual(SidebarPress.commands(for: .tab(tab("a")), command: false, shift: false), [.tabTools(.select(a, .replace)), .tab(.focus(a))])
        XCTAssertEqual(SidebarPress.commands(forTile: a, command: false, shift: false), [.tab(.focus(a))])
    }

    func testCommandAndShiftOpenNothing() {
        let a = ItemID("a")
        for (command, shift) in [(true, false), (false, true), (true, true)] {
            XCTAssertEqual(SidebarPress.commands(for: .tab(tab("a")), command: command, shift: shift), [])
            XCTAssertEqual(SidebarPress.commands(forTile: a, command: command, shift: shift), [])
        }
    }
}

/// A drop on the Space name strip (Q13-g/h) and a Favorite's drop on the page (Q13-e).
final class FavoritesDragRulesTests: XCTestCase {
    func testADropOnTheSpaceNameStripIsTheFirstPinnedTabWithTheRenameHint() throws {
        let d = Driver()
        let pinned = d.open("https://fixture.example/pinned")
        d.user(.tab(.togglePin(.item(pinned))))
        let tab = d.open("https://fixture.example/inbox")
        d.user(.item(.dropOnSpaceHeader(tab)))
        XCTAssertEqual(d.view.space.pinned.rows.first?.id, tab)
        XCTAssertFalse(d.view.space.today.rows.contains { $0.id == tab })
        XCTAssertEqual(d.paneIDs, [tab], "the dropped tab stays the shown one")
        guard case .tab(let row)? = d.view.space.pinned.rows.first else { return XCTFail("not a tab row") }
        XCTAssertTrue(row.renameHint)
        XCTAssertEqual(row.status, .current)
        XCTAssertNotNil(d.state.tree(of: d.window)?[tab].flatMap { item in if case .tab(let t) = item.body { t.pinnedURL } else { nil } }, "not pinned to its address")
    }

    func testOpenInSplitLeavesAFavoriteInFavorites() throws {
        let d = Driver()
        let original = d.paneIDs[0], favorite = d.open("https://fixture.example/favorite")
        d.user(.item(.move(favorite, to: .into(parent: d.view.favorites.root, index: 0))))
        d.user(.tab(.focus(original)))
        d.user(.tabTools(.openInSplit(.items([favorite]))))
        XCTAssertTrue(d.view.favorites.tiles.contains { $0.id == favorite }, "the menu's Open in Split moved a Favorite out")
    }
}
