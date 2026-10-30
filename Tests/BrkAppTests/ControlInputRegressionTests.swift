import AppKit
import BrkBase
import BrkControl
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor
final class ControlInputRegressionTests: XCTestCase {
    func testClickAndTypingReachTheEditorInAnInactiveWindow() throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        let menu = NSMenu(title: "Main")
        let edit = NSMenu(title: "Edit")
        let holder = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        holder.submenu = edit
        menu.addItem(holder)
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = previousMenu }
        let window = InactiveInputWindow(contentRect: CGRect(x: 100, y: 100, width: 300, height: 100),
                                         styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let field = NSTextField(frame: CGRect(x: 10, y: 20, width: 250, height: 24))
        field.stringValue = "Default"
        window.contentView?.addSubview(field)
        window.orderFront(nil)
        let events = EventInjector()
        try events.click(at: field.convert(CGPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil), modifiers: [], count: 1, in: window)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertFalse(window.isKeyWindow)

        try events.press(KeyChord(.command, .a), in: window)
        try events.type("Personal", in: window)

        XCTAssertEqual(editor.string, "Personal")
    }

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

    func testSettingsCloseWithoutAKeyWindowDoesNotArchiveABrowserTab() async throws {
        let h = Harness()
        defer { h.store.dispatch(.user(h.window, .settings(.closeWindow))); h.cleanUp() }
        h.store.start()
        let executor = ControlExecutor(store: h.store, engine: h.engine, clock: nil)
        guard case .dispatched = await executor.run(.openSettings(pane: .profiles)) else { return XCTFail("openSettings failed") }
        NSApp.keyWindow?.resignKey()
        XCTAssertNil(NSApp.keyWindow)
        let tabs = h.store.snapshot.windows[h.window]?.space.today.rows

        guard case .ok = await executor.run(.press(chord: "cmd+w")) else { return XCTFail("press failed") }

        XCTAssertNil(h.store.snapshot.settings.pane)
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.space.today.rows, tabs)
    }
}

private final class InactiveInputWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}
