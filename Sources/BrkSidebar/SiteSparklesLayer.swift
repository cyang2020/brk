import AppKit

/// The Boost indicator's three stars (Arc's site-control configuration, 0x10138f6e8): 0.6 s out and back, staggered
/// by 0.2 s, repeating every 4 s; a full rotation takes 5 s. Stops as soon as the pill's accessories disappear.
@MainActor
final class SiteSparklesLayer {
    let layer = CALayer()
    private let stars = (0..<3).map { _ in CAShapeLayer() }
    private var playing = false

    init() {
        for star in stars { layer.addSublayer(star) }
    }

    func show(active: Bool, tint: NSColor, reduceMotion: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (star, spec) in zip(stars, [(7.0, -9.0, -8.0), (5, 10, 8), (6, 10, -8)]) {
            star.bounds = CGRect(x: 0, y: 0, width: spec.0, height: spec.0)
            star.position = CGPoint(x: spec.1, y: spec.2)
            star.fillColor = tint.cgColor
            let s = spec.0 / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: s, y: 0))
            path.addQuadCurve(to: CGPoint(x: 2 * s, y: s), control: CGPoint(x: s, y: s))
            path.addQuadCurve(to: CGPoint(x: s, y: 2 * s), control: CGPoint(x: s, y: s))
            path.addQuadCurve(to: CGPoint(x: 0, y: s), control: CGPoint(x: s, y: s))
            path.addQuadCurve(to: CGPoint(x: s, y: 0), control: CGPoint(x: s, y: s))
            path.closeSubpath()
            star.path = path
            star.transform = CATransform3DMakeScale(0, 0, 1)
        }
        CATransaction.commit()
        let animate = active && !reduceMotion
        guard animate != playing else { return }
        playing = animate
        for (i, star) in stars.enumerated() {
            star.removeAllAnimations()
            guard animate else { continue }
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0; pulse.toValue = 1
            pulse.duration = 0.6; pulse.autoreverses = true
            pulse.beginTime = Double(i) * 0.2
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let cycle = CAAnimationGroup()
            cycle.animations = [pulse]; cycle.duration = 4; cycle.repeatCount = .infinity
            star.add(cycle, forKey: "twinkle")
            let turn = CABasicAnimation(keyPath: "transform.rotation")
            turn.fromValue = 0; turn.toValue = 2 * Double.pi
            turn.duration = 5; turn.repeatCount = .infinity
            star.add(turn, forKey: "turn")
        }
    }
}
