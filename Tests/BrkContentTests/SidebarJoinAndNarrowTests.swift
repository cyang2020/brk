import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// R4-12, the two problems a user reported (verify/visual-pairs/run-20261103: P05-f, P07-b, P23-e/f): at every sidebar
/// width from Arc's 228 down to the 164 minimum no sidebar text leaves its frame and the empty Favorites box keeps
/// Arc's composition inside it; dragging one tab row onto the middle of another shows a slot in the half under the
/// pointer and the release joins them on that side, while a row's edges still reorder and a folder's middle still takes the tab in.
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
                        // The cell draws the text 2 in from the frame, 4 when centred.
                        let needed = field.attributedStringValue.size().width + (field.alignment == .center ? 4 : 2)
                        XCTAssertTrue(needed <= field.bounds.width + 0.5 || [.byTruncatingTail, .byTruncatingMiddle, .byTruncatingHead].contains(field.lineBreakMode),
                                      "\(name): \(needed) wide in a \(field.bounds.width) frame without an ellipsis")
                    }
                }
            }
        }
    }

    /// Clear whole at every width, the word ending 19 before the sidebar's edge; its intrinsic width cut the r
    /// (P02-clear-user-brk.png).
    func testClearIsWholeAndEndsBeforeTheSidebarEdge() throws {
        for width in stride(from: 228.0, through: 164, by: -16) {
            let (window, root, _) = try rig(width: width, sink: Sink())
            defer { window.close() }
            let sidebar = root.sidebar
            var found: ClearButton?
            func walk(_ view: NSView) {
                if let clear = view as? ClearButton { found = clear }
                view.subviews.forEach(walk)
            }
            walk(sidebar)
            let clear = try XCTUnwrap(found)
            clear.superview?.layout()
            clear.layout()
            let label = try XCTUnwrap(clear.subviews.first as? NSTextField)
            let frame = label.convert(label.bounds, to: sidebar)
            let advance = label.attributedStringValue.size().width
            XCTAssertGreaterThanOrEqual(frame.width, try XCTUnwrap(label.cell).cellSize.width - 0.5, "at \(width)")
            XCTAssertEqual(frame.minX + ClearButton.cellInset + advance, width - Draw.clearTrailing.value, accuracy: 0.5, "at \(width)")
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
}
