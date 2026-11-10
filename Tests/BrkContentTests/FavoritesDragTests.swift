import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import BrkUIKit
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

    private func image(_ live: Live) -> DragImage? { ViewTreeSearch.find(ViewID.tabTool("drag-image").identifier, in: live.root) as? DragImage }
    private func drag(_ live: Live) -> DragController { live.root.sidebar.drag }

    // MARK: Rule 3: open on press

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
        // Arc (Q21): the image glides from where it was let go into the cell. The tile is in that cell at once, unseen (the
        // user's recording of 2026-11-06: it showed in its old cell and slid over), and shows when the image arrives.
        XCTAssertEqual(tile.alphaValue, 0, "the tile shows while its image is still on the way")
        XCTAssertEqual(tile.frame, FavoritesGrid.tiles(count: 4, width: 228).tiles[2], "the tile is not in its new cell")
        let landing = try XCTUnwrap(image(live), "the image went at the release")
        XCTAssertEqual(landing.superview?.convert(landing.frame, to: tile.superview), tile.frame, "the image is not sent to the tile's cell")
        waitForLanding(live)
        XCTAssertNil(image(live), "the image stayed")
        XCTAssertEqual(tile.alphaValue, 1)
    }

    /// A press while the image is still on its way: the tile shows at once, so the next drag starts from a tile on screen.
    func testAPressEndsTheLandingAtOnce() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let tile = try tile(0, live)
        let f0 = try XCTUnwrap(drag(live).context?.frames)
        let point = window(CGPoint(x: 141, y: f0.favoritesTray.minY + 31))
        hold(tile, from: centre(tile), at: point, in: w)
        tile.mouseUp(with: mouse(.leftMouseUp, point, in: w))
        XCTAssertNotNil(image(live))
        tile.mouseDown(with: mouse(.leftMouseDown, centre(tile), in: w))
        XCTAssertNil(image(live), "the old image stayed under a new press")
        XCTAssertEqual(tile.alphaValue, 1)
        tile.mouseUp(with: mouse(.leftMouseUp, centre(tile), in: w))
    }

    /// A Favorite let go outside the grid has no cell to glide to: the image goes at the release.
    func testADropOutsideTheGridKeepsNoImage() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let tile = try tile(3, live)
        let inbox = try row("Inbox", live)
        let line = CGPoint(x: 86, y: inbox.convert(CGPoint(x: 0, y: inbox.bounds.maxY - 1), to: nil).y)
        hold(tile, from: centre(tile), at: line, in: w)
        tile.mouseUp(with: mouse(.leftMouseUp, line, in: w))
        XCTAssertNil(image(live))
        XCTAssertNil(live.root.sidebar.favorites.arriving)
    }

    /// Lets the landing's animation run out.
    private func waitForLanding(_ live: Live) {
        let end = Date().addingTimeInterval(3)
        while image(live) != nil, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func first(in view: NSView, where test: (NSView) -> Bool) -> NSView? {
        if test(view) { return view }
        for child in view.subviews { if let hit = first(in: child, where: test) { return hit } }
        return nil
    }

    /// The events here come within a millisecond: each read of the drop rule's clock counts as a real interval of the throttle.
    private func advanceDropClock(_ live: Live) {
        guard let content = ViewTreeSearch.find(ViewID.splitDropPreview.identifier, in: live.root)?.superview as? ContentAreaView else { return XCTFail("no content area") }
        var now = 1000.0
        content.dropClock = { now += 0.2; return now }
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

    func testOverThePageTheWindowShowsTheEarlierTabAgainAndTheCardRidesThePointer() throws {
        let (w, live) = try rig()
        defer { w.close() }
        advanceDropClock(live)
        let shown = try XCTUnwrap(live.view.content.panes.first?.tab)
        let tile = try tile(3, live)
        let id = tile.id
        let today = live.view.space.today.rows.map(\.id)
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
        // Arc (Q17-drop-favorite-right-half): the tile stays and a new tab at its address joins, on the right and focused.
        XCTAssertEqual(live.view.content.panes.count, 2, "the release made no split")
        XCTAssertEqual(live.view.content.panes.first?.tab, shown)
        let new = try XCTUnwrap(live.view.content.panes.last)
        XCTAssertNotEqual(new.tab, id, "the Favorite itself went into the split")
        XCTAssertTrue(new.focused)
        XCTAssertTrue(live.view.favorites.tiles.contains { $0.id == id }, "the Favorite left the grid")
        XCTAssertFalse(today.contains(new.tab))
    }

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
