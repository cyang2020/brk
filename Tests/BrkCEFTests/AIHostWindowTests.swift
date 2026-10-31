import AppKit
import XCTest
@testable import BrkCEF

@MainActor
final class AIHostWindowTests: XCTestCase {
    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = AIActivationWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }
    func testReturningViewsKeepsHostNonKeyUntilNativeDestruction() {
        let host = window()
        defer { host.close() }
        XCTAssertTrue(host.canBecomeKey)
        HostWindows.adopt(host, parent: nil)
        XCTAssertFalse(host.canBecomeKey)
        XCTAssertFalse(host.canBecomeMain)
        HostWindows.release(host)
        XCTAssertFalse(host.canBecomeKey, "CEF still owns this closing native window")
        XCTAssertFalse(host.canBecomeMain)
    }
    func testUnguardedSiblingKeepsItsNormalActivationPolicy() {
        let host = window(), standalone = window()
        defer { host.close(); standalone.close() }
        HostWindows.adopt(host, parent: nil)
        XCTAssertFalse(host.canBecomeKey)
        XCTAssertTrue(standalone.canBecomeKey)
        XCTAssertTrue(standalone.canBecomeMain)
    }
}

@MainActor
private final class AIActivationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
