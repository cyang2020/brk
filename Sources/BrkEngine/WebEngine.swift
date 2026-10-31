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
///
/// Identity rule for reused ids (`PageLedger`): a page id leaves the live set the moment `reconcile` stops listing
/// it, so the same id can be live again while the old browser is still closing. The old incarnation's events are
/// dropped and its OnBeforeClose never removes or reports closure for the new one.
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

    /// Gives keyboard focus to `page` in its owning window, or releases that window's page focus (nil) for a
    /// native view. A pending request survives input-view creation. Never activates a window or affects another
    /// window's request. The caller also repairs focus after AppKit clears a responder during native layout.
    func focus(_ page: PageID?, in window: NSWindow)

    /// Runs JavaScript in a page, no result. For the e2e harness's fixture pages (they report through
    /// `document.title`) and, later, Boosts' user scripts. A no-op for a page that is not live.
    func evaluate(_ script: String, in page: PageID)

    /// Diagnostics for the control socket. Never used for app behavior.
    func facts(for page: PageID) -> PageFacts?

    /// Page lifecycle since launch: created, close requested, closed (OnBeforeClose), with generations, in order.
    var pageLog: [PageLogEntry] { get }

    func find(_ request: FindRequest)

    func cancelDownload(_ id: DownloadID)
    /// Revokes synchronously. Final drain results arrive through the delegate.
    func disposeContext(_ request: ContextDisposal)

    /// Ordered teardown, idempotent: after it returns no browser is alive and every borrowed view is back where it
    /// came from. `.clean` means the runtime is shut down too and the process may exit; `.timedOut` means some
    /// browsers never answered and the runtime was left running (never `cef_shutdown` with browsers alive): the
    /// caller exits anyway, non-zero. Calling it again awaits the same work and returns the same outcome.
    func shutdown() async -> ShutdownOutcome
}

@MainActor
public protocol WebEngineDelegate: AnyObject {
    /// A page reported something. Delivered on the main actor in the order Chromium produced it.
    func engine(_ engine: any WebEngine, page: BrowserToken, didEmit event: PageEvent)

    /// A key event reached a page (`.beforePage` or `.afterPage`). Return true to consume it. Must answer
    /// synchronously: CEF blocks on the return value. `pressID` follows the rule on `PressID`: minted from the
    /// current event before the page, paired by `PressCorrelator` after it.
    func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: PressID) -> Bool

    func engine(_ engine: any WebEngine, page: PageID, keyHandling key: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling

    func engine(_ engine: any WebEngine, ownerWindow id: WindowID) -> NSWindow?
    func engine(_ engine: any WebEngine, find update: FindUpdate)
    func engine(_ engine: any WebEngine, download update: DownloadUpdate)
    func engine(_ engine: any WebEngine, destination prompt: DownloadDestinationPrompt,
                reply: @escaping @MainActor (DestinationAnswer) -> Void)
    func engine(_ engine: any WebEngine, dismissDestination ticket: DestinationTicket)
    func engine(_ engine: any WebEngine, contextDisposed result: ContextDisposalResult)

    /// A page's main frame is about to navigate (CEF's OnBeforeBrowse, synchronous). False cancels it; the app
    /// uses this for Arc's "Open a Peek window when clicking on links to other sites" on Pinned and Favorites tabs
    /// (the Peek opens instead). Redirects are never asked about. F3.
    func engine(_ engine: any WebEngine, page: PageID, shouldNavigateTo url: URL, userGesture: Bool) -> Bool
}

extension WebEngineDelegate {
    public func engine(_ engine: any WebEngine, page: PageID, keyHandling key: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling {
        KeyHandling(handled: self.engine(engine, page: page, key: key, stage: stage, pressID: pressID), shortcut: false)
    }
    public func engine(_ engine: any WebEngine, ownerWindow id: WindowID) -> NSWindow? { nil }
    public func engine(_ engine: any WebEngine, find update: FindUpdate) {}
    public func engine(_ engine: any WebEngine, download update: DownloadUpdate) {}
    public func engine(_ engine: any WebEngine, destination prompt: DownloadDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void) { reply(.ownerGone) }
    public func engine(_ engine: any WebEngine, dismissDestination ticket: DestinationTicket) {}
    public func engine(_ engine: any WebEngine, contextDisposed result: ContextDisposalResult) {}

    /// Allow by default: a delegate that does not route links (tests, tools) lets every navigation through.
    public func engine(_ engine: any WebEngine, page: PageID, shouldNavigateTo url: URL, userGesture: Bool) -> Bool { true }
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

    /// Whether the window may run a key-down through the shortcut table before AppKit's own key handling while this
    /// surface has focus. False (the default) for a real engine: Chromium's view gets the key and CEF's handler
    /// routes it before and after the page. True for a surface that consumes no keys (the stub), so app shortcuts
    /// work on it the way they do with a native view focused.
    open var routesKeysThroughWindow: Bool { false }
}

extension WebEngine {
    public func find(_ request: FindRequest) {
        if let id = request.requestID { delegate?.engine(self, find: .failed(id, .unavailable)) }
    }
}
