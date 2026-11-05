import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// R5-3: Arc's Favorites and sidebar rows under a real mouse (verify/visual-pairs/run-20261103/Q13). Setup moves tabs by
/// command; every gesture under test is posted through the window server, so it is the same path a person's mouse takes.
enum FavoritesDragScenarios {
    static let all = [
        Scenario("R53-PressOpens", "a real press opens a Today row, a pinned row and a Favorite while the button is still down; Command and Shift clicks only select", cefOnly: "real mouse", pressOpens),
        Scenario("R53-TabIn", "a Today tab and a pinned tab held over four Favorites reflow them to 3+2 with the empty cell under the pointer, and land there as the current tab; a folder is refused", cefOnly: "real mouse", tabIn),
        Scenario("R53-Reorder", "a Favorite held inside the grid slides the others live and lands in the cell under the pointer", cefOnly: "real mouse", reorder),
        Scenario("R53-Out", "a Favorite dragged out leaves its cell empty, shows a row and lands in Today or Pinned as the current tab; the grid rebalances after the release", cefOnly: "real mouse", out),
        Scenario("R53-Strip", "a tab held on the Space name strip darkens it; dropped, it is the first pinned tab, current, with Double-click to rename", cefOnly: "real mouse", strip),
        Scenario("R53-Empty", "Favorites dragged out one at a time go 3 wide, 2 wide, 1 full width, then the dashed box; a tab dropped on the box is one full-width tile", cefOnly: "real mouse", empty),
        Scenario("R53-EmptyClosed", "with no Favorites and the hint closed, a tab held on the URL pill opens one full-width cell and the release makes it the first Favorite", cefOnly: "real mouse", emptyClosed),
        Scenario("R53-SplitSides", "a tab held on another tab's middle shows a slot under the pointer's half and lands on that side, focused; 9.5 pt from the edge reorders, 11.5 pt is a slot; on a split row one band, and the left and right ends make it the first and the last pane", cefOnly: "real mouse", splitSides),
        Scenario("R53-Page", "a Favorite over the page brings the earlier tab back, shows the big card and the slots; released on a slot its tile stays and a new tab joins, in the middle nothing moves and it is the current tab", cefOnly: "real mouse", page),
        Scenario("R54-Halves", "a tab released on the left half and on the right half of the page makes a split with it on that side and focused", cefOnly: "real mouse", halves),
        Scenario("R54-Frame", "a tab held on the middle of the page frames it; released, no split, nothing moves and the dragged tab is current", cefOnly: "real mouse", frameDrop),
        Scenario("R54-Favorite", "a Favorite released on the right half: its tile stays, the split holds a new Today tab at its address, and the tab stays in Today when the split comes apart", cefOnly: "real mouse", favoriteDrop),
        Scenario("R54-Pinned", "a pinned tab released on the right half stays pinned; the split holds a new Today tab at its address; apart, the tab stays in Today", cefOnly: "real mouse", pinnedRelease),
        Scenario("R54-PaneHold", "a third tab over a two pane split: a slot at the far left through the left pane, a frame around the right pane", cefOnly: "real mouse", paneHold),
        Scenario("R54-PaneDrop", "a third tab released on a framed pane takes it and the focus; the old tab is the row right after the split row and keeps its page; apart, the order is the two panes then the old tab", cefOnly: "real mouse", paneDrop),
        Scenario("R54-FullSplit", "a full split of four shows only frames; a release replaces that pane and the count stays four", cefOnly: "real mouse", fullSplit),
        Scenario("R54-Paths", "the same place shows a different preview by path, as in Arc: a left slot holds up to the middle, a right slot back to the middle, the frame otherwise; a tab over its own page gets slots and no frame", cefOnly: "real mouse", paths),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios

    /// Four Favorites, Pinned [Home, Docs], Today [a, b, c] with `c` shown.
    private struct Fixture {
        var favorites: [ItemID]
        var home: ItemID, docs: ItemID
        var a: ItemID, b: ItemID, c: ItemID
    }

    private static func fixture(_ app: AppUnderTest, favorites count: Int = 4) throws -> Fixture {
        var tiles: [ItemID] = []
        for n in 0..<count { tiles.append(try E.loadReady(app, "page2.html?fav=\(n)")) }
        let home = try E.loadReady(app, "page2.html?pin=home"), docs = try E.loadReady(app, "page2.html?pin=docs")
        let a = try E.loadReady(app, "page2.html?today=a"), b = try E.loadReady(app, "page2.html?today=b"), c = try E.loadReady(app, "page2.html?today=c")
        let root = try app.view().favorites.root, pinned = try app.view().space.pinned.root
        for (n, tile) in tiles.enumerated() { try app.dispatch(.item(.move(tile, to: .into(parent: root, index: n)))) }
        try app.dispatch(.item(.move(home, to: .into(parent: pinned, index: 0))))
        try app.dispatch(.item(.move(docs, to: .into(parent: pinned, index: 1))))
        try app.dispatch(.tab(.focus(c)))
        try app.waitUntil("c shown") { try E.shown(app.view()) == c }
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real mouse events") }
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        return Fixture(favorites: tiles, home: home, docs: docs, a: a, b: b, c: c)
    }

    private static func frame(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect { try visible(app.native(), id).frame }
    private static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
    private static func tiles(_ app: AppUnderTest) throws -> [ItemID] { try app.view().favorites.tiles.map(\.id) }
    private static func shown(_ app: AppUnderTest) throws -> ItemID? { try E.shown(app.view()) }

    private static func cells(_ app: AppUnderTest, count: Int) throws -> [CGRect] {
        let tray = try frame(app, .favoritesTray)
        return FavoritesGrid.tiles(count: count, width: tray.width).tiles.map { $0.offsetBy(dx: tray.minX, dy: tray.minY) }
    }

    /// Tile frames on screen settle to `expected` (the slide takes a moment).
    private static func settled(_ app: AppUnderTest, _ what: String, _ expected: [ItemID: CGRect]) throws {
        try app.waitUntil(what, timeout: 3) {
            let actual = try app.native().actual
            return expected.allSatisfy { id, rect in
                guard let view = actual[ViewID.favorite(id).identifier] else { return false }
                return abs(view.frame.minX - rect.minX) < 0.75 && abs(view.frame.minY - rect.minY) < 0.75 && abs(view.frame.width - rect.width) < 0.75
            }
        }
    }

    private static func image(_ app: AppUnderTest) throws -> CGRect { try frame(app, .tabTool("drag-image")) }

    // MARK: Rule 3

    @Sendable static func pressOpens(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        for (id, name): (ViewID, String) in [(.row(f.a), "Today row"), (.row(f.home), "pinned row"), (.favorite(f.favorites[1]), "Favorite")] {
            let target: ItemID = switch id { case .row(let item), .favorite(let item): item; default: f.c }
            try PhysicalPointer.press(app, at: centre(frame(app, id)), window: app.window!) {
                try app.waitUntil("\(name) open with the button down") { try shown(app) == target }
                _ = try app.screenshot("held-\(name.replacingOccurrences(of: " ", with: "-"))")
            }
            try expect(try shown(app) == target, "\(name) closed again on the release")
        }
        // The multi-select clicks open nothing.
        try app.dispatch(.tab(.focus(f.c)))
        try app.waitUntil("c shown") { try shown(app) == f.c }
        try app.click(.row(f.a), modifiers: "cmd")
        try app.click(.row(f.b), modifiers: "cmd")
        try app.waitUntil("two rows selected") { Set(try app.view().tabTools.selected).isSuperset(of: [f.a, f.b]) }
        try expect(try shown(app) == f.c, "a Command click opened a row")
        try app.click(.row(f.b), modifiers: "shift")
        try expect(try shown(app) == f.c, "a Shift click opened a row")
        // A double click still renames.
        try app.dispatch(.tabTools(.select(f.a, .replace)))
        let row = try centre(frame(app, .row(f.a)))
        try PhysicalPointer.doubleClick(app, at: row, window: app.window!)
        try app.waitUntil("a double click renames") { try app.view().renaming == f.a }
        try app.press("escape")
    }

    // MARK: Rule 4

    @Sendable static func tabIn(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let tray = try frame(app, .favoritesTray), rowY = tray.minY + 31
        let restHeader = try frame(app, .row(f.home)).minY
        // Q13-a: x 114 is the second of the five cells. Pressed 86 along the row, as the reference.
        let start = CGPoint(x: 86, y: try frame(app, .row(f.a)).midY)
        try PhysicalPointer.drag(app, through: [start, CGPoint(x: 114, y: rowY)], window: app.window!) {
            let five = try cells(app, count: 5)
            try settled(app, "the four tiles flow around the second cell", [f.favorites[0]: five[0], f.favorites[1]: five[2], f.favorites[2]: five[3], f.favorites[3]: five[4]])
            try app.waitUntil("the list makes room for the second row") { try frame(app, .row(f.home)).minY == restHeader + 55 }
            let tile = try image(app)
            try expect(abs(tile.width - 196.0 / 3) < 0.5 && tile.height == 47, "the drag image is \(tile), not a tile of the new layout")
            try expect(try shown(app) == f.a, "the press did not open the dragged tab")
            _ = try app.screenshot("second-cell")
        }
        try app.waitUntil("a is the second Favorite") { try tiles(app) == [f.favorites[0], f.a, f.favorites[1], f.favorites[2], f.favorites[3]] }
        try expect(try shown(app) == f.a, "the dropped tab is not current")
        try expect(try app.view().favorites.tiles.first { $0.id == f.a }?.status == .current, "its tile is not the current one")
        // The empty end of the last row appends.
        let six = try cells(app, count: 6)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.b))), centre(six[5])], window: app.window!) {
            try app.waitUntil("3+3: the sixth cell empty") { try frame(app, .favorite(f.favorites[3])).minX == (try cells(app, count: 6))[4].minX }
        }
        try app.waitUntil("b appended") { try tiles(app).last == f.b && tiles(app).count == 6 }
        // A pinned tab does the same (Q13-f).
        let seven = try cells(app, count: 7)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.home))), centre(seven[0])], window: app.window!) {
            try app.waitUntil("4+3") { try frame(app, .favorite(f.favorites[0])).minX == (try cells(app, count: 7))[1].minX }
            _ = try app.screenshot("pinned-tab")
        }
        try app.waitUntil("Home is the first Favorite") { try tiles(app).first == f.home }
        // A folder is refused: nothing makes room and nothing moves.
        let folder = try E.newFolder(app, "Box")
        let before = try tiles(app), rest = try frame(app, .favorite(before[1]))
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(folder))), centre(rest)], window: app.window!) {
            app.sleep(0.4)
            try expect(try frame(app, .favorite(before[1])) == rest, "the grid made room for a folder")
            _ = try app.screenshot("folder-refused")
        }
        app.sleep(0.3)
        try expect(try tiles(app) == before, "a folder moved the Favorites")
        try expect(try app.view().space.pinned.rows.contains { $0.id == folder }, "the folder left Pinned")
    }

    // MARK: Rule 5

    @Sendable static func reorder(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let four = try cells(app, count: 4)
        // Q13-c: the first over the third.
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(f.favorites[0]))), centre(four[2])], window: app.window!) {
            try settled(app, "the others slide", [f.favorites[1]: four[0], f.favorites[2]: four[1], f.favorites[3]: four[3]])
            let tile = try image(app)
            try expect(abs(tile.midX - four[2].midX) < 1 && tile.width == 47, "the drag image is \(tile)")
            try expect(try shown(app) == f.favorites[0], "the press did not open it")
            _ = try app.screenshot("first-over-third")
        }
        try app.waitUntil("reordered") { try tiles(app) == [f.favorites[1], f.favorites[2], f.favorites[0], f.favorites[3]] }
        try expect(try shown(app) == f.favorites[0], "the dropped tile is not current")
    }

    // MARK: Rule 6

    @Sendable static func out(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let four = try cells(app, count: 4)
        // Today is c, b, a (newest first) over the first page: between c and b.
        let line = CGPoint(x: 86, y: try frame(app, .row(f.c)).maxY)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(f.favorites[3]))), line], window: app.window!) {
            try settled(app, "the others keep size and place", [f.favorites[0]: four[0], f.favorites[1]: four[1], f.favorites[2]: four[2]])
            let row = try image(app)
            try expect(row.width == 212 && row.height == 36, "the drag image is \(row), not a row")
            try expect(abs(row.midX - line.x) < 1, "the row is not centred on the pointer: \(row)")
            _ = try app.screenshot("to-today")
        }
        try app.waitUntil("a Today row") { Array(try app.view().space.today.rows.map(\.id).prefix(4)) == [f.c, f.favorites[3], f.b, f.a] }
        try expect(try shown(app) == f.favorites[3], "not the current tab")
        let three = try cells(app, count: 3)
        try settled(app, "three wide tiles after the release", [f.favorites[0]: three[0], f.favorites[1]: three[1], f.favorites[2]: three[2]])
        // To Pinned: between Home and Docs.
        let pinnedLine = CGPoint(x: 86, y: try frame(app, .row(f.home)).maxY)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(f.favorites[0]))), pinnedLine], window: app.window!) {
            _ = try app.screenshot("to-pinned")
        }
        try app.waitUntil("a pinned row") { try app.view().space.pinned.rows.map(\.id) == [f.home, f.favorites[0], f.docs] }
        try expect(try shown(app) == f.favorites[0], "not the current tab")
    }

    // MARK: Rule 7

    @Sendable static func strip(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let tray = try frame(app, .favoritesTray)
        let point = CGPoint(x: 86, y: tray.maxY + 1)
        // Well right of the row image, so the sample reads the strip.
        let probe = CGPoint(x: tray.maxX - 2, y: tray.maxY + 30)
        let light = try app.pixel(probe)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.a))), point], window: app.window!) {
            try app.waitUntil("the strip darkens") { try app.pixel(probe)[0] < light[0] - 30 }
            try expect(abs(try frame(app, .favoritesTray).height - tray.height) < 0.5, "the grid made room for a drop on the strip")
            _ = try app.screenshot("held")
        }
        try app.waitUntil("first pinned") { try app.view().space.pinned.rows.first?.id == f.a }
        try expect(try shown(app) == f.a, "not selected")
        try app.waitUntil("the hint line") { try tab(f.a, in: app.view())?.renameHint == true }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        let row = try frame(app, .row(f.a))
        try app.waitUntil("Double-click to rename shows in the row") {
            let window = try app.native().windowFrame
            let top = CGDisplayBounds(CGMainDisplayID()).height - window.maxY
            return NativeSystemInput.staticTexts(pid: hello.pid).contains { $0.text == "Double-click to rename" && row.offsetBy(dx: window.minX, dy: top).insetBy(dx: -2, dy: -2).intersects($0.frame) }
        }
        _ = try app.screenshot("dropped")
        // The hint goes with the tab.
        try app.dispatch(.tab(.focus(f.c)))
        try app.waitUntil("the hint left") { try tab(f.a, in: app.view())?.renameHint == false }
        // A Favorite on the strip too.
        let favoriteStart = try centre(frame(app, .favorite(f.favorites[0])))
        let strip = CGPoint(x: 86, y: try frame(app, .favoritesTray).maxY + 1)
        try PhysicalPointer.drag(app, through: [favoriteStart, strip], window: app.window!) {}
        try app.waitUntil("the Favorite is the first pinned tab") { try app.view().space.pinned.rows.first?.id == f.favorites[0] }
    }

    // MARK: Rule 8

    @Sendable static func empty(_ app: AppUnderTest) throws {
        let f = try fixture(app, favorites: 3)
        var left = f.favorites
        for width in [102.0, 212.0] {
            let tile = left.removeLast()
            try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(tile))), CGPoint(x: 86, y: try frame(app, .row(f.c)).midY - 10)], window: app.window!) {}
            try app.waitUntil("\(left.count) left") { try tiles(app) == left }
            try app.waitUntil("\(width) wide") { abs(try frame(app, .favorite(left[0])).width - width) < 0.75 }
            _ = try app.screenshot("\(left.count)-left")
        }
        let last = left.removeLast()
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(last))), CGPoint(x: 86, y: try frame(app, .row(f.c)).midY - 10)], window: app.window!) {}
        try app.waitUntil("no Favorites") { try tiles(app).isEmpty }
        try app.waitUntil("the dashed box is back") { isShown(try app.native(), .tabTool("favorites-empty-title")) }
        _ = try app.screenshot("box")
        let box = try frame(app, .favoritesTray)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.b))), centre(box)], window: app.window!) {
            try app.waitUntil("the box stays under the pointer") { abs(try frame(app, .favoritesTray).height - box.height) < 0.5 }
            _ = try app.screenshot("over-box")
        }
        try app.waitUntil("one tile") { try tiles(app) == [f.b] }
        try app.waitUntil("full width") { abs(try frame(app, .favorite(f.b)).width - 212) < 0.75 }
        _ = try app.screenshot("one-tile")
    }

    /// The user's report (verify/visual-pairs/run-20261103/Q18): with no Favorites and the "Drag to add Favorites" box
    /// closed, the tray had no height and there was nowhere to drop a tab. The strip of the URL pill is the way in: a tab
    /// held there opens one full-width cell under the pill, and the release makes it the first Favorite.
    @Sendable static func emptyClosed(_ app: AppUnderTest) throws {
        let f = try fixture(app, favorites: 1)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(f.favorites[0]))), CGPoint(x: 86, y: try frame(app, .row(f.c)).midY - 10)], window: app.window!) {}
        try app.waitUntil("no Favorites") { try tiles(app).isEmpty }
        try app.waitUntil("the dashed box") { isShown(try app.native(), .tabTool("favorites-empty-close")) }
        try PhysicalPointer.press(app, at: centre(frame(app, .tabTool("favorites-empty-close"))), window: app.window!) {}
        try app.waitUntil("the box is closed") { try app.view().favorites.hintDismissed }
        // The views as drawn (the held layout is the sidebar's own, not the snapshot's): the tray, and the first pinned
        // row, which moves down with the Space name when the tray opens.
        func tray() throws -> Double { Double(try app.native().actual[ViewID.favoritesTray.identifier]?.frame.height ?? 0) }
        func firstPinned() throws -> Double { Double(try frame(app, .row(f.home)).minY) }
        try app.waitUntil("the tray has no height") { try tray() == 0 }
        let pill = try frame(app, .urlPill), home = try firstPinned()
        try expect(try app.native().computed.sidebar?.spaceHeader.minY == pill.maxY, "the Space name is not right under the pill")
        _ = try app.screenshot("closed")
        // Held on the pill: one full-width cell opens under it and the list moves down by it; the image is a tile.
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.b))), centre(pill)], window: app.window!) {
            try app.waitUntil("the tray opens one cell") { abs(try tray() - 63) < 0.5 }
            try app.waitUntil("the list moves down") { abs(try firstPinned() - (home + 63)) < 0.5 }
            let image = try image(app)
            try expect(abs(image.width - 212) < 0.75 && abs(image.height - 47) < 0.75, "the drag image is \(image), not a full-width tile")
            _ = try app.screenshot("held-on-pill")
        }
        try app.waitUntil("one tile") { try tiles(app) == [f.b] }
        try app.waitUntil("full width") { abs(try frame(app, .favorite(f.b)).width - 212) < 0.75 }
        try expect(try shown(app) == f.b, "the dropped tab is not the current tab")
        _ = try app.screenshot("one-tile")
        // A tab held on the Space name, not on the pill, is still the strip's (first pinned), with a tile above it now.
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.a))), centre(frame(app, .favorite(f.b)))], window: app.window!) {}
        try app.waitUntil("two tiles") { try Set(tiles(app)) == [f.a, f.b] }
    }

    // MARK: The page

    @Sendable static func page(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let area = try app.native().computed.contentArea
        let tile = f.favorites[3]
        // Past the middle (from the left, a slot holds up to it): the earlier tab comes back, the card rides, the page is
        // framed. The release moves nothing and the Favorite is the current tab (the rule's replaceContent).
        let past = CGPoint(x: area.midX + 40, y: area.midY)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(tile))), past], window: app.window!) {
            try app.waitUntil("c shows again") { try shown(app) == f.c }
            let card = try frame(app, .tabTool("content-drag-card"))
            try expect(card.width == 169 && card.height == 250, "the card is \(card)")
            try app.waitUntil("the frame") { try frame(app, .splitDropPreview) == area }
            try expect(!isShown(try app.native(), .tabTool("drag-image")), "the row image is still showing")
            _ = try app.screenshot("middle")
        }
        app.sleep(0.3)
        try expect(try tiles(app).contains(tile), "a release in the middle moved the Favorite")
        try expect(try shown(app) == tile, "a release in the middle did not show the dragged tab")
        try app.dispatch(.tab(.focus(f.c)))
        try app.waitUntil("c shown") { try shown(app) == f.c }
        // The right half: the same slot as a row's (P23-d), and the release makes the split with a new tab.
        let edge = CGPoint(x: area.maxX - 40, y: area.midY)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(tile))), edge], window: app.window!) {
            try app.waitUntil("c shows again") { try shown(app) == f.c }
            let slot = try frame(app, .splitDropPreview)
            try expect(slot.minX > area.midX - 10 && slot.maxX <= area.maxX + 0.5, "the slot is \(slot)")
            _ = try app.screenshot("edge")
        }
        try app.waitUntil("the split") { try app.view().content.panes.count == 2 && app.view().content.panes[0].tab == f.c }
        try expect(try app.view().content.panes[1].tab != tile, "the Favorite itself went into the split")
        try expect(try tiles(app).contains(tile), "the Favorite left the grid")
    }

    // MARK: R5-4, the page (Q17)

    @Sendable static func halves(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let area = try app.native().computed.contentArea
        let left = CGPoint(x: area.minX + 200, y: area.midY), right = CGPoint(x: area.maxX - 200, y: area.midY)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.a))), left], window: app.window!) {
            try app.waitUntil("c shows again") { try shown(app) == f.c }
            try app.waitUntil("the left slot") {
                let slot = try frame(app, .splitDropPreview)
                return slot.minX == area.minX && abs(slot.width - 516) < 1
            }
            _ = try app.screenshot("left")
        }
        try app.waitUntil("the split") { try app.view().content.panes.map(\.tab) == [f.a, f.c] }
        try expect(try app.view().content.panes[0].focused, "the dragged tab is not focused")
        try app.dispatch(.split(.separateAll))
        try app.dispatch(.tab(.focus(f.c)))
        try app.waitUntil("c alone") { try app.view().content.panes.map(\.tab) == [f.c] }
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.b))), right], window: app.window!) {
            try app.waitUntil("the right slot") {
                let slot = try frame(app, .splitDropPreview)
                return slot.maxX == area.maxX && abs(slot.width - 516) < 1
            }
            _ = try app.screenshot("right")
        }
        try app.waitUntil("the split") { try app.view().content.panes.map(\.tab) == [f.c, f.b] }
        try expect(try app.view().content.panes[1].focused, "the dragged tab is not focused")
    }

    @Sendable static func frameDrop(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let area = try app.native().computed.contentArea
        let order = try app.view().space.today.rows.map(\.id), pinned = try app.view().space.pinned.rows.map(\.id)
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.a))), CGPoint(x: area.midX + 40, y: area.midY)], window: app.window!) {
            try app.waitUntil("c shows again") { try shown(app) == f.c }
            try app.waitUntil("the frame") { try frame(app, .splitDropPreview) == area }
            _ = try app.screenshot("frame")
        }
        try app.waitUntil("a shown") { try app.view().content.panes.map(\.tab) == [f.a] }
        try expect(try app.view().content.split == nil, "a split was made")
        try expect(try app.view().space.today.rows.map(\.id) == order && app.view().space.pinned.rows.map(\.id) == pinned, "something moved")
    }

    @Sendable static func favoriteDrop(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let area = try app.native().computed.contentArea
        let tile = f.favorites[3]
        let address = try app.view().favorites.tiles.first { $0.id == tile }?.url
        let grid = try tiles(app), today = try app.view().space.today.rows.map(\.id)
        // Through the page's left part first, as a person's drag goes, then to the right half: the tile stays out of the way.
        try PhysicalPointer.drag(app, through: [centre(frame(app, .favorite(tile))), CGPoint(x: area.maxX - 150, y: area.midY)], window: app.window!) {
            try app.waitUntil("the right slot") {
                let slot = try frame(app, .splitDropPreview)
                return slot.maxX == area.maxX && abs(slot.width - 516) < 1
            }
        }
        try app.waitUntil("the split") { try app.view().content.panes.count == 2 }
        let panes = try app.view().content.panes
        try expect(panes[0].tab == f.c && panes[1].focused, "the panes are \(panes.map(\.tab))")
        try expect(panes[1].tab != tile && !today.contains(panes[1].tab), "the second pane is not a new tab")
        func paneURL() throws -> URL? {
            for case .split(let row) in try app.view().space.today.rows { if let pane = row.panes.first(where: { $0.id == panes[1].tab }) { return pane.url } }
            return nil
        }
        try app.waitUntil("the new tab at the Favorite's address") { try paneURL() == address }
        let after = try tiles(app)
        try expect(after == grid, "the grid changed: \(after)")
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("apart") { try app.view().content.split == nil }
        try expect(try app.view().space.today.rows.contains { $0.id == panes[1].tab }, "the new tab left Today")
        try expect(try tiles(app) == grid, "the grid changed when the split came apart")
    }

    @Sendable static func pinnedRelease(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let area = try app.native().computed.contentArea
        let pinned = try app.view().space.pinned.rows.map(\.id), today = try app.view().space.today.rows.map(\.id)
        let address = try app.view().space.pinned.rows.compactMap { row -> URL? in if case .tab(let tab) = row, tab.id == f.home { return tab.url } else { return nil } }.first
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.home))), CGPoint(x: area.maxX - 220, y: area.midY)], window: app.window!) {
            try app.waitUntil("c shows again") { try shown(app) == f.c }
            try app.waitUntil("the right slot") {
                let slot = try frame(app, .splitDropPreview)
                return slot.maxX == area.maxX && abs(slot.width - 516) < 1
            }
            _ = try app.screenshot("pinned-held")
        }
        try app.waitUntil("the split") { let panes = try app.view().content.panes; return panes.count == 2 && panes[0].tab == f.c }
        let panes = try app.view().content.panes
        try expect(panes[1].tab != f.home && !today.contains(panes[1].tab), "the second pane is not a new tab")
        try expect(panes[1].focused, "the new tab is not focused")
        try expect(try app.view().space.pinned.rows.map(\.id) == pinned, "the pinned row moved")
        let split = try app.view().content.split
        try expect(try app.view().space.today.rows.map(\.id) == today.map { $0 == f.c ? split! : $0 }, "the split is not where c was")
        func paneURL() throws -> URL? {
            for case .split(let row) in try app.view().space.today.rows { if let pane = row.panes.first(where: { $0.id == panes[1].tab }) { return pane.url } }
            return nil
        }
        try app.waitUntil("the new tab at the pinned tab's address") { try paneURL() == address }
        _ = try app.screenshot("pinned-released")
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("apart") { try app.view().content.split == nil }
        try expect(try app.view().space.today.rows.contains { $0.id == panes[1].tab }, "the new tab left Today")
        try expect(try app.view().space.pinned.rows.map(\.id) == pinned, "the pinned row moved when the split came apart")
    }

    /// Today [split c | a, b, the first page] with the split shown.
    private static func splitOfTwo(_ app: AppUnderTest, _ f: Fixture) throws -> ItemID {
        try app.dispatch(.split(.joinRow(f.a, onto: f.c, at: 1)))
        try app.waitUntil("the split") { try app.view().content.panes.map(\.tab) == [f.c, f.a] }
        let split = try app.view().content.split!
        try app.dispatch(.tab(.focus(split)))
        return split
    }

    @Sendable static func paneHold(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let split = try splitOfTwo(app, f)
        let area = try app.native().computed.contentArea
        let row = centre(try frame(app, .row(f.b)))
        // Q17-split-hold-486-330: through the left pane's left band, then the pointer is on the slot.
        try held(app, [row, CGPoint(x: 486, y: 330)], back: split) {
            let slot = try frame(app, .splitDropPreview)
            try expect(slot.minX == area.minX && abs(slot.width - 341) < 1 && slot.height == area.height, "not the far left slot: \(slot)")
            let cards = [try frame(app, .card(0)), try frame(app, .card(1))]
            try expect(abs(cards[0].minX - 579) < 1 && abs(cards[0].width - 340) < 1 && abs(cards[1].minX - 929) < 1, "the pages did not make room: \(cards)")
            try expect(try app.view().content.split == split, "the split is not shown")
            _ = try app.screenshot("hold-left")
        }
        // Q17-split-hold-1012-330: a frame around the right pane, both pages back at their places.
        try held(app, [row, CGPoint(x: 1012, y: 330)], back: split) {
            let ring = try frame(app, .splitDropPreview), right = try frame(app, .card(1))
            try expect(ring == right && abs(ring.minX - 754) < 1 && abs(ring.width - 516) < 1, "the frame is \(ring), the pane \(right)")
            _ = try app.screenshot("hold-right")
        }
    }

    @Sendable static func paneDrop(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let split = try splitOfTwo(app, f)
        let pinned = try app.view().space.pinned.rows.map(\.id), rest = try app.view().space.today.rows.map(\.id).filter { $0 != split && $0 != f.b }
        let page = PageID(window: app.window!, item: f.a)
        let browser = try app.native().pages[page]?.browserID
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.b))), CGPoint(x: 1012, y: 330)], window: app.window!) {
            try app.waitUntil("the frame on the right pane") { try frame(app, .splitDropPreview) == frame(app, .card(1)) }
        }
        try app.waitUntil("the right pane") { try app.view().content.panes.map(\.tab) == [f.c, f.b] }
        let view = try app.view()
        try expect(view.content.panes[1].focused, "the dragged tab is not focused")
        try expect(view.content.split == split, "the split changed")
        try expect(view.space.today.rows.map(\.id) == [split, f.a] + rest, "Today reads \(view.space.today.rows.map(\.id))")
        try expect(view.space.pinned.rows.map(\.id) == pinned, "Pinned changed")
        _ = try app.screenshot("pane-released")
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("apart") { try app.view().content.split == nil }
        let apart = try app.view().space.today.rows.map(\.id)
        try expect(apart == [f.c, f.b, f.a] + rest, "after separating Today reads \(apart)")
        // The old tab's page was never closed: shown again it is the same browser, without a new load.
        let created = try app.pageLog().filter { $0.kind == .created && $0.page == page }
        try app.dispatch(.tab(.focus(f.a)))
        try app.waitUntil("the old tab shown with its browser") { try browser != nil && app.native().pages[page]?.browserID == browser }
        let after = try app.pageLog().filter { $0.kind == .created && $0.page == page }
        try expect(after == created, "the old tab's page was created again")
    }

    @Sendable static func fullSplit(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let split = try splitOfTwo(app, f)
        for (tab, at) in [(f.home, 2), (f.docs, 3)] {
            try app.dispatch(.split(.joinRow(tab, onto: split, at: at)))
        }
        try app.waitUntil("four panes") { try app.view().content.panes.count == 4 }
        let panes = try app.view().content.panes.map(\.tab)
        let area = try app.native().computed.contentArea
        let row = centre(try frame(app, .row(f.b)))
        // Near a pane's side, where a split with room shows a slot: only the frame, and it is around that pane.
        let last = try frame(app, .card(3))
        try held(app, [row, CGPoint(x: area.maxX - 20, y: area.midY)], back: split) {
            let ring = try frame(app, .splitDropPreview)
            try expect(ring == last, "the frame is \(ring), the pane \(last)")
            _ = try app.screenshot("full-held")
        }
        try PhysicalPointer.drag(app, through: [row, CGPoint(x: last.midX, y: last.midY)], window: app.window!) {
            try app.waitUntil("the frame") { try frame(app, .splitDropPreview) == frame(app, .card(3)) }
        }
        try app.waitUntil("the last pane replaced") { try app.view().content.panes.map(\.tab) == Array(panes.dropLast()) + [f.b] }
        let rows = try app.view().space.today.rows.map(\.id)
        try expect(rows.first == split && rows.dropFirst().first == panes[3], "Today reads \(rows)")
    }

    /// Holds the drag along `path`, checks, and cancels with Escape. The press opens the row and the cancel keeps it open, so the shown tab comes back afterwards.
    private static func held(_ app: AppUnderTest, _ path: [CGPoint], back: ItemID, check: () throws -> Void) throws {
        try PhysicalPointer.drag(app, through: path, window: app.window!) {
            app.sleep(0.3)
            try check()
            try app.press("escape")
        }
        try app.dispatch(.tab(.focus(back)))
        try app.waitUntil("the shown tab is back") { try shown(app) == back }
    }

    @Sendable static func paths(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        let area = try app.native().computed.contentArea
        let row = centre(try frame(app, .row(f.a)))
        func point(_ x: Double, _ y: Double? = nil) -> CGPoint { CGPoint(x: area.minX + x, y: y ?? area.midY) }
        func slot() throws -> CGRect { try frame(app, .splitDropPreview) }
        func isLeft(_ s: CGRect) -> Bool { s.minX == area.minX && abs(s.width - 516) < 1 }
        func isRight(_ s: CGRect) -> Bool { s.maxX == area.maxX && abs(s.width - 516) < 1 }
        // A straight leg from the row, Q17 A: a slot from the left holds through the page's middle (x 520 of 1042), then the frame.
        try held(app, [row, point(520)], back: f.c) { let s = try slot(); try expect(isLeft(s), "slot \(s) at 520") }
        try held(app, [row, point(540)], back: f.c) { let s = try slot(); try expect(s == area, "not the frame at 540: \(s)") }
        try held(app, [row, point(650)], back: f.c) { let s = try slot(); try expect(isRight(s), "not the right slot at 650: \(s)") }
        // From the right, Q17 C's first two: the right slot holds back past the middle, where a straight leg shows the frame.
        try held(app, [row, point(950), point(552)], back: f.c) { let s = try slot(); try expect(isRight(s), "not the right slot from the right: \(s)") }
        // From a left slot upwards past 100 pt and a tenth: it turns into the top slot, Q17 E.
        try held(app, [row, point(160), point(160, area.minY + 40)], back: f.c) {
            let s = try slot()
            try expect(s.minY == area.minY && s.width == area.width && s.height < area.height, "not the top slot: \(s)")
        }
        // Its own page, Q17 C and E: the tab is the shown one. Slots, no frame, and a release on one changes nothing.
        try app.dispatch(.tab(.focus(f.c)))
        let own = centre(try frame(app, .row(f.c)))
        try PhysicalPointer.drag(app, through: [own, point(950)], window: app.window!) {
            app.sleep(0.3)
            let s = try slot()
            try expect(isRight(s), "no right slot over its own page: \(s)")
        }
        app.sleep(0.3)
        try expect(try app.view().content.panes.map(\.tab) == [f.c] && app.view().content.split == nil, "a release on its own page changed the panes")
    }

    // MARK: Rule 9

    @Sendable static func splitSides(_ app: AppUnderTest) throws {
        let f = try fixture(app)
        // Today: c, b, a, then the first page. c held on b.
        func slot(_ row: ItemID) -> ViewID { .tabTool("split-join-slot-" + row.rawValue) }
        func panes() throws -> [ItemID] { try app.view().content.panes.map(\.tab) }
        func heldOn(_ target: ItemID, dx: Double) throws -> CGPoint {
            let row = try frame(app, .row(target))
            return CGPoint(x: row.midX + dx, y: row.midY)
        }
        // The drag image keeps its grab, and runs over the page past the sidebar's edge (Q15-c).
        let sourceRow = try frame(app, .row(f.c))
        let grab = CGPoint(x: sourceRow.minX + 86, y: sourceRow.midY)
        try PhysicalPointer.drag(app, through: [grab, try heldOn(f.b, dx: 80)], window: app.window!) {
            let image = try image(app), row = try frame(app, .row(f.b))
            try expect(image.width == 212 && image.height == 36, "the image is \(image)")
            try expect(image.maxX > row.maxX, "the image stops at the sidebar's edge: \(image)")
            try expect(isShown(try app.native(), slot(f.b)), "no slot")
            let shown = try frame(app, slot(f.b))
            try expect(shown.minX >= row.midX, "the pointer is in the right half and the slot is \(shown)")
            try expect(try app.view().content.panes.map(\.tab) == [f.c], "the page changed while holding")
            _ = try app.screenshot("right-half")
        }
        try app.waitUntil("the tab on the right, focused") { try panes() == [f.b, f.c] }
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == f.c, "the dropped tab is not the focused pane")
        let split = try shownSplit(app)
        try expect(try app.view().space.today.rows.map(\.id).first == split, "the split row is not where b was")
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("separated") { try app.view().content.split == nil }

        // Left half.
        try app.dispatch(.tab(.focus(f.a)))
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.c))), try heldOn(f.b, dx: -60)], window: app.window!) {
            let shown = try frame(app, slot(f.b)), row = try frame(app, .row(f.b))
            try expect(shown.maxX <= row.midX + 0.5, "the pointer is in the left half and the slot is \(shown)")
            _ = try app.screenshot("left-half")
        }
        try app.waitUntil("the tab on the left, focused") { try panes() == [f.c, f.b] }
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == f.c, "the dropped tab is not the focused pane")
        let two = try shownSplit(app)

        // The edge of a's row: 9.5 from the top is the line, 11.5 is the slot.
        let aRow = try frame(app, .row(f.a))
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(two))), CGPoint(x: aRow.midX, y: aRow.minY + 9.5)], window: app.window!) {
            try expect(!isShown(try app.native(), slot(f.a)), "a slot 9.5 from the edge")
        }

        // A split row: one band, the ends take first and last. a is standalone.
        try app.dispatch(.tab(.focus(f.a)))
        try app.waitUntil("a shown") { try shown(app) == f.a }
        let splitRow = try frame(app, .row(two))
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(f.a))), CGPoint(x: splitRow.minX + 30, y: splitRow.midY)], window: app.window!) {
            let band = try frame(app, .tabTool("split-join-band"))
            try expect(band.minX == splitRow.minX && band.width == splitRow.width && band.height == 41, "the band is \(band)")
            _ = try app.screenshot("split-band")
        }
        try app.waitUntil("first pane") { try panes() == [f.a, f.c, f.b] }
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == f.a, "the new pane is not focused")

        // The right end: the last pane.
        let extra = try E.loadReady(app, "page2.html?today=extra")
        let row3 = try frame(app, .row(two))
        try PhysicalPointer.drag(app, through: [centre(frame(app, .row(extra))), CGPoint(x: row3.maxX - 28, y: row3.midY)], window: app.window!) {}
        try app.waitUntil("last pane") { try panes() == [f.a, f.c, f.b, extra] }
        try expect(try app.view().content.panes.first(where: \.focused)?.tab == extra, "the new pane is not focused")
    }

    private static func shownSplit(_ app: AppUnderTest) throws -> ItemID {
        guard let split = try app.view().content.split else { throw Check(description: "no split") }
        return split
    }
}
