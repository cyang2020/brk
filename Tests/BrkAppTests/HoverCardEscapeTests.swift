import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import XCTest
@testable import BrkApp

/// Escape while the search field of a sidebar hover card (Arc Previews of a collapsed folder) has the keyboard closes
/// the card. The window gave Escape to the key table first, as it does for every native field, and the table ran
/// Exit: the card kept its text and stayed, and a full-screen window left full screen. The keyboard then goes back to
/// what the snapshot focuses (the page), not to the window itself.
@MainActor
final class HoverCardEscapeTests: XCTestCase {
    private final class Routed { var keys: [KeyInput] = [] }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for child in view.subviews { if let found = find(identifier, in: child) { return found } }
        return nil
    }

    func testEscapeInAHoverCardsSearchFieldClosesTheCard() throws {
        _ = NSApplication.shared
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: { UUID().uuidString })
        let pc = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://example.test/a"), contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        let window = try XCTUnwrap(project(state, pc).windows.keys.first)
        func run(_ command: Command) { state = reduce(state, .user(window, command), ctx).state }
        func folder() -> FolderRow? {
            let space = project(state, pc).windows[window]!.space
            for row in space.pinned.rows + space.today.rows { if case .folder(let folder) = row { return folder } }
            return nil
        }
        run(.tabTools(.preferences(includeFavorites: false, previews: true)))
        for path in ["b", "c"] {
            run(.commandBar(.open(.newTab)))
            run(.commandBar(.submit("https://example.test/" + path)))
        }
        let today = project(state, pc).windows[window]!.space.today.rows.map(\.id)
        run(.tabTools(.bulk(.items([today[0], today[1]]), .newFolder(group: false))))
        let made = try XCTUnwrap(folder())
        run(.item(.rename(made.id, title: "Folder")))
        if folder()?.collapsed == false { run(.item(.toggleFolder(made.id))) }
        XCTAssertEqual(folder()?.collapsed, true)

        let routed = Routed()
        let engine = FakeEngine()
        let controller = WindowController(id: window, engine: engine, send: { _ in }, routeKey: { routed.keys.append($0); return true })
        defer { controller.window.orderOut(nil) }
        controller.root.frame = CGRect(x: 0, y: 0, width: 1280, height: 776)
        controller.render(project(state, pc).windows[window]!)
        // On screen, far from other windows: the card opens only over a visible window.
        controller.window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        controller.window.orderFront(nil)
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                            windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        let row = try XCTUnwrap(find(ViewID.row(made.id).identifier, in: controller.root))
        row.mouseEntered(with: entered)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let card = try XCTUnwrap(find("sidebar-hover-card", in: controller.root), "the folder's card did not open")
        card.mouseEntered(with: entered)
        let search = try XCTUnwrap(card.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(controller.window.makeFirstResponder(search))
        search.stringValue = "b"

        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber,
                                                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        let focusedBefore = engine.focused.count
        XCTAssertTrue(controller.window.hostEvent(escape), "Escape was not taken")
        XCTAssertNil(find("sidebar-hover-card", in: controller.root), "Escape left the card open")
        XCTAssertTrue(routed.keys.isEmpty, "Escape went to the key table (Exit) instead of the card")
        // The field went with the card: the snapshot's focus takes the keyboard back instead of the window itself.
        XCTAssertGreaterThan(engine.focused.count, focusedBefore, "after Escape the keyboard stayed with the window, not the page")
    }
}
