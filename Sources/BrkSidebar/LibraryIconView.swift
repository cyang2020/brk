import AppKit
import BrkBase
import BrkDomain

/// The Library button's picture with Arc's hover motion (ARCUI `BoxOfThingsIcon`, numbers in `Draw.libraryIcon*`).
///
/// Every time the pointer comes onto the button or leaves it, the star turns over and rises, the triangle turns, moves
/// out and shrinks, and the dot moves up, all on one critically damped spring; then the pieces "twinkle": 0.15 s in
/// the triangle snaps back to full size while the dot shrinks to nothing, and 0.3 s in the dot snaps back. Arc keeps
/// the two twinkles as flags it toggles (on the hover change, then at 0.15 s and 0.3 s), so a quick in and out plays
/// both sequences and still ends with both off. In a dark scheme the hovered picture also shines: a white glow rises
/// out of the box and every piece gets a white halo. With Reduce Motion on nothing moves.
@MainActor
final class LibraryIconView: NSView {
    /// A piece that moves and turns (`holder`), twinkles (`scaler`: scale and opacity) and is drawn (`shape`).
    private final class Piece {
        let holder = CALayer()
        let scaler = CALayer()
        let shape = CAShapeLayer()

        init(path: CGPath) {
            shape.path = path
            for layer in [holder, scaler, shape] as [CALayer] {
                layer.bounds = .zero
                layer.position = .zero
            }
            shape.shadowColor = .white
            shape.shadowOffset = .zero
            shape.shadowOpacity = 0
            holder.addSublayer(scaler)
            scaler.addSublayer(shape)
        }
    }

    private let stack = CALayer()
    private let glow = CALayer()
    private let starClip = CALayer()
    private let star = Piece(path: LibraryBoxArt.star())
    private let triangle = Piece(path: LibraryBoxArt.triangle())
    private let dot = Piece(path: LibraryBoxArt.dot())
    private let box = CAShapeLayer()

