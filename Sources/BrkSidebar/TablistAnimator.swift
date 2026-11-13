import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// Moves the tab list's views the way Arc's outline view moves its rows (`TablistMotionPlan`, the timings in
/// `Draw.tablist*`). Every view is put at its new frame at once, so hit-testing, the harness and the next render see the
/// final layout; what moves is a Core Animation offset added on top of that frame, easing from where the view was to 0.
/// Offsets add up, so a change that arrives while rows are still moving (a folder clicked again half-way) starts from
/// where they are on screen.
///
/// Nothing here is in the sidebar's render slice: the motion lives on the views' layers, so a render that changes nothing
/// returns early as before and a Space swipe never re-renders the column for it.
@MainActor
final class TablistAnimator {
    /// One slide still running on an item: rows that get a view while it runs (scrolled into reach) pick it up mid-way.
    private struct Running {
        let timing: TablistMotionTiming
        let dy: Double
        let start: CFTimeInterval
        let key: String
    }

    private var running: [RowFrame.Kind: [Running]] = [:]
    /// Rows that left the list, drawn until their way out ends.
    private var ghosts: [(view: NSView, end: CFTimeInterval)] = []
    /// Views clipped or raised for the length of a motion.
    private var clipped: [(view: NSView, end: CFTimeInterval)] = []
    private var raised: [(view: NSView, end: CFTimeInterval)] = []
    private var serial = 0
    private var sweepScheduled = false
    /// How long after a render its frame may reach the screen: a motion's end is swept this much later.
    private static let commitMargin = 0.08

    static func duration(_ timing: TablistMotionTiming) -> Double {
        switch timing {
        case .list: Draw.tablistListMotion.value
        case .folderOpen: Draw.tablistFolderOpen.value
        case .folderClose: Draw.tablistFolderClose.value
        }
    }

    static func curve(_ timing: TablistMotionTiming) -> [Double] {
        switch timing {
        case .list: Draw.tablistListCurve.value
        case .folderOpen: Draw.tablistFolderOpenCurve.value
        case .folderClose: Draw.tablistFolderCloseCurve.value
        }
    }

    private static func function(_ timing: TablistMotionTiming) -> CAMediaTimingFunction {
        let c = curve(timing).map(Float.init)
        return CAMediaTimingFunction(controlPoints: c[0], c[1], c[2], c[3])
    }

    /// The plan's slides start now; returns the ones each item gets, to hand to views that already exist.
    func begin(_ plan: TablistMotionPlan, at now: CFTimeInterval) {
        prune(now)
        for (kind, slides) in plan.slides {
            for slide in slides {
                serial += 1
                running[kind, default: []].append(Running(timing: slide.timing, dy: slide.dy, start: now, key: "brk.tablist.slide.\(serial)"))
            }
        }
    }

    /// Gives `view` the slides of `kind`: all that still run when the view is new, only those that start `now` otherwise.
    func slide(_ view: NSView, kind: RowFrame.Kind, fresh: Bool, now: CFTimeInterval) {
        guard let layer = view.layer, let list = running[kind] else { return }
        for item in list where fresh || item.start == now {
            add(slide: item, to: layer, caughtUp: item.start != now)
        }
    }

    /// One more slide of `dy` for `kind` on `timing`, starting now (a row back from its way out, from where its picture
    /// was drawn).
    func extraSlide(_ view: NSView, kind: RowFrame.Kind, dy: Double, timing: TablistMotionTiming, now: CFTimeInterval) {
        guard let layer = view.layer else { return }
        serial += 1
        let item = Running(timing: timing, dy: dy, start: now, key: "brk.tablist.slide.\(serial)")
        running[kind, default: []].append(item)
        add(slide: item, to: layer)
    }

    /// `caughtUp`: the slide began before this view existed and joins it mid-way. Otherwise it starts when this render's
    /// frame is committed, as Arc's table animations do: stamping it with the render's own start would skip the first
    /// frames of the curve by however long the render takes.
    private func add(slide item: Running, to layer: CALayer, caughtUp: Bool = false) {
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.isAdditive = true
        animation.fromValue = item.dy * Self.down(layer.superlayer)
        animation.toValue = 0
        animation.duration = Self.duration(item.timing)
        animation.timingFunction = Self.function(item.timing)
        if caughtUp {
            animation.beginTime = layer.convertTime(item.start, from: nil)
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: item.key)
    }

    /// +1 where a layer's sublayers count y downward (a flipped view's layer), -1 where upward.
    private static func down(_ layer: CALayer?) -> Double { layer?.contentsAreFlipped() ?? true ? 1 : -1 }

    /// An added row fades in where it is (from `from`: a row back from its way out, from its picture's opacity).
    func fadeIn(_ view: NSView, from: Float = 0, now: CFTimeInterval) {
        guard let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = layer.opacity
        animation.duration = Self.duration(.list)
        animation.timingFunction = Self.function(.list)
        layer.add(animation, forKey: "brk.tablist.fade")
    }

