import AppKit
import BrkBase

@MainActor
final class SadTabView: NSView {
    private let illustration = SadTabIllustration(frame: .zero)
    private let title = NSTextField(labelWithString: "This tab has crashed")
    private let message = NSTextField(wrappingLabelWithString: "Something went wrong while displaying this page. Reload to try again.")
    private let reload = NSButton(title: "Reload", target: nil, action: nil)
    var reloadAction: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("sad-tab")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        message.font = .systemFont(ofSize: 14)
        message.textColor = .secondaryLabelColor
        title.alignment = .center
        message.alignment = .center
        reload.bezelStyle = .rounded
        reload.target = self
        reload.action = #selector(retry)
        reload.identifier = NSUserInterfaceItemIdentifier("sad-tab-reload")
        for view in [illustration, title, message, reload] { addSubview(view) }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let width = min(Metrics.sidebarTools.sadMessageWidth.value, max(100, bounds.width - 32))
        let top = max(16, bounds.midY - 140)
        illustration.frame = NSRect(x: bounds.midX - 48, y: top, width: Metrics.sidebarTools.sadIllustration.value.width, height: Metrics.sidebarTools.sadIllustration.value.height)
        title.frame = NSRect(x: bounds.midX - width / 2, y: top + 124, width: width, height: 30)
        message.frame = NSRect(x: bounds.midX - width / 2, y: top + 166, width: width, height: 52)
        reload.frame = NSRect(x: bounds.midX - 52, y: top + 232, width: 104, height: 32)
    }
    @objc private func retry() { reloadAction?() }
}

/// Original AppKit illustration. The Arc asset's existence is known; its pixels are not copied.
@MainActor
private final class SadTabIllustration: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        let paper = NSBezierPath(roundedRect: NSRect(x: 14, y: 4, width: 68, height: 94), xRadius: 9, yRadius: 9)
        paper.fill()
        NSColor.windowBackgroundColor.setFill()
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 61, y: 4)); fold.line(to: NSPoint(x: 82, y: 25)); fold.line(to: NSPoint(x: 61, y: 25)); fold.close(); fold.fill()
        NSColor.labelColor.setStroke()
        let face = NSBezierPath()
        face.lineWidth = 3
        for x in [31.0, 58.0] {
            face.move(to: NSPoint(x: x, y: 44)); face.line(to: NSPoint(x: x + 7, y: 51))
            face.move(to: NSPoint(x: x + 7, y: 44)); face.line(to: NSPoint(x: x, y: 51))
        }
        face.move(to: NSPoint(x: 33, y: 76))
        face.curve(to: NSPoint(x: 64, y: 76), controlPoint1: NSPoint(x: 42, y: 63), controlPoint2: NSPoint(x: 55, y: 63))
        face.stroke()
    }
}
