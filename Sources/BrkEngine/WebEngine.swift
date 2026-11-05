import AppKit
import BrkBase

/// The hosting interface for web pages: the only thing BrkApp knows about Chromium.
///
/// The engine is a page factory and an event source. It knows nothing of tabs, spaces, sidebars or commands:
/// the app tells it which pages should exist (`reconcile`), asks it for a page's view (`surface`), sends one-shot
/// actions (`perform`), moves keyboard focus (`focus`), and receives events and key presses through its delegate.
/// Everything Chromium-specific is hidden behind this interface: CEF initialization, the Chrome-runtime host window
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

    /// The text highlighted in a live page's focused frame (nil when nothing is, or the page is not live). For
    /// Shared Quotes' Copy Link to Highlight.
    func selectedText(_ page: PageID) async -> String?
    /// Reads whether the page has text highlighted and reports a change as `PageEvent.selectionChanged` (the URL
    /// pill's Share Quote). Called after a mouse-up or key-up in the page.
    func checkSelection(_ page: PageID)

    /// The browser engine's version as the About window shows it ("154.0.8037.98" for Chromium); nil without one.
    var engineVersion: String? { get }

    /// Diagnostics for the control socket. Never used for app behavior.
    func facts(for page: PageID) -> PageFacts?
    func isPageHostWindow(_ window: NSWindow) -> Bool

    /// Page lifecycle since launch: created, close requested, closed (OnBeforeClose), with generations, in order.
    var pageLog: [PageLogEntry] { get }

    func readAIPage(_ document: DocumentToken) async throws -> AIPageContent
    func translateAIPage(_ content: AIPageContent, replacements: [AITextNode]) async throws -> Bool
    /// Swaps a translated document between the translation and its own text (`translateAIPage` keeps both); false
    /// when nothing could be swapped (the text changed since).
    func showAITranslation(_ document: DocumentToken, translated: Bool) async -> Bool
    /// The link under the pointer in `document` that leads to `url`, nil when none is hovered: its box (points in the
    /// page's surface, top-left origin), where the 5-Second Preview card opens, and whether it is one of the links Arc
    /// previews without Shift (`HoveredLink.previewSite`).
    func hoveredLink(_ document: DocumentToken, url: URL) async -> HoveredLink?

    func capture(_ request: CaptureRequest) async throws -> CaptureImage
    func captureProbe(_ page: PageID, directory: URL) async throws -> String
    func find(_ request: FindRequest)
    func output(_ request: OutputRequest)
    func cancelOutput(_ id: OutputID)

    func cancelBoostPick(_ target: SiteTarget)
    func pickBoostElement(_ target: SiteTarget) async throws -> String?
    func cancelSiteData(_ id: String)
    func clearSiteData(_ request: ClearSiteData) async -> ClearSiteDataResult
    func clearProfileData(_ request: ClearProfileData) async -> ClearProfileDataResult
    func setPictureInPicture(_ active: Bool, document: DocumentToken)
    func editExtension(_ id: String, edit: ExtensionEdit, context: BrowsingContext) async -> String?
    func extensionCatalog(context: BrowsingContext) async -> ExtensionCatalog
    func invokeExtension(_ id: String, target: SiteTarget) async -> String?
    func removeExtension(_ id: String, context: BrowsingContext, in page: PageID) async -> String?
    func installExtension(at directory: URL, context: BrowsingContext, in page: PageID) async -> String?
    func cancelDownload(_ id: DownloadID)
    /// Revokes synchronously. Final drain results arrive through the delegate.
    func disposeContext(_ request: ContextDisposal)

    /// AppleScript's `execute`: runs `script` in the page's main frame and answers its value as text (a string as it
    /// is, other values as JSON, nil for undefined or null). Throws when the page is not live or the script threw.
    func evaluateForResult(_ script: String, in page: PageID) async throws -> String?
    /// Help > Troubleshooting > Record Trace: starts a browser-wide trace (all processes). False when the engine
    /// cannot (already tracing, or no runtime).
    func beginTrace() async -> Bool
    /// Stops the trace and writes it as Chromium's JSON trace file at `file` (nil discards it). Answers the file.
    func endTrace(writingTo file: URL?) async -> URL?
    /// Open Task Manager: the browser's processes and what each costs now.
    func tasks() -> [EngineTask]
    /// The Task Manager's End Process. False when the task cannot be ended.
    func endTask(_ id: Int64) -> Bool

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
    /// AI adapter hook. The reply must be fenced to this document and must honor the user's AI settings.
    func engine(_ engine: any WebEngine, summarizeLink request: LinkPreviewRequest, reply: @escaping @MainActor (String?) -> Void)
    /// The language of a document that declares none, from a sample of its visible text (a BCP 47 code; nil when
    /// the sample does not say). The engine has no language recognizer of its own.
    func engine(_ engine: any WebEngine, recognizeLanguageOf sample: String, reply: @escaping @MainActor (String?) -> Void)
    func engine(_ engine: any WebEngine, find update: FindUpdate)
    func engine(_ engine: any WebEngine, output update: OutputUpdate)
    func engine(_ engine: any WebEngine, outputDestination prompt: OutputDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void)
    func engine(_ engine: any WebEngine, printOutput request: OutputRequest, pdf: URL, reply: @escaping @MainActor (PrintAnswer) -> Void)
    func engine(_ engine: any WebEngine, dismissOutput id: OutputID)
    func engine(_ engine: any WebEngine, download update: DownloadUpdate)
    func engine(_ engine: any WebEngine, destination prompt: DownloadDestinationPrompt,
                reply: @escaping @MainActor (DestinationAnswer) -> Void)
    func engine(_ engine: any WebEngine, dismissDestination ticket: DestinationTicket)
    func engine(_ engine: any WebEngine, contextDisposed result: ContextDisposalResult)

    func engine(_ engine: any WebEngine, permission prompt: SitePermissionPrompt, reply: @escaping @MainActor (SitePermission) -> Void)
    func engine(_ engine: any WebEngine, dismissPermission id: String)

    /// A page's main frame is about to navigate (CEF's OnBeforeBrowse, synchronous). False cancels it; the app
    /// uses this for Arc's "Open a Peek window when clicking on links to other sites" on Pinned and Favorites tabs
    /// (the Peek opens instead). Redirects are never asked about. F3.
    func engine(_ engine: any WebEngine, page: PageID, shouldNavigateTo url: URL, userGesture: Bool) -> Bool
}

