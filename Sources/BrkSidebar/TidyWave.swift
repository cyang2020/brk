import AppKit
import QuartzCore

/// When the Today divider's wave starts, grows, fades and stops: Arc's `SquiggleViewModel` (isLoading, allowAnimation,
/// startTime). `setLoading(true)` starts the clock and lets it animate; the amplitude rises from 0 to full over
/// `ramp`. `setLoading(false)` restarts the clock; the amplitude falls from full to 0 over `ramp`, then animation stops
/// (bin:0x1002b1344 schedules that `ramp` later) and the line width eases back over `widthDuration`.
struct TidyWaveClock: Equatable {
    let ramp: TimeInterval, widthDuration: TimeInterval
    private(set) var isLoading = false
    private var startTime: TimeInterval?
    private var stopTime: TimeInterval?

    init(ramp: TimeInterval = Draw.tidyWaveRamp.value, widthDuration: TimeInterval = Draw.tidyWaveWidthDuration.value) {
        self.ramp = ramp
        self.widthDuration = widthDuration
    }

    mutating func setLoading(_ loading: Bool, at now: TimeInterval) {
        isLoading = loading
        startTime = now
        // Arc's end is a delayed block that is never cancelled, so a Tidy started within 0.4 s of the last one's end
        // loses its wave; here a new start replaces the pending end.
        stopTime = loading ? nil : now
    }

    /// Arc's `allowAnimation`: the clock runs and the line is thick.
    func animates(at now: TimeInterval) -> Bool {
        isLoading || stopTime.map { now - $0 < ramp } == true
    }

    /// The wave view replaces the resting hairline until the line has eased back to the hairline's width.
    func shows(at now: TimeInterval) -> Bool {
        isLoading || stopTime.map { now - $0 < ramp + widthDuration } == true
    }

    /// The amplitude as a share of the full one (bin:0x1002b1ec4).
    func progress(at now: TimeInterval) -> Double {
        guard let startTime, animates(at: now) else { return 0 }
        let p = (now - startTime) / ramp
        return isLoading ? min(p, 1) : max(1 - p, 0)
    }
}

/// The wave's path: Arc's squiggle shape (bin:0x1002b21a0). From the left edge at mid height, half waves alternate
/// down and up (`amplitude` is positive downwards in a flipped view), each a cubic whose control points sit at the
/// amplitude 0.3 and 0.7 of the way along it, so a crest reaches 0.75 of the amplitude. `phase` (in waves) shifts the
/// pattern left by its fractional part.
enum TidyWavePath {
    static func make(width: CGFloat, midY: CGFloat, wavelength: CGFloat, amplitude: CGFloat, phase: Double,
                     control: CGFloat = Draw.tidyWaveControl.value) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: midY))
        guard wavelength > 0 else { return path }
        let half = wavelength / 2
        var x = -wavelength * CGFloat(phase.truncatingRemainder(dividingBy: 1))
        while x < width {
            path.addCurve(to: CGPoint(x: x + half, y: midY),
                          control1: CGPoint(x: x + half * control, y: midY + amplitude),
                          control2: CGPoint(x: x + half * (1 - control), y: midY + amplitude))
            path.addCurve(to: CGPoint(x: x + wavelength, y: midY),
                          control1: CGPoint(x: x + half + half * control, y: midY - amplitude),
                          control2: CGPoint(x: x + half + half * (1 - control), y: midY - amplitude))
            x += wavelength
        }
        return path
    }
}

/// The Today divider while Tidy works (Arc's `SquiggleDivider`): the hairline's colour drawn as a wave that moves left
/// five waves a second, grows in over 0.4 s, thickens from the hairline to 2 pt, and settles back to the hairline when
/// Tidy ends. Clipped to its frame, which spans the hairline's length.
@MainActor
final class TidyWaveView: NSView {
    private let shape = CAShapeLayer()
    private var clock = TidyWaveClock()
    private var link: CADisplayLink?
    private var thick = false
    /// Called when the view starts or stops standing in for the hairline.
    var onShownChange: (() -> Void)?
    private(set) var isShown = false
    var restWidth: CGFloat = 1 { didSet { if !thick { shape.lineWidth = restWidth } } }
    var color: CGColor? { didSet { shape.strokeColor = color } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        shape.fillColor = nil
        shape.lineCap = .butt
        shape.lineJoin = .miter
        shape.miterLimit = 10
        shape.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull(), "strokeColor": NSNull()]
        layer?.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var isLoading: Bool { clock.isLoading }

    func setLoading(_ loading: Bool) {
        guard loading != clock.isLoading else { return }
        clock.setLoading(loading, at: CACurrentMediaTime())
        update(at: CACurrentMediaTime())
    }

    override func layout() {
        super.layout()
        shape.frame = bounds
        redraw(at: CACurrentMediaTime())
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        shape.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopLink() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shape.contentsScale = window?.backingScaleFactor ?? 2
        update(at: CACurrentMediaTime())
    }

    @objc private func step(_ link: CADisplayLink) { update(at: link.targetTimestamp) }

    private func update(at now: TimeInterval) {
        let animates = clock.animates(at: now)
        if animates != thick {
            thick = animates
            easeWidth(to: animates ? Draw.tidyWaveLineWidth.value : restWidth)
        }
        let shown = clock.shows(at: now)
        if shown != isShown {
            isShown = shown
            onShownChange?()
        }
        if shown, window != nil { startLink() } else { stopLink() }
        redraw(at: now)
    }

    private func redraw(at now: TimeInterval) {
        let height = Draw.tidyWaveHeight.value
        let amplitude = CGFloat(clock.progress(at: now)) * height / 2
        shape.path = TidyWavePath.make(width: bounds.width, midY: bounds.midY, wavelength: height * Draw.tidyWaveLength.value,
                                       amplitude: amplitude, phase: now * Draw.tidyWaveSpeed.value)
    }

    private func easeWidth(to width: CGFloat) {
        let from = shape.presentation()?.lineWidth ?? shape.lineWidth
        let ease = CABasicAnimation(keyPath: "lineWidth")
        ease.fromValue = from
        ease.toValue = width
        ease.duration = Draw.tidyWaveWidthDuration.value
        ease.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
        shape.lineWidth = width
        shape.add(ease, forKey: "lineWidth")
    }

    private func startLink() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }
}
