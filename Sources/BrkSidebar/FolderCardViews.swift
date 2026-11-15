import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The card behind a folder or tab group in the tab list: Ardia's group box, the user's choice for Brk's folders and
/// Tidy's groups (2026-11-15, docs/checks/2026-11-15-folder-card.md). As in Ardia it shows on the innermost folder under
/// the pointer (a closed folder's card is its header's hover) and on the open folder a drag would drop into, fading in and
/// out; it moves, grows and shrinks with the rows (`TablistAnimator`). Where cards go is `TablistLayout.folderCards`.
///
/// Only the cards that show have views (one or two, plus one fading out), so a list of hundreds of rows costs nothing more.
@MainActor
final class FolderCards {
    private var views: [ItemID: FolderCardView] = [:]
    private var cards: [ItemID: FolderCard] = [:]
    private var containers: [ItemID: NSView] = [:]
    private var palette: Palette?
    private var hovered: ItemID?
    private var dropping: ItemID?

    /// The card the pointer is in (nil: none, or a drag is on).
    func hover(_ folder: ItemID?) {
        guard folder != hovered else { return }
        hovered = folder
        sync(now: CACurrentMediaTime())
    }

    /// The open folder a held item would drop into.
    func drop(_ folder: ItemID?) {
        guard folder != dropping else { return }
        dropping = folder
        sync(now: CACurrentMediaTime())
    }

    /// A render's cards, each in the section view `container` holds its folder in. `plan`: the rows' motion of this render,
    /// started at `now`; the cards that show ride it.
    func update(_ list: [FolderCard], palette: Palette, container: (ItemID) -> NSView?, plan: TablistMotionPlan?, animator: TablistAnimator,
                now: CFTimeInterval) {
        let paletteChanged = palette != self.palette
        self.palette = palette
        cards = Dictionary(list.map { ($0.folder, $0) }, uniquingKeysWith: { a, _ in a })
        containers = [:]
        for card in list { containers[card.folder] = container(card.folder) }
        for (id, view) in views {
            guard let card = cards[id], let host = containers[id] else { continue }
            if paletteChanged { view.paint(palette) }
            let old = view.rect
            if view.superview !== host { host.addSubview(view, positioned: .below, relativeTo: nil) }
            place(view, at: card.rect)
            guard let plan, old != card.rect else { continue }
            animator.slide(view, kind: .item(id), fresh: false, now: now)
            if abs(old.height - card.rect.height) > 0.5 { grow(view, from: old, to: card.rect, timing: Self.timing(of: id, in: plan)) }
        }
        sync(now: now, animator: animator)
    }

    /// Gives a view to each card that shows and fades out the others.
    private func sync(now: CFTimeInterval, animator: TablistAnimator? = nil) {
        let shown = Set([hovered, dropping].compactMap { $0 }.filter { cards[$0] != nil })
        for (id, view) in views where !shown.contains(id) {
            views[id] = nil
            view.leave()
        }
        guard let palette else { return }
        for id in shown where views[id] == nil {
            guard let card = cards[id], let host = containers[id] else { continue }
            let view = FolderCardView()
            view.identify(.tabTool("folder-card-" + id.rawValue))
            view.paint(palette)
            host.addSubview(view, positioned: .below, relativeTo: nil)
            place(view, at: card.rect)
            // A card that shows while its rows still move joins their motion where it is.
            animator?.slide(view, kind: .item(id), fresh: true, now: now)
            view.enter()
            views[id] = view
        }
    }

    private func place(_ view: FolderCardView, at rect: CGRect) {
        view.rect = rect
        let origin = view.superview?.frame.origin ?? .zero
        view.frame = rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    /// The card's height eases from `old`'s to `new`'s with its top where the header row is drawn: an additive change of
    /// height, and of the layer's position by what the height moves it (none where the layer hangs from its top edge).
    private func grow(_ view: FolderCardView, from old: CGRect, to new: CGRect, timing: TablistMotionTiming) {
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(view, at: CGRect(x: new.minX, y: new.minY, width: new.width, height: old.height))
        let tall = layer.position
        place(view, at: new)
        let rest = layer.position
        CATransaction.commit()
        let c = TablistAnimator.curve(timing).map(Float.init)
        for (key, from) in [("bounds.size.height", old.height - new.height), ("position.y", tall.y - rest.y)] where abs(from) > 0.01 {
            let animation = CABasicAnimation(keyPath: key)
            animation.isAdditive = true
            animation.fromValue = from
            animation.toValue = 0
            animation.duration = TablistAnimator.duration(timing)
            animation.timingFunction = CAMediaTimingFunction(controlPoints: c[0], c[1], c[2], c[3])
            layer.add(animation, forKey: "brk.folder-card." + key + ".\(CACurrentMediaTime())")
        }
    }

    /// A folder's card changes height on its own opening or closing, else on another folder's, else with the list.
    private static func timing(of folder: ItemID, in plan: TablistMotionPlan) -> TablistMotionTiming {
        guard let opened = plan.toggled[folder] ?? plan.toggled.values.first else { return .list }
        return opened ? .folderOpen : .folderClose
    }
}

/// One card: the fill and border, behind the rows, taking no clicks.
@MainActor
final class FolderCardView: NSView {
    /// Where it is at rest, in the list's document coordinates.
    var rect: CGRect = .zero
    private var leaving = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.tablist.folderCardRadius.value
        layer?.borderWidth = Metrics.tablist.folderCardBorder.value
        // Under the pictures of rows on their way out of the list (TablistAnimator.depart puts them at -1).
        layer?.zPosition = -2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func paint(_ palette: Palette) {
        let light = palette.scheme == .light
        layer?.backgroundColor = palette.color(light ? Draw.folderCardFillLight.value : Draw.folderCardFillDark.value).cgColor
        layer?.borderColor = palette.color(light ? Draw.folderCardStrokeLight.value : Draw.folderCardStrokeDark.value).cgColor
    }

    func enter() { fade(to: 1) }

    /// Fades out, then goes.
    func leave() {
        leaving = true
        fade(to: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + Draw.folderCardFade.value) { [weak self] in
            MainActor.assumeIsolated { if self?.leaving == true { self?.removeFromSuperview() } }
        }
    }

    private func fade(to opacity: Float) {
        guard let layer else { return }
        // A new card (nothing on screen yet) fades in from nothing; one already fading goes on from where it is.
        let from = layer.presentation()?.opacity ?? (opacity > 0 ? 0 : layer.opacity)
        layer.opacity = opacity
        let c = Draw.folderCardFadeCurve.value.map(Float.init)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = opacity
        animation.duration = Draw.folderCardFade.value
        animation.timingFunction = CAMediaTimingFunction(controlPoints: c[0], c[1], c[2], c[3])
        layer.add(animation, forKey: "brk.folder-card.fade")
    }
}
