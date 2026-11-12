import AppKit
import BrkBase
import BrkLayout

/// A row of pages and where it stands (Arc: `PageSwipeController<WindowLayoutPage>`). The sidebar's row is the Library
/// first, then the Spaces in dock order; the AI panel's is its conversation list, then the conversation
/// (docs/design/ai-threads.md). The rules are `PageSwipeRule`; this object holds the position, which is view state: only
/// the page the fingers settle on reaches the document.
///
/// It moves with the fingers while tracking, then on a `PageSpring` driven by the display link. A page chosen any other
/// way (the keyboard, the dock, the command bar, a click) settles on the same spring.
@MainActor
public final class PagePager<Page: Hashable>: NSObject {
    public private(set) var pages: [Page] = []
    public private(set) var origins: [Double] = []
    public private(set) var selected = 0
    private var raw = 0.0
    private var begin: (page: Int, interrupted: Bool)?
    private var velocity = PageSwipeVelocity()
    /// `start` is set by the first display-link tick: its clock runs from then, after the render a Space change costs (Arc's
    /// spring does the same: a recorded release has the column stand still for that long, then the whole curve, Q19-h2).
    private var spring: (curve: PageSpring, start: CFTimeInterval?)?
    private var link: CADisplayLink?
    private var detent: Int?

    /// The view whose display link drives the spring.
    public weak var host: NSView?
    /// The shown position changed.
    public var onMove: (() -> Void)?
    /// The fingers lifted (or a wheel stepped) and this page is the new one; called before it starts to settle.
    public var onSelect: ((Page) -> Void)?
    /// The fingers lifted, before `onSelect`.
    public var onLift: (() -> Void)?
    /// The position crossed into another page while tracking (Arc's haptic, bin:0x100a1b99c).
    public var onDetent: (() -> Void)?
    /// Standing on the selected page again.
    public var onSettled: (() -> Void)?

    public override init() { super.init() }

    public var isTracking: Bool { begin != nil }
    public var isActive: Bool { begin != nil || spring != nil }
    public var selectedPage: Page? { pages.indices.contains(selected) ? pages[selected] : nil }

    /// The position on screen: pressed past what the swipe can reach.
    public var position: Double {
        guard let begin else { return raw }
        return PageSwipeRule.rubberBanded(raw, in: PageSwipeRule.range(around: begin.page, origins: origins))
    }

    /// The page row changed (a Space added or moved, a width). The selected page keeps its place in it, and a move under way
    /// keeps its offset from that page.
    public func update(pages newPages: [Page], widths: [Double]) {
        let newOrigins = PageSwipeRule.origins(widths: widths)
        guard newPages != pages || newOrigins != origins else { return }
        let page = selectedPage
        let offset = origins.indices.contains(selected) ? raw - origins[selected] : 0
        pages = newPages
        origins = newOrigins
        if let page, let index = newPages.firstIndex(of: page) { selected = index }
        guard origins.indices.contains(selected) else {
            selected = 0
            raw = origins.first ?? 0
            return
        }
        raw = origins[selected] + (isActive ? offset : 0)
        if let current = spring { spring = (PageSpring(from: raw, target: origins[selected], velocity: current.curve.velocity), nil) }
    }

    /// `page` is the selected one now, for a reason other than the fingers. `animated`: settles there on the spring, from one
    /// page away at most (the page left stands beside the new one, whatever lies between them in the row).
    public func select(_ page: Page, animated: Bool) {
        guard let index = pages.firstIndex(of: page), origins.indices.contains(selected) else { return }
        let old = selected, from = position
        begin = nil
        selected = index
        guard animated, host?.window?.isVisible == true else { return settle() }
        var start = from
        if abs(index - old) > 1 {
            // The page left stands right beside the new one: to its left, the width of the page before it away; to its
            // right, the new page's own width away. (Before the first Space is the Library, far wider than a Space: a
            // jump there from the right started that much too far.)
            let width = old < index ? origins[index] - origins[index - 1] : origins[index + 1] - origins[index]
            start = origins[index] + (from - origins[old]) + (old < index ? -width : width)
        }
        startSpring(from: start, velocity: 0)
    }

    /// One page on, for a wheel (bin:0x100a1b46c).
    public func step(by direction: Int) {
        guard !isTracking, pages.indices.contains(selected + direction) else { return }
        let from = position
        selected += direction
        onSelect?(pages[selected])
        startSpring(from: from, velocity: 0)
    }

    public func beginTracking(at time: Double) {
        guard origins.indices.contains(selected) else { return }
        let interrupted = spring != nil
        let shown = position
        stopSpring()
        raw = PageSwipeRule.unbanded(shown, in: PageSwipeRule.range(around: selected, origins: origins))
        begin = (selected, interrupted)
        velocity = PageSwipeVelocity()
        velocity.add(raw, at: time)
        detent = PageSwipeRule.floorPage(at: shown, origins: origins)
        onMove?()
    }

    public func track(delta: Double, at time: Double) {
        guard begin != nil else { return }
        raw = PageSwipeRule.moved(raw, by: delta)
        velocity.add(raw, at: time)
        let page = PageSwipeRule.floorPage(at: position, origins: origins)
        if page != detent {
            detent = page
            onDetent?()
        }
        onMove?()
    }

