import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// Owner: W2. The content cards and split dividers. Each card is a rounded, clipping layer (Metrics.Content
/// .cornerRadius, continuous) with a separate shadow view behind it (a clipping layer cannot cast its own shadow),
/// hosting the engine's page surface for its pane. Divider drags dispatch `.split(.resize)` with
/// `ContentLayout.fractions(afterDragging:...)`.
@MainActor
public final class ContentAreaView: NSView {
    let dispatch: Dispatch
    private var cards: [CardView] = []

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    func render(_ content: ContentSnapshot, frames: WindowFrames, palette: Palette, surface: (PageID) -> NSView?) {
        // TODO(W2): frame = full window bounds (cards are in window coordinates); grow/shrink `cards` to
        // frames.cards.count; card i: frame, radius, identify(.card(i)); host = .page(id) -> surface(id) (add as the
        // card's only page subview if not already there, frame = card bounds), .blank -> empty white card,
        // .crashed -> sad-tab placeholder. Surfaces no longer shown are removed from the card (the engine hides them).
        // Dividers: invisible hit views at frames.dividers with identify(.divider(i)) and a resize cursor.
        fatalError("not implemented")
    }
}

@MainActor
final class CardView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.Content.cornerRadius.value
        layer?.backgroundColor = NSColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
}
