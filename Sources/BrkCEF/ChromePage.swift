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
    let isAIReader: Bool
    let context: BrowsingContext
    let incarnation: PageLedger.Incarnation
    let surface: EmbeddedSurface
    private let chrome: CefChromeBrowser
    unowned let engine: CEFEngine
    /// Pairs OnKeyEvent with its OnPreKeyEvent so both carry one PressID (rule on `PressID`).
    private var presses = PressCorrelator()
    private var fullscreenTransition = ChromeFullscreenTransition()
    private var keyReceipts: [PageKeyReceipt] = []
    var sourceWindow: NSWindow?
    var sourceRequest: UInt64 = 0
    var developerResult: String?
    var toolsBrowser: CefBrowser?
    var requestedDeveloperPanel: String?
    var developerPanelTask: Task<Void, Never>?
    var developerTransport: CefDevTools?
    private var popupRequests: [PageOpenMetadata] = []
    var cast: PageCast?
    var drainingCasts: [PageCast] = []
    private func recordKey(_ receipt: PageKeyReceipt) {
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        keyReceipts.append(receipt)
        if keyReceipts.count > 64 { keyReceipts.removeFirst(keyReceipts.count - 64) }
    }
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
    private(set) var mediaPlayers: [MediaPlayer] = []
    private var mediaError: String?
    private var mediaOperationError: String?
    var audioError: String?
    var documentPiPSource: DocumentToken?
    var documentPiPActive = false
    private(set) var captureRevision: UInt64 = 0
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
    var boostPolicy = BoostPolicy()
    var boostRevision: UInt64 = 0
    var boostDocument: DocumentToken?
    var boostOwner = UUID().uuidString
    var boostExecuted: Set<String> = []
    var boostError: String?
    var boostPickerGeneration: UInt64 = 0
    var boostPickerWorld: (target: SiteTarget, id: Int, token: String)?
    var permissionRequests: [String: PagePermissionRequest] = [:] { didSet { refreshWebsitePolicy() } }
    var policyRevision: UInt64 = 0
    var websiteError: String?
    /// The automatic dark mode last sent to this page's DevTools session, and for which document (nil: never sent).
    var autoDark: (document: DocumentToken, enabled: Bool)?
    var frozen = false
    var pictureInPictureDocument: DocumentToken?

    private func emit(_ events: [PageEvent]) {
        for event in events {
            if case .documentChanged(let document) = event {
                mediaPlayers = []; mediaError = nil; mediaOperationError = nil
                fullscreenTransition.cancelPending()
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
        isAIReader = spec.isAIReader
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
        options.prepareNativeWindow = { HostWindows.adopt($0, parent: nil) }
        let initialRule = SiteOrigin(url).map { spec.websitePolicy.preferences.rule(for: $0) } ?? SiteRule()
        let list = spec.websitePolicy.preferences.blockingRules ?? .builtIn
        options.requestRules = CefRequestRules(enabled: initialRule.blocking, hosts: list.blockedHosts, paths: list.blockedPathPrefixes, urlPrefixes: list.blockedURLPrefixes ?? [])
        options.showsChromeToolbar = false
        options.prepareWindow = { HostWindows.adopt($0, parent: nil) }
        options.backgroundColor = .white
        options.initialBounds = Self.offscreenBounds
        // The page's request context: nil (the runtime's cache) for the default profile, a profile's persistent
        // context, or the shared incognito one (W2-2 and W2-3 prove the isolation on the real engine).
        options.profile = engine.profile(for: spec.context)
        chrome = CefChromeBrowser.create(url: url, options: options, delegate: nil)
        if let host = chrome.nsWindow { HostWindows.adopt(host,parent:nil) }
        chrome.browser.delegate = self
        chrome.onFullscreenTransition = { [weak self] nativeFullscreen, completed in
            guard let self else { return }
            self.surface.nativeFullscreenChanged(nativeFullscreen, completed: completed)
            if let fullscreen = self.fullscreenTransition.nativeChanged(fullscreen: nativeFullscreen, completed: completed) {
                self.emitFullscreen(fullscreen)
            }
        }
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
        applyBoostPolicy(spec.boostPolicy)
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
        if let document = readyDocument {
            let error = reading.mediaError ?? mediaOperationError
            if mediaPlayers != reading.players || mediaError != error {
                mediaPlayers = reading.players; mediaError = error
                engine.pageDidEmit(self, .mediaChanged(document, mediaPlayers, error: error))
            }
        }
        audioObserverID = observer
        audioError = nil
        if changed { emit([.audioChanged(reading.audible)]); refreshWebsitePolicy() }
    }

    func mediaControlFinished(_ error: String?) {
        mediaOperationError = error
        mediaError = error
        if let document = readyDocument { engine.pageDidEmit(self, .mediaChanged(document, mediaPlayers, error: error)) }
    }

    func audioUnavailable(_ error: String) {
        if !mediaPlayers.isEmpty {
            mediaPlayers = []
            if let document = readyDocument { engine.pageDidEmit(self, .mediaChanged(document, [], error: error)) }
        }
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
        facts.nativeFullscreenTransitioning = fullscreenTransition.isTransitioning
        facts.requestedReloads = requestedReloads
        facts.extensionDialogDecision = extensionDialogDecision
        facts.extensionFileDialogCallbacks = extensionFileDialogCallbacks
        facts.websiteFrozen = frozen
        facts.websitePolicyError = websiteError
        facts.boostError = boostError
        facts.keyReceipts = keyReceipts
        facts.hasDevTools = browser.hasDevTools
        facts.auxiliaryBrowsers = browser.nativeAuxiliaries.map { Int($0.browser.id) }
        facts.auxiliaryWindows = browser.nativeAuxiliaries.compactMap { $0.browser.nativeView?.window?.windowNumber }
        facts.popupRequests = popupRequests
        facts.developerResult = developerResult
        facts.castSinkNotifications = cast?.router?.sinkNotifications
        facts.castRouteNotifications = cast?.router?.routeNotifications
        facts.castSinks = cast?.router?.sinks.map(\.name)
        facts.castRoutes = cast?.router?.routes
        facts.castResult = cast?.router?.lastResult
        facts.castAvailable = cast.map { $0.router != nil }
        facts.castError = cast?.unavailableReason ?? cast?.router?.lastError
        facts.castSourceSupported = cast?.router?.sourceSupported
        if let number = cast?.visibleWindowNumber { facts.auxiliaryWindows?.append(number) }
        if let sourceWindow, sourceWindow.isVisible { facts.auxiliaryWindows?.append(sourceWindow.windowNumber) }
        return facts
    }

    /// Idempotent: views back first (never close a browser whose views are in our window), then force-close.
    /// OnBeforeClose arrives later as `browserDidClose` -> `engine.pageDidClose(self)`.
    func close() {
        captureRevision &+= 1
        closeDocumentPiP()
        fullscreenTransition.cancelPending()
        audio.invalidate(retire: true)
        audioTargetTransport?.invalidate()
        find.invalidate()
        linkPreviews.stop()
        reloadSequence.cancel()
        cancelPermissions()
        contextMenu.cancel()
        closeDeveloperWindows()
        stopCasting()
        browser.closeNativeAuxiliaries()
        browser.closeDevTools()
        surface.returnViews()
        chrome.browser.close(force: true)
    }

    func park() { fullscreenTransition.cancelPending(); reloadSequence.cancel(); approvedExtensionDirectory = nil; cancelPermissions(); audio.invalidate(retire: true); audioTargetTransport?.invalidate(); find.invalidate(); contextMenu.cancel(); closeDeveloperWindows(); stopCasting(); browser.closeNativeAuxiliaries(); captureRevision &+= 1; browser.executeJavaScript("if(document.pictureInPictureElement)document.exitPictureInPicture().catch(()=>{});"); closeDocumentPiP(); linkPreviews.stop(); surface.park() }

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
        fullscreenTransition.cancelPending()
        expectedReloadBrowse = nil
        reloadSequence.cancel()
        prepareDocumentNavigation()
    }

    private func prepareDocumentNavigation() {
        currentLoadProgress = 0
        pictureInPictureDocument = nil
        stopCasting()
        captureRevision &+= 1
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
        if let fullscreen = fullscreenTransition.pageChanged(isFullscreen) { emitFullscreen(fullscreen) }
    }
    private func emitFullscreen(_ fullscreen: Bool) {
        guard surface.window?.isVisible == true, !surface.isHiddenOrHasHiddenAncestor else { return }
        engine.pageDidEmit(self, .fullscreenChanged(fullscreen))
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
        let plainLink = params.linkURL != nil && params.mediaType == .none && !params.isEditable
        contextMenu.show(menu, at: CGPoint(x: params.x, y: params.y), in: surface, link: plainLink, callback: callback) { [weak self] in
            guard let self else { return false }; return self.engine.isLive(self) && !self.surface.isHiddenOrHasHiddenAncestor
        }
        return true
    }

    func browserContextMenuDidClose(_ b: CefBrowser) { contextMenu.cancel() }

    func browser(_ b: CefBrowser, didChangeURL url: URL?) {
        emit(mainDocument.addressChanged(url, loading: b.isLoading))
    }

    func browser(_ b: CefBrowser, didStartMainDocument url: URL?) {
        closeDocumentPiP()
        emit(mainDocument.started(url))
        refreshBoosts()
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

    /// Keep the actual Chromium browsing context so empty window.open/document.write and opener survive.
    func browser(_ b: CefBrowser, decideWindowOpenFor request: CefWindowOpenRequest) -> CefWindowOpenAction {
        guard engine.isLive(self) else { return .deny }
        if request.disposition == .newPictureInPicture {
            guard let document = readyDocument else { return .deny }
            documentPiPSource = document
        }
        popupRequests.append(openMetadata(request))
        if popupRequests.count > 16 { popupRequests.removeFirst() }
        let namedWindow = !request.frameName.isEmpty && !["_blank", "_self", "_parent", "_top"].contains(request.frameName.lowercased())
        if !namedWindow, let url = request.targetURL, !url.absoluteString.isEmpty,
           url.absoluteString != "about:blank", [.newForegroundTab, .newBackgroundTab, .newPopup].contains(request.disposition) {
            engine.pageDidEmit(self, .openRequested(url, request.disposition == .newBackgroundTab ? .backgroundTab : .foregroundTab,
                                                  metadata: openMetadata(request)))
            return .handled
        }
        return .allowNativePopup
    }

    func browser(_ b: CefBrowser, auxiliaryCountChanged count: Int) {
        engine.auxiliaryCountChanged(self, count: count)
        observePictureInPictureAuxiliaries()
    }
    func browser(_ b: CefBrowser, didCreateAuxiliary auxiliary: CefBrowser, kind: CefAuxiliaryKind) {
        guard engine.isLive(self) else { auxiliary.close(force: true); return }
        if case .devTools = kind { toolsBrowser = auxiliary; selectDeveloperPanel() }
        observePictureInPictureAuxiliary(auxiliary, kind: kind)
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

    func browserDidClose(_ b: CefBrowser) { closeDeveloperWindows(); stopCasting(); cancelPermissions(); audio.invalidate(retire: true); audioTargetTransport?.invalidate(); find.invalidate(nativeAlive: false); contextMenu.cancel(); engine.pageDidClose(self) }

    /// A main-frame navigation the page is about to make. Redirects always go through; the rest ask the app
    /// (`WebEngineDelegate.shouldNavigateTo`), which cancels when a Peek opens instead.
    func browser(_ b: CefBrowser, decidePolicyForNavigation url: URL?, isRedirect: Bool, userGesture: Bool) -> CefNavigationDecision {
        guard let url else { return .allow }
        if isAIReader, !["http", "https"].contains(url.scheme?.lowercased()) { return .cancel }
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
        guard !isAIReader else { decision.resolve(nil); return }
        engine.download(self, item: download, name: suggestedName, decision: decision)
    }
    func browser(_ b: CefBrowser, download: CefDownload, control: CefDownloadControl?) {
        guard !isAIReader else { control?.cancel(); control?.release(); return }
        engine.download(self, item: download, control: control)
    }

    /// CEF's two key callbacks. Before the page (`OnPreKeyEvent`) the id is minted from the event being dispatched;
    /// after the page (`OnKeyEvent`, only when the page did not consume it) the id is the partner's, paired by
    /// `PressCorrelator`. Modifier-only keys and character events are not routed (Control reaches BrkApp as
    /// `WindowEvent.modifiersChanged` from the window's `flagsChanged` events).
    func browser(_ b: CefBrowser, preKeyEvent event: CefKeyEvent) -> CefKeyDisposition { route(event, before: true) }
    func browser(_ b: CefBrowser, chromeCommand id: Int, disposition: CefWindowOpenDisposition) -> Bool {
        recordKey(PageKeyReceipt(stage: "chrome", handled: false, chromeCommand: id))
        return false
    }
    func browser(_ b: CefBrowser, handleKeyEvent event: CefKeyEvent, isBeforePage: Bool) -> Bool { route(event, before: isBeforePage).handled }
    private func route(_ event: CefKeyEvent, before isBeforePage: Bool) -> CefKeyDisposition {
        guard let press = KeyTranslation.press(from: event) else { return CefKeyDisposition(handled: false, shortcut: false) }
        // Monotonic; only the correlation timeout reads it, never app time (the app clock stays in BrkApp/Clock.swift).
        let uptime = ProcessInfo.processInfo.systemUptime
        let now = Instant(milliseconds: Int64(uptime * 1000))
        let pressID: PressID
        if isBeforePage {
            pressID = PressID(eventTimestamp: event.nativeTimestamp ?? NSApp.currentEvent?.timestamp ?? uptime)
        } else {
            pressID = presses.afterPage(press, nativeID: event.nativeTimestamp.map { PressID(eventTimestamp: $0) }, at: now) ?? PressID(eventTimestamp: uptime)
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
            recordKey(PageKeyReceipt(stage: isBeforePage ? "pre" : "post", chord: press.chord.description,
                                     press: pressID.raw, handled: handled, shortcut: result.shortcut))
            log.notice("cef.\(isBeforePage ? "pre" : "post", privacy: .public) page \(self.id.description, privacy: .public) \(press.chord.description, privacy: .public) native=\(event.nativeKeyCode, privacy: .public) editable=\(event.isEditableFieldFocused, privacy: .public) \(pressID.description, privacy: .public) consumed=\(handled, privacy: .public)")
        }
        return CefKeyDisposition(handled: handled, shortcutIntent: handled ? .unchanged : (result.shortcut ? .enabled : .disabled))
    }
}


extension ChromePage {
    func browser(_ b: CefBrowser, didChangeStatusMessage message: String) {
        guard !isAIReader else { return }
        engine.pageDidEmit(self, .linkHovered(URL(string: message)))
    }
}
