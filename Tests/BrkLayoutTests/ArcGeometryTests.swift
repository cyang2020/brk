import BrkBase
import BrkDomain
import XCTest
@testable import BrkLayout

/// Frames against Arc's decompiled constants (docs/arc-anatomy/layout-constants.md). These are the unit-level
/// pixel checks; e2e N3 checks the same numbers on the real window.
final class ArcGeometryTests: XCTestCase {
    /// 8 + 8 + 4 x 47 + 3 x 8 = 228: the reset width is the narrowest that keeps four square favorites.
    func testResetWidthIsFourFavoritesWide() {
        let f = Metrics.favorites.self
        let width = 2 * f.inset.value + Double(f.maxColumns.value) * f.minTile.value + Double(f.maxColumns.value - 1) * f.gap.value
        XCTAssertEqual(width, Metrics.sidebar.resetWidth.value)
    }

    /// Title row centre = header top inset + title row height / 2 (cra L141 measures 24).
    func testTrafficLightCentreLine() {
        XCTAssertEqual(Metrics.sidebar.headerTopInset.value + Metrics.sidebar.titleRowHeight.value / 2,
                       Metrics.window.trafficLightCenterY.value)
    }

    /// cra L1590-1594: 4 columns at sidebar width 230, 2 columns at 227.
    func testFavoritesColumnsFallTo2Below228() throws {
        // cra L1590-1594: widths -> tile widths (47 tall), 4 columns while a tile is at least 47 wide, else 2, else 1.
        let table: [(Double, Int, Double)] = [
            (347, 4, 76), (300, 4, 65), (260, 4, 55), (230, 4, 47), (228, 4, 47), (227, 2, 101), (225, 2, 100), (220, 2, 98),
            (212, 2, 94), (205, 2, 90), (200, 2, 88), (170, 2, 73), (140, 2, 58), (100, 1, 84),
        ]
        for (width, columns, tile) in table {
            XCTAssertEqual(FavoritesGrid.columns(forWidth: width), columns, "width \(width)")
            XCTAssertEqual(FavoritesGrid.tiles(count: 4, width: width).tiles.map(\.size), Array(repeating: CGSize(width: tile, height: 47), count: 4), "width \(width)")
        }
        let grid = FavoritesGrid.tiles(count: 4, width: 227)
        XCTAssertEqual(grid.tiles, [CGRect(x: 8, y: 8, width: 101, height: 47), CGRect(x: 117, y: 8, width: 101, height: 47),
                                    CGRect(x: 8, y: 63, width: 101, height: 47), CGRect(x: 117, y: 63, width: 101, height: 47)])
        XCTAssertEqual(grid.tray, CGSize(width: 227, height: 118))
        XCTAssertEqual(FavoritesGrid.tiles(count: 0, width: 228).tray, CGSize(width: 228, height: 114), "Arc's Drag to add Favorites box (P07-b)")
        XCTAssertEqual(FavoritesGrid.tiles(count: 0, width: 228, hintDismissed: true).tray, CGSize(width: 228, height: 0), "dismissed: no room")
    }

