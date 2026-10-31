import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

@MainActor final class CaptureOverlayView: NSView {
    private let dispatch: Dispatch
    private let hint = NSTextField(labelWithString: "")
    private let accept = NSButton(title: "Capture Selection", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let preview = NSImageView()
    private var snapshot: CaptureSnapshot?
    private var selection = CGRect.zero
    private var anchor: CGPoint?
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        identify(.tabTool("capture-overlay"))
        hint.textColor = .white; hint.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        hint.maximumNumberOfLines = 2
        for button in [accept, cancel] { button.target = self; button.bezelStyle = .rounded; addSubview(button) }
        accept.action = #selector(confirm); cancel.action = #selector(dismiss)
        accept.identify(.tabTool("capture-confirm")); cancel.identify(.tabTool("capture-cancel"))
        addSubview(hint); addSubview(preview)
        preview.imageScaling = .scaleProportionallyUpOrDown
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    func render(_ value: CaptureSnapshot?, frames: WindowFrames) {
        guard let value, let card = frames.cards.first(where: { if case .page(let page) = $0.content { page == value.request.document.browser.page } else { false } }) else { isHidden = true; snapshot = nil; return }
        let fresh = snapshot?.request.id != value.request.id
        snapshot = value; frame = card.rect; isHidden = false
        if fresh {
            let width = min(360, bounds.width, bounds.height * 9 / 16)
            selection = value.request.mode == .portrait ? CGRect(x: (bounds.width - width) / 2, y: (bounds.height - width * 16 / 9) / 2, width: width, height: width * 16 / 9) : .zero
        }
        let privateCapture: Bool = if case .incognito = value.request.context { true } else { false }
        hint.stringValue = value.image != nil ? "Private capture · memory only · closes when you leave this page" : value.rendering ? "Capturing page…" : value.request.mode == .portrait ? "Drag to frame a portrait capture" : "Drag to select an area · Esc to cancel"
        if privateCapture && value.image == nil { hint.stringValue += " · private, never saved" }
        accept.isHidden = value.rendering || value.image != nil
        accept.isEnabled = selection.width >= 1 && selection.height >= 1
        cancel.title = value.image == nil ? "Cancel" : "Close"
        preview.image = value.image.flatMap { NSImage(data: $0.png) }; preview.isHidden = value.image == nil
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        let margin = Metrics.content.inset.value
        cancel.frame = CGRect(x: bounds.width - 90 - margin, y: margin, width: 90, height: 30)
        accept.frame = CGRect(x: cancel.frame.minX - 164, y: margin, width: 156, height: 30)
        hint.frame = CGRect(x: margin, y: margin + 40, width: bounds.width - margin * 2, height: 44)
        preview.frame = bounds.insetBy(dx: margin * 2, dy: 96)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(snapshot?.image == nil ? 0.35 : 0.88).setFill(); bounds.fill()
        if snapshot?.image == nil, !selection.isEmpty {
            NSColor.white.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { guard snapshot?.rendering == false, snapshot?.image == nil else { return }; anchor = point(event) }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let p = point(event)
        if snapshot?.request.mode == .portrait {
            let width = min(max(1, abs(p.x - anchor.x)), bounds.width, bounds.height * 9 / 16)
            let height = width * 16 / 9
            selection = CGRect(x: min(max(0, min(p.x,anchor.x)), bounds.width - width), y: min(max(0,min(p.y,anchor.y)),bounds.height - height), width: width, height: height)
        } else { selection = CGRect(x: min(p.x,anchor.x), y: min(p.y,anchor.y), width: abs(p.x-anchor.x), height: abs(p.y-anchor.y)) }
        accept.isEnabled = selection.width >= 1 && selection.height >= 1; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); anchor = nil }
    private func point(_ event: NSEvent) -> CGPoint { let p = convert(event.locationInWindow, from: nil); return CGPoint(x: min(bounds.width,max(0,p.x)),y:min(bounds.height,max(0,p.y))) }
    override func keyDown(with event: NSEvent) { if event.keyCode == Key.escape.code { dismiss() } else { super.keyDown(with: event) } }
    @objc private func confirm() {
        guard !selection.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        dispatch(.capture(.select(CaptureRegion(x: selection.minX / bounds.width, y: selection.minY / bounds.height, width: selection.width / bounds.width, height: selection.height / bounds.height))))
    }
    @objc private func dismiss() { dispatch(.capture(.cancel)) }
}
