import AppKit
import BrkContent
import BrkDomain
import BrkLayout
import XCTest

extension WindowRootViewTests {
    func testRevealStripRejectsEnteredEventsOutsideItsOwnEdgeBounds() throws {
        _ = NSApplication.shared
        var commands: [Command] = []
        let root = WindowRootView(dispatch: { commands.append($0) })
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let view = snapshot(sidebarVisible: false)
        root.render(view, frames: WindowLayout.compute(view, contentSize: root.bounds.size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        let strip = try XCTUnwrap(root.subviews.first { $0.accessibilityIdentifier() == ViewID.revealStrip.identifier })
        XCTAssertTrue(strip.clipsToBounds)
        func entered(_ point: CGPoint) throws {
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: root.convert(point, to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
            strip.mouseEntered(with: event)
        }
        try entered(CGPoint(x: root.bounds.width - 30, y: root.bounds.midY))
        XCTAssertTrue(commands.isEmpty, "an unclipped tracking area must not reveal from the content side")
        try entered(CGPoint(x: 3, y: root.bounds.midY))
        XCTAssertEqual(commands, [.sidebar(.peek(true))])
    }
}
