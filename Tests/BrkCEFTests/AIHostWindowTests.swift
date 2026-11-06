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
    /// Q22 (the user's recording of 2026-11-06): a page shown again whose host had stayed behind another window took the
    /// browser window down behind that window. Three windows on screen: ours in front, another one behind it, the host
    /// behind both.
    func testAHostBehindAnotherWindowDoesNotTakeItsParentDown() throws {
        _ = NSApplication.shared
        func shown(_ x: CGFloat, _ window: NSWindow) -> NSWindow {
            window.setFrame(NSRect(x: x, y: 240, width: 220, height: 140), display: false)
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            return window
        }
        let parent = shown(40, NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false))
        let other = shown(80, NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false))
        let host = shown(120, window())
        defer { parent.removeChildWindow(host); for window in [host, other, parent] { window.close() } }
        other.order(.below, relativeTo: parent.windowNumber)
        host.order(.below, relativeTo: other.windowNumber)
        func order() -> [String] {
            (NSWindow.windowNumbers(options: []) ?? []).compactMap { number in
                switch number.intValue {
                case parent.windowNumber: "parent"
                case other.windowNumber: "other"
                case host.windowNumber: "host"
                default: nil
                }
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard order() == ["parent", "other", "host"] else { throw XCTSkip("the windows are not on screen in this session: \(order())") }
        HostWindows.adopt(host, parent: parent)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(order(), ["host", "parent", "other"], "the browser window went behind the other window")
        XCTAssertTrue(host.parent === parent)
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
