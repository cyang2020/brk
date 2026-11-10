import XCTest

@testable import BrkLayout
import BrkBase
import BrkDomain

// Ported from electron-v1:src/main/layout.test.ts. The Arc-constant cases (title row, pill, favorites, rows, dock,
// command bar, resize snapping) are in ArcGeometryTests.swift. Window 1280 x 776, sidebar 228, inset 10, radius 6.

final class LayoutSpecTests: XCTestCase {
    let size = LayoutDriver.size

    // MARK: - electron-v1:src/main/layout.test.ts
    // MARK: computeLayout

    /// two panes: side by side, equal heights, one inset gap between them, integer pixels, last pane absorbs rounding
    func test_twoPanesSideBySideEqualHeightsOneInsetGapBetweenThemIntegerPixelsLastPane() throws {
        let area = CGRect(x: 238, y: 10, width: 1032, height: 756)
        let (two, dividers) = ContentLayout.cards(in: area, fractions: [1.0 / 3, 2.0 / 3])
        XCTAssertEqual(two, [CGRect(x: 238, y: 10, width: 341, height: 756), CGRect(x: 589, y: 10, width: 681, height: 756)])
        XCTAssertEqual(dividers, [CGRect(x: 579, y: 10, width: 10, height: 756)])
        XCTAssertEqual(two[1].maxX, area.maxX)
        for rect in two { XCTAssertEqual(rect, rect.integral) }
        // Four panes: three gaps, widths sum to the content width minus the gaps, the last ends at the edge. Each boundary
        // rounds where it falls (Arc's three panes of 1022 are 341, 340, 341, Q15-f).
        let (four, gaps) = ContentLayout.cards(in: area, fractions: [0.25, 0.25, 0.25, 0.25])
        XCTAssertEqual(four.map(\.width), [251, 250, 251, 250])
        XCTAssertEqual(gaps.count, 3)
        XCTAssertEqual(four.last?.maxX, area.maxX)
        // Stacked (vertical orientation) splits the height instead, the gap out of the upper pane (Arc's P23-c:
        // 10...378 and 388...766).
        let (stacked, gap) = ContentLayout.cards(in: area, fractions: [0.5, 0.5], orientation: .vertical)
        XCTAssertEqual(stacked, [CGRect(x: 238, y: 10, width: 1032, height: 368), CGRect(x: 238, y: 388, width: 1032, height: 378)])
        XCTAssertEqual(gap, [CGRect(x: 238, y: 378, width: 1032, height: 10)])
        // No panes: nothing to place; the window shows one empty card filling the area.
        XCTAssertEqual(ContentLayout.cards(in: area, fractions: []).cards, [])
        let empty = LayoutDriver(startURL: nil)
        empty.user(.commandBar(.dismiss))
        XCTAssertEqual(empty.frames().cards, [CardFrame(pane: 0, content: .blank, rect: CGRect(x: 228, y: 10, width: 1042, height: 756), cornerRadius: 6)])
        // A divider drag gives new fractions, each at least Metrics.content.minPaneFraction.
        XCTAssertEqual(ContentLayout.fractions(afterDragging: 0, to: 238 + 516, in: area, current: [1, 1]), [0.5, 0.5])
        let dragged = ContentLayout.fractions(afterDragging: 0, to: 238, in: area, current: [0.5, 0.5])
        XCTAssertEqual(dragged[0], 0.15, accuracy: 1e-12)
        XCTAssertEqual(dragged[1], 0.85, accuracy: 1e-12)
    }
}

/// Drag and drop targets: the same placement rule and index rule the reducer applies, so a drop lands where the
/// feedback said (electron-wave1-review.md finding 2: favorites reorder inside their grid).
final class DropTargetTests: XCTestCase {
    /// Pinned [p, folder [f1]], Today [t2, t1], favorites [v1, v2, v3].
    func makeSidebar() -> (LayoutDriver, p: ItemID, folder: ItemID, f1: ItemID, t1: ItemID, t2: ItemID, v: [ItemID]) {
        let d = LayoutDriver()
        let p = d.view.space.today.rows[0].id
        d.user(.tab(.togglePin(.item(p))))
        d.user(.item(.newFolder))
        let folder = d.view.space.pinned.rows[0].id
        d.user(.item(.move(folder, to: .into(parent: d.view.space.pinned.root, index: 1))))
        let f1 = d.open("f1.example.com")
        d.user(.item(.move(f1, to: .into(parent: folder, index: 0))))
        var favorites: [ItemID] = []
        for i in 1...3 {
            let v = d.open("v\(i).example.com")
            d.user(.item(.move(v, to: .into(parent: d.view.favorites.root, index: 9))))
            favorites.append(v)
        }
        let t1 = d.open("t1.example.com")
        let t2 = d.open("t2.example.com")
        return (d, p, folder, f1, t1, t2, favorites)
    }

