import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// R5-3: the pointer gestures of Arc's Favorites and sidebar rows (Q13), driven through the views' own mouse methods on
/// a window whose commands go through the real reducer, so what a press opens is what the drag then sees.
@MainActor
final class FavoritesDragTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)

    private final class Live {
        var state: AppState
        let ctx: Context
        let projection: ProjectionContext
        let id: WindowID
        var commands: [Command] = []
        var root: WindowRootView!
        init(state: AppState, ctx: Context, projection: ProjectionContext, id: WindowID) {
            self.state = state; self.ctx = ctx; self.projection = projection; self.id = id
        }
        var view: WindowSnapshot { project(state, projection).windows[id]! }
        func user(_ command: Command) { state = reduce(state, .user(id, command), ctx).state }
        @MainActor func send(_ command: Command) {
            commands.append(command)
            user(command)
            render()
        }
        @MainActor func render() {
            let view = self.view
            root.render(view, frames: WindowLayout.compute(view, contentSize: FavoritesDragTests.size), surface: { _ in nil })
            root.layoutSubtreeIfNeeded()
        }
    }

    /// Favorites 1, 2, 3, 4; Pinned Home; Today Inbox, Other, Visual (shown).
    private func rig(favorites: Int = 4) throws -> (NSWindow, Live) {
        let ids = IDs()
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/visual"), contentSize: Self.size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        let live = Live(state: state, ctx: ctx, projection: projection, id: id)
        func open(_ path: String, title: String) -> ItemID {
            live.user(.commandBar(.open(.newTab)))
            live.user(.commandBar(.submit("http://127.0.0.1:9/" + path)))
            let tab = live.view.space.today.rows[0].id
            live.user(.item(.rename(tab, title: title)))
            return tab
        }
        let visual = live.view.space.today.rows[0].id
        live.user(.item(.rename(visual, title: "Visual")))
        for n in stride(from: favorites, to: 0, by: -1) {
            let tile = open("f\(n)", title: "F\(n)")
            live.user(.item(.move(tile, to: .into(parent: live.view.favorites.root, index: 0))))
        }
        let home = open("home", title: "Home")
        live.user(.item(.move(home, to: .into(parent: live.view.space.pinned.root, index: 0))))
        _ = open("other", title: "Other")
        _ = open("inbox", title: "Inbox")
        live.user(.tab(.focus(visual)))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = WindowRootView(dispatch: { [weak live] in live?.send($0) })
        window.contentView = root
        live.root = root
        live.render()
        return (window, live)
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func row(_ title: String, _ live: Live) throws -> RowView {
        func find(_ rows: [Row]) -> ItemID? {
            for row in rows {
                if case .tab(let tab) = row, tab.title == title { return tab.id }
                if case .folder(let folder) = row, let hit = find(folder.children) { return hit }
            }
            return nil
        }
        let id = try XCTUnwrap(find(live.view.space.pinned.rows + live.view.space.today.rows), title)
        return try XCTUnwrap(ViewTreeSearch.find(ViewID.row(id).identifier, in: live.root) as? RowView)
    }

    private func tile(_ index: Int, _ live: Live) throws -> FavoriteTileView {
        try XCTUnwrap(ViewTreeSearch.find(ViewID.favorite(live.view.favorites.tiles[index].id).identifier, in: live.root) as? FavoriteTileView)
    }

    /// `point` is in the window's top-left content coordinates, like the frames.
    private func window(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: Self.size.height - point.y) }

    private func centre(_ view: NSView) -> CGPoint { view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) }

    private func hold(_ view: NSView, from start: CGPoint, at point: CGPoint, in window: NSWindow) {
        view.mouseDown(with: mouse(.leftMouseDown, start, in: window))
        for step in 1...6 {
            let t = Double(step) / 6
            view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t), in: window))
        }
    }

    private func first(in view: NSView, where test: (NSView) -> Bool) -> NSView? {
        if test(view) { return view }
        for child in view.subviews { if let hit = first(in: child, where: test) { return hit } }
        return nil
    }

    private func image(_ live: Live) -> DragImage? { ViewTreeSearch.find(ViewID.tabTool("drag-image").identifier, in: live.root) as? DragImage }
    private func drag(_ live: Live) -> DragController { live.root.sidebar.drag }

    // MARK: Rule 3: open on press

    func testAPressOpensTheRowAndATileBeforeAnyRelease() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let inbox = try row("Inbox", live)
        inbox.mouseDown(with: mouse(.leftMouseDown, centre(inbox), in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, inbox.row?.id, "the press did not open the row")
        inbox.mouseUp(with: mouse(.leftMouseUp, centre(inbox), in: w))
        let tile = try tile(1, live)
        tile.mouseDown(with: mouse(.leftMouseDown, centre(tile), in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, tile.id, "the press did not open the tile")
        tile.mouseUp(with: mouse(.leftMouseUp, centre(tile), in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, tile.id)
    }

    func testCommandAndShiftPressesOpenNothing() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let shown = live.view.content.panes.first?.tab
        let inbox = try row("Inbox", live)
        for modifier: NSEvent.ModifierFlags in [.command, .shift] {
            inbox.mouseDown(with: mouse(.leftMouseDown, centre(inbox), in: w, modifiers: modifier))
            inbox.mouseUp(with: mouse(.leftMouseUp, centre(inbox), in: w, modifiers: modifier))
            XCTAssertEqual(live.view.content.panes.first?.tab, shown, "\(modifier)")
        }
        // A Command press on a tile opens on the release, as a click did before.
        let tile = try tile(1, live)
        tile.mouseDown(with: mouse(.leftMouseDown, centre(tile), in: w, modifiers: .command))
        XCTAssertEqual(live.view.content.panes.first?.tab, shown)
        tile.mouseUp(with: mouse(.leftMouseUp, centre(tile), in: w, modifiers: .command))
        XCTAssertEqual(live.view.content.panes.first?.tab, tile.id)
    }

    func testAFolderStillTogglesOnTheRelease() throws {
        let (w, live) = try rig()
        defer { w.close() }
        live.send(.item(.newFolder))
        let folder = try XCTUnwrap(live.view.renaming)
        live.send(.item(.rename(folder, title: "Box")))
        let view = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(folder).identifier, in: live.root) as? RowView)
        let before = live.commands.count
        view.mouseDown(with: mouse(.leftMouseDown, centre(view), in: w))
        XCTAssertEqual(live.commands.count, before, "a press on a folder sent \(live.commands.suffix(1))")
        view.mouseUp(with: mouse(.leftMouseUp, centre(view), in: w))
        XCTAssertTrue(live.commands.contains(.item(.toggleFolder(folder))))
    }

    // MARK: Rule 4: a tab over the grid

    func testATabOverTheGridReflowsWithAGapAndATileImage() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let inbox = try row("Inbox", live)
        let rest = try XCTUnwrap(drag(live).context?.frames)
        let start = CGPoint(x: 86, y: centre(inbox).y)
        // Q13-a: x 114, in the tiles' row.
        hold(inbox, from: start, at: window(CGPoint(x: 114, y: rest.favoritesTray.minY + 31)), in: w)
        XCTAssertEqual(live.root.sidebar.favoritesDrag, .incoming(slot: 1))
        let f = try XCTUnwrap(drag(live).context?.frames)
        XCTAssertEqual(f.favoritesTray.height, rest.favoritesTray.height + 55, "the second row")
        XCTAssertEqual(f.spaceHeader.minY, rest.spaceHeader.minY + 55, "the strip moves with the tray")
        XCTAssertEqual(f.tablistViewport.minY, rest.tablistViewport.minY + 55, "the list moves with the tray")
        let cells = FavoritesGrid.tiles(count: 5, width: 228).tiles.map { $0.offsetBy(dx: 0, dy: rest.favoritesTray.minY) }
        let tiles = live.view.favorites.tiles.map { f.favoriteTiles[$0.id] }
        XCTAssertEqual(tiles, [cells[0], cells[2], cells[3], cells[4]])
        let shown = try XCTUnwrap(image(live))
        XCTAssertFalse(shown.isHidden)
        XCTAssertEqual(shown.frame.width, 196.0 / 3, accuracy: 0.01, "not a tile of the new layout")
        XCTAssertEqual(shown.frame.height, 47)
        XCTAssertEqual(shown.frame.minX, 114 - (86 - 8) / 212 * (196.0 / 3), accuracy: 0.01, "the pointer keeps its place along the image")
        XCTAssertTrue(inbox.dragLifted, "the row does not stay on its card")
        XCTAssertFalse(inbox.dragSource, "the row dims")
        XCTAssertEqual(inbox.alphaValue, 1)
        let tabID = try XCTUnwrap(inbox.row?.id)
        inbox.mouseUp(with: mouse(.leftMouseUp, window(CGPoint(x: 114, y: rest.favoritesTray.minY + 31)), in: w))
        XCTAssertEqual(live.view.favorites.tiles[1].id, tabID, "not the second tile")
        XCTAssertEqual(live.view.favorites.tiles.count, 5)
        XCTAssertEqual(live.view.content.panes.first?.tab, tabID, "the dropped tab is not the current one")
        XCTAssertNil(live.root.sidebar.favoritesDrag)
        XCTAssertNil(image(live))
    }

    func testAFolderOverTheGridChangesNothing() throws {
        let (w, live) = try rig()
        defer { w.close() }
        live.send(.item(.newFolder))
        let folder = try XCTUnwrap(live.view.renaming)
        live.send(.item(.rename(folder, title: "Box")))
        let view = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(folder).identifier, in: live.root) as? RowView)
        let rest = try XCTUnwrap(drag(live).context?.frames)
        let point = window(CGPoint(x: 114, y: rest.favoritesTray.minY + 31))
        hold(view, from: centre(view), at: point, in: w)
        XCTAssertNil(live.root.sidebar.favoritesDrag)
        XCTAssertEqual(try XCTUnwrap(drag(live).context?.frames).favoritesTray, rest.favoritesTray)
        let before = live.commands.count
        view.mouseUp(with: mouse(.leftMouseUp, point, in: w))
        XCTAssertEqual(live.commands.count, before, "the release sent \(live.commands.suffix(1))")
    }

    func testAnEmptyTrayKeepsItsBoxAndTakesAFullWidthTile() throws {
        let (w, live) = try rig(favorites: 0)
        defer { w.close() }
        let inbox = try row("Inbox", live)
        let rest = try XCTUnwrap(drag(live).context?.frames)
        let point = window(CGPoint(x: 100, y: rest.favoritesTray.midY))
        hold(inbox, from: centre(inbox), at: point, in: w)
        XCTAssertEqual(try XCTUnwrap(drag(live).context?.frames).favoritesTray, rest.favoritesTray, "the box moved under the pointer")
        let tabID = try XCTUnwrap(inbox.row?.id)
        inbox.mouseUp(with: mouse(.leftMouseUp, point, in: w))
        XCTAssertEqual(live.view.favorites.tiles.map(\.id), [tabID])
        let f = try XCTUnwrap(drag(live).context?.frames)
        XCTAssertEqual(f.favoriteTiles[tabID]?.size, CGSize(width: 212, height: 47), "not a full-width tile")
    }

    // MARK: Rule 5: reorder inside the grid

    func testAReorderSlidesTheOthersAndTheImageIsTheTile() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let tile = try tile(0, live)
        let ids = live.view.favorites.tiles.map(\.id)
        let f0 = try XCTUnwrap(drag(live).context?.frames)
        let point = window(CGPoint(x: 141, y: f0.favoritesTray.minY + 31))
        hold(tile, from: centre(tile), at: point, in: w)
        XCTAssertEqual(live.root.sidebar.favoritesDrag, .reordering(ids[0], slot: 2))
        XCTAssertEqual(tile.alphaValue, 0, "the tile's old place is not empty")
        let f = try XCTUnwrap(drag(live).context?.frames)
        let cells = FavoritesGrid.tiles(count: 4, width: 228).tiles.map { $0.offsetBy(dx: 0, dy: f0.favoritesTray.minY) }
        XCTAssertEqual([f.favoriteTiles[ids[1]], f.favoriteTiles[ids[2]], f.favoriteTiles[ids[3]]], [cells[0], cells[1], cells[3]])
        let shown = try XCTUnwrap(image(live))
        XCTAssertEqual(shown.frame.size, CGSize(width: 47, height: 47))
        XCTAssertEqual(shown.frame.midX, 141, accuracy: 0.01)
        tile.mouseUp(with: mouse(.leftMouseUp, point, in: w))
        XCTAssertEqual(live.view.favorites.tiles.map(\.id), [ids[1], ids[2], ids[0], ids[3]])
        XCTAssertEqual(tile.alphaValue, 1)
    }

    // MARK: Rule 6: a favorite dragged out

    func testAFavoriteOutOfTheGridIsARowAndItsCellStaysEmpty() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let tile = try tile(3, live)
        let ids = live.view.favorites.tiles.map(\.id)
        let f0 = try XCTUnwrap(drag(live).context?.frames)
        // Between Inbox and Other.
        let inbox = try row("Inbox", live)
        let line = CGPoint(x: 86, y: inbox.convert(CGPoint(x: 0, y: inbox.bounds.maxY - 1), to: nil).y)
        hold(tile, from: centre(tile), at: line, in: w)
        XCTAssertEqual(live.root.sidebar.favoritesDrag, .leaving(ids[3]))
        XCTAssertEqual(tile.alphaValue, 0)
        let f = try XCTUnwrap(drag(live).context?.frames)
        XCTAssertEqual(f.favoritesTray, f0.favoritesTray, "the grid changed before the release")
        for id in ids.dropLast() { XCTAssertEqual(f.favoriteTiles[id], f0.favoriteTiles[id], "a tile moved before the release") }
        let shown = try XCTUnwrap(image(live))
        XCTAssertEqual(shown.frame.size, CGSize(width: 212, height: 36), "not a row")
        XCTAssertEqual(shown.frame.midX, 86, accuracy: 0.01, "a tile's middle stays under the pointer as a row's middle")
        let drop = try XCTUnwrap(first(in: live.root) { ($0 as? DropLineView).map { !$0.isHidden } ?? false } as? DropLineView)
        XCTAssertEqual(drop.frame.minX, 16)
        XCTAssertEqual(drop.frame.maxX, 217)
        XCTAssertEqual(drop.frame.height, 7, "no room for the ring")
        tile.mouseUp(with: mouse(.leftMouseUp, line, in: w))
        XCTAssertEqual(live.view.favorites.tiles.map(\.id), Array(ids.dropLast()))
        XCTAssertEqual(live.view.space.today.rows.map(\.id).contains(ids[3]), true, "not a Today row")
        XCTAssertEqual(live.view.content.panes.first?.tab, ids[3], "not the current tab")
    }

    func testOverThePageTheWindowShowsTheEarlierTabAgainAndTheCardRidesThePointer() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let shown = try XCTUnwrap(live.view.content.panes.first?.tab)
        let tile = try tile(3, live)
        let id = tile.id
        tile.mouseDown(with: mouse(.leftMouseDown, centre(tile), in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, id)
        // The right edge of the page: Arc's slot (P23-d), for a Favorite too (Q13-e).
        let edge = window(CGPoint(x: 1200, y: 400))
        tile.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: centre(tile).x, y: centre(tile).y - 10), in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, id, "still in the sidebar")
        tile.mouseDragged(with: mouse(.leftMouseDragged, edge, in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, shown, "the earlier tab did not come back")
        let card = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("content-drag-card").identifier, in: live.root))
        XCTAssertFalse(card.isHidden)
        XCTAssertEqual(image(live)?.isHidden, true)
        XCTAssertEqual(ViewTreeSearch.find(ViewID.splitDropPreview.identifier, in: live.root)?.isHidden, false, "no slot")
        // Back in the sidebar it is the current tab again.
        let back = window(CGPoint(x: 100, y: 500))
        tile.mouseDragged(with: mouse(.leftMouseDragged, back, in: w))
        XCTAssertEqual(live.view.content.panes.first?.tab, id)
        tile.mouseDragged(with: mouse(.leftMouseDragged, edge, in: w))
        tile.mouseUp(with: mouse(.leftMouseUp, edge, in: w))
        XCTAssertEqual(live.view.content.panes.map(\.tab), [shown, id], "the release made no split")
        XCTAssertFalse(live.view.favorites.tiles.contains { $0.id == id })
    }

    func testTheMiddleOfThePageRingsItAndAReleaseThereMovesNothing() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let shown = try XCTUnwrap(live.view.content.panes.first?.tab)
        let inbox = try row("Inbox", live)
        let id = try XCTUnwrap(inbox.row?.id)
        let middle = window(CGPoint(x: 780, y: 330))
        hold(inbox, from: centre(inbox), at: middle, in: w)
        XCTAssertEqual(live.view.content.panes.first?.tab, shown)
        let ring = try XCTUnwrap(ViewTreeSearch.find(ViewID.splitDropPreview.identifier, in: live.root))
        XCTAssertFalse(ring.isHidden)
        let area = WindowLayout.compute(live.view, contentSize: Self.size).contentArea
        XCTAssertEqual(ring.frame, area, "the ring is not the whole page")
        XCTAssertEqual(ring.layer?.borderWidth, 3)
        inbox.mouseUp(with: mouse(.leftMouseUp, middle, in: w))
        XCTAssertTrue(live.view.space.today.rows.contains { $0.id == id })
        XCTAssertEqual(live.view.content.panes.map(\.tab), [shown])
    }

    // MARK: Rule 7: the Space name strip

    func testTheStripHighlightsAndTakesTheDropAsTheFirstPinnedTab() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let inbox = try row("Inbox", live)
        let id = try XCTUnwrap(inbox.row?.id)
        let f = try XCTUnwrap(drag(live).context?.frames)
        let point = window(CGPoint(x: 86, y: f.spaceHeader.minY + 1))
        hold(inbox, from: CGPoint(x: 86, y: centre(inbox).y), at: point, in: w)
        let header = live.root.sidebar.spaceHeader
        XCTAssertTrue(header.dropHighlighted)
        XCTAssertNil(live.root.sidebar.favoritesDrag, "the grid made room for a drop on the strip")
        let shown = try XCTUnwrap(image(live))
        XCTAssertEqual(shown.frame.width, 212 * 0.875, accuracy: 0.01)
        inbox.mouseUp(with: mouse(.leftMouseUp, point, in: w))
        XCTAssertFalse(header.dropHighlighted)
        XCTAssertEqual(live.view.space.pinned.rows.first?.id, id)
        XCTAssertEqual(live.view.content.panes.first?.tab, id)
        guard case .tab(let row)? = live.view.space.pinned.rows.first else { return XCTFail("not a tab") }
        XCTAssertTrue(row.renameHint)
        let hint = try XCTUnwrap(first(in: live.root) { ($0 as? NSTextField)?.stringValue == "Double-click to rename" && !$0.isHidden }, "no hint line under the title")
        XCTAssertFalse(hint.isHidden)
    }
}
