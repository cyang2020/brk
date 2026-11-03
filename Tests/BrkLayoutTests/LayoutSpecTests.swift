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
    /// sidebar visible: content.x = sidebar width (Arc's card starts at the sidebar edge), inset on the other three sides, radius = LAYOUT.contentRadius
    func test_sidebarVisibleContentXSidebarWidthInsetInsetOnTheOtherThreeSidesRadiusLAYOUT() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        let frames = d.frames()
        XCTAssertEqual(frames.contentSize, size)
        XCTAssertEqual(frames.contentArea, CGRect(x: 228, y: 10, width: 1042, height: 756))
        XCTAssertEqual(frames.cards, [CardFrame(pane: 0, content: .page(PageID(window: d.window, item: a)), rect: frames.contentArea, cornerRadius: 6)])
        XCTAssertEqual(frames.sidebar?.frame, CGRect(x: 0, y: 0, width: 228, height: 776))
        XCTAssertFalse(frames.sidebarFloats)
        XCTAssertEqual(frames.resizeHandle, CGRect(x: 224, y: 11, width: 8, height: 754))
        XCTAssertNil(frames.revealStrip)
        XCTAssertNil(frames.commandBar)
        XCTAssertNil(frames.library)
        XCTAssertEqual(frames.dividers, [])
        d.user(.sidebar(.resize(width: 300)))
        XCTAssertEqual(d.frames().contentArea.minX, 300)
    }

    /// sidebar hidden: the content card spans the window minus the inset on every side and keeps its radius
    func test_sidebarHiddenTheContentCardSpansTheWindowMinusTheInsetOnEverySideAndKeeps() throws {
        let d = LayoutDriver()
        d.user(.sidebar(.toggle))
        let frames = d.frames()
        XCTAssertEqual(frames.contentArea, CGRect(x: 10, y: 10, width: 1260, height: 756))
        XCTAssertEqual(frames.cards.map(\.rect), [frames.contentArea])
        XCTAssertEqual(frames.cards.map(\.cornerRadius), [6])
        XCTAssertNil(frames.sidebar)
        XCTAssertNil(frames.resizeHandle)
        XCTAssertEqual(frames.revealStrip, CGRect(x: -20, y: 0, width: 35, height: 776), "2 x 10 outside to 1.5 x 10 inside")
    }

    /// hidden + peek: floatingSidebar is the sidebar column over the content; content unchanged
    func test_hiddenPeekFloatingSidebarIsTheSidebarColumnOverTheContentContentUnchanged() throws {
        let d = LayoutDriver()
        d.user(.sidebar(.toggle))
        let hidden = d.frames()
        d.user(.sidebar(.peek(true)))
        let peek = d.frames()
        XCTAssertEqual(peek.contentArea, hidden.contentArea)
        XCTAssertEqual(peek.cards, hidden.cards)
        XCTAssertTrue(peek.sidebarFloats)
        XCTAssertEqual(peek.sidebar?.frame, CGRect(x: 5, y: 5, width: 228, height: 766))
        // Peek only matters while hidden.
        var visible = d.view
        visible.sidebar.visible = true
        let anchored = d.frames(visible)
        XCTAssertFalse(anchored.sidebarFloats)
        XCTAssertEqual(anchored.sidebar?.frame, CGRect(x: 0, y: 0, width: 228, height: 776))
    }

    /// two panes: side by side, equal heights, one inset gap between them, integer pixels, last pane absorbs rounding
    func test_twoPanesSideBySideEqualHeightsOneInsetGapBetweenThemIntegerPixelsLastPane() throws {
        let area = CGRect(x: 238, y: 10, width: 1032, height: 756)
        let (two, dividers) = ContentLayout.cards(in: area, fractions: [1.0 / 3, 2.0 / 3])
        XCTAssertEqual(two, [CGRect(x: 238, y: 10, width: 341, height: 756), CGRect(x: 589, y: 10, width: 681, height: 756)])
        XCTAssertEqual(dividers, [CGRect(x: 579, y: 10, width: 10, height: 756)])
        XCTAssertEqual(two[1].maxX, area.maxX)
        for rect in two { XCTAssertEqual(rect, rect.integral) }
        // Four panes: three gaps, widths sum to the content width minus the gaps, the last ends at the edge.
        let (four, gaps) = ContentLayout.cards(in: area, fractions: [0.25, 0.25, 0.25, 0.25])
        XCTAssertEqual(four.map(\.width), [251, 251, 251, 249])
        XCTAssertEqual(gaps.count, 3)
        XCTAssertEqual(four.last?.maxX, area.maxX)
        // Stacked (vertical orientation) splits the height instead.
        let (stacked, _) = ContentLayout.cards(in: area, fractions: [0.5, 0.5], orientation: .vertical)
        XCTAssertEqual(stacked, [CGRect(x: 238, y: 10, width: 1032, height: 373), CGRect(x: 238, y: 393, width: 1032, height: 373)])
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

    /// overlay command-bar: overlay rect is the full window; overlay archive: overlay rect equals content
    /// (Swift: the command bar frame is the bar's box, centred in the content area; the archive is the content area,
    /// beside the Library panel that replaces the sidebar.)
    func test_overlayCommandBarOverlayRectIsTheFullWindowOverlayArchiveOverlayRectEquals() throws {
        let d = LayoutDriver()
        d.user(.commandBar(.open(.newTab)))
        let bar = d.frames()
        XCTAssertEqual(bar.commandBar.map { CGPoint(x: $0.midX, y: $0.midY) }, CGPoint(x: bar.contentArea.midX, y: bar.contentArea.midY))
        XCTAssertNil(bar.library)
        d.user(.library(.open(.archive)))
        let archive = d.frames()
        // The Library's panel replaces the sidebar (Arc: max(417, min(window - 56, sidebar width)) wide, here 417 for a
        // 228 sidebar): a 112 pt navigation column and the archive's column beside it; the content area keeps the page.
        let panel = CGRect(x: 0, y: 0, width: 417, height: 776)
        XCTAssertEqual(archive.library?.frame, panel)
        XCTAssertEqual(archive.library?.strip, panel)
        XCTAssertEqual(archive.library?.nav, CGRect(x: 0, y: 0, width: 112, height: 776))
        XCTAssertEqual(archive.library?.page, CGRect(x: 112, y: 0, width: 305, height: 776))
        XCTAssertEqual(archive.contentArea, CGRect(x: 427, y: 10, width: 843, height: 756))
        XCTAssertEqual(archive.cards.map(\.rect), [archive.contentArea])
        XCTAssertNil(archive.sidebar)
        XCTAssertNil(archive.resizeHandle)
        XCTAssertNil(archive.revealStrip)
        // One 78 pt cell per page in Arc's order, 100 apart from y 94 in a 776 pt window (P32); the exit button is the
        // dock's Library button, the gift button level with it at the column's right.
        XCTAssertEqual(LibraryPage.allCases, [.media, .downloads, .easelsAndNotes, .spaces, .boosts, .archive])
        XCTAssertEqual(LibraryPage.allCases.map { archive.library?.pageCells[$0] },
                       (0..<6).map { CGRect(x: 9.5, y: 94 + 100 * Double($0), width: 94.5, height: 78) })
        XCTAssertEqual(LibraryLayout.closeButton(in: panel), CGRect(x: 8, y: 735, width: 32, height: 32))
        XCTAssertEqual(LibraryLayout.giftButton(in: archive.library!.nav), CGRect(x: 73, y: 735, width: 32, height: 32))
        XCTAssertEqual(LibraryLayout.trafficLightsOrigin(in: panel), bar.sidebar?.trafficLightsOrigin, "the window buttons stay put")
        XCTAssertNil(archive.commandBar)
        XCTAssertEqual(archive.frame(of: .library), archive.library?.frame)
        XCTAssertEqual(archive.frame(of: .archive), archive.library?.page)
        // The Spaces page widens the panel to hold a 240 pt card per space and the + button (P32-d: two spaces, 745).
        d.user(.space(.create(title: "Second", icon: .none, theme: .default)))
        d.user(.library(.open(.spaces)))
        XCTAssertEqual(d.frames().library?.strip.width, 745)
        XCTAssertEqual(d.frames().contentArea.minX, 755)
        XCTAssertEqual(LibraryLayout.panelWidth(windowWidth: 700, sidebarWidth: 228, page: .spaces, spaces: 2), 644, "never past the window minus 56")
        d.user(.library(.open(.archive)))
        // A wider sidebar keeps its width up to the window minus 56, never below 417; a hidden one is replaced all the same.
        var wide = d.view
        wide.sidebar.width = 450
        XCTAssertEqual(d.frames(wide).library?.strip.width, 450)
        XCTAssertEqual(d.frames(wide, size: CGSize(width: 480, height: 776)).library?.strip.width, 424)
        XCTAssertEqual(d.frames(wide, size: CGSize(width: 440, height: 776)).library?.strip.width, 417)
        d.user(.sidebar(.toggle))
        d.user(.library(.open(.archive)))
        let hidden = d.frames()
        XCTAssertEqual(hidden.library?.strip, panel)
        XCTAssertEqual(hidden.contentArea, CGRect(x: 427, y: 10, width: 843, height: 756))
        XCTAssertNil(hidden.revealStrip)
        d.user(.commandBar(.dismiss))
        XCTAssertNil(d.frames().library)
        XCTAssertNil(d.frames().commandBar)
        XCTAssertNotNil(d.frames().revealStrip, "the hidden sidebar is back to its reveal strip")
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

    func testFavoriteTilesReorderInsideTheGrid() throws {
        let (d, _, _, _, t1, _, v) = makeSidebar()
        let frames = try XCTUnwrap(d.frames().sidebar)
        let favorites = d.view.favorites
        // Three tiles at width 228: x 8, 63, 118 (47 wide, gap 8), one row at y 90...137.
        XCTAssertEqual(v.map { frames.favoriteTiles[$0] }, [
            CGRect(x: 8, y: 90, width: 47, height: 47), CGRect(x: 63, y: 90, width: 47, height: 47), CGRect(x: 118, y: 90, width: 47, height: 47),
        ])
        func drop(_ x: Double, _ y: Double, _ kind: ItemKind = .tab, item: ItemID?) -> Destination? {
            FavoritesGrid.dropTarget(at: CGPoint(x: x, y: y), frames: frames, favorites: favorites, dragging: kind, item: item)
        }
        // v3 dragged before v1: index 0.
        XCTAssertEqual(drop(10, 100, item: v[2]), .into(parent: favorites.root, index: 0))
        // v1 dragged right of v2's centre: after v2, counted after v1 is detached: index 1.
        XCTAssertEqual(drop(100, 100, item: v[0]), .into(parent: favorites.root, index: 1))
        // A Today tab dropped in the row's band (half a gap around the tiles) goes by x; below it, it appends; a
        // folder is refused; outside the tray (82...145) is nil.
        XCTAssertEqual(drop(100, 140, item: t1), .into(parent: favorites.root, index: 2))
        XCTAssertEqual(drop(100, 143, item: t1), .into(parent: favorites.root, index: 3))
        XCTAssertNil(drop(100, 100, .folder, item: nil))
        XCTAssertNil(drop(100, 300, item: t1))
        d.user(.item(.move(v[2], to: try XCTUnwrap(drop(10, 100, item: v[2])))))
        XCTAssertEqual(d.view.favorites.tiles.map(\.id), [v[2], v[0], v[1]])
    }

    func testRowFramesConvertToWindowCoordinates() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        let frames = d.frames()
        // Viewport at y 232 (under the empty favorites box); the first Today row follows spacer (2+1), divider (16+1),
        // New Tab (40+1): document y 61.
        XCTAssertEqual(frames.frame(of: .row(a)), CGRect(x: 0, y: 293, width: 228, height: 40))
        XCTAssertEqual(frames.frame(of: .todayNewTab), CGRect(x: 0, y: 252, width: 228, height: 40))
        XCTAssertEqual(frames.frame(of: .urlPill), CGRect(x: 8, y: 46, width: 212, height: 36))
        XCTAssertEqual(frames.frame(of: .dockLibrary), CGRect(x: 8, y: 735, width: 32, height: 32))
        XCTAssertNil(frames.frame(of: .renameField), "view-owned")
    }
}
