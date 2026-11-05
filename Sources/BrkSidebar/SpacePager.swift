import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// The row of pages in a standard window's sidebar and where it stands (Arc: `PageSwipeController<WindowLayoutPage>`,
/// the Library first, then the Spaces in dock order). The rules are `PageSwipeRule`; this object holds the position, which is
/// view state: only the page the fingers settle on reaches the document.
///
/// It moves with the fingers while tracking, then on a `PageSpring` driven by the display link. A page chosen any other
/// way (the keyboard, the dock, the command bar) settles on the same spring.
@MainActor
final class SpacePager: NSObject {
    enum Page: Hashable { case library, space(SpaceID) }

    private(set) var pages: [Page] = []
    private(set) var origins: [Double] = []
    private(set) var selected = 0
    private var raw = 0.0
    private var begin: (page: Int, interrupted: Bool)?
    private var velocity = PageSwipeVelocity()
    private var spring: (curve: PageSpring, start: CFTimeInterval)?
    private var link: CADisplayLink?
    private var detent: Int?

    /// The view whose display link drives the spring.
    weak var host: NSView?
    /// The shown position changed.
    var onMove: (() -> Void)?
    /// The fingers lifted (or a wheel stepped) and this page is the new one; called before it starts to settle.
    var onSelect: ((Page) -> Void)?
    /// The fingers lifted, before `onSelect`.
    var onLift: (() -> Void)?
    /// The position crossed into another page while tracking (Arc's haptic, bin:0x100a1b99c).
    var onDetent: (() -> Void)?
    /// Standing on the selected page again.
    var onSettled: (() -> Void)?

    var isTracking: Bool { begin != nil }
    var isActive: Bool { begin != nil || spring != nil }
    var selectedPage: Page? { pages.indices.contains(selected) ? pages[selected] : nil }

    /// The position on screen: pressed past what the swipe can reach.
    var position: Double {
        guard let begin else { return raw }
        return PageSwipeRule.rubberBanded(raw, in: PageSwipeRule.range(around: begin.page, origins: origins))
    }

    /// The page row changed (a Space added or moved, a width). The selected page keeps its place in it, and a move under way
    /// keeps its offset from that page.
    func update(pages newPages: [Page], widths: [Double]) {
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
        if let current = spring { spring = (PageSpring(from: raw, target: origins[selected], velocity: current.curve.velocity), CACurrentMediaTime()) }
    }

    /// `page` is the selected one now, for a reason other than the fingers. `animated`: settles there on the spring, from one
    /// page away at most (the page left stands beside the new one, whatever lies between them in the row).
    func select(_ page: Page, animated: Bool) {
        guard let index = pages.firstIndex(of: page), origins.indices.contains(selected) else { return }
        let old = selected, from = position
        begin = nil
        selected = index
        guard animated, host?.window?.isVisible == true else { return settle() }
        var start = from
        if abs(index - old) > 1 {
            let width = origins[index] - origins[index - 1 >= 0 ? index - 1 : index]
            start = origins[index] + (from - origins[old]) + (old < index ? -width : width)
        }
        startSpring(from: start, velocity: 0)
    }

    /// One page on, for a wheel (bin:0x100a1b46c).
    func step(by direction: Int) {
        guard !isTracking, pages.indices.contains(selected + direction) else { return }
        let from = position
        selected += direction
        onSelect?(pages[selected])
        startSpring(from: from, velocity: 0)
    }

    func beginTracking(at time: Double) {
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

    func track(delta: Double, at time: Double) {
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

    func endTracking(at time: Double) {
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

    func cancelTracking() {
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
        spring = (curve, CACurrentMediaTime())
        if link == nil {
            let link = host.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        onMove?()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let spring else { return stopSpring() }
        let t = link.targetTimestamp - spring.start
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
