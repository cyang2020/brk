import BrkBase
import BrkDomain
import XCTest
@testable import BrkLayout

/// Frames against Arc's decompiled constants (docs/arc-anatomy/layout-constants.md). These are the unit-level
/// pixel checks; e2e N3 checks the same numbers on the real window.
final class ArcGeometryTests: XCTestCase {
    /// The most columns a tray may have: the largest of 4, 3, 2, 1 whose tile is at least 47 wide (Q13-w200: 3 is used).
    func testTheWidthSetsTheMostColumns() throws {
        let table: [(Double, Int)] = [(500, 4), (347, 4), (228, 4), (227, 3), (205, 3), (200, 3), (173, 3), (172, 2), (166, 2), (164, 2), (118, 2), (117, 1), (100, 1)]
        for (width, columns) in table { XCTAssertEqual(FavoritesGrid.maxColumns(forWidth: width), columns, "width \(width)") }
        XCTAssertEqual(FavoritesGrid.tiles(count: 0, width: 228).tray, CGSize(width: 228, height: 114), "Arc's Drag to add Favorites box (P07-b)")
        XCTAssertEqual(FavoritesGrid.tiles(count: 0, width: 228, hintDismissed: true).tray, CGSize(width: 228, height: 0), "dismissed: no room")
    }