    public func endTracking(at time: Double) {
        guard let began = begin else { return }
        let shown = position, speed = velocity.velocity(at: time)
        let target = PageSwipeRule.target(position: shown, velocity: speed, begin: began.page, origins: origins, interrupted: began.interrupted)
        onLift?()
        begin = nil
        raw = shown
        let changed = target != selected
        selected = target
        if changed { onSelect?(pages[target]) }
        startSpring(from: shown, velocity: PageSwipeRule.settleVelocity(speed, position: shown, target: origins[target]))
    }

    public func cancelTracking() {
        guard begin != nil else { return }
        let shown = position
        begin = nil
        startSpring(from: shown, velocity: 0)
    }

    private func startSpring(from: Double, velocity: Double) {
        guard origins.indices.contains(selected) else { return settle() }
        raw = from
        let curve = PageSpring(from: from, target: origins[selected], velocity: velocity)
        guard !curve.isSettled(at: 0), let host, host.window?.isVisible == true else { return settle() }
        spring = (curve, nil)
        if link == nil {
            let link = host.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        onMove?()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let spring else { return stopSpring() }
        let start = spring.start ?? link.timestamp
        self.spring?.start = start
        let t = link.targetTimestamp - start
        if spring.curve.isSettled(at: t) { return settle() }
        raw = spring.curve.position(at: t)
        onMove?()
    }

    private func stopSpring() {
        spring = nil
        link?.invalidate()
        link = nil
    }

    private func settle() {
        stopSpring()
        if origins.indices.contains(selected) { raw = origins[selected] }
        onSettled?()
        onMove?()
    }
}

/// The two-finger swipe over a column of pages, one for the sidebar's Spaces and one for the AI panel's two pages: the
/// first events are held until the direction is clear (`SpaceSwipe`); a vertical gesture goes to the scroll view under
/// the pointer with the events held so far; a sideways one moves the `PagePager` with the fingers and settles it when they
/// lift; momentum after a swipe is ignored; a wheel without phases steps one page (`PageSwipeWheel`).
@MainActor
public final class PageSwipeGesture {
    private var swipe = SpaceSwipe()
    /// The gesture's events so far, kept from the column until the direction is known.
    private var held: [NSEvent] = []
    private var swallowMomentum = false
    private var wheel = PageSwipeWheel()

    public init() {}

    /// Whether the event was taken. `starts`: the gesture began over this column. `willMove` runs before the pages move,
    /// told whether a wheel's step (true) or the fingers (false) move them.
    public func handle<Page>(_ event: NSEvent, starts: Bool, pager: PagePager<Page>, window: NSWindow?, willMove: (_ wheel: Bool) -> Void) -> Bool {
        if !event.momentumPhase.isEmpty {
            // Arc ignores inertia after a swipe: the release decided (bin:0x100a1a2b0 with a settling page).
            let consumed = swallowMomentum
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swallowMomentum = false }
            return consumed
        }
        if event.phase.isEmpty || !event.hasPreciseScrollingDeltas { return handleWheel(event, starts: starts, pager: pager, willMove: willMove) }
        let phase: SpaceSwipe.Phase
        if event.phase.contains(.began) { phase = .began; swallowMomentum = false; held = [] }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return false }
        let verdict = swipe.update(horizontal: event.scrollingDeltaX, vertical: event.scrollingDeltaY, phase: phase,
                                   startsInSidebar: starts, precise: event.hasPreciseScrollingDeltas)
        switch verdict {
        case .pass:
            return false
        case .hold:
            held.append(event)
            return true
        case .handOver:
            // What is under the pointer gets the events held so far now, and this one and the rest by the normal path.
            let events = held
            held = []
            if let first = events.first, let scroller = window?.contentView?.hitTest(window?.contentView?.superview?.convert(first.locationInWindow, from: nil) ?? first.locationInWindow)?.enclosingScrollView {
                for event in events { scroller.scrollWheel(with: event) }
            }
            return false
        case .begin(let travel):
            held = []
            willMove(false)
            pager.beginTracking(at: event.timestamp)
            if travel != 0 { pager.track(delta: travel, at: event.timestamp) }
            if phase == .ended {
                swipe = SpaceSwipe()
                swallowMomentum = true
                pager.endTracking(at: event.timestamp)
            }
            return true
        case .move(let delta):
            pager.track(delta: delta, at: event.timestamp)
            return true
        case .end:
            swallowMomentum = true
            pager.endTracking(at: event.timestamp)
            return true
        case .cancel:
            held = []
            swallowMomentum = true
            pager.cancelTracking()
            return true
        }
    }

    /// A wheel's sideways travel steps one page (Arc: `nonGesturalScrollState`). Its vertical travel stays the column's.
    private func handleWheel<Page>(_ event: NSEvent, starts: Bool, pager: PagePager<Page>, willMove: (_ wheel: Bool) -> Void) -> Bool {
        guard starts, event.scrollingDeltaX != 0, !pager.isTracking else { return false }
        if let step = wheel.update(horizontal: event.scrollingDeltaX, inverted: event.isDirectionInvertedFromDevice, at: CACurrentMediaTime()) {
            willMove(true)
            pager.step(by: step)
        }
        return true
    }

    public func reset<Page>(_ pager: PagePager<Page>) {
        swipe = SpaceSwipe()
        held = []
        pager.cancelTracking()
    }
}