    /// The empty box keeps Arc's 228 proportions as the sidebar narrows (P05-f, P07-b): 213 x 94.5 at 228, scaled by
    /// the box width down to 149 x 66.1 at the 164 minimum; the tray keeps its 7 above and 12.5 below the box.
    func testTheEmptyFavoritesBoxShrinksWithTheSidebar() throws {
        let (full, one) = FavoritesGrid.emptyBox(width: 228)
        XCTAssertEqual(full, CGRect(x: 7.5, y: 7, width: 213, height: 94.5))
        XCTAssertEqual(one, 1)
        XCTAssertEqual(FavoritesGrid.emptyBox(width: 300).box, CGRect(x: 7.5, y: 7, width: 285, height: 94.5), "wider: stretched, same height")
        var previous = full.height
        for width in stride(from: 212.0, through: 164, by: -16) {
            let (box, scale) = FavoritesGrid.emptyBox(width: width)
            XCTAssertEqual(scale, (width - 15) / 213, accuracy: 1e-9, "width \(width)")
            XCTAssertEqual(box.width, width - 15, "width \(width)")
            XCTAssertEqual(box.height / box.width, full.height / full.width, accuracy: 1e-9, "width \(width): Arc's proportions")
            XCTAssertLessThan(box.height, previous)
            previous = box.height
            XCTAssertEqual(FavoritesGrid.tiles(count: 0, width: width).tray.height, 19.5 + box.height, accuracy: 1e-9, "width \(width)")
        }
        XCTAssertEqual(FavoritesGrid.emptyBox(width: 164).box.height, 66.1, accuracy: 0.05)
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
    /// P46-a: with Max's Tidy Tabs on Arc keeps the divider 8 points taller, however many tabs Today holds.
    func testTidyTabsMakesTheDividerRowTaller() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        d.user(.tab(.togglePin(.item(a))))
        _ = d.open("c.example.com")
        func dividerHeight() -> Double? { TablistLayout.rows(d.view.space, width: 228).first { $0.kind == .divider }?.rect.height }
        XCTAssertEqual(dividerHeight(), 16)
        d.user(.settings(.max(.tidyTabs(true))))
        XCTAssertEqual(dividerHeight(), 24)
    }
    /// P01-b: with the toolbar shown the page starts a point above the toolbar's bottom, under its hairline.
    func testPageStartsUnderTheToolbarsHairline() throws {
        let d = LayoutDriver()
        d.user(.sidebar(.toggleToolbar))
        let frames = d.frames()
        let toolbar = try XCTUnwrap(frames.toolbar)
        XCTAssertEqual(try XCTUnwrap(frames.cards.first).rect.minY, toolbar.maxY - 1)
    }
    /// Q02 b: with Today empty Arc draws no Pinned/Today divider; New Tab sits right under Pinned.
    func testNoDividerWhileTodayIsEmpty() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        d.user(.tab(.togglePin(.item(a))))
        XCTAssertTrue(d.view.space.today.rows.isEmpty)
        XCTAssertEqual(TablistLayout.rows(d.view.space, width: 228).map(\.kind), [.topSpacer, .item(a), .newTab])
        let b = d.open("b.example.com")
        XCTAssertEqual(TablistLayout.rows(d.view.space, width: 228).map(\.kind), [.topSpacer, .item(a), .divider, .newTab, .item(b)])
    }
    /// Title row 40 at y 4; URL pill 36 tall, 8 from each side; dock 50 at the bottom.
    func testSidebarColumnStack() throws {
        let f = try XCTUnwrap(LayoutDriver().frames().sidebar)
        XCTAssertEqual(f.frame, CGRect(x: 0, y: 0, width: 228, height: 776))
        XCTAssertEqual(f.titleRow, CGRect(x: 0, y: 4, width: 228, height: 40))
        XCTAssertEqual(f.trafficLightsOrigin, CGPoint(x: 13, y: 17), "14 pt lights centred 24 from the top, 13 from the left")
        XCTAssertEqual(f.urlPill, CGRect(x: 8, y: 46, width: 212, height: 36))
        // No favorites: the tray holds Arc's 114 pt "Drag to add Favorites" box (P07-b).
        XCTAssertEqual(f.favoritesTray, CGRect(x: 0, y: 82, width: 228, height: 114))
        XCTAssertEqual(f.favoriteTiles, [:])
        // The space header strip (36) sits between the tray and the list: 196...232.
        XCTAssertEqual(f.spaceHeader, CGRect(x: 0, y: 196, width: 228, height: 36))
        XCTAssertEqual(f.tablistViewport, CGRect(x: 0, y: 232, width: 228, height: 494))
        XCTAssertEqual(f.tablistViewport.minY, f.spaceHeader.maxY)
        XCTAssertEqual(f.dock, CGRect(x: 0, y: 726, width: 228, height: 50))
        XCTAssertEqual(f.libraryButton, CGRect(x: 8, y: 735, width: 32, height: 32))
        XCTAssertEqual(f.plusButton, CGRect(x: 188, y: 735, width: 32, height: 32))
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
    /// Centered command bar: min(766, area - 160) wide, 338 tall, centered in the window (Q01-a: Arc's card spans
    /// 257...1023 with the sidebar shown).
    func testCommandBarCentered() throws {
        let d = LayoutDriver()
        d.user(.commandBar(.open(.newTab)))
        let frames = d.frames()
        XCTAssertEqual(frames.contentArea, CGRect(x: 228, y: 10, width: 1042, height: 756))
        XCTAssertEqual(frames.commandBar, CGRect(x: 257, y: 219, width: 766, height: 338))
        let area = { (w: Double, h: Double) in CGRect(x: 0, y: 0, width: w, height: h) }
        XCTAssertEqual(CommandBarLayout.frame(placement: .centered, contentArea: area(800, 600), urlPill: nil).width, 640, "min(766, 800 - 160)")
        XCTAssertEqual(CommandBarLayout.frame(placement: .centered, contentArea: area(700, 600), urlPill: nil).width, 680, "narrower than 766: area - 20")
        XCTAssertEqual(CommandBarLayout.frame(placement: .centered, contentArea: area(1000, 300), urlPill: nil).height, 252, "24 from top and bottom")
        // Cmd+L with the sidebar shown: from the pill's left edge, 2 above it (P02-b), reaching right, 80 from the
        // window's right edge at most 720 wide.
        d.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(d.frames().commandBar, CGRect(x: 8, y: 44, width: 720, height: 338))
        XCTAssertEqual(d.frames(size: CGSize(width: 600, height: 400)).commandBar, CGRect(x: 8, y: 44, width: 512, height: 332))
    }
    /// Card inset 10 on every side with the sidebar hidden; beside the sidebar the card starts at its edge; radius 6.
    func testContentCardInsetAndRadius() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        XCTAssertEqual(d.frames().cards, [CardFrame(pane: 0, content: .page(PageID(window: d.window, item: a)), rect: CGRect(x: 228, y: 10, width: 1042, height: 756), cornerRadius: 6)])
        d.user(.sidebar(.toggle))
        XCTAssertEqual(d.frames().cards, [CardFrame(pane: 0, content: .page(PageID(window: d.window, item: a)), rect: CGRect(x: 10, y: 10, width: 1260, height: 756), cornerRadius: 6)])
        XCTAssertEqual(d.frames().frame(of: .card(0)), CGRect(x: 10, y: 10, width: 1260, height: 756))
    }
    /// Floating sidebar: 5 from left, top and bottom.
    func testFloatingSidebarInset() throws {
        let d = LayoutDriver()
        d.user(.sidebar(.toggle))
        d.user(.sidebar(.peek(true)))
        let frames = d.frames()
        XCTAssertTrue(frames.sidebarFloats)
        XCTAssertEqual(frames.sidebar?.frame, CGRect(x: 5, y: 5, width: 228, height: 766))
        XCTAssertEqual(frames.sidebar?.urlPill, CGRect(x: 13, y: 51, width: 212, height: 36))
        XCTAssertEqual(frames.frame(of: .floatingSidebar), CGRect(x: 5, y: 5, width: 228, height: 766))
        XCTAssertNil(frames.frame(of: .sidebar))
        XCTAssertNil(frames.resizeHandle)
        XCTAssertNil(frames.revealStrip)
    }
    /// Two panes: gap 10, equal heights, integer widths, the last card absorbs rounding.
    func testSplitGap() throws {
        let d = LayoutDriver()
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("b.example.com")))
        var snapshot = d.view
        snapshot.content.panes[0].fraction = 1.0 / 3
        snapshot.content.panes[1].fraction = 2.0 / 3
        let frames = d.frames(snapshot)
        XCTAssertEqual(frames.cards.map(\.rect), [CGRect(x: 228, y: 10, width: 344, height: 756), CGRect(x: 582, y: 10, width: 688, height: 756)])
        XCTAssertEqual(frames.dividers, [CGRect(x: 572, y: 10, width: 10, height: 756)])
        XCTAssertEqual(frames.cards.map(\.cornerRadius), [6, 6])
        XCTAssertEqual(frames.frame(of: .divider(0)), CGRect(x: 572, y: 10, width: 10, height: 756))
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