    func testRowDropTargetsFollowTheRowHalvesAndTheFolderBands() throws {
        let (d, p, folder, f1, t1, t2, _) = makeSidebar()
        let space = d.view.space
        let rows = TablistLayout.rows(space, width: 228)
        // spacer 0, p 3, folder 44, f1 85, divider 126, new tab 143, t2 184, t1 225.
        XCTAssertEqual(rows.map(\.kind), [.topSpacer, .item(p), .item(folder), .item(f1), .divider, .newTab, .item(t2), .item(t1)])
        let pinned = space.pinned.root, today = space.today.root
        func drop(_ y: Double, _ kind: ItemKind = .tab, item: ItemID? = nil) -> Destination? {
            TablistLayout.dropTarget(at: CGPoint(x: 50, y: y), rows: rows, space: space, dragging: kind, item: item)
        }
        XCTAssertEqual(drop(1), .into(parent: pinned, index: 0), "top spacer")
        XCTAssertEqual(drop(10), .into(parent: pinned, index: 0), "upper half of p")
        XCTAssertEqual(drop(30), .into(parent: pinned, index: 1), "lower half of p")
        XCTAssertEqual(drop(46), .into(parent: pinned, index: 1), "top quarter of the folder: before it")
        XCTAssertEqual(drop(64), .into(parent: folder, index: 1), "middle of the folder: into it, at the end")
        XCTAssertEqual(drop(80), .into(parent: folder, index: 0), "bottom quarter of an open folder: its first slot")
        XCTAssertEqual(drop(90), .into(parent: folder, index: 0), "upper half of f1")
        XCTAssertEqual(drop(130), .into(parent: pinned, index: 2), "divider, upper half: end of Pinned")
        XCTAssertEqual(drop(138), .into(parent: today, index: 0), "divider, lower half: top of Today")
        XCTAssertEqual(drop(150), .into(parent: today, index: 0), "the New Tab row")
        XCTAssertEqual(drop(250), .into(parent: today, index: 2), "lower half of t1")
        XCTAssertEqual(drop(900), .into(parent: today, index: 2), "below every row: end of Today")
        // Today accepts topic groups; a folder still cannot move into itself.
        XCTAssertEqual(drop(190, .folder, item: folder), .into(parent: today, index: 0))
        XCTAssertNil(drop(64, .folder, item: folder))
        XCTAssertEqual(drop(10, .folder, item: folder), .into(parent: pinned, index: 0))
        // The index counts after the dragged item is detached: t2 dropped below t1 is index 1 of a 2-item list.
        XCTAssertEqual(drop(250, item: t2), .into(parent: today, index: 1))
        // What the reducer does with it is exactly what the feedback said.
        d.user(.item(.move(t2, to: try XCTUnwrap(drop(250, item: t2)))))
        XCTAssertEqual(d.view.space.today.rows.map(\.id), [t1, t2])
    }

