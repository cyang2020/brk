import AppKit
import BrkBase
import BrkEngine
import CefKit
import os

/// One page: a frameless Chrome-runtime browser (`CefChromeBrowser`), the CEF delegate that turns its callbacks into
/// `PageEvent`s and key presses, and the surface its views are embedded in. One instance per incarnation of a page
/// id (`PageLedger`): a reused id gets a new ChromePage while the old one is still closing.
@MainActor
final class ChromePage: CefBrowserDelegate {
    let id: PageID
    let incarnation: PageLedger.Incarnation
    let surface: EmbeddedSurface
    private let chrome: CefChromeBrowser
    private unowned let engine: CEFEngine
    /// Pairs OnKeyEvent with its OnPreKeyEvent so both carry one PressID (rule on `PressID`).
    private var presses = PressCorrelator()
    /// CEF destroyed the host window (after OnBeforeClose); nothing of this page is left on screen.
    private(set) var windowDestroyed = false
    private let log = Logger(subsystem: "brk", category: "page")

    /// Where a new browser's host window first appears: off every screen, so nothing flashes before its views are
    /// moved into a card. The card then sets the real size.
    static let offscreenBounds = CGRect(x: -20_000, y: -20_000, width: 1024, height: 768)

    init(spec: PageSpec, url: URL, engine: CEFEngine, incarnation: PageLedger.Incarnation) {
        id = spec.id
        self.incarnation = incarnation
        self.engine = engine
        surface = EmbeddedSurface(page: spec.id)
        var options = CefChromeBrowserOptions()
        options.isFrameless = true
        options.showsChromeToolbar = false
        options.backgroundColor = .white
        options.initialBounds = Self.offscreenBounds
        // The page's request context: a profile's persistent context or the shared incognito one (F2 proves it).
        options.profile = engine.profile(for: spec.context)
        chrome = CefChromeBrowser.create(url: url, options: options, delegate: nil)
        chrome.browser.delegate = self
        chrome.onWindowDestroyed = { [weak self] in
            guard let self else { return }
            self.windowDestroyed = true
            self.engine.pageWindowDidClose(self)
        }
        surface.onReadyForFocus = { [weak self] in
            guard let self else { return }
            self.engine.pageReadyForFocus(self)
        }
        surface.adopt(chrome)
    }

    var browser: CefBrowser { chrome.browser }

    var facts: PageFacts {
        PageFacts(surfaceFrame: surface.frameInWindow, embeddedViews: surface.embeddedViewClasses,
                  browserID: Int(chrome.browser.id), hostWindowNumber: chrome.nsWindow?.windowNumber,
                  hasKeyboardFocus: surface.containsFirstResponder)
    }

    /// Idempotent: views back first (never close a browser whose views are in our window), then force-close.
    /// OnBeforeClose arrives later as `browserDidClose` -> `engine.pageDidClose(self)`.
    func close() {
        surface.returnViews()
        chrome.browser.close(force: true)
    }

    /// Keyboard focus into the page: our window (never the host) becomes key and Chromium's input view inside the
    /// surface becomes first responder; Chromium is told it has focus (the spike's focus sequence, u2-bar).
    func takeFocus() {
        guard let window = surface.window else {
            log.notice("page \(self.id.description, privacy: .public): takeFocus with no window")
            return
        }
        if !window.isKeyWindow { window.makeKey() }
        let target = surface.keyboardTarget
        let accepted = window.makeFirstResponder(target)
        chrome.browser.setFocus(true)
        log.notice("page \(self.id.description, privacy: .public): takeFocus -> \(NSStringFromClass(type(of: target)), privacy: .public) accepted=\(accepted, privacy: .public) firstResponder=\(window.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil", privacy: .public)")
    }

    func dropFocus() { chrome.browser.setFocus(false) }

    // MARK: CefBrowserDelegate -> PageEvent

    func browser(_ b: CefBrowser, didChangeURL url: URL?) {
        if let url { engine.pageDidEmit(self, .committed(url)) }
    }

    func browser(_ b: CefBrowser, didChangeTitle title: String) {
        log.notice("page \(self.id.description, privacy: .public) title: \(title, privacy: .public)")
        engine.pageDidEmit(self, .titleChanged(title))
    }

    func browser(_ b: CefBrowser, didChangeFavicon urls: [URL]) { engine.pageDidEmit(self, .faviconChanged(urls.first)) }

    func browser(_ b: CefBrowser, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        engine.pageDidEmit(self, .loadingChanged(isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward))
    }