    /// Rows are 40 tall on a 41 pt pitch; the divider is 16; the top spacer is 2 (cra L748: 41, 17, 3).
    func testTablistRowPitch() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        let b = d.open("b.example.com")
        d.user(.tab(.togglePin(.item(a))))
        d.user(.tab(.togglePin(.item(b))))
        let c = d.open("c.example.com")
        let e = d.open("e.example.com")
        let rows = TablistLayout.rows(d.view.space, width: 228)
        func row(_ kind: RowFrame.Kind, _ y: Double, _ h: Double, depth: Int = 0) -> RowFrame {
            RowFrame(kind: kind, rect: CGRect(x: 0, y: y, width: 228, height: h), depth: depth)
        }
        XCTAssertEqual(rows, [row(.topSpacer, 0, 2), row(.item(a), 3, 40), row(.item(b), 44, 40), row(.divider, 85, 16),
                              row(.newTab, 102, 40), row(.item(e), 143, 40), row(.item(c), 184, 40)])
        // A folder's children are one level deeper while it is open, and gone while it is closed or Pinned is.
        d.user(.item(.newFolder))
        let folder = d.view.space.pinned.rows[0].id
        d.user(.item(.move(a, to: .into(parent: folder, index: 0))))
        let nested = TablistLayout.rows(d.view.space, width: 228)
        XCTAssertEqual(Array(nested.prefix(4)), [row(.topSpacer, 0, 2), row(.item(folder), 3, 40), row(.item(a), 44, 40, depth: 1), row(.item(b), 85, 40)])
        d.user(.item(.toggleFolder(folder)))
        XCTAssertEqual(TablistLayout.rows(d.view.space, width: 228).map(\.kind), [.topSpacer, .item(folder), .item(b), .divider, .newTab, .item(e), .item(c)])
        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertEqual(TablistLayout.rows(d.view.space, width: 228).map(\.kind), [.topSpacer, .divider, .newTab, .item(e), .item(c)])
    }
    /// Arc 1.170, a new Space with Today tabs and nothing pinned (8dc9260d6a:verify/completion/max-ui-20261107/arc-no-pinned-*.png):
    /// the divider is there, with Clear and, with Tidy Tabs on, Tidy, so a person without pinned tabs can tidy.
    func testTheDividerShowsWithoutPinnedTabs() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        XCTAssertTrue(d.view.space.pinned.rows.isEmpty)
        XCTAssertEqual(TablistLayout.rows(d.view.space, width: 228).map(\.kind), [.topSpacer, .divider, .newTab, .item(a)])
        d.user(.settings(.max(.tidyTabs(true))))
        while d.view.space.today.rows.count < 7 { _ = d.open("t\(d.view.space.today.rows.count).example.com") }
        XCTAssertTrue(d.view.space.today.canTidy)
        XCTAssertTrue(TablistLayout.rows(d.view.space, width: 228).contains { $0.kind == .divider })
    }
    /// Dock cells at most 34 x 32, shrinking to fit, compact below 22.
    func testDockCellsShrinkToFit() throws {
        let dock = CGRect(x: 0, y: 726, width: 228, height: 50)
        let four = DockLayout.cells(count: 4, in: dock)
        XCTAssertEqual(four.spaces, (0..<4).map { CGRect(x: 46 + Double($0) * 34, y: 735, width: 34, height: 32) })
        let ten = DockLayout.cells(count: 10, in: dock).spaces
        XCTAssertEqual(ten.first, CGRect(x: 44, y: 735, width: 14, height: 32))
        XCTAssertLessThan(ten[0].width, Metrics.dock.compactBelow.value, "below 22 the view draws the compact style")
        let crowded = DockLayout.cells(count: 30, in: dock).spaces
        XCTAssertEqual(crowded.first, CGRect(x: 40, y: 735, width: 8, height: 32), "never below 8; overflow starts at the Library button")
        XCTAssertEqual(DockLayout.cells(count: 0, in: dock).spaces, [])
        let d = LayoutDriver()
        let frames = try XCTUnwrap(d.frames().sidebar)
        XCTAssertEqual(frames.dockSpaces, [d.view.dock[0].id: CGRect(x: 97, y: 735, width: 34, height: 32)])
    }
    /// Drag: clamps to 164...500, snaps to 228 within 14, holds 0.5 s unless faster than 50 pt/s, hides below 82.
    func testSidebarResizeDragSnapsAndHides() throws {
        var drag = SidebarResizeDrag(startWidth: 300)
        XCTAssertEqual(drag.update(translation: -10, velocity: 0, time: 0), 290)
        XCTAssertEqual(drag.update(translation: -60, velocity: 10, time: 0), 228, "within 14 of 228: snaps")
        XCTAssertEqual(drag.snappedAt, 0)
        XCTAssertEqual(drag.update(translation: -50, velocity: 10, time: 0.1), 228, "held for 0.5 s while slow")
        XCTAssertEqual(drag.update(translation: -50, velocity: 100, time: 0.2), 250, "faster than 50 pt/s: unsnaps")
        XCTAssertEqual(drag.update(translation: -150, velocity: 0, time: 0.3), 164, "clamped at the minimum")
        XCTAssertEqual(drag.update(translation: -219, velocity: 0, time: 0.4), 0, "below 82: hidden")
        XCTAssertEqual(drag.update(translation: -217, velocity: 0, time: 0.45), 164, "back above 82: shown at the minimum")
        XCTAssertEqual(drag.update(translation: 300, velocity: 0, time: 0.5), 500, "clamped at the maximum")
        var hold = SidebarResizeDrag(startWidth: 228)
        XCTAssertEqual(hold.update(translation: 5, velocity: 0, time: 1), 228)
        XCTAssertEqual(hold.update(translation: 30, velocity: 0, time: 1.4), 228)
        XCTAssertEqual(hold.update(translation: 30, velocity: 0, time: 1.6), 258, "the hold ends after 0.5 s")
        XCTAssertEqual(SidebarResizeDrag.resetWidth, 228)
    }
    /// A frame saved on a display that is gone reopens centered on the main screen (regression finding 8).
    func testWindowPlacementOffScreen() throws {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(WindowPlacement.fit(CGRect(x: 5000, y: 4000, width: 1280, height: 776), screens: [main], main: main),
                       CGRect(x: 80, y: 62, width: 1280, height: 776), "off every display: centred on the main screen")
        XCTAssertEqual(WindowPlacement.fit(CGRect(x: 1500, y: 100, width: 800, height: 600), screens: [main, second], main: main),
                       CGRect(x: 1500, y: 100, width: 800, height: 600), "on the second display: kept")
        XCTAssertEqual(WindowPlacement.fit(CGRect(x: 1390, y: 100, width: 800, height: 600), screens: [main], main: main),
                       CGRect(x: 320, y: 150, width: 800, height: 600), "only 50 pt on screen: re-centred")
        XCTAssertEqual(WindowPlacement.fit(CGRect(x: 0, y: 0, width: 3000, height: 2000), screens: [], main: main), main, "clamped to the main screen")
        XCTAssertEqual(WindowPlacement.fit(nil, screens: [main], main: main), CGRect(x: 80, y: 62, width: 1280, height: 776), "the default size, centred")
    }
}
