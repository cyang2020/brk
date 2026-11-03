import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
import XCTest

/// Advanced > "Allow window dragging from the top of webpages": on, the page card at the window's top edge has a
/// band that moves the window and hands a plain click to the page; off, there is no band and a press there is the
/// page's.
@MainActor
final class PageDragStripTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    /// A page view that records the clicks it receives.
    final class Page: NSView {
        var clicks = 0
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) { clicks += 1 }
    }

    private func snapshot(dragging: Bool) -> WindowSnapshot {
        let ids = IDs()
        let ctx = { Context(now: self.now, newID: ids.next) }
        let calendar = Calendar(identifier: .gregorian)
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size), ctx: ctx()).state
        let window = project(state, ProjectionContext(now: now, calendar: calendar)).windows.keys.sorted()[0]
        state = reduce(state, .user(window, .settings(.advanced(.windowDraggingFromPages(dragging)))), ctx()).state
        return project(state, ProjectionContext(now: now, calendar: calendar)).windows[window]!
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func testTheBandMovesTheWindowAndPassesClicksToThePage() throws {
        XCTAssertFalse(snapshot(dragging: false).content.windowDragging)
        let v = snapshot(dragging: true)
        XCTAssertTrue(v.content.windowDragging, "on, with the toolbar hidden (the default)")
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: Self.size.width, height: Self.size.height), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = WindowRootView(dispatch: { _ in })
        window.contentView = root
        let page = Page(frame: .zero)
        let frames = WindowLayout.compute(v, contentSize: Self.size)
        root.render(v, frames: frames, surface: { _ in page })
        root.layoutSubtreeIfNeeded()
        let strip = try XCTUnwrap(ViewTreeSearch.find("page-drag-0", in: root) as? PageDragStrip, "the band is over the first card")
        let card = try XCTUnwrap(frames.cards.first?.rect)
        let band = strip.convert(strip.bounds, to: root)
        XCTAssertEqual(band.minY, card.minY, accuracy: 0.5)
        XCTAssertEqual(band.height, Metrics.content.pageDragHeight.value, accuracy: 0.5)

        // A press without movement is the page's click.
        let inside = strip.convert(CGPoint(x: strip.bounds.midX, y: strip.bounds.midY), to: nil)
        strip.mouseDown(with: mouse(.leftMouseDown, inside, in: window))
        strip.mouseUp(with: mouse(.leftMouseUp, inside, in: window))
        XCTAssertEqual(page.clicks, 1, "the click went through to the page")

        // A drag moves the window by the pointer's movement.
        let origin = window.frame.origin
        strip.mouseDown(with: mouse(.leftMouseDown, inside, in: window))
        let screen = window.convertPoint(toScreen: inside)
        for step in 1...4 {
            let point = window.convertPoint(fromScreen: CGPoint(x: screen.x + Double(step) * 10, y: screen.y - Double(step) * 5))
            strip.mouseDragged(with: mouse(.leftMouseDragged, point, in: window))
        }
        strip.mouseUp(with: mouse(.leftMouseUp, window.convertPoint(fromScreen: CGPoint(x: screen.x + 40, y: screen.y - 20)), in: window))
        XCTAssertEqual(window.frame.origin.x - origin.x, 40, accuracy: 0.5)
        XCTAssertEqual(window.frame.origin.y - origin.y, -20, accuracy: 0.5)
        XCTAssertEqual(page.clicks, 1, "a drag is not a click")

        // Off: no band.
        let off = snapshot(dragging: false)
        root.render(off, frames: WindowLayout.compute(off, contentSize: Self.size), surface: { _ in page })
        XCTAssertNil(ViewTreeSearch.find("page-drag-0", in: root))
    }
}

/// Finds a view by accessibility identifier.
enum ViewTreeSearch {
    @MainActor static func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for child in view.subviews { if let found = find(identifier, in: child) { return found } }
        return nil
    }
}
