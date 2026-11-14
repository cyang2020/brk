import AppKit
import BrkBase

@MainActor
final class UpdateActionButton: NSButton {
    private let gradient = CAGradientLayer()
    var reduceMotion = false
    var animates = false { didSet { updateMotion() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = Metrics.updateBanner.actionRadius.value
        layer?.masksToBounds = true
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        gradient.colors = [NSColor(red: 0.16, green: 0.02, blue: 0.22, alpha: 1).cgColor,
                           NSColor(red: 0.42, green: 0.24, blue: 0.48, alpha: 1).cgColor,
                           NSColor(red: 0.18, green: 0.04, blue: 0.25, alpha: 1).cgColor]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer?.insertSublayer(gradient, at: 0)
        font = .systemFont(ofSize: 12, weight: .semibold)
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
        animation.fromValue = [-0.3, 0.1, 0.9]
        animation.toValue = [0.1, 0.9, 1.3]
        animation.duration = 3.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(animation, forKey: "glow")
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMotion() }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        alphaValue = flag ? 0.75 : 1
    }
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
