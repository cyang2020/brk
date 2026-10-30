import AppKit
import BrkBase

/// The hosting interface for web pages: the only thing BrkApp knows about Chromium.
///
/// The engine is a page factory and an event source. It knows nothing of tabs, spaces, sidebars or commands:
/// the app tells it which pages should exist (`reconcile`), asks it for a page's view (`surface`), sends one-shot
/// actions (`perform`), moves keyboard focus (`focus`), and receives events and key presses through its delegate.
/// Everything Chromium-specific is hidden behind these six calls: CEF initialization, the Chrome-runtime host window
/// per page, moving Chromium's views into our card, keeping host windows from becoming key, renderer crashes, and
/// the shutdown order.
///
/// Implementations: `CEFEngine` (BrkCEF; Chrome runtime, views embedded) and `StubEngine` (no Chromium; placeholder
/// views; used by `BRK_ENGINE=stub` and by UI work without a CEF download). An Alloy-runtime engine can be added as a
/// third implementation for testing or fallback without touching any caller.
@MainActor
public protocol WebEngine: AnyObject {
    var delegate: (any WebEngineDelegate)? { get set }

    /// Makes the set of live pages equal `pages`: creates pages that are missing (loading `initialURL`; a nil URL
    /// creates nothing), closes pages that are not listed. Idempotent; called after every state change.
    /// A page id closed and listed again in a later call gets a fresh page even if the old one is still closing.
    func reconcile(_ pages: [PageSpec])

    /// The view that shows `page`, or nil if it is not live. The same instance for the page's lifetime. The caller
    /// puts it in a card and sets its frame; the engine keeps Chromium's views inside it and in step with its bounds.
    /// Removing it from its window hides the page (Chromium is told it is hidden); adding it to another window moves
    /// the page there.
    func surface(for page: PageID) -> PageSurfaceView?

    func perform(_ action: PageAction, on page: PageID)

    /// Gives keyboard focus to `page`'s content, or takes it away from every page (nil) so the caller can focus a
    /// native view. The caller decides when (only when the snapshot's `focus` changes).
    func focus(_ page: PageID?)

    /// Diagnostics for the control socket. Never used for app behavior.
    func facts(for page: PageID) -> PageFacts?

    /// Ordered teardown, idempotent: after it returns no browser is alive, every borrowed view is back where it came
    /// from, and the engine's runtime is shut down, so the process may exit. Calling it again awaits the same work.
    func shutdown() async
}

@MainActor
public protocol WebEngineDelegate: AnyObject {
    /// A page reported something. Delivered on the main actor in the order Chromium produced it.
    func engine(_ engine: any WebEngine, page: PageID, didEmit event: PageEvent)

    /// A key event reached a page (`.beforePage` or `.afterPage`). Return true to consume it. Must answer
    /// synchronously: CEF blocks on the return value.
    func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: UInt64) -> Bool
}

/// A page's view. Engines subclass it; callers treat it as a plain NSView placed inside a card.
@MainActor
open class PageSurfaceView: NSView {
    public let page: PageID

    public init(page: PageID) {
        self.page = page
        super.init(frame: .zero)
        wantsLayer = true
        autoresizesSubviews = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    open override var isFlipped: Bool { true }
}
