import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: W3. Arc's `DownloadToLibrary` overlay (docs/arc-anatomy/library-flyout.md, "The download flight"): a
// click-through layer over the whole window in which each new download's icon is thrown from the pointer into the
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
        // The pointer in the window, y up from the bottom left corner (Arc reads NSEvent.mouseLocation).
        let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let pointer = CGPoint(x: local.x, y: bounds.height - local.y)
        guard let path = DownloadFlightPath.plan(pointer: pointer, window: bounds.size, bin: useBin), !path.frames.isEmpty else { return }
        clearTimer?.invalidate(); clearTimer = nil
        // The first flight of a run: Arc's springs have run `firstFlightLead` when its overlay draws its first frame.
        let lead = usesBin == nil ? m.firstFlightLead.value : 0
        if usesBin == nil {
            usesBin = useBin
            if useBin { showBin(lead: lead) }
        }
        let icon = makeIcon()
        layer?.addSublayer(icon)
        icons.append(icon)
        let flipped = layer?.contentsAreFlipped() ?? true
        let begin = icon.convertTime(CACurrentMediaTime(), from: nil)
        let point = { (p: CGPoint) in CGPoint(x: p.x, y: self.bounds.height - p.y) }
        let last = path.frames[path.frames.count - 1]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icon.position = point(last.position)
        icon.setValue(last.scale.width, forKeyPath: "transform.scale.x")
        icon.setValue(last.scale.height, forKeyPath: "transform.scale.y")
        let degrees = m.rotation.value.map { $0 * .pi / 180 * (flipped ? 1 : -1) }
        icon.setValue(degrees[1], forKeyPath: "transform.rotation.z")
        icon.opacity = 1
        CATransaction.commit()
        let span = Double(path.frames.count - 1) / m.frameRate.value
        let times = path.frames.indices.map { NSNumber(value: path.frames.count > 1 ? Double($0) / Double(path.frames.count - 1) : 0) }
        func keyframes(_ key: String, _ values: [Any]) {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times
            animation.calculationMode = .linear
            animation.duration = max(span, 1 / m.frameRate.value)
            animation.beginTime = begin
            animation.fillMode = .backwards
            icon.add(animation, forKey: key)
        }
        keyframes("position", path.frames.map { NSValue(point: point($0.position)) })
        keyframes("transform.scale.x", path.frames.map { $0.scale.width })
        keyframes("transform.scale.y", path.frames.map { $0.scale.height })
        icon.add(spring("transform.rotation.z", from: degrees[0], to: degrees[1], response: m.rotationSpring.value, begin: begin - lead), forKey: "turn")
        icon.add(spring("opacity", from: 0, to: 1, response: m.fadeSpring.value, begin: begin - lead), forKey: "fade")
        // Each flight keeps the overlay `hold` after it lands; the last one to finish ends the run.
        holdUntil = max(holdUntil, CACurrentMediaTime() + path.duration + m.hold.value)
        scheduleEnd()
    }

    /// A spring given as SwiftUI's (response, damping ratio): mass 1, stiffness (2 pi / response)^2, damping 4 pi ratio / response.
    private func spring(_ key: String, from: Double, to: Double, response: [Double], begin: CFTimeInterval) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: key)
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / response[0], 2)
        animation.damping = 4 * .pi * response[1] / response[0]
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        animation.beginTime = begin
        animation.fillMode = .backwards
        return animation
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
        CATransaction.commit()
        // Arc springs it in from x -80, but its window shows only once that spring has run `lead`.
        let slide = binSpring(from: m.binHiddenX.value, to: center[0])
        slide.beginTime = bin.convertTime(CACurrentMediaTime(), from: nil) - lead
        bin.add(slide, forKey: "slide")
    }

    private func binSpring(from: Double, to: Double) -> CASpringAnimation {
        let k = Metrics.downloadFlight.binSpring.value
        let animation = CASpringAnimation(keyPath: "position.x")
        animation.mass = 1
        animation.stiffness = k[0]
        animation.damping = k[1]
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
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
            CATransaction.commit()
            bin.add(binSpring(from: x, to: m.binHiddenX.value), forKey: "slide")
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
