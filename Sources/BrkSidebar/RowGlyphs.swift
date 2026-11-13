import AppKit
import BrkBase
import BrkUIKit

// The tab row's two moving glyphs, drawn in Brk's own code with Arc 1.170's numbers (read from the binary; the parts
// and their places checked on ~/brk-arc-reference/Q18 and Q13). No file of Arc's is used.

/// A SwiftUI `spring(response:dampingFraction:)` as Core Animation runs it (mass 1).
@MainActor
func swiftUISpring(_ keyPath: String, response: Double, damping: Double) -> CASpringAnimation {
    let spring = CASpringAnimation(keyPath: keyPath)
    spring.mass = 1
    spring.stiffness = pow(2 * .pi / response, 2)
    spring.damping = 4 * .pi * damping / response
    spring.duration = spring.settlingDuration
    return spring
}

/// Arc's row button glyph (`XMarkOrHyphenIcon`, bin:0x100af3ef0): two rounded bars crossed at ±45° for ×, both level
/// for − (the current pinned tab's "Close and Keep Pinned"). Between the two they turn on Arc's spring (bin:0x100af41f0).
@MainActor
final class CrossOrHyphenView: NSView {
    private let bars = [CALayer(), CALayer()]
    private(set) var hyphen = false
    private var tint: CGColor?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
        }
        quietly { turn() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `animated`: the same row changed between × and − (a pinned tab became or stopped being the current one).
    func render(hyphen: Bool, tint: NSColor, animated: Bool) {
        if tint.cgColor != self.tint {
            self.tint = tint.cgColor
            quietly { for bar in bars { bar.backgroundColor = tint.cgColor } }
        }
        guard hyphen != self.hyphen else { return }
        self.hyphen = hyphen
        let from = bars.map { ($0.presentation() ?? $0).value(forKeyPath: "transform.rotation.z") }
        quietly { turn() }
        for (bar, start) in zip(bars, from) {
            guard animated, window != nil else { bar.removeAnimation(forKey: Self.key); continue }
            let p = Draw.rowButtonSpring.value
            let spring = swiftUISpring("transform.rotation.z", response: p[0], damping: p[1])
            spring.fromValue = start
            spring.toValue = bar.value(forKeyPath: "transform.rotation.z")
            bar.add(spring, forKey: Self.key)
        }
    }

    private static let key = "brk.crossOrHyphen"

    private func turn() {
        for (bar, sign) in zip(bars, [1.0, -1.0]) { bar.transform = CATransform3DMakeRotation(hyphen ? 0 : sign * .pi / 4, 0, 0, 1) }
    }

    override func layout() {
        super.layout()
        let size = Draw.rowButtonBar.value
        quietly {
            for bar in bars {
                bar.bounds = CGRect(x: 0, y: 0, width: size[0], height: size[1])
                bar.position = CGPoint(x: bounds.midX, y: bounds.midY)
                bar.cornerRadius = size[2]
            }
        }
    }
}