    /// Shows only the part of `view` below the line `clip` (the view's own y at its final place) while its `timing`
    /// slide of `dy` runs: the line stays put as the view moves, so the row comes out from (or goes in) under the row above.
    func clip(_ view: NSView, below clip: Double, slide dy: Double, timing: TablistMotionTiming, now: CFTimeInterval) {
        guard let layer = view.layer else { return }
        // A row clipped again before its last motion ended (a folder clicked twice) keeps its mask: the running counter-
        // motion goes on, the new one adds to it, and only the line's place at rest is set again.
        let mask = layer.mask ?? CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        let big = 100_000.0
        let down = Self.down(layer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = down > 0 ? CGRect(x: -big, y: clip, width: 2 * big, height: big)
            : CGRect(x: -big, y: Double(layer.bounds.height) - clip - big, width: 2 * big, height: big)
        layer.mask = mask
        CATransaction.commit()
        serial += 1
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.isAdditive = true
        animation.fromValue = -dy * down
        animation.toValue = 0
        animation.duration = Self.duration(timing)
        animation.timingFunction = Self.function(timing)
        mask.add(animation, forKey: "brk.tablist.clip.\(serial)")
        clipped.append((view, now + Self.duration(timing)))
        scheduleSweep(after: Self.duration(timing))
    }

    /// Draws `view` over its neighbours until its slide ends (a moved row passes over the rows it crosses).
    func raise(_ view: NSView, now: CFTimeInterval) {
        view.layer?.zPosition = 1
        raised.append((view, now + Self.duration(.list)))
        scheduleSweep(after: Self.duration(.list))
    }

    /// Keeps a row that left on screen for its way out, then removes it. It takes no pointer meanwhile.
    func depart(_ view: NSView, departure: TablistMotionPlan.Departure, clipLine: Double?, now: CFTimeInterval) {
        guard let layer = view.layer else { view.removeFromSuperview(); return }
        layer.zPosition = -1
        let length: Double
        switch departure {
        case .fade:
            length = Self.duration(.list)
            fadeOut(layer, timing: .list, now: now)
        case .slideUp(let by, _, let fades, let timing):
            length = Self.duration(timing)
            serial += 1
            add(slide: Running(timing: timing, dy: by, start: now, key: "brk.tablist.slide.\(serial)"), to: layer)
            if let clipLine { clip(view, below: clipLine, slide: by, timing: timing, now: now) }
            if fades { fadeOut(layer, timing: timing, now: now) }
        }
        ghosts.append((view, now + length))
        scheduleSweep(after: length)
    }

    private func fadeOut(_ layer: CALayer, timing: TablistMotionTiming, now: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.opacity
        animation.toValue = 0
        animation.duration = Self.duration(timing)
        animation.timingFunction = Self.function(timing)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "brk.tablist.fade")
    }

    /// How far `view` is drawn from its frame now (document points, positive below), by its layer's presented position.
    func presentedOffset(_ view: NSView) -> Double {
        guard let layer = view.layer, let shown = layer.presentation() else { return 0 }
        return Double(shown.position.y - layer.position.y) * Self.down(layer.superlayer)
    }

    /// A picture on its way out is taken away early (its row came back).
    func forget(_ view: NSView) {
        ghosts.removeAll { $0.view === view }
        clipped.removeAll { $0.view === view }
    }

    /// Ends everything at once (the Space changed, the list went away, a drag began).
    func stopAll() {
        for ghost in ghosts { ghost.view.removeFromSuperview() }
        ghosts.removeAll()
        for entry in clipped { entry.view.layer?.mask = nil }
        clipped.removeAll()
        for entry in raised { entry.view.layer?.zPosition = 0 }
        raised.removeAll()
        running.removeAll()
    }

    private func prune(_ now: CFTimeInterval) {
        running = running.compactMapValues { list in
            let left = list.filter { now < $0.start + Self.duration($0.timing) }
            return left.isEmpty ? nil : left
        }
    }

    private func scheduleSweep(after delay: Double) {
        guard !sweepScheduled else { return }
        sweepScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.commitMargin) { [weak self] in
            MainActor.assumeIsolated { self?.sweep() }
        }
    }

    private func sweep() {
        sweepScheduled = false
        let now = CACurrentMediaTime()
        let over = { (end: CFTimeInterval) in end + Self.commitMargin <= now + 0.001 }
        for ghost in ghosts where over(ghost.end) { ghost.view.removeFromSuperview() }
        ghosts.removeAll { over($0.end) }
        // A view clipped or raised again since keeps its newer mask or place until that one ends.
        let liveClips = clipped.filter { !over($0.end) }, liveRaises = raised.filter { !over($0.end) }
        for entry in clipped where over(entry.end) && !liveClips.contains(where: { $0.view === entry.view }) { entry.view.layer?.mask = nil }
        for entry in raised where over(entry.end) && !liveRaises.contains(where: { $0.view === entry.view }) { entry.view.layer?.zPosition = 0 }
        clipped = liveClips
        raised = liveRaises
        prune(now)
        let next = (ghosts.map(\.end) + clipped.map(\.end) + raised.map(\.end)).min()
        if let next { scheduleSweep(after: max(0, next - now)) }
    }

}