    private(set) var isHovered = false
    private(set) var twinkle1 = false
    private(set) var twinkle2 = false
    private var dark = false
    private var glowScale: CGFloat = 0
    /// Read on each hover change, as Arc reads `accessibilityReduceMotion`.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        stack.shadowColor = .white
        stack.shadowOffset = .zero
        stack.shadowOpacity = 0
        stack.shadowRadius = Draw.libraryIconShine.value[4]
        star.shape.shadowRadius = Draw.libraryIconShine.value[0]
        triangle.shape.shadowRadius = Draw.libraryIconShine.value[1]
        dot.shape.shadowRadius = Draw.libraryIconShine.value[2]
        box.path = LibraryBoxArt.box()
        box.fillRule = .evenOdd
        box.opacity = Float(Draw.libraryIconBox.value[2])
        glow.opacity = 0
        starClip.masksToBounds = true
        starClip.addSublayer(star.holder)
        for sub in [glow, starClip, triangle.holder, dot.holder, box] as [CALayer] { stack.addSublayer(sub) }
        layer?.addSublayer(stack)
        withoutActions { apply(animated: false) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    /// The button under it takes every click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The pieces' colour (the dock's glyph ink) and whether the sidebar is dark, which turns the shine on.
    func render(tint: NSColor, dark: Bool) {
        let changed = dark != self.dark
        self.dark = dark
        withoutActions {
            for shape in [star.shape, triangle.shape, dot.shape, box] { shape.fillColor = tint.cgColor }
            if changed { applyShine(animated: false) }
        }
    }

    /// The pointer came onto the button or left it.
    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered, !reduceMotion() else { return }
        isHovered = hovered
        twinkle1.toggle()
        apply(animated: true)
        let at = Draw.libraryIconTwinkle.value
        DispatchQueue.main.asyncAfter(deadline: .now() + at[0]) { [weak self] in
            guard let self else { return }
            twinkle1.toggle()
            twinkle2.toggle()
            withoutActions { self.applyTwinkles(animated: false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + at[1]) { [weak self] in
            guard let self else { return }
            twinkle2.toggle()
            withoutActions { self.applyTwinkles(animated: false) }
        }
    }

    override func layout() {
        super.layout()
        withoutActions { place() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [stack, starClip, box, star.shape, triangle.shape, dot.shape] as [CALayer] { layer.contentsScale = scale }
        if scale != glowScale {
            glowScale = scale
            let g = Draw.libraryIconGlow.value
            glow.contents = LibraryBoxArt.glow(size: CGSize(width: 81 * g[2], height: 27 * g[3]), foot: 81 * g[2] * g[6], blur: g[5], scale: scale)
            glow.contentsScale = scale
            needsLayout = true
        }
    }

    // MARK: - Drawing

    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func place() {
        stack.frame = bounds
        let c = centre, m = Draw.libraryIconStarMask.value, g = Draw.libraryIconGlow.value
        starClip.frame = CGRect(x: c.x + m[0] - m[2] / 2, y: c.y + m[1] - m[3] / 2, width: m[2], height: m[3])
        let pad = LibraryBoxArt.glowPad(blur: g[5])
        glow.bounds = CGRect(x: 0, y: 0, width: 81 * g[2] + pad * 2, height: 27 * g[3] + pad * 2)
        glow.position = CGPoint(x: c.x + g[0], y: c.y + g[1])
        box.position = CGPoint(x: c.x + Draw.libraryIconBox.value[0], y: c.y + Draw.libraryIconBox.value[1])
        movePieces(animated: false)
    }

    /// Where a piece's holder sits for an offset from the picture's centre (the star's lives in its clip).
    private func point(_ piece: Piece, _ x: Double, _ y: Double) -> CGPoint {
        let p = CGPoint(x: centre.x + x, y: centre.y + y)
        return piece === star ? CGPoint(x: p.x - starClip.frame.minX, y: p.y - starClip.frame.minY) : p
    }

    private func apply(animated: Bool) {
        movePieces(animated: animated)
        applyTwinkles(animated: animated)
        applyShine(animated: animated)
    }

    private func movePieces(animated: Bool) {
        let s = Draw.libraryIconStar.value, t = Draw.libraryIconTriangle.value, d = Draw.libraryIconDot.value
        let h = isHovered
        move(star, to: point(star, h ? s[3] : s[0], h ? s[4] : s[1]), turned: h ? s[5] : s[2], animated: animated)
        move(triangle, to: point(triangle, h ? t[3] : t[0], h ? t[4] : t[1]), turned: h ? t[5] : t[2], animated: animated)
        move(dot, to: point(dot, h ? d[2] : d[0], h ? d[3] : d[1]), turned: 0, animated: animated)
    }

    private func applyTwinkles(animated: Bool) {
        let t = Draw.libraryIconTriangle.value, d = Draw.libraryIconDot.value
        twinkle(triangle, scale: twinkle1 ? t[6] : 1, opacity: twinkle1 ? t[7] : 1, animated: animated)
        twinkle(dot, scale: twinkle2 ? d[4] : 1, opacity: twinkle2 ? d[5] : 1, animated: animated)
    }

    private func applyShine(animated: Bool) {
        let on = dark && isHovered
        let g = Draw.libraryIconGlow.value
        fade(glow, \.opacity, "opacity", to: on ? g[4] : 0, animated: animated)
        for shape in [star.shape, triangle.shape, dot.shape] { fade(shape, \.shadowOpacity, "shadowOpacity", to: on ? 1 : 0, animated: animated) }
        fade(stack, \.shadowOpacity, "shadowOpacity", to: on ? Draw.libraryIconShine.value[3] : 0, animated: animated)
    }

    // MARK: - Motion

    /// Arc's spring, as Core Animation numbers.
    private func spring(_ keyPath: String) -> CASpringAnimation {
        let k = Draw.libraryIconSpring.value
        let motion = MotionSpring(response: k[0], dampingRatio: k[1])
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = motion.stiffness
        animation.damping = motion.damping
        animation.duration = animation.settlingDuration
        return animation
    }

    /// SwiftUI moves a spring that is retargeted mid-way on from where it is, at its speed. Additive springs from the
    /// old target to the new one add up to the same motion, so each change only adds its own.
    private func additive(_ layer: CALayer, _ keyPath: String, from delta: Any, zero: Any) {
        let animation = spring(keyPath)
        animation.isAdditive = true
        animation.fromValue = delta
        animation.toValue = zero
        layer.add(animation, forKey: nil)
    }

    private func move(_ piece: Piece, to position: CGPoint, turned degrees: Double, animated: Bool) {
        let angle = CGFloat(degrees * .pi / 180)
        let old = piece.holder.position
        let oldAngle = piece.holder.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        withoutActions {
            piece.holder.position = position
            piece.holder.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }
        guard animated else { return }
        if old != position {
            additive(piece.holder, "position", from: NSValue(point: CGPoint(x: old.x - position.x, y: old.y - position.y)), zero: NSValue(point: .zero))
        }
        if oldAngle != angle { additive(piece.holder, "transform.rotation.z", from: oldAngle - angle, zero: 0) }
    }

    /// A twinkle that comes with a hover change rides its spring; the later ones land at once, cutting off the spring.
    private func twinkle(_ piece: Piece, scale: Double, opacity: Double, animated: Bool) {
        let layer = piece.scaler
        let oldScale = (layer.presentation() ?? layer).value(forKeyPath: "transform.scale") as? CGFloat ?? 1
        let oldOpacity = (layer.presentation() ?? layer).opacity
        layer.removeAnimation(forKey: "twinkle-scale")
        layer.removeAnimation(forKey: "twinkle-opacity")
        withoutActions {
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
            layer.opacity = Float(opacity)
        }
        guard animated else { return }
        if oldScale != CGFloat(scale) {
            let animation = spring("transform.scale")
            animation.fromValue = oldScale
            animation.toValue = scale
            layer.add(animation, forKey: "twinkle-scale")
        }
        if oldOpacity != Float(opacity) {
            let animation = spring("opacity")
            animation.fromValue = oldOpacity
            animation.toValue = opacity
            layer.add(animation, forKey: "twinkle-opacity")
        }
    }

    private func fade(_ layer: CALayer, _ property: ReferenceWritableKeyPath<CALayer, Float>, _ keyPath: String, to value: Double, animated: Bool) {
        let old = layer[keyPath: property]
        withoutActions { layer[keyPath: property] = Float(value) }
        if animated, old != Float(value) { additive(layer, keyPath, from: old - Float(value), zero: Float(0)) }
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