    /// Arc's P23-e: the middle half of another standalone tab's row joins it in a split; its quarters still reorder
    /// (`dropTarget`), and folders, the dragged row itself, non-tabs and Favorites never join.
    func testTheMiddleHalfOfATabRowJoinsItInASplit() throws {
        let (d, p, folder, f1, t1, t2, v) = makeSidebar()
        let space = d.view.space
        let rows = TablistLayout.rows(space, width: 228)
        // p 3...43, folder 44...84, f1 85...125, t2 184...224, t1 225...265.
        func join(_ y: Double, _ kind: ItemKind = .tab, from section: SectionKind = .today, item: ItemID) -> ItemID? {
            TablistLayout.splitTarget(at: CGPoint(x: 50, y: y), rows: rows, space: space, dragging: kind, from: section, item: item)?.target
        }
        XCTAssertNil(join(190, item: t1), "top quarter of t2: reorder")
        XCTAssertEqual(join(194, item: t1), t2, "a quarter down t2")
        XCTAssertEqual(join(204, item: t1), t2, "middle of t2")
        XCTAssertEqual(join(214, item: t1), t2, "three quarters down t2")
        XCTAssertNil(join(220, item: t1), "bottom quarter of t2: reorder")
        XCTAssertNil(join(245, item: t1), "its own row")
        XCTAssertEqual(join(23, item: t1), p, "a Today tab onto a pinned tab")
        XCTAssertEqual(join(105, from: .pinned, item: p), f1, "a pinned tab onto a pinned folder's tab")
        XCTAssertEqual(join(245, from: .pinned, item: f1), t1, "a pinned folder's tab onto a Today tab")
        XCTAssertNil(join(64, item: t1), "the folder's middle stays a drop into it")
        XCTAssertNil(join(204, .folder, item: folder), "a folder never joins")
        XCTAssertNil(join(204, from: .favorites, item: v[0]), "a Favorites tile never joins")
        XCTAssertNil(join(150, item: t1), "the New Tab row")
        // Where the feedback says join, the reducer makes the split there.
        d.user(.split(.joinRow(t1, onto: try XCTUnwrap(join(204, item: t1)))))
        let split = try XCTUnwrap(d.view.content.split)
        XCTAssertEqual(d.view.space.today.rows.map(\.id), [split])
        XCTAssertEqual(d.view.content.panes.map(\.tab), [t1, t2])
        // Left or right is the pointer against the row's midpoint (Q15: 428 and 434 on screen are 108 and 114 in the window).
        func side(_ x: Double, _ y: Double = 204, rows: [RowFrame]? = nil, space: SpaceSnapshot? = nil, item: ItemID) -> SplitJoin? {
            TablistLayout.splitTarget(at: CGPoint(x: x, y: y), rows: rows ?? TablistLayout.rows(space ?? d.view.space, width: 228), space: space ?? d.view.space,
                                      dragging: .tab, from: .today, item: item)
        }
        d.user(.split(.separateAll))
        let after = d.view.space.today.rows.map(\.id)
        let plain = TablistLayout.rows(d.view.space, width: 228)
        let target = try XCTUnwrap(after.first { $0 != t1 })
        let y = try XCTUnwrap(plain.first { $0.kind == .item(target) }).rect.midY
        XCTAssertEqual(side(108, y, rows: plain, item: t1)?.paneIndex, 0)
        XCTAssertEqual(side(114, y, rows: plain, item: t1)?.paneIndex, 1)
        XCTAssertEqual(side(10, y, rows: plain, item: t1), .tab(target, leading: true))
        XCTAssertEqual(side(220, y, rows: plain, item: t1), .tab(target, leading: false))
    }

    /// Arc's Q15-e/f/g: a split row answers as a whole; the place follows the pointer, the nearest boundary between panes.
    func testASplitRowTakesAPlaceBetweenItsPanes() throws {
        let (d, _, _, _, t1, t2, _) = makeSidebar()
        d.user(.split(.joinRow(t1, onto: t2, at: 0)))
        let split = try XCTUnwrap(d.view.content.split)
        let extra = d.open("extra.example.com")
        let space = d.view.space, rows = TablistLayout.rows(space, width: 228)
        let y = try XCTUnwrap(rows.first { $0.kind == .item(split) }).rect.midY
        func at(_ x: Double, _ y: Double) -> SplitJoin? { TablistLayout.splitTarget(at: CGPoint(x: x, y: y), rows: rows, space: space, dragging: .tab, from: .today, item: extra) }
        // Two panes over 8...220: boundaries at 8, 114, 220.
        XCTAssertEqual(at(30, y), .split(split, index: 0), "Q15-f: the left end")
        XCTAssertEqual(at(114, y), .split(split, index: 1), "between the two (inferred)")
        XCTAssertEqual(at(200, y), .split(split, index: 2), "Q15-g: the right end")
        // The row's top and bottom edges still reorder.
        let row = try XCTUnwrap(rows.first { $0.kind == .item(split) }).rect
        XCTAssertNil(at(114, row.minY + 9.5))
        XCTAssertNil(at(114, row.maxY - 9.5))
        XCTAssertNotNil(at(114, row.minY + 11.5))
        XCTAssertNotNil(at(114, row.maxY - 11.5))
    }

    func testFavoriteTilesDropOnTheCellUnderThePointer() throws {
        let (d, _, _, _, t1, _, v) = makeSidebar()
        let frames = try XCTUnwrap(d.frames().sidebar)
        let favorites = d.view.favorites
        // Three tiles at width 228 fill the row: third-width tiles, one row at y 90...137.
        let third = 196.0 / 3
        for (id, x) in zip(v, [8, 8 + third + 8, 8 + 2 * third + 16]) {
            let rect = try XCTUnwrap(frames.favoriteTiles[id])
            XCTAssertEqual(rect.minX, x, accuracy: 1e-9)
            XCTAssertEqual(rect.minY, 90)
            XCTAssertEqual(rect.size.width, third, accuracy: 1e-9)
            XCTAssertEqual(rect.size.height, 47)
        }
        func drop(_ x: Double, _ y: Double, _ kind: ItemKind = .tab, item: ItemID?) -> Destination? {
            FavoritesGrid.dropTarget(at: CGPoint(x: x, y: y), frames: frames, favorites: favorites, dragging: kind, item: item)
        }
        // A reorder keeps three cells: v3 over the first cell lands first, v1 over the second lands second.
        XCTAssertEqual(drop(10, 100, item: v[2]), .into(parent: favorites.root, index: 0))
        XCTAssertEqual(drop(100, 100, item: v[0]), .into(parent: favorites.root, index: 1))
        // A Today tab makes four cells (47 wide): x 114 is the second... at 8, 63, 118, 173.
        XCTAssertEqual(drop(60, 100, item: t1), .into(parent: favorites.root, index: 1), "half a gap left of the second cell")
        XCTAssertEqual(drop(114, 100, item: t1), .into(parent: favorites.root, index: 2))
        XCTAssertEqual(drop(200, 143, item: t1), .into(parent: favorites.root, index: 3), "the tray's bottom edge counts as the last row")
        // A folder is refused; outside the tray (82...145) is nil.
        XCTAssertNil(drop(100, 100, .folder, item: nil))
        XCTAssertNil(drop(100, 300, item: t1))
        d.user(.item(.move(v[2], to: try XCTUnwrap(drop(10, 100, item: v[2])))))
        XCTAssertEqual(d.view.favorites.tiles.map(\.id), [v[2], v[0], v[1]])
    }

