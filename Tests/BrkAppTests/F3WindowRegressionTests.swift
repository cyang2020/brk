import AppKit
import BrkBase
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor
final class F3WindowRegressionTests: XCTestCase {
    func testControlClicksKeepTheRecentTabWalkUntilControlRelease() throws {
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            let h = Harness()
            defer { h.cleanUp() }
            h.store.start()
            let a = h.page.item
            h.store.dispatch(.user(h.window, .commandBar(.submit("https://example.com/b"))))
            let b = try XCTUnwrap(h.store.snapshot.windows[h.window]?.content.panes.first?.tab)
            h.store.dispatch(.user(h.window, .commandBar(.submit("https://example.com/c"))))
            let c = try XCTUnwrap(h.store.snapshot.windows[h.window]?.content.panes.first?.tab)
            let window = try XCTUnwrap(h.store.windowController(h.window)?.window)
            func flags(_ held: NSEvent.ModifierFlags) throws {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: held,
                    timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: 59))
                _ = window.hostEvent(event)
            }
            func cycle(_ press: UInt64) {
                XCTAssertTrue(h.store.dispatchKey(h.window, h.key("ctrl+tab", stage: .menu, id: press)))
            }
            func shown() -> ItemID? { h.store.snapshot.windows[h.window]?.content.panes.first?.tab }
            func selected() -> ItemID? { h.store.snapshot.windows[h.window]?.tabTools.recent?.selected }
            try flags(.control)
            cycle(101)
            XCTAssertEqual(selected(), b)
            XCTAssertEqual(shown(), c, "a press moves only the switcher's selection")
            let click = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: .control,
                timestamp: 2, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            _ = window.hostEvent(click)
            cycle(102)
            XCTAssertEqual(selected(), a, "\(type) restarted the walk")
            XCTAssertEqual(shown(), c)
            try flags([])
            XCTAssertEqual(shown(), a, "release shows the final selection")
            try flags(.control)
            cycle(103)
            try flags([])
            XCTAssertEqual(shown(), c, "the next walk starts from A; intermediate B was only selected, never shown")
        }
    }

    /// The last standard window closed while an incognito window stays open, then the incognito window closed (an open
    /// Settings window keeps Brk running then): no browser window is left on screen, but the menus, the Dock and the
    /// Settings window still have a window to send to, and New Window brings the closed one back with a host window
    func testAMenuCommandAfterEveryBrowserWindowClosedBringsTheClosedWindowBack() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .window(.newIncognito)))
        let incognito = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        h.store.dispatch(.system(.window(h.window, .closed)))
        XCTAssertNil(h.store.windowController(h.window), "its host window is torn down")
        h.store.dispatch(.system(.window(incognito, .closed)))
        XCTAssertNil(h.store.windowController(nil))
        let target = try XCTUnwrap(h.store.commandWindow, "a window for the commands")
        XCTAssertEqual(target, h.window)
        h.router.menuAction(.newWindow, in: target, event: nil)
        XCTAssertNotNil(h.store.windowController(h.window), "New Window brings the closed window back on screen")
        XCTAssertEqual(Array(h.store.snapshot.windows.keys), [h.window])
    }
}
