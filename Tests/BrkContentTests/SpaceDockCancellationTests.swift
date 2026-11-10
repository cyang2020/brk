import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkSidebar

@MainActor
final class SpaceDockCancellationTests: XCTestCase {
    func testCancellationSurvivesContinuedPointerMovementUntilRelease() throws {
        try exercise(cancel: true, moveAfterCancel: true)
    }

    func testFreshPressAfterCancelledSequenceCanReorder() throws {
        try exercise(cancel: true, moveAfterCancel: true, freshPress: true)
    }

    private func exercise(cancel: Bool, moveAfterCancel: Bool, freshPress: Bool = false) throws {
        let size = CGSize(width: 1280, height: 776)
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: { UUID().uuidString })
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: size), ctx: ctx).state
        let projection = ProjectionContext(now: now, calendar: .current)
        let window = try XCTUnwrap(project(state, projection).windows.keys.first)
        for title in ["Second", "Third"] {
            state = reduce(state, .user(window, .space(.create(title: title, icon: .none, theme: .default))), ctx).state
        }
        let snapshot = try XCTUnwrap(project(state, projection).windows[window])
        let frames = try XCTUnwrap(WindowLayout.compute(snapshot, contentSize: size).sidebar)
        var commands: [Command] = []
        let dock = DockView(dispatch: { commands.append($0) })
        dock.hapticsEnabled = false
        dock.frame = frames.dock
        dock.render(snapshot.dock, frames: frames, palette: Palette(snapshot.theme))
        let first = snapshot.dock[0].id, third = snapshot.dock[2].id
        let cell = try XCTUnwrap(dock.subviews.compactMap { $0 as? DockCellView }.first { $0.id == third })
        let a = try XCTUnwrap(frames.dockSpaces[third]), b = try XCTUnwrap(frames.dockSpaces[first])
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let start = CGPoint(x: a.midX, y: a.midY), end = CGPoint(x: b.midX, y: b.midY)
        cell.mouseDown(with: try mouse(.leftMouseDown, start))
        cell.mouseDragged(with: try mouse(.leftMouseDragged, end))
        // The cancellation entry point shared by Escape and window resignation.
        if cancel { dock.cancelReorder() }
        if moveAfterCancel { cell.mouseDragged(with: try mouse(.leftMouseDragged, end)) }
        cell.mouseUp(with: try mouse(.leftMouseUp, end))
        if freshPress {
            XCTAssertTrue(commands.isEmpty)
            cell.mouseDown(with: try mouse(.leftMouseDown, start))
            cell.mouseDragged(with: try mouse(.leftMouseDragged, end))
            cell.mouseUp(with: try mouse(.leftMouseUp, end))
        }
        print("DOCK_REPRO cancel=\(cancel) moveAfterCancel=\(moveAfterCancel) commands=\(commands)")
        XCTAssertEqual(commands, cancel && !freshPress ? [] : [.space(.move(third, index: 0))],
            "A cancelled drag must stay cancelled until mouse-up, even if the pointer moves again")
        dock.cancelReorder()
    }
}
