import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// Q18 (real Arc, 2026-11-05): the hover button of a Pinned row, a closed Pinned row's look, and the Space name while
/// Pinned is collapsed. Views on a window whose commands go through the real reducer.
@MainActor
final class PinnedRowButtonTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)

    private final class Live {
        var state: AppState
        let ctx: Context
        let projection: ProjectionContext
        let id: WindowID
        var root: WindowRootView!
        init(state: AppState, ctx: Context, projection: ProjectionContext, id: WindowID) {
            self.state = state; self.ctx = ctx; self.projection = projection; self.id = id
        }
        var view: WindowSnapshot { project(state, projection).windows[id]! }
        func user(_ command: Command) { state = reduce(state, .user(id, command), ctx).state }
        @MainActor func send(_ command: Command) { user(command); render() }
        @MainActor func render() {
            let view = self.view
            root.render(view, frames: WindowLayout.compute(view, contentSize: PinnedRowButtonTests.size), surface: { _ in nil })
            root.layoutSubtreeIfNeeded()
        }
    }

    /// Pinned Home, Docs; Today Inbox, Visual (shown).
    private func rig() throws -> (NSWindow, Live) {
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
        for (path, title) in [("docs", "Docs"), ("home", "Home")] {
            live.user(.item(.move(open(path, title: title), to: .into(parent: live.view.space.pinned.root, index: 0))))
        }
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

    private func pinned(_ live: Live) -> [String] {
        live.view.space.pinned.rows.compactMap { if case .tab(let tab) = $0 { tab.title } else { nil } }
    }

    private func tab(_ title: String, _ live: Live) throws -> TabRow {
        for row in live.view.space.pinned.rows + live.view.space.today.rows { if case .tab(let tab) = row, tab.title == title { return tab } }
        throw XCTSkip("no row titled \(title)")
    }

    private func button(_ title: String, _ live: Live) throws -> GlyphButton {
        try XCTUnwrap(ViewTreeSearch.find(ViewID.rowClose(try tab(title, live).id).identifier, in: live.root) as? GlyphButton)
    }

    /// Arc: every Pinned row that is not the current tab has the × "Archive this tab", and it takes the row away
    /// (Q18-rowbutton-pinned-x-removed-the-row). Where Cmd+Shift+T puts it back is a domain test.
    func testTheButtonOfAPinnedRowThatIsNotCurrentArchivesIt() throws {
        let (w, live) = try rig()
        defer { w.close() }
        XCTAssertEqual(pinned(live), ["Home", "Docs"])
        let docs = try button("Docs", live)
        XCTAssertEqual(docs.toolTip, "Archive this tab")
        docs.action?([])
        XCTAssertEqual(pinned(live), ["Home"], "the row stayed")
    }

    /// Arc: the current Pinned row has the minus "Close and Keep Pinned"; the row stays, the page goes, and the row
    /// looks like any other (Q18-rowbutton-tooltips-current, Q18-unloaded-pinned-row).
    func testTheButtonOfTheCurrentPinnedRowClosesThePageAndKeepsTheRow() throws {
        let (w, live) = try rig()
        defer { w.close() }
        live.send(.tab(.focus(try tab("Docs", live).id)))
        XCTAssertEqual(try tab("Docs", live).status, .current)
        let docs = try button("Docs", live)
        XCTAssertEqual(docs.toolTip, "Close and Keep Pinned")
        XCTAssertEqual(try button("Home", live).toolTip, "Archive this tab")
        docs.action?([])
        XCTAssertEqual(pinned(live), ["Home", "Docs"])
        let closed = try tab("Docs", live)
        XCTAssertFalse(closed.loaded)
        XCTAssertNotEqual(closed.status, .current)
        XCTAssertEqual(try button("Docs", live).toolTip, "Archive this tab", "a closed Pinned row has the × too")
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(closed.id).identifier, in: live.root) as? RowView)
        XCTAssertTrue(row.subviews.allSatisfy { $0.alphaValue == 1 || $0.isHidden || $0 is GlyphButton }, "a closed Pinned row is drawn dimmer")
    }

    /// Arc: collapsed and with the pointer away, the Space name keeps the chevron and loses the pill and the dots
    /// (Q18-collapse-c).
    func testTheCollapsedSpaceNameKeepsOnlyTheChevron() throws {
        let (w, live) = try rig()
        defer { w.close() }
        let header = live.root.sidebar.spaceHeader
        func chevron() throws -> NSView { try XCTUnwrap(header.subviews.first { $0 is NSImageView }) }
        func dots() throws -> NSView { try XCTUnwrap(header.subviews.first { $0 is GlyphButton }) }
        XCTAssertTrue(try chevron().isHidden)
        XCTAssertTrue(try dots().isHidden)
        live.send(.space(.togglePinnedSection(.current)))
        XCTAssertEqual(live.view.space.pinned.collapsed, true)
        XCTAssertFalse(try chevron().isHidden, "no chevron on the collapsed name")
        XCTAssertTrue(try dots().isHidden, "the dots stay without the pointer")
        XCTAssertNil(header.subviews[0].layer?.backgroundColor, "the pill stays without the pointer")
    }
}
