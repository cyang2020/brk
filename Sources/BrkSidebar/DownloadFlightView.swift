import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: W3. Arc's `DownloadToLibrary` overlay (docs/arc-anatomy/library-flyout.md, "The download flight"): a
// click-through layer over the whole window in which each new download's icon is thrown from the click into the
// Library button, or, while the sidebar is hidden, into a bin that slides in at the window's bottom left corner.
// Arc draws it in a borderless child window the size of the browser window; a top-most view that takes no clicks
// covers the same area here.

/// The flights of one window. Several share the overlay; it stays while any of them is in the air or holding, then
/// the bin slides out and the icons go.
@MainActor
public final class DownloadFlightView: NSView {
    private var seen: Set<DownloadID> = []
    private var icons: [CALayer] = []
    private let bin = CALayer()
    private let binGlyph = CALayer()
    /// Whether this run of flights uses the bin: decided by the first flight (Arc's view model keeps `showsBin`).
    private var usesBin: Bool?
    private var holdUntil: CFTimeInterval = 0
    private var endTimer: Timer?
    private var clearTimer: Timer?
    private var scheme: Scheme = .light
    /// The window's last mouse press (y up from the bottom left corner) and when: Arc's download event carries where
    /// the click that started it happened.
    private var press: (point: CGPoint, at: TimeInterval)?
    private var monitor: Any?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        bin.isHidden = true
        bin.cornerCurve = .continuous
        bin.addSublayer(binGlyph)
        layer?.addSublayer(bin)
        identify(.tabTool("download-flight"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        // Presses on the page reach Chromium's views, not this one: a local monitor sees them all first.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window else { return }
                let local = self.convert(event.locationInWindow, from: nil)
                self.press = (CGPoint(x: local.x, y: self.bounds.height - local.y), ProcessInfo.processInfo.systemUptime)
            }
            return event
        }
    }

    /// `flights` are the window's recent downloads; each one not thrown yet, and not older than a second (a view
    /// made after the fact does not replay it), flies now.
    public func render(_ flights: [DownloadFlight], sidebarHidden: Bool, scheme: Scheme, now: Instant) {
        self.scheme = scheme
        seen.formIntersection(flights.map(\.id))
        for flight in flights where !seen.contains(flight.id) {
            seen.insert(flight.id)
            guard now.since(flight.started) < .seconds(1), window != nil, bounds.width > 0 else { continue }
            launch(bin: usesBin ?? sidebarHidden)
        }
        setAccessibilityValue(icons.isEmpty ? nil : "\(icons.count) in flight\(usesBin == true ? ", bin" : "")")
    }

    // MARK: A flight

    private func launch(bin useBin: Bool) {
        guard let window else { return }
        let m = Metrics.downloadFlight
        // Where the click that started it happened (r8), else the pointer now (Arc's NSEvent.mouseLocation), y up from
        // the bottom left corner.
        let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        var pointer = CGPoint(x: local.x, y: bounds.height - local.y)
        if let press, ProcessInfo.processInfo.systemUptime - press.at < m.pressMemory.value { pointer = press.point }
        guard let path = DownloadFlightPath.plan(pointer: pointer, window: bounds.size, bin: useBin), !path.frames.isEmpty else { return }
        clearTimer?.invalidate(); clearTimer = nil
        // The first flight of a run: Arc's springs have run `firstFlightLead` when its overlay draws its first frame.
        let lead = usesBin == nil ? m.firstFlightLead.value : 0
        if usesBin == nil {
            usesBin = useBin
            if useBin { showBin(lead: lead) }
        }
        let icon = makeIcon()
        let flipped = layer?.contentsAreFlipped() ?? true
        let point = { (p: CGPoint) in CGPoint(x: p.x, y: self.bounds.height - p.y) }
        let last = path.frames[path.frames.count - 1]
        let degrees = m.rotation.value.map { $0 * .pi / 180 * (flipped ? 1 : -1) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icon.position = point(last.position)
        icon.setValue(last.scale.width, forKeyPath: "transform.scale.x")
        icon.setValue(last.scale.height, forKeyPath: "transform.scale.y")
        icon.setValue(degrees[1], forKeyPath: "transform.rotation.z")
        icon.opacity = 1
        layer?.addSublayer(icon)
        icons.append(icon)
        // Every animation starts when this transaction reaches the screen (begin time 0), so the path's first frame
        // is the first one drawn; the springs are sampled from `lead` on the same clock.
        Self.keyframes(icon, "position", path.frames.map { NSValue(point: point($0.position)) })
        Self.keyframes(icon, "transform.scale.x", path.frames.map { $0.scale.width })
        Self.keyframes(icon, "transform.scale.y", path.frames.map { $0.scale.height })
        let turn = MotionSpring(response: m.rotationSpring.value[0], dampingRatio: m.rotationSpring.value[1])
        Self.keyframes(icon, "transform.rotation.z", turn.samples(from: degrees[0] - degrees[1], velocity: 0, step: 1 / m.frameRate.value, start: lead).map { degrees[1] + $0 })
        let fade = MotionSpring(response: m.fadeSpring.value[0], dampingRatio: m.fadeSpring.value[1])
        Self.keyframes(icon, "opacity", fade.samples(from: -1, velocity: 0, step: 1 / m.frameRate.value, start: lead).map { 1 + $0 })
        CATransaction.commit()
        // Each flight keeps the overlay `hold` after it lands; the last one to finish ends the run.
        holdUntil = max(holdUntil, CACurrentMediaTime() + path.duration + m.hold.value)
        scheduleEnd()
    }

    /// One value per frame (`Metrics.downloadFlight.frameRate`), from when the transaction is committed.
    private static func keyframes(_ layer: CALayer, _ key: String, _ values: [Any]) {
        let rate = Metrics.downloadFlight.frameRate.value
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values
        animation.keyTimes = values.indices.map { NSNumber(value: values.count > 1 ? Double($0) / Double(values.count - 1) : 0) }
        animation.calculationMode = .linear
        animation.duration = Double(max(1, values.count - 1)) / rate
        animation.fillMode = .backwards
        layer.add(animation, forKey: key)
    }

    /// The thrown icon: SF Symbol arrow.down.circle in Arc's ink on a disc, with a blue shadow below it.
    private func makeIcon() -> CALayer {
        let m = Metrics.downloadFlight
        let side = m.iconSize.value
        let dark = scheme == .dark ? 1 : 0
        let ink = NSColor(rgba: RGBA(hex: m.iconInk.value[dark])), disc = NSColor(rgba: RGBA(hex: m.iconDisc.value[dark]))
        let icon = CALayer()
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.contentsScale = window?.backingScaleFactor ?? 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            disc.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            if let symbol = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: side * 0.8, weight: .regular)) {
                let grow = side * (m.iconGlyphScale.value - 1) / 2
                let glyph = NSImage(size: rect.size, flipped: false) { inner in
                    symbol.draw(in: inner.insetBy(dx: -grow, dy: -grow))
                    ink.setFill()
                    inner.fill(using: .sourceAtop)
                    return true
                }
                glyph.draw(in: rect)
            }
            return true
        }
        icon.contents = image.layerContents(forContentsScale: icon.contentsScale)
        let shadow = m.iconShadow.value
        icon.shadowColor = NSColor.systemBlue.cgColor
        icon.shadowOpacity = Float(shadow[0])
        icon.shadowRadius = shadow[1]
        icon.shadowOffset = CGSize(width: 0, height: (layer?.contentsAreFlipped() ?? true) ? shadow[2] : -shadow[2])
        return icon
    }

    // MARK: The bin (sidebar hidden)

    private func showBin(lead: Double) {
        let m = Metrics.downloadFlight
        let dark = scheme == .dark
        let side = m.binSize.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bin.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        bin.cornerRadius = m.binRadius.value
        bin.backgroundColor = NSColor(rgba: RGBA(hex: m.binFill.value[dark ? 1 : 0])).cgColor
        let shadow = m.binShadow.value
        bin.shadowColor = (dark ? NSColor.white : NSColor.black).cgColor
        bin.shadowOpacity = Float(dark ? shadow[1] : shadow[0])
        bin.shadowRadius = shadow[2]
        bin.shadowOffset = .zero
        let glyph = LibraryGlyph.image(tint: NSColor(rgba: RGBA(hex: m.binGlyph.value[dark ? 1 : 0])))
        binGlyph.contentsScale = window?.backingScaleFactor ?? 2
        binGlyph.contents = glyph.layerContents(forContentsScale: binGlyph.contentsScale)
        binGlyph.frame = CGRect(x: (side - glyph.size.width) / 2, y: (side - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
        let center = m.binCenter.value
        bin.position = CGPoint(x: center[0], y: bounds.height - center[1])
        bin.isHidden = false
        // Arc draws the bin first; the icons fly over it.
        bin.zPosition = -1
        // Arc springs it in from x -80, but its window shows only once that spring has run `lead`.
        slideBin(from: m.binHiddenX.value, to: center[0], start: lead)
        CATransaction.commit()
    }

    /// The bin's slide on Arc's Motion spring, sampled from `start` seconds in.
    private func slideBin(from: Double, to: Double, start: Double) {
        let k = Metrics.downloadFlight.binSpring.value
        let spring = MotionSpring(stiffness: k[0], damping: k[1])
        Self.keyframes(bin, "position.x", spring.samples(from: from - to, velocity: 0, step: 1 / Metrics.downloadFlight.frameRate.value, start: start).map { to + $0 })
    }

    // MARK: The end of a run

    private func scheduleEnd() {
        endTimer?.invalidate()
        endTimer = Timer.scheduledTimer(withTimeInterval: max(0, holdUntil - CACurrentMediaTime()), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endRun() }
        }
    }

    /// Arc's group notify: the bin slides out to x -80; when its window closes (`clearDelay` later) the icons go.
    private func endRun() {
        endTimer = nil
        let m = Metrics.downloadFlight
        if usesBin == true {
            let x = (bin.presentation() ?? bin).position.x
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bin.position.x = m.binHiddenX.value
            slideBin(from: x, to: m.binHiddenX.value, start: 0)
            CATransaction.commit()
        }
        clearTimer = Timer.scheduledTimer(withTimeInterval: m.clearDelay.value, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
    }

    private func clear() {
        clearTimer = nil
        for icon in icons { icon.removeFromSuperlayer() }
        icons.removeAll()
        bin.removeAllAnimations()
        bin.isHidden = true
        usesBin = nil
        holdUntil = 0
        setAccessibilityValue(nil)
    }
}
