import AppKit
import BrkDomain

/// Arc's MoreMenuIcon: the outer dots disappear as the centre dot becomes one arm of a cross; the other arm enters
/// after 0.15 s. Closing reverses the order (spring response 0.3, damping 0.6, Arc 0x100af33d8).
@MainActor
final class MoreMenuIconLayer {
    let layer = CALayer()
    private let row = CALayer()
    private let otherArm = CALayer()
    private let dots = (0..<3).map { _ in CALayer() }
    private var open = false

    init() {
        layer.addSublayer(otherArm)
        layer.addSublayer(row)
        for dot in dots { row.addSublayer(dot) }
    }


    func show(open: Bool, size: Double, tint: NSColor, animated: Bool) {
        let changed = open != self.open
        self.open = open
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        for part in [row, otherArm] { part.position = CGPoint(x: size / 2, y: size / 2) }
        row.bounds = layer.bounds
        otherArm.bounds = CGRect(x: 0, y: 0, width: size, height: 2)
        otherArm.cornerRadius = otherArm.bounds.height / 2
        otherArm.backgroundColor = tint.cgColor
        otherArm.transform = CATransform3DMakeRotation(-.pi / 4, 0, 0, 1)
        for (i, dot) in dots.enumerated() {
            dot.position = CGPoint(x: size / 2 + Double(i - 1) * 5, y: size / 2)
            dot.backgroundColor = tint.cgColor
        }
        let animates = changed && animated
        let rowDelay = open ? 0.0 : 0.15
        set(row, "transform", NSValue(caTransform3D: CATransform3DMakeRotation(open ? .pi / 4 : 0, 0, 0, 1)), animated: animates, delay: rowDelay)
        for (i, dot) in dots.enumerated() {
            set(dot, "bounds", NSValue(rect: CGRect(x: 0, y: 0, width: open && i == 1 ? size : 3, height: open && i == 1 ? 2 : 3)), animated: animates, delay: rowDelay)
            dot.cornerRadius = dot.bounds.height / 2
            set(dot, "opacity", open && i != 1 ? 0.0 : 1.0, animated: animates, delay: rowDelay)
        }
        set(otherArm, "opacity", open ? 1.0 : 0.0, animated: animates, delay: open ? 0.15 : 0)
        set(otherArm, "transform.scale", open ? 1.0 : 0.7, animated: animates, delay: open ? 0.15 : 0)
        CATransaction.commit()
    }

    private func set(_ layer: CALayer, _ key: String, _ value: Any, animated: Bool, delay: Double) {
        let before = (layer.presentation() ?? layer).value(forKeyPath: key)
        layer.setValue(value, forKeyPath: key)
        guard animated else { return }
        let motion = MotionSpring(response: 0.3, dampingRatio: 0.6)
        let spring = CASpringAnimation(keyPath: key)
        spring.mass = 1; spring.stiffness = motion.stiffness; spring.damping = motion.damping
        spring.fromValue = before; spring.toValue = value
        spring.duration = spring.settlingDuration
        spring.beginTime = CACurrentMediaTime() + delay
        spring.fillMode = .backwards
        layer.add(spring, forKey: key)
    }
}
