import AppKit
import BrkBase
import BrkEngine
import CefKit

/// One page: a frameless Chrome-runtime browser (`CefChromeBrowser`), the CEF delegate that turns its callbacks into
/// `PageEvent`s and key presses, and the surface its views are embedded in.
@MainActor
final class ChromePage: CefBrowserDelegate {
    let id: PageID
    let surface: EmbeddedSurface
    private let chrome: CefChromeBrowser
    private unowned let engine: CEFEngine
    /// Pairs OnKeyEvent with its OnPreKeyEvent so both carry one PressID (rule on `PressID`).
    private var presses = PressCorrelator()

    init(spec: PageSpec, url: URL, engine: CEFEngine) {
        // TODO(W2): options: isFrameless = true, showsChromeToolbar = false, backgroundColor = .white,
        // initialBounds = the surface's screen frame if it is already in a window (else an off-screen rect).
        // chrome = CefChromeBrowser.create(url:options:delegate: self); surface.adopt(chrome) starts embedding.
        fatalError("not implemented")
    }

    var browser: CefBrowser { chrome.browser }

    var facts: PageFacts {
        PageFacts(surfaceFrame: surface.frameInWindow, embeddedViews: surface.embeddedViewClasses,
                  browserID: Int(chrome.browser.id), hostWindowNumber: chrome.nsWindow?.windowNumber,
                  hasKeyboardFocus: surface.containsFirstResponder)
    }

    func close() {
        surface.returnViews()
        chrome.browser.close(force: true)
    }

    // MARK: CefBrowserDelegate -> PageEvent

    func browser(_ b: CefBrowser, didChangeURL url: URL?) {
        if let url { engine.pageDidEmit(self, .committed(url)) }
    }

    func browser(_ b: CefBrowser, didChangeTitle title: String) { engine.pageDidEmit(self, .titleChanged(title)) }

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

    func browser(_ b: CefBrowser, decideWindowOpenFor request: CefWindowOpenRequest) -> CefWindowOpenAction {
        // Every open becomes a tab the domain creates (or refuses); CEF never makes its own popup window.
        // TODO(W2): map request.disposition: .newBackgroundTab -> .backgroundTab; .newPopup -> .popup; else
        // .foregroundTab. Emit .openRequested(url, disposition) when targetURL != nil.
        return .handled
    }

    func browserDidClose(_ b: CefBrowser) { engine.pageDidClose(self) }

    func browser(_ b: CefBrowser, handleKeyEvent event: CefKeyEvent, isBeforePage: Bool) -> Bool {
        // TODO(W2): guard let press = KeyTranslation.press(from: event) else { return false }  (chars, unknown keys)
        // Modifier-only keys (Control up/down) -> return false; they reach BrkApp as WindowEvent.modifiersChanged
        // from the window's flagsChanged events (one source for both focus cases).
        // let now = Instant(milliseconds: Int64(ProcessInfo.processInfo.systemUptime * 1000))  // monotonic; only the
        //     correlation timeout reads it, never app time (the app clock stays in BrkApp/Clock.swift)
        // if isBeforePage {
        //     let id = PressID(eventTimestamp: NSApp.currentEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        //     if press.phase == .down { presses.beforePage(press.chord, id: id, at: now) }
        //     return engine.pageKey(self, press, stage: .beforePage, pressID: id)
        // } else {
        //     let id = presses.afterPage(press.chord, at: now) ?? PressID(eventTimestamp: ProcessInfo.processInfo.systemUptime)
        //     return engine.pageKey(self, press, stage: .afterPage, pressID: id)
        // }
        fatalError("not implemented")
    }
}
