import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
import XCTest

/// A conversation row dragged onto a Space's dot in the dock moves the conversation there. The list changes under a drag
/// often (a running conversation's steps, a "Replied 2 min ago" minute ticking over); the drag must still end where the
/// user lets go, with its picture and the dot's highlight gone.
@MainActor
final class AIThreadListDragTests: XCTestCase {
    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func panel(_ detail: String) -> AIPanelSnapshot {
        let row = AIThreadRow(id: AIRequestID("kettle"), title: "Kettle prices", state: .idle, detail: detail, updatedAt: Instant(milliseconds: 0))
        return AIPanelSnapshot(page: .list, hasConversation: false, space: SpaceID("home"), spaceTitle: "Home", language: .en, search: "",
                               strips: [], groups: [AIThreadGroup(kind: .today, title: "Today", rows: [row])], waiting: 0, spaces: [])
    }

    /// A list in an off-screen window, a row of it dragged onto the dock's "work" dot (the button held down).
    @MainActor private final class Drag {
        /// What the list sent and lit, and the button's state; its own object, so the list's closures do not keep the window.
        final class Log {
            var sent: [Command] = []
            var lit: [SpaceID?] = []
            var buttonDown = false
        }
        let log: Log
        var sent: [Command] { log.sent }
        var lit: [SpaceID?] { log.lit }
        var buttonDown: Bool {
            get { log.buttonDown }
            set { log.buttonDown = newValue }
        }
        let window: NSWindow
        let root: NSView
        let list: AIThreadListView
        let style = AIPanelStyle(resolveTheme(.default))
        var start = CGPoint.zero

        init() {
            _ = NSApplication.shared
            let log = Log()
            self.log = log
            // Off screen, but ordered in: a window that is not ordered in takes no mouse events.
            window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: 360, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            root = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 640))
            window.contentView = root
            list = AIThreadListView(dispatch: { [log] in log.sent.append($0) })
            list.frame = root.bounds
            root.addSubview(list)
            list.dockSpace = { _ in SpaceID("work") }
            list.showDockDrop = { [log] in log.lit.append($0) }
            list.leftButtonDown = { [log] in log.buttonDown }
        }
    }

    private func startDrag(_ d: Drag, detail: String) throws {
        d.list.render(panel(detail), style: d.style)
        d.list.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.aiControl("thread-kettle").identifier, in: d.list))
        XCTAssertFalse(row.frame.isEmpty)
        d.start = row.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        d.buttonDown = true
        d.window.sendEvent(mouse(.leftMouseDown, d.start, in: d.window))
        d.window.sendEvent(mouse(.leftMouseDragged, CGPoint(x: d.start.x + 10, y: d.start.y - 10), in: d.window))
        d.window.sendEvent(mouse(.leftMouseDragged, CGPoint(x: d.start.x + 30, y: d.start.y - 30), in: d.window))
        XCTAssertNotNil(ViewTreeSearch.find(ViewID.aiControl("thread-drag").identifier, in: d.root), "the row's picture follows the pointer")
        XCTAssertEqual(d.lit.last, SpaceID("work"))
    }

    func testARowDraggedWhileTheListChangesStillDrops() throws {
        let d = Drag()
        defer { d.window.close() }
        let (window, root, list, style, work) = (d.window, d.root, d.list, d.style, SpaceID("work"))
        try startDrag(d, detail: "Replied 1 min ago")
        let start = d.start

        list.render(panel("Replied 2 min ago"), style: style)   // the minute ticks over mid-drag
        d.buttonDown = false
        window.sendEvent(mouse(.leftMouseUp, CGPoint(x: start.x + 30, y: start.y - 30), in: window))
        let (sent, lit) = (d.sent, d.lit)
        XCTAssertNil(ViewTreeSearch.find(ViewID.aiControl("thread-drag").identifier, in: root), "the picture goes on release")
        XCTAssertEqual(lit.last, .some(nil), "the dot is no longer lit")
        XCTAssertEqual(sent.filter { if case .assist(.moveConversation) = $0 { true } else { false } },
                       [.assist(.moveConversation(AIRequestID("kettle"), work))])
        XCTAssertEqual((ViewTreeSearch.find(ViewID.aiControl("thread-kettle").identifier, in: list) as? AIThreadRowView)?.row.detail,
                       "Replied 2 min ago", "the list catches up once the drag is over")
    }

    /// The mouse-up of a drag can go elsewhere (an alert or a menu opens mid-drag and takes it). The next change to the
    /// list ends that drag without a drop: the picture and the dot's highlight go and the rows catch up. The list used to
    /// stop changing until another row drag ended.
    func testADragWhoseMouseUpWentElsewhereEndsAtTheNextChange() throws {
        let d = Drag()
        defer { d.window.close() }
        try startDrag(d, detail: "Replied 1 min ago")
        d.buttonDown = false   // released, but the row never saw it
        d.list.render(panel("Replied 2 min ago"), style: d.style)
        XCTAssertNil(ViewTreeSearch.find(ViewID.aiControl("thread-drag").identifier, in: d.root), "the picture goes")
        XCTAssertEqual(d.lit.last, .some(nil), "the dot is no longer lit")
        XCTAssertEqual((ViewTreeSearch.find(ViewID.aiControl("thread-kettle").identifier, in: d.list) as? AIThreadRowView)?.row.detail,
                       "Replied 2 min ago", "the rows catch up")
        XCTAssertFalse(d.sent.contains { if case .assist(.moveConversation) = $0 { true } else { false } }, "nothing was dropped")
    }
}