    func browser(_ b: CefBrowser, didFailLoad code: Int, errorText: String, failedURL: String) {
        // ERR_ABORTED (-3) is a navigation replaced by another one, not a failure.
        guard code != -3 else { return }
        engine.pageDidEmit(self, .loadFailed(code: code, description: errorText, url: failedURL))
    }

    func browser(_ b: CefBrowser, renderProcessDidTerminate reason: CefTerminationReason, errorCode: Int) {
        engine.pageDidEmit(self, .rendererGone)
    }

    func browserDidGainFocus(_ b: CefBrowser) { engine.pageDidEmit(self, .gainedFocus) }

    /// Every open becomes a tab the domain creates (or refuses); CEF never makes its own popup window.
    func browser(_ b: CefBrowser, decideWindowOpenFor request: CefWindowOpenRequest) -> CefWindowOpenAction {
        if let url = request.targetURL {
            let disposition: OpenDisposition
            switch request.disposition {
            case .newBackgroundTab: disposition = .backgroundTab
            case .newPopup: disposition = .popup
            default: disposition = .foregroundTab
            }
            engine.pageDidEmit(self, .openRequested(url, disposition))
        }
        return .handled
    }

    /// A link opened with a modifier (Cmd+click) arrives here (CEF's OnOpenURLFromTab), not as a popup. Handled the
    /// same way: a tab the domain creates; unhandled, CEF would make a Chrome-runtime browser without a client that
    /// nothing closes and that crashes cef_shutdown. The wrapper does not forward the disposition on this path, so
    /// every such open is a background tab (Cmd+click's); Cmd+Shift+click is not told apart.
    func browser(_ b: CefBrowser, didRequestNewTab url: URL?) -> Bool {
        guard let url else { return false }
        engine.pageDidEmit(self, .openRequested(url, .backgroundTab))
        return true
    }

    func browserDidClose(_ b: CefBrowser) { engine.pageDidClose(self) }

    /// A main-frame navigation the page is about to make. Redirects always go through; the rest ask the app
    /// (`WebEngineDelegate.shouldNavigateTo`), which cancels when a Peek opens instead.
    func browser(_ b: CefBrowser, decidePolicyForNavigation url: URL?, isRedirect: Bool, userGesture: Bool) -> CefNavigationDecision {
        guard let url, !isRedirect else { return .allow }
        return engine.pageShouldNavigate(self, to: url, userGesture: userGesture) ? .allow : .cancel
    }

    // TODO(F5): downloads. `browser(_:decidePolicyForDownload:suggestedName:)` asks the engine's delegate
    // (`decideDownload`) and answers `.allow(destination:)` or `.deny`; `browser(_:downloadDidProgress:)` emits
    // `PageEvent.download(id, .progress/.finished/.cancelled)` with `DownloadID("\(browser.id)-\(download.id)")`.

    /// CEF's two key callbacks. Before the page (`OnPreKeyEvent`) the id is minted from the event being dispatched;
    /// after the page (`OnKeyEvent`, only when the page did not consume it) the id is the partner's, paired by
    /// `PressCorrelator`. Modifier-only keys and character events are not routed (Control reaches BrkApp as
    /// `WindowEvent.modifiersChanged` from the window's `flagsChanged` events).
    func browser(_ b: CefBrowser, handleKeyEvent event: CefKeyEvent, isBeforePage: Bool) -> Bool {
        guard let press = KeyTranslation.press(from: event) else { return false }
        // Monotonic; only the correlation timeout reads it, never app time (the app clock stays in BrkApp/Clock.swift).
        let uptime = ProcessInfo.processInfo.systemUptime
        let now = Instant(milliseconds: Int64(uptime * 1000))
        let pressID: PressID
        if isBeforePage {
            pressID = PressID(eventTimestamp: NSApp.currentEvent?.timestamp ?? uptime)
            if press.phase == .down { presses.beforePage(press.chord, id: pressID, at: now) }
        } else {
            pressID = presses.afterPage(press.chord, at: now) ?? PressID(eventTimestamp: uptime)
        }
        let handled = engine.pageKey(self, press, stage: isBeforePage ? .beforePage : .afterPage, pressID: pressID)
        if press.phase == .down, !press.chord.modifiers.isDisjoint(with: [.command, .control]) || press.chord.key == .escape {
            log.notice("cef.\(isBeforePage ? "pre" : "post", privacy: .public) page \(self.id.description, privacy: .public) \(press.chord.description, privacy: .public) native=\(event.nativeKeyCode, privacy: .public) editable=\(event.isEditableFieldFocused, privacy: .public) \(pressID.description, privacy: .public) consumed=\(handled, privacy: .public)")
        }
        return handled
    }
}
