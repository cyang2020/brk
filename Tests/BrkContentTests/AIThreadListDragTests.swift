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

    func testARowDraggedWhileTheListChangesStillDrops() throws {
        _ = NSApplication.shared
        var sent: [Command] = []
        var lit: [SpaceID?] = []
        // Off screen, but ordered in: a window that is not ordered in takes no mouse events.
        let window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: 360, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        defer { window.close() }
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 640))
        window.contentView = root
        let list = AIThreadListView(dispatch: { sent.append($0) })
        list.frame = root.bounds
        root.addSubview(list)
        let work = SpaceID("work")
        list.dockSpace = { _ in work }
        list.showDockDrop = { lit.append($0) }
        let style = AIPanelStyle(resolveTheme(.default))
        list.render(panel("Replied 1 min ago"), style: style)
        list.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.aiControl("thread-kettle").identifier, in: list))
        XCTAssertFalse(row.frame.isEmpty)
        let start = row.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        window.sendEvent(mouse(.leftMouseDown, start, in: window))
        window.sendEvent(mouse(.leftMouseDragged, CGPoint(x: start.x + 10, y: start.y - 10), in: window))
        window.sendEvent(mouse(.leftMouseDragged, CGPoint(x: start.x + 30, y: start.y - 30), in: window))
        XCTAssertNotNil(ViewTreeSearch.find(ViewID.aiControl("thread-drag").identifier, in: root), "the row's picture follows the pointer")
        XCTAssertEqual(lit.last, work)

        list.render(panel("Replied 2 min ago"), style: style)   // the minute ticks over mid-drag
        window.sendEvent(mouse(.leftMouseUp, CGPoint(x: start.x + 30, y: start.y - 30), in: window))
        XCTAssertNil(ViewTreeSearch.find(ViewID.aiControl("thread-drag").identifier, in: root), "the picture goes on release")
        XCTAssertEqual(lit.last, .some(nil), "the dot is no longer lit")
        XCTAssertEqual(sent.filter { if case .assist(.moveConversation) = $0 { true } else { false } },
                       [.assist(.moveConversation(AIRequestID("kettle"), work))])
        XCTAssertEqual((ViewTreeSearch.find(ViewID.aiControl("thread-kettle").identifier, in: list) as? AIThreadRowView)?.row.detail,
                       "Replied 2 min ago", "the list catches up once the drag is over")
    }
}
