import AppKit
import BrkBase
import BrkControl
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor
final class ControlInputRegressionTests: XCTestCase {
    func testWindowlessTypingTargetsTheAttachedSheetBeforeTheBrowser() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let owner = try XCTUnwrap(h.store.windowController(h.window)?.window)
        let sheet = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        let editor = NSTextView(frame: CGRect(x: 10, y: 10, width: 280, height: 100))
        sheet.contentView?.addSubview(editor)
        owner.beginSheet(sheet, completionHandler: { _ in })
        defer { owner.endSheet(sheet); sheet.orderOut(nil) }
        sheet.makeFirstResponder(editor)
        NSApp.keyWindow?.resignKey()
        XCTAssertNil(NSApp.keyWindow)
        h.store.inputWindow = owner
        let executor = ControlExecutor(store: h.store, engine: h.engine, clock: nil)
        let result = await executor.run(.type(text: "sheet input"))
        XCTAssertEqual(result, .ok)
        XCTAssertEqual(editor.string, "sheet input", "The browser must not receive typing intended for its native sheet")
    }

    func testLoadingInAnIncognitoWindowReturnsItsPrivateTab() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .window(.newIncognito)))
        let privateWindow = try XCTUnwrap(h.store.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        defer { h.store.windowController(privateWindow)?.window.orderOut(nil) }
        let executor = ControlExecutor(store: h.store, engine: h.engine, clock: nil)
        let result = await executor.run(.load(window: privateWindow, url: URL(string: "https://example.com/private")!))
        guard case .loaded(let tab) = result else { return XCTFail("load did not return the private tab: \(result)") }
        XCTAssertTrue(h.store.snapshot.windows[privateWindow]?.scratch?.rows.contains { $0.id == tab } == true)
        guard case .incognito? = h.store.snapshot.pages.first(where: { $0.id == PageID(window: privateWindow, item: tab) })?.context else { return XCTFail("missing private epoch") }
    }

    func testWindowlessControlOperationsFollowTheLastExplicitBrowserTarget() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .window(.newIncognito)))
        let executor = ControlExecutor(store: h.store, engine: h.engine, clock: nil)
        let windows = h.store.snapshot.windows.keys.sorted()
        defer { for id in windows { h.store.windowController(id)?.window.orderOut(nil) } }
        XCTAssertEqual(windows.count, 2)
        for id in windows {
            guard case .dispatched = await executor.run(.dispatch(window: id, command: .commandBar(.open(.newTab)))) else {
                return XCTFail("targeted dispatch failed")
            }
            NSApp.keyWindow?.resignKey()
            XCTAssertEqual(h.store.windowController(nil)?.id, id)
        }
    }

    func testClickAndTypingReachTheEditorInAnInactiveWindow() throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        let menu = NSMenu(title: "Main")
        let edit = NSMenu(title: "Edit")
        let holder = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        holder.submenu = edit
        menu.addItem(holder)
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let fullscreen = NSMenuItem(title: "Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = .function
        edit.addItem(fullscreen)
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
        try events.type("Profile", in: window)

        XCTAssertEqual(editor.string, "Profile")
        XCTAssertEqual(window.fullscreenRequests, 0, "plain f must not match Fn+F")
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

private final class InactiveInputWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    private(set) var fullscreenRequests = 0
    override func toggleFullScreen(_ sender: Any?) { fullscreenRequests += 1 }
}
