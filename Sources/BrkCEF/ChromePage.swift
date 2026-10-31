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
    /// The request context it was created in; fixed for the page's life (a changed spec replaces the page).
    let context: BrowsingContext
    let incarnation: PageLedger.Incarnation
    let surface: EmbeddedSurface
    private let chrome: CefChromeBrowser
    unowned let engine: CEFEngine
    /// Pairs OnKeyEvent with its OnPreKeyEvent so both carry one PressID (rule on `PressID`).
    private var presses = PressCorrelator()
    private let contextMenu = PageContextMenu()
    private(set) lazy var linkPreviews = PageLinkPreviews(browser: browser, surface: surface, available: { [weak self] in
        guard let self else { return false }
        return self.engine.isLive(self) && self.surface.window?.isVisible == true && self.surface.window?.attachedSheet == nil && !self.surface.isHiddenOrHasHiddenAncestor
    }, summarize: { [weak self] request, reply in
        guard let self, self.engine.isLive(self), self.readyDocument == request.document else { reply(nil); return }
        self.engine.delegate?.engine(self.engine, summarizeLink: request, reply: reply)
    })
    private(set) lazy var find = PageFind(browser: browser) { [weak self] update in
        guard let self, self.engine.isLive(self) else { return }
        self.engine.findUpdated(update)
    }
    private(set) var audio: AudioObservation
    private var audioTargetTransport: CefDevTools?
    var audioObserverID: Int?
    var audioError: String?
    var mainDocument: MainDocumentState
    private var reloadSequence = ReloadSequence()
    private var expectedReloadBrowse: URL?
    private var currentLoadProgress: Double = 0
    private var progressSamples: [Double] = []
    var requestedReloads = 0
    var extensionDialogDecision: String?
    var extensionFileDialogCallbacks = 0
    var extensionInstallerDocument: DocumentToken?
    var approvedExtensionDirectory: (document: DocumentToken, directory: URL)?
    var websiteStyleOwner: (document: DocumentToken, id: String)?
    var websitePolicy = WebsitePolicy()
    var permissionRequests: [String: PagePermissionRequest] = [:] { didSet { refreshWebsitePolicy() } }
    var policyRevision: UInt64 = 0
    var websiteError: String?
    var frozen = false

    private func emit(_ events: [PageEvent]) {
        for event in events {
            if case .documentChanged(let document) = event {
                audio.document(document)
                if !audio.audible { engine.pageDidEmit(self, .audioChanged(false)) }
            }
            find.observe(event); engine.pageDidEmit(self, event)
        }
    }
    /// Latest projected policy; each operation freezes its own copy on its first callback.
    var downloadPolicy: DownloadPolicy
    private var desiredMuted: Bool
    /// CEF destroyed the host window (after OnBeforeClose); nothing of this page is left on screen.
    private(set) var windowDestroyed = false
    private let log = Logger(subsystem: "brk", category: "page")

    /// Where a new browser's host window first appears: off every screen, so nothing flashes before its views are
    /// moved into a card. The card then sets the real size.
    static let offscreenBounds = CGRect(x: -20_000, y: -20_000, width: 1024, height: 768)

    init(spec: PageSpec, url: URL, engine: CEFEngine, incarnation: PageLedger.Incarnation) {
        id = spec.id
        context = spec.context
        downloadPolicy = spec.downloadPolicy
        desiredMuted = spec.muted
        self.incarnation = incarnation
        audio = AudioObservation(browser: incarnation, context: spec.context)
        mainDocument = MainDocumentState(browser: incarnation)
        self.engine = engine
        surface = EmbeddedSurface(page: spec.id)
        var options = CefChromeBrowserOptions()
        options.isFrameless = true
        let initialRule = SiteOrigin(url).map { spec.websitePolicy.preferences.rule(for: $0) } ?? SiteRule()
        let list = spec.websitePolicy.preferences.blockingRules ?? .builtIn
        options.requestRules = CefRequestRules(enabled: initialRule.blocking, hosts: list.blockedHosts, paths: list.blockedPathPrefixes)
        options.showsChromeToolbar = false
        options.backgroundColor = .white
        options.initialBounds = Self.offscreenBounds
        // The page's request context: nil (the runtime's cache) for the default profile, a profile's persistent
        // context, or the shared incognito one (W2-2 and W2-3 prove the isolation on the real engine).
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
            self.setMuted(self.desiredMuted)
            self.engine.pageReadyForFocus(self)
        }
        surface.adopt(chrome)
        linkPreviews.setEnabled(spec.hoverPreviews)
        applyWebsitePolicy(spec.websitePolicy)
    }

    func resolveAudioTarget() async {
        guard engine.isLive(self), browser.id > 0, audio.target == nil, audioTargetTransport == nil,
              let transport = CefDevTools(browser: browser) else { return }
        audioTargetTransport = transport
        defer { transport.invalidate(); audioTargetTransport = nil }
        do {
            let data = try await transport.call("Target.getTargetInfo")
            guard engine.isLive(self), let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = result["targetInfo"] as? [String: Any], info["type"] as? String == "page",
                  let target = info["targetId"] as? String, !target.isEmpty else { return }
            audio.bind(target)
        } catch { audioError = String(describing: error) }
    }

    func applyAudio(_ reading: ChromeAudibility.Reading, ticket: AudioObservation.Ticket, observer: Int) {
        let changed = audio.audible != reading.audible
        guard engine.isLive(self), reading.target == ticket.target, audio.accept(reading.audible, tab: reading.tab, for: ticket) else { return }
        audioObserverID = observer
        audioError = nil
        if changed { emit([.audioChanged(reading.audible)]) }
    }

    func audioUnavailable(_ error: String) {
        audioError = error
        if let ticket = audio.ticket, let tab = audio.tab, audio.audible,
           audio.accept(false, tab: tab, for: ticket) { emit([.audioChanged(false)]) }
    }

    func setMuted(_ value: Bool) {
        desiredMuted = value
        if chrome.browser.isAudioMuted != value { chrome.browser.isAudioMuted = value }
    }

    var browser: CefBrowser { chrome.browser }
    var readyDocument: DocumentToken? { mainDocument.readyDocument }

    var facts: PageFacts {
        var facts = PageFacts(surfaceFrame: surface.frameInWindow, embeddedViews: surface.embeddedViewClasses,
                  browserID: Int(chrome.browser.id), hostWindowNumber: chrome.nsWindow?.windowNumber,
                  hasKeyboardFocus: surface.containsFirstResponder, audioMuted: chrome.browser.isAudioMuted,
                  audioTargetID: audio.target, audioTabID: audio.tab, audioObserverID: audioObserverID, audioError: audioError)
        facts.loadProgressSamples = progressSamples
        facts.linkPreviewError = linkPreviews.lastFailure
        facts.linkPreviewFrameCount = linkPreviews.frameCount
        facts.linkPreviewTitle = linkPreviews.title
        facts.linkPreviewURL = linkPreviews.destination
        facts.requestedReloads = requestedReloads
        facts.extensionDialogDecision = extensionDialogDecision
        facts.extensionFileDialogCallbacks = extensionFileDialogCallbacks
        facts.websiteFrozen = frozen
        facts.websitePolicyError = websiteError
        return facts
    }

    /// Idempotent: views back first (never close a browser whose views are in our window), then force-close.
    /// OnBeforeClose arrives later as `browserDidClose` -> `engine.pageDidClose(self)`.
    func close() {
        audio.invalidate(retire: true)
        audioTargetTransport?.invalidate()
        find.invalidate()
        linkPreviews.stop()
        reloadSequence.cancel()
        cancelPermissions()
        contextMenu.cancel()
        browser.closeDevTools()
        surface.returnViews()
        chrome.browser.close(force: true)
    }

    func park() { linkPreviews.stop(); reloadSequence.cancel(); approvedExtensionDirectory = nil; cancelPermissions(); audio.invalidate(retire: true); audioTargetTransport?.invalidate(); find.invalidate(); contextMenu.cancel(); surface.park() }

    /// Focus the attached input view without activating its window. Native layout repair also runs in inactive
    /// windows; making one key here would take focus from a different window's editor.
    func takeFocus() {
        guard let window = surface.window else {
            log.notice("page \(self.id.description, privacy: .public): takeFocus with no window")
            return
        }
        let target = surface.keyboardTarget
        let accepted = window.makeFirstResponder(target)
        chrome.browser.setFocus(true)
        log.notice("page \(self.id.description, privacy: .public): takeFocus -> \(NSStringFromClass(type(of: target)), privacy: .public) accepted=\(accepted, privacy: .public) firstResponder=\(window.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil", privacy: .public)")
    }

    func dropFocus() { chrome.browser.setFocus(false) }

    /// Explicit browser actions start a new attempt, even for URLs such as about:blank that can skip BeforeBrowse.
    func prepareNavigation() {
        expectedReloadBrowse = nil
        reloadSequence.cancel()
        prepareDocumentNavigation()
    }

    private func prepareDocumentNavigation() {
        currentLoadProgress = 0
        approvedExtensionDirectory = nil
        cancelPermissions()
        audio.navigationRequested()
        engine.pageDidEmit(self, .audioChanged(false))
        contextMenu.cancel()
        mainDocument.prepareNavigation()
    }

    /// Construction can deliver CEF's first progress callback before the engine publishes browserCreated.
    func reportInitialLoading() {
        engine.pageDidEmit(self, .loadingChanged(isLoading: browser.isLoading, canGoBack: browser.canGoBack, canGoForward: browser.canGoForward))
        if browser.isLoading { engine.pageLoadProgress(self, progress: currentLoadProgress) }
    }

    func prepareStop() { reloadSequence.cancel(); emit(mainDocument.stopped()) }
    func reportZoom() { engine.pageDidEmit(self, .zoomChanged(BrowserZoom.percentage(level: browser.zoomLevel))) }
    func browser(_ b: CefBrowser, didChangeFullscreen isFullscreen: Bool) {
        engine.pageDidEmit(self, .fullscreenChanged(isFullscreen))
    }

    func browser(_ b: CefBrowser, findResult identifier: Int, count: Int, ordinal: Int, final: Bool) {
        find.nativeResult(id: identifier, count: count, ordinal: ordinal, final: final)
    }
    func browser(_ b: CefBrowser, rendererMessage: CefRendererMessage) { find.receive(rendererMessage) }
    func requestReload(ignoringCache: Bool) {
        requestedReloads += 1
        if let request = reloadSequence.request(ignoringCache: ignoringCache, after: mainDocument.lastSequence) { issueReload(request) }
    }

    private func issueReload(_ request: ReloadSequence.Request) {
        guard engine.isLive(self), reloadSequence.current == request else { return }
        guard mainDocument.lastSequence == request.afterDocumentSequence else { reloadSequence.cancel(); return }
        prepareDocumentNavigation()
        expectedReloadBrowse = browser.url
        browser.reload(ignoreCache: request.ignoringCache)
    }


    // MARK: CefBrowserDelegate -> PageEvent

    func browser(_ b: CefBrowser, presentContextMenu menu: CefMenuModel, params: CefContextMenuParams, callback: CefRunContextMenuCallback) -> Bool {
        contextMenu.show(menu, at: CGPoint(x: params.x, y: params.y), in: surface, callback: callback) { [weak self] in
            guard let self else { return false }; return self.engine.isLive(self) && !self.surface.isHiddenOrHasHiddenAncestor
        }
        return true
    }

    func browserContextMenuDidClose(_ b: CefBrowser) { contextMenu.cancel() }

    func browser(_ b: CefBrowser, didChangeURL url: URL?) {
        emit(mainDocument.addressChanged(url, loading: b.isLoading))
    }

    func browser(_ b: CefBrowser, didStartMainDocument url: URL?) {
        emit(mainDocument.started(url))
        if b.isLoading { engine.pageLoadProgress(self, progress: currentLoadProgress) }
    }

    func browser(_ b: CefBrowser, didFinishMainDocument url: URL?) {
        setMuted(desiredMuted)
        emit(mainDocument.finished(url))
        reportZoom()
        refreshWebsitePolicy()
        if case .ready(let document) = mainDocument.availability,
           let request = reloadSequence.finished(documentSequence: document.sequence) {
            Task { @MainActor [weak self] in self?.issueReload(request) }
        }
    }

    func browser(_ b: CefBrowser, didChangeTitle title: String) {
        if case .profile = context { log.debug("page title changed") }
        engine.pageDidEmit(self, .titleChanged(title))
    }

    func browser(_ b: CefBrowser, didChangeFavicon urls: [URL]) { engine.pageDidEmit(self, .faviconChanged(urls.first)) }

    func browser(_ b: CefBrowser, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        engine.pageDidEmit(self, .loadingChanged(isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward))
        emit(mainDocument.loadingChanged(isLoading))
        if isLoading { engine.pageLoadProgress(self, progress: currentLoadProgress) }
        else { currentLoadProgress = 0 }
    }

    func browser(_ b: CefBrowser, didChangeProgress progress: Double) {
        guard progress.isFinite else { return }
        currentLoadProgress = progress
        progressSamples.append(progress)
        if progressSamples.count > 24 { progressSamples.removeFirst() }
        engine.pageLoadProgress(self, progress: progress)
    }

    func browser(_ b: CefBrowser, didFailLoad code: Int, errorText: String, failedURL: String) {
        reloadSequence.cancel()
        emit(mainDocument.loadFailed(code: code, description: errorText, url: failedURL))
    }

    func browser(_ b: CefBrowser, renderProcessDidTerminate reason: CefTerminationReason, errorCode: Int) {
        reloadSequence.cancel()
        cancelPermissions()
        emit(mainDocument.rendererGone())
        engine.pageRendererTerminated(self)
    }

    func browserDidGainFocus(_ b: CefBrowser) { engine.pageDidEmit(self, .gainedFocus); reportZoom() }

    private func openMetadata(_ request: CefWindowOpenRequest) -> PageOpenMetadata {
        PageOpenMetadata(rawDisposition: request.rawDisposition, userGesture: request.userGesture,
                         sourceFrame: request.sourceFrame, sourceIsMainFrame: request.sourceIsMainFrame,
                         targetFrame: request.frameName, popupID: request.popupID, x: request.features.x,
                         y: request.features.y, width: request.features.width, height: request.features.height)
    }

    /// Every open becomes a tab the domain creates (or refuses); CEF never makes its own popup window.
    func browser(_ b: CefBrowser, decideWindowOpenFor request: CefWindowOpenRequest) -> CefWindowOpenAction {
        if let url = request.targetURL {
            let disposition: OpenDisposition
            switch request.disposition {
            case .newBackgroundTab: disposition = .backgroundTab
            case .newPopup: disposition = .popup
            case .newWindow: disposition = .newWindow
            default: disposition = .foregroundTab
            }
            engine.pageDidEmit(self, .openRequested(url, disposition, metadata: openMetadata(request)))
        }
        return .handled
    }

    /// A link opened with a modifier (Cmd+click) arrives here (CEF's OnOpenURLFromTab), not as a popup. Handled the
    /// same way: a tab the domain creates; unhandled, CEF would make a Chrome-runtime browser without a client that
    /// nothing closes and that crashes cef_shutdown. The wrapper does not forward the disposition on this path, so
    /// every such open is a background tab (Cmd+click's); Cmd+Shift+click is not told apart.
    func browser(_ b: CefBrowser, openURLFromTab request: CefWindowOpenRequest) -> Bool {
        guard let url = request.targetURL else { return true }
        let disposition: OpenDisposition = request.disposition == .newBackgroundTab ? .backgroundTab : (request.disposition == .newWindow ? .newWindow : .foregroundTab)
        engine.pageDidEmit(self, .openRequested(url, disposition, metadata: openMetadata(request)))
        return true
    }

    func browser(_ b: CefBrowser, didRequestNewTab url: URL?) -> Bool {
        guard let url else { return false }
        engine.pageDidEmit(self, .openRequested(url, .backgroundTab))
        return true
    }

    func browserDidClose(_ b: CefBrowser) { cancelPermissions(); audio.invalidate(retire: true); audioTargetTransport?.invalidate(); find.invalidate(nativeAlive: false); contextMenu.cancel(); engine.pageDidClose(self) }

    /// A main-frame navigation the page is about to make. Redirects always go through; the rest ask the app
    /// (`WebEngineDelegate.shouldNavigateTo`), which cancels when a Peek opens instead.
    func browser(_ b: CefBrowser, decidePolicyForNavigation url: URL?, isRedirect: Bool, userGesture: Bool) -> CefNavigationDecision {
        guard let url else { return .allow }
        guard isRedirect || engine.pageShouldNavigate(self, to: url, userGesture: userGesture) else { return .cancel }
        if !isRedirect, reloadSequence.current != nil {
            if expectedReloadBrowse == url { expectedReloadBrowse = nil }
            else { reloadSequence.cancel(); expectedReloadBrowse = nil }
        }
        if !isRedirect { currentLoadProgress = 0 }
        cancelPermissions()
        configureRequestFilter(url)
        contextMenu.cancel()
        emit(mainDocument.allowed(url, redirect: isRedirect))
        return .allow
    }

    func browser(_ b: CefBrowser, download: CefDownload, suggestedName: String, decision: CefDownloadDecisionCallback) {
        engine.download(self, item: download, name: suggestedName, decision: decision)
    }
    func browser(_ b: CefBrowser, download: CefDownload, control: CefDownloadControl?) {
        engine.download(self, item: download, control: control)
    }

    /// CEF's two key callbacks. Before the page (`OnPreKeyEvent`) the id is minted from the event being dispatched;
    /// after the page (`OnKeyEvent`, only when the page did not consume it) the id is the partner's, paired by
    /// `PressCorrelator`. Modifier-only keys and character events are not routed (Control reaches BrkApp as
    /// `WindowEvent.modifiersChanged` from the window's `flagsChanged` events).
    func browser(_ b: CefBrowser, preKeyEvent event: CefKeyEvent) -> CefKeyDisposition { route(event, before: true) }
    func browser(_ b: CefBrowser, handleKeyEvent event: CefKeyEvent, isBeforePage: Bool) -> Bool { route(event, before: isBeforePage).handled }
    private func route(_ event: CefKeyEvent, before isBeforePage: Bool) -> CefKeyDisposition {
        guard let press = KeyTranslation.press(from: event) else { return CefKeyDisposition(handled: false, shortcut: false) }
        // Monotonic; only the correlation timeout reads it, never app time (the app clock stays in BrkApp/Clock.swift).
        let uptime = ProcessInfo.processInfo.systemUptime
        let now = Instant(milliseconds: Int64(uptime * 1000))
        let pressID: PressID
        if isBeforePage {
            pressID = PressID(eventTimestamp: NSApp.currentEvent?.timestamp ?? uptime)
        } else {
            pressID = presses.afterPage(press, at: now) ?? PressID(eventTimestamp: uptime)
        }
        let result = engine.pageKeyHandling(self, press, stage: isBeforePage ? .beforePage : .afterPage, pressID: pressID)
        var handled = result.handled
        // Embedded Chrome's native responder does not execute these unhandled editing accelerators.
        // Renderer prevention and any user-remapped app command have already had their turn.
        if !isBeforePage, !handled, press.phase == .down, event.isEditableFieldFocused, press.chord.key == .z {
            if press.chord.modifiers == .command { browser.undo(); handled = true }
            else if press.chord.modifiers == [.command, .shift] { browser.redo(); handled = true }
        }
        if isBeforePage { presses.beforePage(press, id: pressID, handled: handled, at: now) }
        if press.phase == .down, !press.chord.modifiers.isDisjoint(with: [.command, .control]) || press.chord.key == .escape {
            log.notice("cef.\(isBeforePage ? "pre" : "post", privacy: .public) page \(self.id.description, privacy: .public) \(press.chord.description, privacy: .public) native=\(event.nativeKeyCode, privacy: .public) editable=\(event.isEditableFieldFocused, privacy: .public) \(pressID.description, privacy: .public) consumed=\(handled, privacy: .public)")
        }
        return CefKeyDisposition(handled: handled, shortcut: result.shortcut)
    }
}