/// Arc's tab row speaker (`SpeakerIcon`, bin:0x100aed47c, in `SidebarCellSpeakerIconWrapperView`): the "speaker" symbol at
/// 14 pt medium, three sound waves of Arc's own drawing in an 8 x 12 frame, and a slash across a 14 x 14 square that cuts
/// a gap twice its width out of the speaker. Muting, the waves slide into the speaker and fade one after another, then
/// the slash draws in while the speaker moves to the middle; unmuting, the slash goes and the speaker moves back at once,
/// the waves come back last, one after another. Each part runs its own spring after its own delay (`Draw.rowSpeaker*`).
@MainActor
final class SpeakerGlyphView: NSView {
    private let body = CALayer()
    private let bodyCut = CAShapeLayer()
    private let waves = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    private let slash = CAShapeLayer()
    private(set) var muted = false
    private var tint: NSColor?
    private var bodySize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        bodyCut.fillRule = .evenOdd
        bodyCut.fillColor = NSColor.black.cgColor
        body.mask = bodyCut
        for layer in [body] + waves + [slash] as [CALayer] { self.layer?.addSublayer(layer) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `animated`: the same tab was muted or unmuted.
    func render(muted: Bool, tint: NSColor, animated: Bool) {
        if tint != self.tint {
            self.tint = tint
            paint(tint)
        }
        guard muted != self.muted else { return }
        self.muted = muted
        place(animated && window != nil ? .animate : .snap)
    }

    /// How `place` puts the parts: running each spring, at once, or only their resting values (a layout while a
    /// motion runs keeps the motion).
    private enum Placing { case animate, snap, rest }

    private func paint(_ tint: NSColor) {
        guard let symbol = symbolImage("speaker", size: Draw.rowSpeakerSymbol.value, weight: .medium) else { return }
        let painted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        bodySize = symbol.size
        quietly {
            body.contents = painted
            for wave in waves { wave.fillColor = tint.cgColor }
            slash.fillColor = tint.cgColor
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        quietly {
            body.bounds = CGRect(origin: .zero, size: bodySize)
            body.contentsScale = window?.backingScaleFactor ?? 2
            let frame = Draw.rowSpeakerWaveFrame.value
            for (wave, path) in zip(waves, Self.wavePaths) {
                wave.bounds = CGRect(x: 0, y: 0, width: frame[0], height: frame[1])
                var scale = CGAffineTransform(scaleX: frame[0], y: frame[1])
                wave.path = path.copy(using: &scale)
            }
            let side = Draw.rowSpeakerSlashSide.value
            slash.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            bodyCut.frame = body.bounds
        }
        place(.rest)
    }

    /// The parts where they rest for `muted`; `.animate` runs each one's spring after its delay, from where it is.
    private func place(_ placing: Placing) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let waveShift = Draw.rowSpeakerWaveShift.value, speed = Draw.rowSpeakerSpeedup.value
        let increment = Draw.rowSpeakerWaveIncrement.value * speed
        let slashDelay = muted ? Draw.rowSpeakerSlashStart.value * speed : 0
        let wavesDelay = muted ? 0 : Draw.rowSpeakerWaveReappear.value * speed
        let move = Draw.rowSpeakerSpring.value
        let slashSpring = muted ? Draw.rowSpeakerSlashInSpring.value : Draw.rowSpeakerSlashOutSpring.value
        let now = CACurrentMediaTime()

        func set(_ target: CALayer, _ keyPath: String, _ value: Any, spring: [Double], delay: Double) {
            let from = (target.presentation() ?? target).value(forKeyPath: keyPath)
            quietly { target.setValue(value, forKeyPath: keyPath) }
            if placing == .rest { return }
            guard placing == .animate else { target.removeAnimation(forKey: "brk.speaker." + keyPath); return }
            let animation = swiftUISpring(keyPath, response: spring[0], damping: spring[1])
            animation.fromValue = from
            animation.toValue = value
            animation.beginTime = target.convertTime(now + delay, from: nil)
            animation.fillMode = .backwards
            target.add(animation, forKey: "brk.speaker." + keyPath)
        }

        let bodyX = muted ? 0 : -Draw.rowSpeakerBodyShift.value
        set(body, "position", NSValue(point: CGPoint(x: centre.x + bodyX, y: centre.y)), spring: move, delay: slashDelay)
        for (index, wave) in waves.enumerated() {
            let x = muted ? waveShift[index + 1] : waveShift[0]
            let delay = wavesDelay + Double(index) * increment
            set(wave, "position", NSValue(point: CGPoint(x: centre.x + x, y: centre.y)), spring: move, delay: delay)
            set(wave, "opacity", muted ? 0 : 1, spring: move, delay: delay)
        }
        quietly { slash.position = centre }
        let progress = muted ? 1.0 : 0
        set(slash, "path", slashPath(progress, cut: false), spring: slashSpring, delay: slashDelay)
        // The gap, in the speaker's own coordinates: the slash's square is centred on the icon, the speaker sits beside.
        let offset = CGPoint(x: -bodyX + bodySize.width / 2 - slash.bounds.width / 2, y: bodySize.height / 2 - slash.bounds.height / 2)
        set(bodyCut, "path", cutPath(progress, offset: offset), spring: slashSpring, delay: slashDelay)
    }

    /// bin:0x100aedf1c: a bar with round ends from the square's top left corner toward its bottom right, `progress` of the
    /// diagonal long; the cut is twice as thick and reaches a little past both ends.
    private func bar(_ progress: Double, cut: Bool) -> CGPath {
        let side = Draw.rowSpeakerSlashSide.value
        let thickness = side * Draw.rowSpeakerSlashWidth.value * (cut ? 2 : 1)
        let reach = cut ? thickness / Draw.rowSpeakerCutReach.value : 0
        let length = max(0.01, 2 * reach + progress * 2.0.squareRoot() * side)
        let corner = min(thickness / 2, length / 2)
        var turn = CGAffineTransform(rotationAngle: .pi / 4)
        let rect = CGRect(x: -reach, y: -thickness / 2, width: length, height: thickness)
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: &turn)
    }

