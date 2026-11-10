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
