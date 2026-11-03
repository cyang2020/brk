import AppKit
import BrkBase
import BrkLayout
import BrkUIKit

/// Advanced > "Allow window dragging from the top of webpages": a clear band over the top of a page card that touches
/// the window's top edge while the toolbar is hidden (`ContentSnapshot.windowDragging`). Dragging it moves the
/// window; a press that does not move past `Metrics.content.pageDragThreshold` is handed to the page underneath on
/// release, so the page's own controls at its top edge still take clicks.
@MainActor
final class PageDragStrip: NSView {
    private var down: NSEvent?
    private var downScreen = CGPoint.zero
    private var startOrigin = CGPoint.zero
    private var dragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        down = event
        dragging = false
        downScreen = window.convertPoint(toScreen: event.locationInWindow)
        startOrigin = window.frame.origin
    }

    /// The pointer's screen position, not its position in the moving window, decides where the window goes.
    override func mouseDragged(with event: NSEvent) {
        guard let window, down != nil else { return }
        let screen = window.convertPoint(toScreen: event.locationInWindow)
        let dx = screen.x - downScreen.x, dy = screen.y - downScreen.y
        if !dragging, hypot(dx, dy) < Metrics.content.pageDragThreshold.value { return }
        dragging = true
        window.setFrameOrigin(CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { down = nil; dragging = false }
        guard let down, !dragging, let page = viewUnder(down) else { return }
        page.mouseDown(with: down)
        page.mouseUp(with: event)
    }

    /// What the press would have hit without the band (the page surface's own view).
    private func viewUnder(_ event: NSEvent) -> NSView? {
        guard let root = window?.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }
        let hit = root.hitTest(root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        return hit === self ? nil : hit
    }
}
