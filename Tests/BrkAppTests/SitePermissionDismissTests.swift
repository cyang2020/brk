import AppKit
import BrkBase
import XCTest
@testable import BrkApp

/// Escape, a click elsewhere or a newer document dismisses a permission prompt. The prompt forgot its popover before
/// closing it, so the popover stayed on screen with buttons that did nothing.
@MainActor
final class SitePermissionDismissTests: XCTestCase {
    func testDismissingAPromptTakesItsPopoverOffScreen() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        window.orderFront(nil)
        defer { window.close() }
        let page = PageID(window: WindowID("w"), item: ItemID("t"))
        let origin = try XCTUnwrap(SiteOrigin(URL(string: "https://camera.example/")!))
        let target = SiteTarget(document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1), context: .profile(.default), origin: origin)
        let dialogs = SiteDialogs()
        var answers: [SitePermission] = []
        dialogs.permission(SitePermissionPrompt(id: "p1", target: target, requestingOrigin: origin, capabilities: [.camera], frame: nil, mask: 0),
                           in: window) { decision, _ in answers.append(decision) }
        let shown = try XCTUnwrap(dialogs.permissionWindow(for: page.window))
        XCTAssertTrue(shown.isVisible)
        dialogs.dismiss("p1")
        XCTAssertFalse(shown.isVisible, "the popover leaves the screen")
        XCTAssertEqual(answers, [.ask], "answered once, unanswered")
    }
}
