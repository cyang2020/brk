import AppKit
import BrkBase
import BrkUIKit

/// Arc's sidebar folder glyph (`FolderIcon.FolderIconView`, Arc 1.170, read from the binary): one drawing of a closed
/// folder, a back panel with its tab and a front flap in front of it, that opens by turning its two halves in 3D about
/// their bottom edge. Open is not a second picture: the back tips away, the front tips forward and both turn sideways,
/// seen in perspective, and the change runs as a Core Animation transition, so a folder clicked again half-way turns
/// back from where it is. Brk draws and moves it in its own code with Arc's numbers (`Draw.folderIcon*`); no file of
/// Arc's is used.
@MainActor
final class FolderIconView: NSView {
    /// Arc's `State` has two more cases, `peekedOpen` and `peekedClosed` (a closed folder showing its current tab under
    /// it, with a badge); Brk has no such rows.
    enum State { case collapsed, expanded }

    private let back = CAShapeLayer()
    private let backShading = CAGradientLayer()
    private let backShadingMask = CAShapeLayer()
    private let frontContainer = CALayer()
    private let front = CAShapeLayer()
    private let frontShading = CAGradientLayer()
    private(set) var state = State.collapsed
    private var colors: (outline: CGColor, back: CGColor, front: CGColor)?
    private var laidOut: (size: CGSize, scale: Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        // bin:0x10166b6e4 and bin:0x10166ba30: black from clear to `folderIconFrontShade` / `folderIconBackShade`.
        frontShading.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(Draw.folderIconFrontShade.value).cgColor]
        frontShading.locations = [0, 1]
        let fs = Draw.folderIconFrontShadeAxis.value
        frontShading.startPoint = CGPoint(x: fs[0], y: fs[1])
        frontShading.endPoint = CGPoint(x: fs[2], y: fs[3])
        frontShading.masksToBounds = true
        backShading.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(Draw.folderIconBackShade.value).cgColor]
        backShading.locations = [0, 1]
        let bs = Draw.folderIconBackShadeAxis.value
        backShading.startPoint = CGPoint(x: bs[0], y: bs[1])
        backShading.endPoint = CGPoint(x: bs[2], y: bs[3])
        backShadingMask.fillColor = NSColor.white.cgColor
        backShading.mask = backShadingMask
        back.addSublayer(backShading)
        frontContainer.addSublayer(front)
        front.addSublayer(frontShading)
        layer?.addSublayer(back)
        layer?.addSublayer(frontContainer)
        quietly { apply(state) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows `state` in the space's hue. `animated`: the folder just opened or closed under the user's hand, so the halves
    /// turn over `Draw.folderIconTurn` from wherever they are; otherwise they are put there at once.
    func render(_ state: State, ink: HueInk, animated: Bool) {
        let colors = (ink.outline.cgColor, ink.back.cgColor, ink.front.cgColor)
        if self.colors.map({ $0.outline != colors.0 || $0.back != colors.1 || $0.front != colors.2 }) ?? true {
            self.colors = colors
            quietly {
                back.strokeColor = colors.0
                back.fillColor = colors.1
                front.strokeColor = colors.0
                front.fillColor = colors.2
            }
        }
        guard state != self.state else { return }
        self.state = state
        guard animated, window != nil else {
            quietly {
                for target in [back, frontContainer, backShading, frontShading] { target.removeAnimation(forKey: Self.key) }
                apply(state)
            }
            return
        }
        let turns: [(CALayer, String)] = [(back, "transform"), (frontContainer, "transform"), (backShading, "opacity"), (frontShading, "opacity")]
        let from = turns.map { ($0.0.presentation() ?? $0.0).value(forKeyPath: $0.1) }
        quietly { apply(state) }
        let curve = Draw.folderIconTurnCurve.value.map(Float.init)
        for ((target, path), start) in zip(turns, from) {
            let animation = CABasicAnimation(keyPath: path)
            animation.fromValue = start
            animation.toValue = target.value(forKeyPath: path)
            animation.duration = Draw.folderIconTurn.value
            animation.timingFunction = CAMediaTimingFunction(controlPoints: curve[0], curve[1], curve[2], curve[3])
            target.add(animation, forKey: Self.key)
        }
    }

    private static let key = "brk.folderIcon.turn"

    /// bin:0x10166c6a8 with the tables at bin:0x1037526d8 (shift), 0x1037526f8 (turn), 0x103752718 (front tilt) and
    /// 0x103752738 (back tilt), the perspective at bin:0x10166c834.
    private func apply(_ state: State) {
        let open = state == .expanded
        back.transform = Self.turn(open, tilt: Draw.folderIconBackTilt.value)
        frontContainer.transform = Self.turn(open, tilt: Draw.folderIconFrontTilt.value)
        frontShading.opacity = open ? 1 : 0
        backShading.opacity = Float(open ? 1 : Draw.folderIconClosedBackShading.value)
    }

    private static func turn(_ open: Bool, tilt: Double) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m34 = -1 / Draw.folderIconPerspective.value
        guard open else { return t }
        t = CATransform3DTranslate(t, Draw.folderIconOpenShift.value, 0, 0)
        t = CATransform3DRotate(t, Draw.folderIconOpenTurn.value * .pi / 180, 0, 1, 0)
        return CATransform3DRotate(t, tilt * .pi / 180, 1, 0, 0)
    }

    override func layout() {
        super.layout()
        let scale = Double(window?.backingScaleFactor ?? 2), size = bounds.size
        guard laidOut.map({ $0.size != size || $0.scale != scale }) ?? true, size.width > 0 else { return }
        laidOut = (size, scale)
        quietly { draw(size: size, scale: scale) }
    }

    /// bin:0x10166cc40: the paths, at whole device pixels like Arc's.
    private func draw(size: CGSize, scale: Double) {
        let w = Double(size.width), h = Double(size.height)
        func pixel(_ v: Double) -> Double { (v * scale).rounded() / scale }
        let radius = (w / Draw.folderIconRadiusDivisor.value).rounded()
        let line = pixel(Draw.folderIconLine.value)
        let frontTop = pixel((h * Draw.folderIconFrontTop.value).rounded())
        let tab = (frontTop / Draw.folderIconTabDivisor.value).rounded(.down)
        let tabEnd = pixel(w * Draw.folderIconTabEnd.value[0]), slopeEnd = pixel(w * Draw.folderIconTabEnd.value[1])
        // The back panel: the whole folder's outline with the tab standing up at the left.
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: radius, y: 0))
        outline.addLine(to: CGPoint(x: tabEnd, y: 0))
        outline.addLine(to: CGPoint(x: slopeEnd, y: tab))
        outline.addLine(to: CGPoint(x: w - radius, y: tab))
        outline.addArc(center: CGPoint(x: w - radius, y: radius + tab), radius: radius, startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: false)
        outline.addLine(to: CGPoint(x: w, y: h - radius))
        outline.addArc(center: CGPoint(x: w - radius, y: h - radius), radius: radius, startAngle: 0, endAngle: 0.5 * .pi, clockwise: false)
        outline.addLine(to: CGPoint(x: radius, y: h))
        outline.addArc(center: CGPoint(x: radius, y: h - radius), radius: radius, startAngle: 0.5 * .pi, endAngle: .pi, clockwise: false)
        outline.addLine(to: CGPoint(x: 0, y: radius))
        outline.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        outline.closeSubpath()
        // Both halves hinge on their bottom left corner.
        for (target, rect) in [(back as CALayer, CGRect(x: 0, y: 0, width: w, height: h)),
                               (frontContainer, CGRect(x: 0, y: 0, width: w, height: h - frontTop))] {
            target.bounds = rect
            target.anchorPoint = CGPoint(x: 0, y: 1)
            target.position = CGPoint(x: 0, y: h)
        }
        back.path = outline
        back.lineWidth = line
        backShading.frame = back.bounds
        backShadingMask.frame = backShading.bounds
        backShadingMask.path = outline
        front.frame = frontContainer.bounds
        front.path = CGPath(roundedRect: front.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        front.lineWidth = line
        frontShading.frame = front.bounds
        frontShading.cornerRadius = radius
    }

    private func quietly(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
