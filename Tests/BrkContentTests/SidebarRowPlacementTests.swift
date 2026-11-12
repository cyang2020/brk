import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// A sidebar imported from Arc has hundreds of rows per Space. Only rows near the visible part of the list have views;
/// scrolling gives the next rows theirs and takes them from the far ones (the sidebar lagged with every row a view).
@MainActor
final class SidebarRowPlacementTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    func testOnlyRowsNearTheVisiblePartHaveViewsAndScrollingPlacesTheRest() throws {
        let ids = IDs()
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/0"), contentSize: Self.size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        for n in 1..<200 {
            state = reduce(state, .user(id, .commandBar(.open(.newTab))), ctx).state
            state = reduce(state, .user(id, .commandBar(.submit("http://127.0.0.1:9/\(n)"))), ctx).state
        }
        let view = try XCTUnwrap(project(state, projection).windows[id])
        let rows = view.space.today.rows.map(\.id)
        XCTAssertEqual(rows.count, 200)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = WindowRootView(dispatch: { _ in })
        window.contentView = root
        root.render(view, frames: WindowLayout.compute(view, contentSize: Self.size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()

        func rowViews(_ node: NSView) -> [RowView] { (node as? RowView).map { [$0] } ?? node.subviews.flatMap(rowViews) }
        func shown(_ item: ItemID) -> Bool { rowViews(root).contains { $0.row?.id == item } }
        let list = try XCTUnwrap(Self.tablist(in: root))
        let first = rowViews(root).count
        XCTAssertGreaterThan(first, 10, "the rows on screen have views")
        XCTAssertLessThan(first, 100, "200 rows, \(first) views: rows far below the list have none")
        XCTAssertTrue(shown(rows[0]))
        XCTAssertFalse(shown(rows[199]))

        let bottom = (list.documentView?.bounds.height ?? 0) - list.contentView.bounds.height
        list.contentView.scroll(to: CGPoint(x: 0, y: bottom))
        list.reflectScrolledClipView(list.contentView)
        XCTAssertTrue(shown(rows[199]), "scrolled to the end, the last row has its view")
        XCTAssertFalse(shown(rows[0]), "and the first one's is gone")
        XCTAssertLessThan(rowViews(root).count, 100)
    }

    private static func tablist(in node: NSView) -> TablistView? {
        if let list = node as? TablistView, list.window != nil, !list.isHiddenOrHasHiddenAncestor { return list }
        for child in node.subviews { if let found = tablist(in: child) { return found } }
        return nil
    }
}
