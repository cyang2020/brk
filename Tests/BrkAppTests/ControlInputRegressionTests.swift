import AppKit
import BrkBase
import BrkControl
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor
final class ControlInputRegressionTests: XCTestCase {
    func testRepeatedPreferencesRaisesTheExistingWindow() throws {
        let h = Harness()
        defer { h.store.dispatch(.user(h.window, .settings(.closeWindow))); h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .settings(.openPane(.general))))
        let settings = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.contentView?.accessibilityIdentifier() == "settings" })
        settings.orderOut(nil)
        let before = h.store.snapshot.settings

        XCTAssertTrue(h.store.dispatchKey(h.window, h.key("cmd+,", stage: .menu, id: 1)))

        XCTAssertTrue(settings.isVisible, "Preferences must present the existing window even when the pane did not change")
        XCTAssertEqual(h.store.snapshot.settings, before, "raising a window should not mutate settings")
    }

    /// A real key still waiting in the app's queue is handled before keys the control socket types after it. The README
    /// recording (2026-11-10) typed "emoji" through the socket, pressed a real Tab, then typed "define" through the socket:
    /// the socket's keys went in at the head of the queue, the bar read "emojidefine" before the Tab came, and that Tab sent
    /// "emojidefine" to the agent.
    func testAWaitingRealTabIsHandledBeforeKeysTypedAfterIt() throws {
        let h = Harness()
        defer { h.store.dispatch(.user(h.window, .commandBar(.dismiss))); h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .commandBar(.open(.newTab))))
        let window = try XCTUnwrap(h.store.windowController(h.window)?.window)
        let input = try XCTUnwrap(ViewTree.find("command-bar-input", in: window) as? NSTextField)
        let injector = EventInjector()
        try injector.type("emoji", in: window)
        for down in [true, false] {
            let tab = try XCTUnwrap(NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
                                                     isARepeat: false, keyCode: Key.tab.code))
            NSApp.postEvent(tab, atStart: false)
        }
        try injector.type("define", in: window)
        let pill = try XCTUnwrap(ViewTree.find("command-bar-pill", in: window))
        XCTAssertFalse(pill.isHidden, "the Tab entered the emoji prefix before define was typed")
        XCTAssertEqual(input.stringValue, "define")
    }

    func testSettingsCloseWithoutAKeyWindowDoesNotArchiveABrowserTab() async throws {
        let h = Harness()
        defer { h.store.dispatch(.user(h.window, .settings(.closeWindow))); h.cleanUp() }
        h.store.start()
        let executor = ControlExecutor(store: h.store, engine: h.engine, clock: nil)
        let opened = await executor.run(.openSettings(pane: .profiles))
        guard case .dispatched = opened else { return XCTFail("openSettings failed: \(opened)") }
        NSApp.keyWindow?.resignKey()
        XCTAssertNil(NSApp.keyWindow)
        let tabs = h.store.snapshot.windows[h.window]?.space.today.rows

        guard case .ok = await executor.run(.press(chord: "cmd+w")) else { return XCTFail("press failed") }

        XCTAssertNil(h.store.snapshot.settings.pane)
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.space.today.rows, tabs)
    }
}
