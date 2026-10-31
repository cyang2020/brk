import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W2. The content cards and split dividers. Each card is a rounded, clipping layer (Metrics.content
/// .cornerRadius, continuous) with a separate shadow view behind it (a clipping layer cannot cast its own shadow),
/// hosting the engine's page surface for its pane. Divider drags dispatch `.split(.resize)` with
/// `ContentLayout.fractions(afterDragging:...)`.
@MainActor
public final class ContentAreaView: NSView {
    let dispatch: Dispatch
    private var cards: [CardView] = []
    private var shadows: [ShadowView] = []
    private var dividers: [DividerView] = []

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// This view spans the window (cards are in window coordinates), so only its cards and dividers take clicks;
    /// anywhere else the views below it (the sidebar, the dock) do.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Cards are in window coordinates, so this view spans the window. Cards grow and shrink to `frames.cards`; card
    /// i hosts the surface for pane i (`.page`), a white card (`.blank`) or the sad-tab placeholder (`.crashed`).
    /// Surfaces no longer shown are removed from their card; the engine hides the page when its view leaves the window.
    func render(_ content: ContentSnapshot, frames: WindowFrames, palette: Palette, surface: (PageID) -> NSView?) {
        frame = CGRect(origin: .zero, size: frames.contentSize)
        while cards.count < frames.cards.count {
            let shadow = ShadowView(frame: .zero)
            shadows.append(shadow)
            addSubview(shadow, positioned: .below, relativeTo: cards.first)
            let card = CardView(frame: .zero)
            cards.append(card)
            addSubview(card)
        }
        while cards.count > frames.cards.count {
            cards.removeLast().removeFromSuperview()
            shadows.removeLast().removeFromSuperview()
        }
        for ((card, shadow), frame) in zip(zip(cards, shadows), frames.cards) {
            shadow.frame = frame.rect
            shadow.layer?.cornerRadius = frame.cornerRadius
            card.frame = frame.rect
            card.layer?.cornerRadius = frame.cornerRadius
            card.identify(.card(frame.pane))
            switch frame.content {
            case .page(let page):
                card.host(surface(page), placeholder: nil)
            case .blank:
                card.host(nil, placeholder: nil)
            case .crashed(let page):
                card.host(nil, placeholder: "☹\nThis page stopped responding.\nBrk is trying to recover the page. You can also retry.")
                card.retryAction = { [dispatch] in dispatch(.page(.reload(.item(page.item), ignoringCache: false))) }
            }
        }
        while dividers.count < frames.dividers.count {
            let divider = DividerView(index: dividers.count, dispatch: dispatch)
            dividers.append(divider)
            addSubview(divider)
        }
        while dividers.count > frames.dividers.count { dividers.removeLast().removeFromSuperview() }
        for (divider, rect) in zip(dividers, frames.dividers) {
            divider.frame = rect
            divider.identify(.divider(divider.index))
            divider.split = content.split
            divider.panes = content.panes.map(\.tab)
            divider.fractions = content.panes.map(\.fraction)
            divider.area = frames.contentArea
            divider.orientation = content.orientation
        }
    }
}

/// The soft shadow behind a card. A clipping layer cannot cast its own shadow, so this opaque sibling sits under the
/// card with the same frame and radius (Metrics.content.shadowRadius, shadowOpacity; hidden when showsShadow is off).
@MainActor
final class ShadowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(Metrics.content.shadowOpacity.value)
        layer?.shadowRadius = Metrics.content.shadowRadius.value
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        isHidden = !Metrics.content.showsShadow.value
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

@MainActor
final class CardView: NSView {
    private let placeholder = NSTextField(labelWithString: "")
    var retryAction: (() -> Void)?
    private let retry = NSButton(title: "Retry", target: nil, action: nil)
    private weak var hosted: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        layer?.backgroundColor = NSColor.white.cgColor
        placeholder.alignment = .center
        placeholder.textColor = .secondaryLabelColor
        placeholder.isHidden = true
        addSubview(placeholder)
        placeholder.maximumNumberOfLines = 4
        retry.target = self
        retry.action = #selector(retryPage)
        retry.isHidden = true
        addSubview(retry)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Puts `surface` in the card (moving it here from another card if needed) or shows `placeholder` text.
    func host(_ surface: NSView?, placeholder text: String?) {
        if let surface {
            if surface.superview !== self {
                hosted?.removeFromSuperview()
                surface.removeFromSuperview()
                addSubview(surface)
            }
            hosted = surface
            surface.frame = bounds
            surface.autoresizingMask = [.width, .height]
        } else {
            hosted?.removeFromSuperview()
            hosted = nil
        }
        placeholder.stringValue = text ?? ""
        placeholder.isHidden = text == nil
        retry.isHidden = text == nil
        retry.sizeToFit()
        retry.frame.origin = NSPoint(x: bounds.midX - retry.frame.width / 2, y: bounds.midY + 50)
        placeholder.sizeToFit()
        placeholder.frame.origin = CGPoint(x: bounds.midX - placeholder.frame.width / 2, y: bounds.midY - placeholder.frame.height / 2)
    }

    @objc private func retryPage() { retryAction?() }

    override func layout() {
        super.layout()
        hosted?.frame = bounds
    }
}

/// An invisible hit view in the gap between two cards; dragging it dispatches `.split(.resize)`.
@MainActor
final class DividerView: NSView {
    let index: Int
    let dispatch: Dispatch
    var split: ItemID?
    /// The pane tabs in order; the fractions dictionary of `.split(.resize)` is keyed by them.
    var panes: [ItemID] = []
    var fractions: [Double] = []
    var area: CGRect = .zero
    var orientation: SplitOrientation = .horizontal

    init(index: Int, dispatch: @escaping Dispatch) {
        self.index = index
        self.dispatch = dispatch
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: orientation == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let split, let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let position = orientation == .horizontal ? point.x : point.y
        let next = ContentLayout.fractions(afterDragging: index, to: position, in: area, current: fractions, orientation: orientation)
        guard next.count == panes.count else { return }
        dispatch(.split(.resize(split, fractions: Dictionary(uniqueKeysWithValues: zip(panes, next)))))
    }
}