    /// The user's report (verify/visual-pairs/run-20261103/Q18): with no Favorites and the hint closed the tray has no
    /// height, so there was nowhere to drop a tab. The strip above the Space name (the URL pill) is the way in: a tab
    /// held there opens one full-width cell and a release makes it the first Favorite.
    func testAnEmptyTrayWithTheHintClosedTakesATabFromThePillStrip() throws {
        let d = LayoutDriver()
        let tab = d.view.space.today.rows[0].id
        XCTAssertTrue(d.view.favorites.tiles.isEmpty)
        // With the box showing there is no strip: the box itself is the target.
        XCTAssertNil(FavoritesGrid.emptyDropZone(frames: try XCTUnwrap(d.frames().sidebar), favorites: d.view.favorites))
        d.user(.tabTools(.dismissFavoritesHint))
        let rest = try XCTUnwrap(d.frames().sidebar)
        let favorites = d.view.favorites
        XCTAssertEqual(rest.favoritesTray.height, 0)
        XCTAssertEqual(rest.spaceHeader.minY, rest.urlPill.maxY, "the Space name sits right under the pill")
        let zone = try XCTUnwrap(FavoritesGrid.emptyDropZone(frames: rest, favorites: favorites))
        XCTAssertEqual(zone, CGRect(x: rest.frame.minX, y: rest.urlPill.minY, width: rest.frame.width, height: rest.urlPill.height))
        func drop(_ point: CGPoint, _ frames: SidebarFrames, _ kind: ItemKind = .tab) -> Destination? {
            FavoritesGrid.dropTarget(at: point, frames: frames, favorites: favorites, dragging: kind, item: tab)
        }
        let onPill = CGPoint(x: rest.urlPill.midX, y: rest.urlPill.midY)
        XCTAssertEqual(drop(onPill, rest), .into(parent: favorites.root, index: 0))
        XCTAssertNil(drop(onPill, rest, .folder), "Favorites hold tabs only")
        XCTAssertNil(drop(CGPoint(x: rest.spaceHeader.midX, y: rest.spaceHeader.midY), rest), "the Space name strip is its own target")
        // Held there, the tray opens one cell and everything below moves down by it.
        let open = FavoritesGrid.applying(.incoming(slot: 0), to: rest, favorites: favorites)
        let one = FavoritesGrid.tiles(count: 1, width: rest.frame.width)
        XCTAssertEqual(open.favoritesTray.height, one.tray.height)
        XCTAssertEqual(open.spaceHeader.minY, rest.spaceHeader.minY + one.tray.height)
        XCTAssertEqual(open.tablistViewport.minY, rest.tablistViewport.minY + one.tray.height)
        XCTAssertEqual(FavoritesGrid.layout([], width: rest.frame.width, hintDismissed: true, drag: .incoming(slot: 0)).gap, one.tiles[0])
        // The open cell and the strip both take the release.
        XCTAssertEqual(drop(CGPoint(x: open.favoritesTray.midX, y: open.favoritesTray.midY), open), .into(parent: favorites.root, index: 0))
        XCTAssertEqual(drop(onPill, open), .into(parent: favorites.root, index: 0))
        d.user(.item(.move(tab, to: try XCTUnwrap(drop(onPill, rest)))))
        XCTAssertEqual(d.view.favorites.tiles.map(\.id), [tab])
        XCTAssertEqual(try XCTUnwrap(d.frames().sidebar?.favoriteTiles[tab]).width, rest.frame.width - 16, "one tile, the full width")
        XCTAssertNil(FavoritesGrid.emptyDropZone(frames: try XCTUnwrap(d.frames().sidebar), favorites: d.view.favorites), "no strip once there is a tile")
    }
}
