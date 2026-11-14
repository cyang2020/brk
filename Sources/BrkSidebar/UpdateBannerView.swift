import AppKit
import BrkBase
import BrkUIKit

@MainActor
final class UpdateBannerView: HoverView {
    private let dispatch: Dispatch
    private var presentation: UpdatePresentation?
    private var palette: Palette?
    private var requested = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        identify(.tabTool("install-update"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func render(_ presentation: UpdatePresentation?, palette: Palette) {
        if self.presentation != presentation {
            requested = false
            isPressed = false
        }
        self.presentation = presentation
        self.palette = palette
        isHidden = presentation == nil
        setAccessibilityLabel(title)
        setAccessibilityEnabled(canActivate)
        if case .failed(let message) = presentation {
            toolTip = message
            setAccessibilityHelp(message)
        } else {
            toolTip = nil
            setAccessibilityHelp(nil)
        }
        needsDisplay = true
    }

    private var title: String {
        switch presentation {
        case nil: return ""
        case .checking: return "Checking for Updates…"
        case .available: return "New \(Product.name) Version Available"
        case .downloading(_, let fraction):
            guard let fraction, fraction.isFinite else { return "Downloading Update…" }
            return "Downloading Update… \(Int((min(1, max(0, fraction)) * 100).rounded()))%"
        case .preparing: return "Preparing Update…"
        case .ready: return "Restart and Update"
        case .installing: return "Restarting…"
        case .failed: return "Update Failed · Retry"
        }
    }

    private var canActivate: Bool {
        guard !requested else { return false }
        switch presentation {
        case .available, .ready, .failed: return true
        case nil, .checking, .downloading, .preparing, .installing: return false
        }
    }

    override func stateChanged() { needsDisplay = true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard layer?.mask == nil else { return nil }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette, presentation != nil else { return }
        let m = Metrics.updateBanner
        let dark = palette.scheme == .dark
        let index = dark ? 1 : 0
        let shade = dark ? NSColor.white : NSColor.black
        let feedback = canActivate ? (isPressed ? m.pressedAlpha.value : isHovered ? m.hoverAlpha.value : 0) : 0
        let line = m.strokeWidth.value
        let rect = bounds.insetBy(dx: line / 2, dy: line / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        shade.withAlphaComponent(m.fillAlpha.value[index] + feedback).setFill()
        path.fill()
        shade.withAlphaComponent(m.strokeAlpha.value[index]).setStroke()
        path.lineWidth = line
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: m.fontSize.value, weight: .regular),
            .foregroundColor: dark ? NSColor.white : NSColor.black,
            .paragraphStyle: paragraph,
        ])
        let height = text.size().height
        text.draw(in: CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height))
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = canActivate && layer?.mask == nil && alphaValue > 0 && !isHiddenOrHasHiddenAncestor
    }

    override func mouseUp(with event: NSEvent) {
        let activate = isPressed && bounds.contains(local(event))
        isPressed = false
        if activate { _ = accessibilityPerformPress() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard canActivate, layer?.mask == nil, alphaValue > 0, !isHiddenOrHasHiddenAncestor else { return false }
        requested = true
        setAccessibilityEnabled(false)
        needsDisplay = true
        dispatch(.app(.help(.installUpdate)))
        return true
    }
}
