import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// R4-12, the two problems a user reported (verify/visual-pairs/run-20261103: P05-f, P07-b, P23-e/f): at every sidebar
/// width from Arc's 228 down to the 164 minimum no sidebar text leaves its frame and the empty Favorites box keeps
/// Arc's composition inside it; dragging one tab row onto the middle of another shows Arc's split capsule and the
/// release joins them, while a row's edges still reorder and a folder's middle still takes the tab in.
@MainActor
final class SidebarJoinAndNarrowTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    private final class Sink { var commands: [Command] = [] }

    /// A window with Today [Inbox, a long title, Secondary reference, Visual fixture] and a pinned folder holding Design
    /// notes, rendered offscreen at `width`.
    private func rig(width: Double, favorites: Bool = false, sink: Sink, then: ((WindowSnapshot) -> [Command])? = nil) throws -> (NSWindow, WindowRootView, WindowSnapshot) {
        let ids = IDs()
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/visual"), contentSize: Self.size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        func user(_ command: Command) { state = reduce(state, .user(id, command), ctx).state }
        func today() -> [ItemID] { project(state, projection).windows[id]!.space.today.rows.map(\.id) }
        user(.item(.rename(today()[0], title: "Visual fixture")))
        for (path, title) in [("secondary", "Secondary reference"), ("long", "Long title for truncation and readable sidebar ellipsis"), ("inbox", "Inbox"), ("design", "Design notes")] {
            user(.commandBar(.open(.newTab)))
            user(.commandBar(.submit("http://127.0.0.1:9/" + path)))
            user(.item(.rename(today()[0], title: title)))
        }
        user(.item(.newFolder))
        user(.item(.rename(project(state, projection).windows[id]!.space.pinned.rows[0].id, title: "资料")))
        let folder = project(state, projection).windows[id]!.space.pinned.rows[0].id
        user(.item(.move(today()[0], to: .into(parent: folder, index: 0))))
        if favorites {
            let view = project(state, projection).windows[id]!
            user(.item(.move(today()[1], to: .into(parent: view.favorites.root, index: 0))))
        }
        user(.tab(.focus(today().last!)))
        user(.sidebar(.resize(width: width)))
        for command in then?(project(state, projection).windows[id]!) ?? [] { user(command) }
        let view = try XCTUnwrap(project(state, projection).windows[id])
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = WindowRootView(dispatch: { sink.commands.append($0) })
        window.contentView = root
        root.render(view, frames: WindowLayout.compute(view, contentSize: Self.size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        return (window, root, view)
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func row(_ item: ItemID, in root: NSView) throws -> RowView {
        try XCTUnwrap(ViewTreeSearch.find(ViewID.row(item).identifier, in: root) as? RowView)
    }

    /// Every visible label of the sidebar, in the sidebar's coordinates.
    private func labels(in view: NSView, sidebar: NSView) -> [(NSTextField, CGRect)] {
        var out: [(NSTextField, CGRect)] = []
        func walk(_ v: NSView) {
            guard !v.isHidden, v.alphaValue > 0 else { return }
            if let field = v as? NSTextField, !field.stringValue.isEmpty { out.append((field, field.convert(field.bounds, to: sidebar))) }
            for child in v.subviews { walk(child) }
        }
        walk(view)
        return out
    }

    /// Arc's P05-f at every 16 pt step from 228 to 164: each label lies inside the sidebar, and its text either fits
    /// its frame or is cut off there with an ellipsis (no wrapped line runs past the frame's bottom).
    func testNoSidebarTextLeavesItsFrameFrom228To164() throws {
        for favorites in [false, true] {
            for width in stride(from: 228.0, through: 164, by: -16) {
                let (window, root, _) = try rig(width: width, favorites: favorites, sink: Sink())
                defer { window.close() }
                let sidebar = root.sidebar
                let found = labels(in: sidebar, sidebar: sidebar)
                XCTAssertFalse(found.isEmpty)
                for (field, frame) in found {
                    let name = "\(field.stringValue) at \(width) (favorites: \(favorites))"
                    XCTAssertGreaterThanOrEqual(frame.minX, -0.5, name)
                    XCTAssertLessThanOrEqual(frame.maxX, sidebar.bounds.width + 0.5, name)
                    let lines = field.maximumNumberOfLines
                    if field.cell?.wraps == true {
                        let needed = field.cell!.cellSize(forBounds: CGRect(x: 0, y: 0, width: field.bounds.width, height: .greatestFiniteMagnitude)).height
                        XCTAssertTrue(needed <= field.bounds.height + 0.5 || (lines > 0 && field.cell?.truncatesLastVisibleLine == true),
                                      "\(name): \(needed) tall in a \(field.bounds.height) frame")
                    } else {
                        let needed = field.attributedStringValue.size().width
                        XCTAssertTrue(needed <= field.bounds.width + 4 || [.byTruncatingTail, .byTruncatingMiddle, .byTruncatingHead].contains(field.lineBreakMode),
                                      "\(name): \(needed) wide in a \(field.bounds.width) frame without an ellipsis")
                    }
                }
            }
        }
    }

    /// The empty Favorites box (P07-b's composition, shrunk with the sidebar): the badge, the whole bold title on one
    /// line, the whole explanation on two, and the × all inside the dashed box at every width; at 164 the box is 149 x
    /// 66 and nothing reaches the space header under it.
    func testTheEmptyFavoritesBoxHoldsItsCopyAtEveryWidth() throws {
        for width in stride(from: 228.0, through: 164, by: -16) {
            let (window, root, _) = try rig(width: width, sink: Sink())
            defer { window.close() }
            let tray = root.sidebar.favorites
            let box = FavoritesGrid.emptyBox(width: tray.bounds.width).box
            for name in ["favorites-empty-title", "favorites-empty-subtitle", "favorites-empty-badge", "favorites-empty-close"] {
                let view = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool(name).identifier, in: tray), name)
                XCTAssertFalse(view.isHidden, name)
                let frame = view.convert(view.bounds, to: tray)
                XCTAssertTrue(box.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(name) \(frame) leaves the box \(box) at \(width)")
            }
            let title = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("favorites-empty-title").identifier, in: tray) as? NSTextField)
            XCTAssertLessThanOrEqual(title.attributedStringValue.size().width, title.bounds.width + 0.5, "the title is cut at \(width)")
            let subtitle = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("favorites-empty-subtitle").identifier, in: tray) as? NSTextField)
            let full = subtitle.cell!.cellSize(forBounds: CGRect(x: 0, y: 0, width: subtitle.bounds.width, height: .greatestFiniteMagnitude)).height
            XCTAssertLessThanOrEqual(full, subtitle.bounds.height + 0.5, "the explanation is cut at \(width)")
            let line = subtitle.font!.boundingRectForFont.height
            XCTAssertLessThanOrEqual(full, 2.5 * line, "the explanation takes more than two lines at \(width)")
            // Arc's break (P07-b): "Favorites keep your most" over "used sites and apps close".
            func cell(_ text: String) -> Double {
                let probe = NSTextField(labelWithString: text)
                probe.font = subtitle.font
                return probe.cell!.cellSize.width
            }
            XCTAssertLessThanOrEqual(cell("Favorites keep your most"), subtitle.bounds.width, "the first line breaks before \"most\" at \(width)")
            XCTAssertLessThanOrEqual(cell("used sites and apps close"), subtitle.bounds.width, "the second line does not fit at \(width)")
            XCTAssertGreaterThan(cell("Favorites keep your most used"), subtitle.bounds.width, "the first line runs past \"most\" at \(width)")
            XCTAssertTrue(tray.bounds.contains(box), "the box \(box) runs out of its tray \(tray.bounds) into the space header at \(width)")
        }
        XCTAssertEqual(FavoritesGrid.emptyBox(width: 164).box.size.width, 149)
    }

    private func drag(_ source: RowView, to point: CGPoint, in window: NSWindow) {
        let start = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil)
        source.mouseDown(with: mouse(.leftMouseDown, start, in: window))
        for step in 1...6 {
            let t = Double(step) / 6
            source.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t), in: window))
        }
    }

    /// A point `fraction` of the way down `row` (0 is its top), in window coordinates.
    private func point(in row: NSView, fraction: Double) -> CGPoint {
        row.convert(CGPoint(x: row.bounds.midX, y: row.bounds.height * fraction), to: nil)
    }

    /// Arc's P23-e/f: Inbox held on the middle of Secondary reference shows the capsule in Secondary's place (Inbox's
    /// title on the chip, Secondary's beside it), keeps Inbox lifted with its ×, and the release asks for the split.
    func testHoldingATabOnAnotherTabsMiddleShowsArcsCapsuleAndTheReleaseJoinsThem() throws {
        let sink = Sink()
        let (window, root, view) = try rig(width: 228, sink: sink)
        defer { window.close() }
        let today = view.space.today.rows.map(\.id)
        let inbox = today[0], secondary = today[2]
        let source = try row(inbox, in: root), target = try row(secondary, in: root)
        let held = point(in: target, fraction: 0.5)
        drag(source, to: held, in: window)
        let preview = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("split-join-preview").identifier, in: root))
        XCTAssertFalse(preview.isHidden, "no capsule on the middle of the row")
        XCTAssertEqual(preview.convert(preview.bounds, to: nil), target.convert(target.bounds, to: nil), "the capsule is not in the target row's place")
        XCTAssertEqual(target.alphaValue, 0, "the target row shows under the capsule")
        let chip = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("split-join-chip").identifier, in: preview))
        let rest = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("split-join-target").identifier, in: preview) as? NSTextField)
        XCTAssertEqual(rest.stringValue, "Secondary reference")
        XCTAssertLessThan(chip.frame.maxX, rest.frame.minX, "the dragged tab is not on the left half")
        let titles = preview.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(titles.contains("Inbox"), "the chip does not carry the dragged tab: \(titles)")
        XCTAssertTrue(source.dragLifted, "the dragged row is not lifted in place")
        XCTAssertFalse(source.dragSource)
        source.mouseUp(with: mouse(.leftMouseUp, held, in: window))
        XCTAssertEqual(sink.commands.last, .split(.joinRow(inbox, onto: secondary)))
        XCTAssertTrue(preview.isHidden, "the capsule stayed after the release")
        XCTAssertEqual(target.alphaValue, 1)
    }

    /// The row's upper and lower quarters still reorder (a drop line, no capsule), and a pinned folder's middle still
    /// takes the tab in.
    func testARowsEdgesStillReorderAndAFoldersMiddleStillTakesTheTabIn() throws {
        let sink = Sink()
        let (window, root, view) = try rig(width: 228, sink: sink)
        defer { window.close() }
        let today = view.space.today.rows.map(\.id), folder = view.space.pinned.rows[0].id
        let inbox = today[0], secondary = today[2]
        for (fraction, index) in [(0.1, 1), (0.9, 2)] {
            let source = try row(inbox, in: root), target = try row(secondary, in: root)
            let held = point(in: target, fraction: fraction)
            drag(source, to: held, in: window)
            let preview = ViewTreeSearch.find(ViewID.tabTool("split-join-preview").identifier, in: root)
            XCTAssertTrue(preview == nil || preview!.isHidden, "a capsule at \(fraction) of the row")
            source.mouseUp(with: mouse(.leftMouseUp, held, in: window))
            XCTAssertEqual(sink.commands.last, .item(.move(inbox, to: .into(parent: view.space.today.root, index: index))), "at \(fraction)")
        }
        let source = try row(inbox, in: root)
        let held = point(in: try row(folder, in: root), fraction: 0.5)
        drag(source, to: held, in: window)
        source.mouseUp(with: mouse(.leftMouseUp, held, in: window))
        guard case .item(.move(inbox, to: .into(parent: folder, _)))? = sink.commands.last else {
            return XCTFail("the folder's middle did not take the tab in: \(String(describing: sink.commands.last))")
        }
    }

    /// A pinned folder's tab joins a Today tab the same way (`Placement.canJoinSplit`).
    func testAPinnedFolderTabJoinsATodayTab() throws {
        let sink = Sink()
        let (window, root, view) = try rig(width: 228, sink: sink)
        defer { window.close() }
        guard case .folder(let folder) = view.space.pinned.rows[0] else { return XCTFail("no folder") }
        let design = folder.children[0].id, inbox = view.space.today.rows[0].id
        let source = try row(design, in: root)
        let held = point(in: try row(inbox, in: root), fraction: 0.5)
        drag(source, to: held, in: window)
        let preview = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("split-join-preview").identifier, in: root))
        XCTAssertFalse(preview.isHidden)
        source.mouseUp(with: mouse(.leftMouseUp, held, in: window))
        XCTAssertEqual(sink.commands.last, .split(.joinRow(design, onto: inbox)))
    }

    /// The capsule follows the pointer sideways (Arc's sits 7 pt right of the row in P23-e), no further than the list's
    /// 8 pt side inset.
    func testTheCapsuleFollowsThePointerSideways() throws {
        for (dx, expected) in [(7.0, 7.0), (-5.0, -5.0), (30.0, 8.0)] {
            let sink = Sink()
            let (window, root, view) = try rig(width: 228, sink: sink)
            defer { window.close() }
            let today = view.space.today.rows.map(\.id)
            let source = try row(today[0], in: root), target = try row(today[2], in: root)
            let start = point(in: source, fraction: 0.5), middle = point(in: target, fraction: 0.5)
            drag(source, to: CGPoint(x: start.x + dx, y: middle.y), in: window)
            let preview = try XCTUnwrap(ViewTreeSearch.find(ViewID.tabTool("split-join-preview").identifier, in: root))
            XCTAssertFalse(preview.isHidden)
            XCTAssertEqual(preview.convert(preview.bounds, to: nil).minX - target.convert(target.bounds, to: nil).minX, expected, accuracy: 0.5, "pointer moved \(dx)")
            source.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: start.x + dx, y: middle.y), in: window))
        }
    }

    /// Arc's lifted row keeps the current tab's shadow (P23-e: Inbox is the shown tab); a lifted row that is not the
    /// current tab has none (P23-d).
    func testALiftedRowKeepsTheCurrentTabsShadow() throws {
        for current in [true, false] {
            let (window, root, view) = try rig(width: 228, sink: Sink())
            defer { window.close() }
            let today = view.space.today.rows.map(\.id)   // Inbox, Long title, Secondary, Visual fixture (shown)
            let source = try row(current ? today[3] : today[0], in: root), target = try row(today[1], in: root)
            drag(source, to: point(in: target, fraction: 0.5), in: window)
            XCTAssertTrue(source.dragLifted)
            let card = try XCTUnwrap(source.subviews.first, "the row's card")
            XCTAssertEqual(card.shadow != nil, current, current ? "the lifted current tab lost its shadow" : "a lifted other row got a shadow")
            source.mouseUp(with: mouse(.leftMouseUp, point(in: target, fraction: 0.5), in: window))
        }
    }

    /// P23-f: an unfocused pane's header shows only back, forward and its address while the pointer is out of the
    /// window; with the pointer in the window its × shows too (P23-a/b/c, P12-e). The focused pane's × always shows.
    func testAnUnfocusedPanesCloseShowsOnlyWithThePointerInTheWindow() throws {
        let (window, root, view) = try rig(width: 228, sink: Sink()) { view in
            let today = view.space.today.rows.map(\.id)
            return [.split(.joinRow(today[0], onto: today[2]))]
        }
        defer { window.close() }
        XCTAssertEqual(view.content.panes.count, 2)
        func headers(_ v: NSView) -> [PaneHeaderView] { (v as? PaneHeaderView).map { [$0] } ?? v.subviews.flatMap(headers) }
        func closeShown(_ header: PaneHeaderView) -> Bool {
            header.layoutSubtreeIfNeeded()
            return header.subviews.contains { ($0 as? PaneHeaderButton)?.toolTip == "Close this Split Pane" && !$0.isHidden }
        }
        let found = headers(root).filter { !$0.isHidden }.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(view.content.panes.map(\.focused), [true, false], "the dragged tab is the focused left pane")
        let content = try XCTUnwrap(sequence(first: found[0] as NSView, next: \.superview).first { $0 is ContentAreaView } as? ContentAreaView)
        // The state starts from wherever the real pointer is; leave the window first.
        content.mouseEntered(with: mouse(.mouseMoved, CGPoint(x: 900, y: 400), in: window))
        content.mouseExited(with: mouse(.mouseMoved, CGPoint(x: 100, y: 400), in: window))
        XCTAssertEqual(found.map(closeShown), [true, false], "out of the window only the focused pane shows ×")
        content.mouseEntered(with: mouse(.mouseMoved, CGPoint(x: 900, y: 400), in: window))
        XCTAssertEqual(found.map(closeShown), [true, true], "with the pointer in the window both panes show ×")
        content.mouseExited(with: mouse(.mouseMoved, CGPoint(x: 100, y: 400), in: window))
        XCTAssertEqual(found.map(closeShown), [true, false])
    }
}