extension WebEngine {
    public func selectedText(_ page: PageID) async -> String? { nil }
    public func checkSelection(_ page: PageID) {}
    public func cancelBoostPick(_ target: SiteTarget) {}
    public func pickBoostElement(_ target: SiteTarget) async throws -> String? { throw CocoaError(.featureUnsupported) }
    public func capture(_ request: CaptureRequest) async throws -> CaptureImage { throw CocoaError(.featureUnsupported) }
    public func captureProbe(_ page: PageID, directory: URL) async throws -> String { "unsupported" }
    public func isPageHostWindow(_ window: NSWindow) -> Bool { false }
    public func output(_ request: OutputRequest) {}
    public func cancelOutput(_ id: OutputID) {}
}

extension WebEngineDelegate {
    public func engine(_ engine: any WebEngine, summarizeLink request: LinkPreviewRequest, reply: @escaping @MainActor (String?) -> Void) { reply(nil) }
    public func engine(_ engine: any WebEngine, recognizeLanguageOf sample: String, reply: @escaping @MainActor (String?) -> Void) { reply(nil) }
    public func engine(_ engine: any WebEngine, page: PageID, keyHandling key: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling {
        KeyHandling(handled: self.engine(engine, page: page, key: key, stage: stage, pressID: pressID), shortcut: false)
    }
    public func engine(_ engine: any WebEngine, output update: OutputUpdate) {}
    public func engine(_ engine: any WebEngine, outputDestination prompt: OutputDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void) { reply(.ownerGone) }
    public func engine(_ engine: any WebEngine, printOutput request: OutputRequest, pdf: URL, reply: @escaping @MainActor (PrintAnswer) -> Void) { reply(.ownerGone) }
    public func engine(_ engine: any WebEngine, dismissOutput id: OutputID) {}
    public func engine(_ engine: any WebEngine, permission prompt: SitePermissionPrompt, reply: @escaping @MainActor (SitePermission) -> Void) { reply(.deny) }
    public func engine(_ engine: any WebEngine, dismissPermission id: String) {}
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
    public static let contextMenuWillOpen = Notification.Name("brk.page-context-menu.will-open")
    public static let contextMenuDidClose = Notification.Name("brk.page-context-menu.did-close")
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
    /// Extended Edit menu commands use the actual page adapter, rather than inherited no-op Cocoa selectors.
    open var editingMenuResponder: NSResponder? { nil }
    open func prepareEditingMenu() async {}
}

extension WebEngine {
    public func find(_ request: FindRequest) {
        if let id = request.requestID { delegate?.engine(self, find: .failed(id, .unavailable)) }
    }
    public func setPictureInPicture(_ active: Bool, document: DocumentToken) {}
    public func cancelSiteData(_ id: String) {}
    public func clearProfileData(_ request: ClearProfileData) async -> ClearProfileDataResult {
        ClearProfileDataResult(request: request, completed: [], error: "This engine has no profile storage")
    }
    public func clearSiteData(_ request: ClearSiteData) async -> ClearSiteDataResult {
        ClearSiteDataResult(request: request, completed: [], error: "This engine has no website storage")
    }
    public func editExtension(_ id: String, edit: ExtensionEdit, context: BrowsingContext) async -> String? { "This engine has no extensions" }
    public func extensionCatalog(context: BrowsingContext) async -> ExtensionCatalog { ExtensionCatalog(context: context, extensions: [], error: "This engine has no extensions") }
    public func invokeExtension(_ id: String, target: SiteTarget) async -> String? { "This engine has no extension actions" }
    public func removeExtension(_ id: String, context: BrowsingContext, in page: PageID) async -> String? { "This engine has no extensions" }
    public func installExtension(at directory: URL, context: BrowsingContext, in page: PageID) async -> String? { "This engine cannot install extensions" }
}

/// What `WebEngine.hoveredLink` reports.
public struct HoveredLink: Sendable, Equatable {
    public let frame: CGRect
    /// Arc's 5-Second Previews open without Shift on "certain websites" (the selectors in Arc 1.170: Hacker News
    /// story titles, Google's news headings, links in posts and cards on X).
    public let previewSite: Bool
    public init(frame: CGRect, previewSite: Bool) { self.frame = frame; self.previewSite = previewSite }
}

extension WebEngine {
    public func readAIPage(_ document: DocumentToken) async throws -> AIPageContent { throw AIPageFailure.unavailable }
    public func translateAIPage(_ content: AIPageContent, replacements: [AITextNode]) async throws -> Bool { throw AIPageFailure.unavailable }
    public func showAITranslation(_ document: DocumentToken, translated: Bool) async -> Bool { false }
    public func hoveredLink(_ document: DocumentToken, url: URL) async -> HoveredLink? { nil }
}

extension WebEngine {
    public var engineVersion: String? { nil }
}

/// One row of the Task Manager (CEF's `cef_task_info_t`): a browser, renderer, GPU, utility or extension process.
public struct EngineTask: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case browser, gpu, zygote, utility, renderer, `extension`, guest, plugin, sandboxHelper, dedicatedWorker, sharedWorker, serviceWorker, unknown }
    public let id: Int64
    public let kind: Kind
    public let title: String
    /// Percent of one core (Chrome's CPU column); nil when not measured yet.
    public let cpu: Double?
    /// Private memory footprint in bytes; nil when not measured.
    public let memory: Int64?
    public let gpuMemory: Int64?
    public let killable: Bool
    public init(id: Int64, kind: Kind, title: String, cpu: Double?, memory: Int64?, gpuMemory: Int64?, killable: Bool) {
        self.id = id; self.kind = kind; self.title = title; self.cpu = cpu; self.memory = memory; self.gpuMemory = gpuMemory; self.killable = killable
    }
}

/// Engines without scripting, tracing or a task manager (the stub, test fakes) answer that they have none.
extension WebEngine {
    public func evaluateForResult(_ script: String, in page: PageID) async throws -> String? { throw CocoaError(.featureUnsupported) }
    public func beginTrace() async -> Bool { false }
    public func endTrace(writingTo file: URL?) async -> URL? { nil }
    public func tasks() -> [EngineTask] { [] }
    public func endTask(_ id: Int64) -> Bool { false }
}