    private func slashPath(_ progress: Double, cut: Bool) -> CGPath { bar(progress, cut: cut) }

    private func cutPath(_ progress: Double, offset: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(x: -50, y: -50, width: 100, height: 100))
        path.addPath(bar(progress, cut: true), transform: CGAffineTransform(translationX: offset.x, y: offset.y))
        return path
    }

    /// Arc's three waves (`FirstSoundWave`, `SecondSoundWave`, `ThirdSoundWave`, bin:0x100aeee1c, 0x100aef264,
    /// 0x100aef68c): each a closed crescent of eight cubic curves, in fractions of the 8 x 12 frame, y down.
    private static let wavePaths: [CGPath] = {
        let curves: [[(CGFloat, CGFloat)]] = [
            [(0.3031, 0.5096),
             (0.1915, 0.3204), (0.3031, 0.4393), (0.2627, 0.3731), (0.0737, 0.3162), (0.1599, 0.2966), (0.1045, 0.2961),
             (0.0843, 0.3829), (0.0447, 0.3354), (0.0544, 0.3586), (0.1528, 0.5096), (0.1291, 0.4176), (0.1528, 0.4615),
             (0.0843, 0.6363), (0.1528, 0.5577), (0.1291, 0.6016), (0.0737, 0.7024), (0.0544, 0.6600), (0.0447, 0.6833),
             (0.1915, 0.6983), (0.1045, 0.7231), (0.1599, 0.7226), (0.3031, 0.5096), (0.2627, 0.6461), (0.3031, 0.5799)],
            [(0.6239, 0.5096),
             (0.4130, 0.1834), (0.6239, 0.3855), (0.5483, 0.2702), (0.2961, 0.1813), (0.3778, 0.1611), (0.3269, 0.1606),
             (0.3084, 0.2475), (0.2671, 0.2004), (0.2750, 0.2258), (0.4736, 0.5096), (0.4148, 0.3183), (0.4736, 0.4093),
             (0.3084, 0.7717), (0.4736, 0.6094), (0.4148, 0.7009), (0.2961, 0.8379), (0.2750, 0.7934), (0.2671, 0.8183),
             (0.4130, 0.8353), (0.3269, 0.8580), (0.3778, 0.8580), (0.6239, 0.5096), (0.5483, 0.7490), (0.6239, 0.6337)],
            [(0.9438, 0.5096),
             (0.6398, 0.0562), (0.9438, 0.3354), (0.8331, 0.1751), (0.5272, 0.0546), (0.6055, 0.0345), (0.5554, 0.0360),
             (0.5369, 0.1208), (0.4982, 0.0732), (0.5035, 0.1001), (0.7936, 0.5096), (0.7030, 0.2232), (0.7936, 0.3602),
             (0.5369, 0.8984), (0.7936, 0.6590), (0.7030, 0.7960), (0.5272, 0.9640), (0.5035, 0.9191), (0.4982, 0.9459),
             (0.6398, 0.9630), (0.5554, 0.9832), (0.6055, 0.9847), (0.9438, 0.5096), (0.8331, 0.8436), (0.9438, 0.6838)],
        ]
        return curves.map { points in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: points[0].0, y: points[0].1))
            var i = 1
            while i + 2 < points.count {
                path.addCurve(to: CGPoint(x: points[i].0, y: points[i].1), control1: CGPoint(x: points[i + 1].0, y: points[i + 1].1),
                              control2: CGPoint(x: points[i + 2].0, y: points[i + 2].1))
                i += 3
            }
            path.closeSubpath()
            return path
        }
    }()
}

@MainActor
private func quietly(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}
