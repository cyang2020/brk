import AppKit
import BrkBase

/// The card's button: Arc's blue (#3038FF) under a violet glow that drifts across it while the card is open
/// (arc-hover.png, arc-hover-above.png), 24 pt tall, white 12 pt title.
@MainActor
final class UpdateActionButton: NSButton {
    private let gradient = CAGradientLayer()
    var reduceMotion = false
    var animates = false { didSet { updateMotion() } }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.55 } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        wantsLayer = true
        let u = Metrics.updateBanner
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = u.actionRadius.value
        layer?.masksToBounds = true
        let blue = u.actionBlue.value, glow = u.actionGlow.value
        let base = NSColor(srgbRed: blue[0], green: blue[1], blue: blue[2], alpha: 1).cgColor
        layer?.backgroundColor = base
        gradient.colors = [base, NSColor(srgbRed: glow[0], green: glow[1], blue: glow[2], alpha: 1).cgColor, base]
        gradient.locations = [0.1, 0.5, 0.9]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.insertSublayer(gradient, at: 0)
        font = .systemFont(ofSize: u.fontSize.value)
        contentTintColor = .white
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gradient.frame = bounds.insetBy(dx: -bounds.width * 0.3, dy: 0)
        CATransaction.commit()
    }
    private func updateMotion() {
        guard animates, !reduceMotion, window != nil else { gradient.removeAllAnimations(); return }
        guard gradient.animation(forKey: "glow") == nil else { return }
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.3, 0.1, 0.5]
        animation.toValue = [0.5, 0.9, 1.3]
        animation.duration = Metrics.updateBanner.actionGlowCycle.value
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(animation, forKey: "glow")
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMotion() }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        alphaValue = flag ? 0.75 : (isEnabled ? 1 : 0.55)
    }
}

/// Arc's Automatic Updates row: an SF Symbol square (`checkmark.square` when on) before the label, both in the card's
/// secondary colour (bin:0x102585424). A toggle button, so a click, Space and VoiceOver flip it like a checkbox.
@MainActor
final class UpdateCheckbox: NSButton {
    var ink: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setButtonType(.toggle)
        isBordered = false
        font = .systemFont(ofSize: Metrics.updateBanner.fontSize.value)
        setAccessibilityRole(.checkBox)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var symbol: NSImage? {
        let name = state == .on ? "checkmark.square" : "square"
        let config = NSImage.SymbolConfiguration(pointSize: Metrics.updateBanner.checkboxSymbolSize.value, weight: .regular)
            .applying(.init(paletteColors: [ink]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font ?? .systemFont(ofSize: Metrics.updateBanner.fontSize.value), .foregroundColor: ink])
    }
    override var intrinsicContentSize: NSSize {
        let image = symbol?.size ?? .zero, text = label.size()
        return NSSize(width: ceil(image.width + Metrics.updateBanner.checkboxGap.value + text.width), height: ceil(max(image.height, text.height)))
    }
    override var state: NSControl.StateValue { didSet { needsDisplay = true; setAccessibilityValue(state == .on) } }
    override func draw(_ dirtyRect: NSRect) {
        let text = label, size = text.size()
        var x = 0.0
        if let image = symbol {
            image.draw(in: CGRect(x: 0, y: (bounds.height - image.size.height) / 2, width: image.size.width, height: image.size.height))
            x = image.size.width + Metrics.updateBanner.checkboxGap.value
        }
        text.draw(at: CGPoint(x: x, y: (bounds.height - size.height) / 2))
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill() }
}

@MainActor
final class UpdateCelebrationView: NSView {
    private let heart = CAShapeLayer()
    private let ring = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16, y: 6))
        path.addCurve(to: CGPoint(x: 4, y: 22), control1: CGPoint(x: 2, y: 15), control2: CGPoint(x: 3, y: 18))
        path.addCurve(to: CGPoint(x: 16, y: 23), control1: CGPoint(x: 5, y: 29), control2: CGPoint(x: 14, y: 29))
        path.addCurve(to: CGPoint(x: 28, y: 22), control1: CGPoint(x: 18, y: 29), control2: CGPoint(x: 27, y: 29))
        path.addCurve(to: CGPoint(x: 16, y: 6), control1: CGPoint(x: 29, y: 18), control2: CGPoint(x: 30, y: 15))
        path.closeSubpath()
        heart.path = path
        heart.fillColor = NSColor(red: 0.75, green: 0.45, blue: 0.87, alpha: 1).cgColor
        ring.path = CGPath(ellipseIn: CGRect(x: 1, y: 1, width: 30, height: 30), transform: nil)
        ring.strokeColor = heart.fillColor
        ring.fillColor = nil
        ring.lineWidth = 1.5
        ring.opacity = 0
        for shape in [ring, heart] { shape.frame = CGRect(x: 0, y: 0, width: 32, height: 32); layer?.addSublayer(shape) }
        setAccessibilityElement(false)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func play(reduced: Bool) {
        heart.removeAllAnimations(); ring.removeAllAnimations()
        guard !reduced else { return }
        let beat = CAKeyframeAnimation(keyPath: "transform.scale")
        beat.values = [0.35, 1.16, 0.94, 1.06, 1]
        beat.keyTimes = [0, 0.22, 0.4, 0.57, 1]
        beat.duration = 2
        heart.add(beat, forKey: "celebrate")
        let expand = CABasicAnimation(keyPath: "transform.scale")
        expand.fromValue = 0.7; expand.toValue = 1.29
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8; fade.toValue = 0
        let ripple = CAAnimationGroup()
        ripple.animations = [expand, fade]
        ripple.duration = 1.4
        ripple.beginTime = CACurrentMediaTime() + 0.4
        ripple.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(ripple, forKey: "ripple")
    }
}
