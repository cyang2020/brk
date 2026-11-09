import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The strip between the web card and the AI panel (`WindowFrames.aiPanelHandle`, docs/design/ai-right-panel.md): the
/// pointer there is the left-right resize cursor, and a drag to the left widens the panel, as the sidebar's edge widens the
/// sidebar. Each step sends the width the panel's edge would have under the pointer (`AIIntent.panelWidth`); the layout
/// keeps it within the panel's minimum, half the window and the card's minimum. A double click goes back to the default.
@MainActor
final class AIPanelResizeHandle: NSView {
    private let dispatch: Dispatch
    private var rect: CGRect?
    /// The panel's width as laid out now, and where a drag started.
    private var width = Metrics.ai.width.value
    private var start: (x: Double, width: Double)?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.aiControl("panel-resize"))
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func render(_ rect: CGRect?, panelWidth: Double) {
        width = panelWidth
        isHidden = rect == nil && start == nil
        guard rect != self.rect else { return }
        self.rect = rect
        if let rect { frame = rect }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            dispatch(.assist(.panelWidth(Metrics.ai.width.value)))
            return
        }
        start = (Double(event.locationInWindow.x), width)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        // The panel's edge follows the pointer: moving left by n widens it by n.
        dispatch(.assist(.panelWidth(start.width + start.x - Double(event.locationInWindow.x))))
    }

    override func mouseUp(with event: NSEvent) { start = nil }
}

/// The drop area at the window's right edge (docs/design/ai-right-panel.md, 把 tab 拖到窗口右边): while the panel is closed
/// and tabs dragged from the sidebar come within `Metrics.ai.edgeDropBand` of the right edge, an area as wide as the panel
/// shows there, outlined with a dashed line in the Space's color, saying "松手交给 AI". Letting go in it gives the tabs to
/// a new conversation, as Ask AI does. It only shows; the drag itself is the sidebar's.
@MainActor
final class AIEdgeDropView: NSView {
    private let outline = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(outline)
        outline.lineWidth = Metrics.ai.dropBorderWidth.value
        outline.lineDashPattern = Metrics.ai.edgeDropDash.value.map { NSNumber(value: $0) }
        label.font = .systemFont(ofSize: Metrics.ai.edgeDropFont.value, weight: .semibold)
        label.alignment = .center
        label.isSelectable = false
        label.drawsBackground = false
        addSubview(label)
        identify(.aiControl("edge-drop"))
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows the area at `rect` in `theme`'s colors, in `language`.
    func show(in rect: CGRect, theme: ResolvedTheme, language: AILanguage) {
        let style = AIPanelStyle(theme)
        if frame != rect { frame = rect }
        isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let radius = Metrics.content.cornerRadius.value
        let inset = outline.lineWidth / 2
        outline.frame = bounds
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: radius, cornerHeight: radius, transform: nil)
        outline.strokeColor = style.accent.cgColor
        outline.fillColor = style.accent.withAlphaComponent(Metrics.ai.litTint.value).cgColor
        CATransaction.commit()
        label.stringValue = AIThreadWords.dropToAI(language)
        label.textColor = style.accent
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: 8, y: ((bounds.height - size.height) / 2).rounded(), width: max(0, bounds.width - 16), height: size.height)
        setAccessibilityLabel(label.stringValue)
    }

    func hide() { isHidden = true }
}
