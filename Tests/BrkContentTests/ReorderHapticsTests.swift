import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// Advanced > "Haptic feedback when reordering tabs": dragging a Today row over the other rows ticks once per new
/// drop slot with the switch on, and never with it off.
@MainActor
final class ReorderHapticsTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    private func ticks(haptics: Bool) throws -> Int {
        let ids = IDs()
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        for path in ["b", "c", "d"] {
            state = reduce(state, .user(id, .commandBar(.open(.newTab))), ctx).state
            state = reduce(state, .user(id, .commandBar(.submit("http://127.0.0.1:9/" + path))), ctx).state
        }
        state = reduce(state, .user(id, .settings(.advanced(.hapticsOnReorder(haptics)))), ctx).state
        let view = try XCTUnwrap(project(state, projection).windows[id])
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = WindowRootView(dispatch: { _ in })
        window.contentView = root
        root.render(view, frames: WindowLayout.compute(view, contentSize: Self.size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        var count = 0
        root.sidebar.drag.haptic = { count += 1 }
        let rows = view.space.today.rows.map(\.id)
        XCTAssertEqual(rows.count, 4)
        func row(_ item: ItemID) throws -> RowView { try XCTUnwrap(ViewTreeSearch.find(ViewID.row(item).identifier, in: root) as? RowView) }
        func center(_ v: NSView) -> CGPoint { v.convert(CGPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil) }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let source = try row(rows[0])
        let start = center(source)
        source.mouseDown(with: mouse(.leftMouseDown, start))
        for target in rows.dropFirst() {
            let end = center(try row(target))
            for step in 1...4 {
                let t = Double(step) / 4
                source.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: start.x, y: start.y + (end.y - start.y) * t)))
            }
        }
        source.mouseUp(with: mouse(.leftMouseUp, center(try row(rows[3]))))
        return count
    }

    func testReorderingTicksOnlyWithTheSwitchOn() throws {
        XCTAssertGreaterThan(try ticks(haptics: true), 0, "on: crossing rows ticks")
        XCTAssertEqual(try ticks(haptics: false), 0, "off: no haptics while reordering")
    }
}
