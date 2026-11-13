import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// Every view that follows the pointer in a full window (Favorites, Pinned, a collapsed folder and its hover card, a
/// group, a split, Today, the command bar, the Library) takes the pointer coming in, a press, a release and the pointer
/// leaving, without calling back into itself without end. Build 24 quit on the folder card's rows: a row's redraw asked
/// for the highlight and the highlight redrew the row. No test had ever put the pointer on them.
@MainActor
final class PointerSweepTests: XCTestCase {
    static let size = CGSize(width: 1280, height: 776)
    let now = Instant(milliseconds: 1_790_000_000_000)

    func testEveryPointerViewTakesHoverAndPress() throws {
        let ids = IDs()
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        func run(_ command: Command) { state = reduce(state, .user(id, command), ctx).state }
        func view() throws -> WindowSnapshot { try XCTUnwrap(project(state, projection).windows[id]) }
        run(.tabTools(.preferences(includeFavorites: false, previews: true)))
        for path in ["b", "c", "d", "e", "f", "g", "h"] {
            run(.commandBar(.open(.newTab)))
            run(.commandBar(.submit("http://127.0.0.1:9/" + path)))
        }
        let today = try view().space.today.rows.map(\.id)
        XCTAssertGreaterThanOrEqual(today.count, 8)
        run(.item(.move(today[0], to: .into(parent: try view().favorites.root, index: 0))))
        run(.tab(.togglePin(.item(today[1]))))
        run(.tabTools(.bulk(.items([today[2], today[3]]), .newFolder(group: false))))
        let folder = try XCTUnwrap(state.doc.tree[today[2]]?.parent)
        run(.item(.toggleFolder(folder)))
        run(.tabTools(.bulk(.items([today[4], today[5]]), .newFolder(group: true))))
        run(.split(.addPane))
        run(.commandBar(.submit("http://127.0.0.1:9/split")))

        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // On screen (the card opens only over a visible window), out of the way of other windows.
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        defer { window.close() }
        let root = WindowRootView(dispatch: { _ in })
        window.contentView = root
        func render() throws {
            let shown = try view()
            root.render(shown, frames: WindowLayout.compute(shown, contentSize: Self.size), surface: { _ in nil })
            root.layoutSubtreeIfNeeded()
        }
        try render()
        XCTAssertGreaterThan(sweep(root, in: window), 20, "the sidebar's rows, tiles and buttons were reached")

        // The collapsed folder's own hover opens its card after the delay; then the card's rows.
        let row = try XCTUnwrap(ViewTreeSearch.find(ViewID.row(folder).identifier, in: root) as? HoverView)
        row.setHovered(true)
        // Until the card is up, not a fixed time: GitHub's runners fire timers late; a fixed wait failed there (builds 35 to 37).
        let opens = Date().addingTimeInterval(PreviewDraw.delay.value + 3)
        while ViewTreeSearch.find("sidebar-hover-card", in: root) == nil, Date() < opens { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        let card = try XCTUnwrap(ViewTreeSearch.find("sidebar-hover-card", in: root), "the folder card opened")
        XCTAssertGreaterThanOrEqual(sweep(card, in: window), 2, "the card's rows were reached")
        row.setHovered(false)

        run(.commandBar(.open(.newTab)))
        try render()
        XCTAssertGreaterThan(sweep(root, in: window), 0)
        run(.commandBar(.dismiss))
        run(.library(.open(nil)))
        try render()
        XCTAssertGreaterThan(sweep(root, in: window), 0)
    }

    /// Sends every pointer-tracking owner under `view` the pointer coming in and moving, a press and release (hover
    /// views), and the pointer leaving. Returns how many owners it reached.
    private func sweep(_ view: NSView, in window: NSWindow) -> Int {
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        let moved = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        var reached = 0
        func visit(_ view: NSView) {
            view.updateTrackingAreas()
            for area in view.trackingAreas {
                guard let owner = area.owner as? NSResponder else { continue }
                if area.options.contains(.mouseEnteredAndExited) { owner.mouseEntered(with: event(.mouseEntered)) }
                if area.options.contains(.mouseMoved) { owner.mouseMoved(with: moved) }
                if let hover = owner as? HoverView { hover.isPressed = true; hover.isPressed = false }
                if area.options.contains(.mouseEnteredAndExited) { owner.mouseExited(with: event(.mouseExited)) }
                reached += 1
            }
            for child in view.subviews { visit(child) }
        }
        visit(view)
        return reached
    }
}
