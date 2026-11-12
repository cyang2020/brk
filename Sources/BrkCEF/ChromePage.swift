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
    /// The ready document's language (CEFEngine.reportLanguage), for the page menu's Translate to English.
    var detectedLanguage: String?
    /// The last highlight state reported (`PageEvent.selectionChanged`), reset with each document.
    var reportedSelection = false
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
    /// Inspect Elements is waiting for DevTools to enter its element picker.
    var inspectPickRequested = false
    var developerPanelTask: Task<Void, Never>?
    var developerTransport: CefDevTools?
    private var popupRequests: [PageOpenMetadata] = []
    /// Dialogs and downloads that native children forwarded to this page, for the e2e harness (kept only under it).
    var auxiliaryEvents: [String] = []
    /// The page's own JavaScript or beforeunload dialog on its window, while it is up.
    private var dialogSheet: NSAlert?
    var cast: PageCast?
    var drainingCasts: [PageCast] = []
    private func recordKey(_ receipt: PageKeyReceipt) {
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        keyReceipts.append(receipt)
        if keyReceipts.count > 64 { keyReceipts.removeFirst(keyReceipts.count - 64) }
    }
    private func recordAuxiliary(_ event: String) {
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        auxiliaryEvents.append(event)
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
    /// The isolated world the site policy runs in for the current document. Its media observer and playing marks
    /// live in that world's globals, so nothing of it shows in the page's DOM; one world per document keeps them.
    var policyWorld: (document: DocumentToken, context: Int)?
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
    /// Requests allowed in the current document, so Chromium's stored grant can follow Brk's remembered choice once
    /// the document ends (Allow this time is not remembered; Chromium stores every accepted request).
    var permissionGrants: [(document: DocumentToken, requesting: SiteOrigin, top: SiteOrigin, capabilities: Set<SiteCapability>)] = []
    /// The page is capturing from a camera or microphone (CEF's media access report).
    var capturingMedia = false
    /// Media in a cross-origin frame was playing when the page was last visible (the audio extension reads every
    /// frame). Chromium pauses muted media of a hidden page, so the intent is kept until the page is visible again.
    var subframeMediaIntent = false
    /// Remembered choices changed in Brk and not yet written to Chromium's store (`flushPermissionSync`).
    var permissionSync: [(requesting: SiteOrigin, top: SiteOrigin, capabilities: Set<SiteCapability>)] = []
    var policyRevision: UInt64 = 0
    var websiteError: String?
    /// The automatic dark mode last sent to this page's DevTools session, and for which document (nil: never sent).
    var autoDark: (document: DocumentToken, enabled: Bool)?
    var frozen = false
    var pictureInPictureDocument: DocumentToken?
    /// The last security report, so a document is reported once and again only when Chromium's view of it changes.
    private var reportedSecurity: PageSecurity?

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

    /// The host window every page browser is made in: frameless, off screen, never activated before its views move
    /// into a card. A popup the page opens as a tab gets the same host (`popupHost`).
    private static func hostOptions(_ policy: WebsitePolicy, url: URL, profile: CefProfile?) -> CefChromeBrowserOptions {
        var options = CefChromeBrowserOptions()
        options.isFrameless = true
        options.prepareNativeWindow = { HostWindows.adopt($0, parent: nil) }
        let initialRule = SiteOrigin(url).map { policy.preferences.rule(for: $0) } ?? SiteRule()
        let list = policy.preferences.blockingRules ?? .builtIn
        options.requestRules = CefRequestRules(enabled: initialRule.blocking, hosts: list.blockedHosts, paths: list.blockedPathPrefixes, urlPrefixes: list.blockedURLPrefixes ?? [])
        options.showsChromeToolbar = false
        options.prepareWindow = { HostWindows.adopt($0, parent: nil) }
        options.backgroundColor = .white
        options.initialBounds = Self.offscreenBounds
        options.profile = profile
        return options
    }

    /// `popup`: a host CEF is creating this page's browser in, because this page's tab is a popup another page
    /// opened (`hostForPopup`); the browser then keeps `window.opener`. Otherwise a new browser loads `url`.
    init(spec: PageSpec, url: URL, engine: CEFEngine, incarnation: PageLedger.Incarnation, adopting popup: CefChromeBrowser? = nil) {
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
        if let popup {
            chrome = popup
        } else {
            // The page's request context: nil (the runtime's cache) for the default profile, a profile's persistent
            // context, or the shared incognito one (W2-2 and W2-3 prove the isolation on the real engine).
            chrome = CefChromeBrowser.create(url: url, options: Self.hostOptions(spec.websitePolicy, url: url, profile: engine.profile(for: spec.context)), delegate: nil)
        }
        if let host = chrome.nsWindow { HostWindows.adopt(host,parent:nil) }
        chrome.browser.delegate = self
        chrome.onPopupAborted = { [weak self] in
            guard let self else { return }
            self.log.notice("page \(self.id.description, privacy: .public): Chromium did not create its popup browser")
            self.surface.returnViews()
            self.windowDestroyed = true
            self.engine.pageWindowDidClose(self)
            self.engine.pageDidClose(self)
        }
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
        let pictureInPicture = mediaPlayers.contains(where: \.pictureInPicture)
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
        // While the page is visible its cross-origin frames' playing state is current; hidden, the last one stands.
        if websitePolicy.visible { subframeMediaIntent = mediaPlayers.contains { $0.id.frame != 0 && !$0.paused && !$0.ended } }
        if changed { emit([.audioChanged(reading.audible)]) }
        // Entering or leaving video picture in picture changes what keeps a hidden page running.
        if changed || pictureInPicture != mediaPlayers.contains(where: \.pictureInPicture) { refreshWebsitePolicy() }
    }

    func browser(_ b: CefBrowser, didChangeMediaAccess camera: Bool, microphone: Bool) {
        let capturing = camera || microphone
        guard capturing != capturingMedia else { return }
        capturingMedia = capturing
        refreshWebsitePolicy()
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
    /// CEF's empty host window for this page; Chromium's bubbles for the page are its child windows (`SavePrompts`).
    var hostWindow: NSWindow? { chrome.nsWindow }
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
        facts.textServices = surface.textServiceLog
        facts.inputViewHidden = EmbeddedSurface.find("RenderWidgetHostViewCocoa", in: surface)?.isHiddenOrHasHiddenAncestor
        facts.hasDevTools = browser.hasDevTools
        facts.auxiliaryBrowsers = browser.nativeAuxiliaries.map { Int($0.browser.id) }
        facts.auxiliaryWindows = browser.nativeAuxiliaries.compactMap { $0.browser.nativeView?.window?.windowNumber }
        facts.popupRequests = popupRequests
        facts.auxiliaryEvents = auxiliaryEvents
        facts.developerResult = developerResult
        facts.castSinkNotifications = cast?.router?.sinkNotifications
        facts.castRouteNotifications = cast?.router?.routeNotifications
        facts.castSinks = cast?.router?.sinks.map(\.name)
        facts.castRoutes = cast?.router?.routes
        facts.castResult = cast?.router?.lastResult
        facts.castAvailable = cast.flatMap { $0.startingService ? nil : $0.router != nil }
        facts.castError = cast?.unavailableReason ?? cast?.router?.lastError
        facts.castSourceSupported = cast?.router?.sourceSupported
        if let number = cast?.visibleWindowNumber { facts.auxiliaryWindows?.append(number) }
        if let sourceWindow, sourceWindow.isVisible { facts.auxiliaryWindows?.append(sourceWindow.windowNumber) }
        return facts
    }

    /// Idempotent: views back first (never close a browser whose views are in our window), then force-close.
    /// OnBeforeClose arrives later as `browserDidClose` -> `engine.pageDidClose(self)`.
    func close() {
        settlePermissionGrants(keeping: nil)
        captureRevision &+= 1
        closeDocumentPiP()
        fullscreenTransition.cancelPending()
        audio.invalidate(retire: true)
        audioTargetTransport?.invalidate()
        find.invalidate()
        linkPreviews.stop()
        reloadSequence.cancel()
        cancelPermissions()
        cancelDialog()
        contextMenu.cancel()
        closeDeveloperWindows()
        stopCasting()
        browser.closeNativeAuxiliaries()
        browser.closeDevTools()
        surface.returnViews()
        chrome.browser.close(force: true)
    }

    func park() { fullscreenTransition.cancelPending(); reloadSequence.cancel(); approvedExtensionDirectory = nil; cancelPermissions(); cancelDialog(); audio.invalidate(retire: true); audioTargetTransport?.invalidate(); find.invalidate(); contextMenu.cancel(); closeDeveloperWindows(); stopCasting(); browser.closeNativeAuxiliaries(); captureRevision &+= 1; browser.executeJavaScript("if(document.pictureInPictureElement)document.exitPictureInPicture().catch(()=>{});"); closeDocumentPiP(); linkPreviews.stop(); surface.park() }

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
        // The capsule naming the hovered link goes while a menu is open (Q07-b); Chromium sends no status of its own then.
        engine.pageDidEmit(self, .linkHovered(nil))
        // Arc's page menu offers "Translate to English" (the system language) on a page in another language (Q07-a).
        let system = Locale.preferredLanguages.first ?? "en"
        let base = { (code: String) in String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "") }
        let translate: String? = if !plainLink, !params.isEditable, params.mediaType == .none, !isAIReader, let language = detectedLanguage,
            !base(language).isEmpty, base(language) != base(system) { Locale(identifier: "en_US").localizedString(forLanguageCode: base(system)) } else { nil }
        contextMenu.show(menu, at: CGPoint(x: params.x, y: params.y), in: surface, link: plainLink, translateTo: translate, callback: callback,
                         onTranslate: { [weak self] in
                             guard let self, let translate, self.engine.isLive(self) else { return }
                             self.engine.pageDidEmit(self, .translateRequested(translate))
                         }, onLink: { [weak self, url = params.linkURL] target in
                             guard let self, let url, self.engine.isLive(self) else { return }
                             self.engine.pageDidEmit(self, .linkMenuRequested(url, target))
                         }) { [weak self] in
            guard let self else { return false }; return self.engine.isLive(self) && !self.surface.isHiddenOrHasHiddenAncestor
        }
        return true
    }

    func browserContextMenuDidClose(_ b: CefBrowser) { contextMenu.cancel() }

    func browser(_ b: CefBrowser, didChangeURL url: URL?) {
        emit(mainDocument.addressChanged(url, loading: b.isLoading))
    }

    func browser(_ b: CefBrowser, didStartMainDocument url: URL?) {
        detectedLanguage = nil
        reportedSelection = false
        closeDocumentPiP()
        settlePermissionGrants(keeping: nil)
        subframeMediaIntent = false
        emit(mainDocument.started(url))
        refreshBoosts()
        if b.isLoading { engine.pageLoadProgress(self, progress: currentLoadProgress) }
    }

    func browser(_ b: CefBrowser, didFinishMainDocument url: URL?) {
        setMuted(desiredMuted)
        emit(mainDocument.finished(url))
        reportZoom()
        reportSecurity()
        refreshWebsitePolicy()
        engine.reportLanguage(self)
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
        else { currentLoadProgress = 0; reportSecurity() }
    }

    /// The site controls' Secure / Insecure: Chromium's SSL status of the visible entry, read when the main document
    /// is ready and again when loading stops (insecure subresources arrive after the document).
    private func reportSecurity() {
        guard let document = mainDocument.readyDocument, let status = browser.visibleSSLStatus() else { return }
        let security = PageSecurity(document: document, secureConnection: status.isSecureConnection,
                                    certificateError: status.hasCertificateError, insecureContent: status.hasInsecureContent,
                                    insecureForm: status.hasInsecureFormAction)
        guard security != reportedSecurity else { return }
        reportedSecurity = security
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            print("[site-security] page=\(id) secure=\(security.secure) tls=\(status.isSecureConnection) cert=0x\(String(status.certStatus, radix: 16)) content=0x\(String(status.contentStatus, radix: 16))")
        }
        engine.pageDidEmit(self, .securityChanged(security))
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
        // A popup (window features: size or position) from the page in front opens as its own native window, as
        // Arc's popups do: the child keeps `window.opener` and the requested geometry, and its downloads and
        // dialogs come back to this page. A hidden source has no window to anchor one; its popup becomes a tab.
        let onScreen = surface.window?.isVisible == true && !surface.isHiddenOrHasHiddenAncestor
        if request.disposition == .newPopup, onScreen, request.targetURL.map({ !$0.absoluteString.isEmpty }) == true { return .allowNativePopup }
        // Everything else with an address becomes a tab, as in Chrome: `window.open(url)` without features,
        // target=_blank, and a hidden page's popup. Chromium still creates the browser (`hostForPopup`), so the tab
        // keeps `window.opener` unless the page asked for noopener; a sign-in or payment page can report back.
        if !namedWindow, let url = request.targetURL, !url.absoluteString.isEmpty,
           url.absoluteString != "about:blank", [.newForegroundTab, .newBackgroundTab, .newPopup].contains(request.disposition) {
            return .adoptAsChromeBrowser
        }
        return .allowNativePopup
    }

    /// The tab for a popup this page opens: the domain decides where it goes (`openRequested`); when the page it
    /// creates for it is in this page's context, that page wraps the host Chromium creates the popup in. Otherwise
    /// (another profile, refused, deferred) the popup is blocked and the domain's tab, if any, loads the address.
    func browser(_ b: CefBrowser, hostForPopup request: CefWindowOpenRequest) -> CefChromeBrowser? {
        guard engine.isLive(self), let url = request.targetURL else { return nil }
        let host = CefChromeBrowser.popupHost(options: Self.hostOptions(websitePolicy, url: url, profile: nil))
        let disposition: OpenDisposition = request.disposition == .newBackgroundTab ? .backgroundTab : .foregroundTab
        let adopted = engine.offerPopupHost(host, url: url, context: context) {
            engine.pageDidEmit(self, .openRequested(url, disposition, metadata: openMetadata(request)))
        }
        recordAuxiliary("popup-tab:\(adopted):" + url.absoluteString)
        guard adopted else { host.discardPopupHost(); return nil }
        return host
    }

    /// A JavaScript dialog of this page, or of a native child it opened (forwarded by CefKit, `b` is the child): a sheet
    /// on the window it shows in, answered later. CefKit's own presenter runs an app-modal alert inside CEF's callback,
    /// which blocks every window and stops every page until it is answered. As on BrkCore (CoreDialogs.swift), the
    /// page's own dialog shows only while the page is on screen; otherwise Chromium gets it as dismissed, as Chrome does
    /// not raise a background tab's dialog over another.
    func browser(_ b: CefBrowser, runJSDialog dialog: CefJSDialog, callback: CefJSDialogCallback) -> Bool {
        let own = b === browser
        guard let window = dialogWindow(b) else {
            guard own else { return false }
            callback.cancel(); return true
        }
        let alert = NSAlert()
        alert.messageText = dialog.origin
        alert.informativeText = dialog.message
        alert.addButton(withTitle: "OK")
        var field: NSTextField?
        if dialog.kind != .alert { alert.addButton(withTitle: "Cancel") }
        if dialog.kind == .prompt {
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); input.stringValue = dialog.defaultPromptText
            alert.accessoryView = input; field = input
        }
        if own { dialogSheet = alert } else { recordAuxiliary("dialog:\(dialog.kind):\(window.windowNumber):" + dialog.message) }
        alert.beginSheetModal(for: window) { [weak self] response in
            let ok = response == .alertFirstButtonReturn
            if !own { self?.recordAuxiliary("dialog-answered:\(ok)") } else if self?.dialogSheet === alert { self?.dialogSheet = nil }
            callback.continue(success: ok, userInput: ok ? field?.stringValue : nil)
        }
        return true
    }

    /// Leaving or reloading the page while it has a `beforeunload` handler: Leave or Stay, on a sheet for the same reason.
    func browser(_ b: CefBrowser, runBeforeUnloadDialog message: String, isReload: Bool, callback: CefJSDialogCallback) -> Bool {
        guard b === browser, let window = dialogWindow(b) else { return false }
        let alert = NSAlert()
        alert.messageText = isReload ? "Reload this page?" : "Leave this page?"
        alert.informativeText = message.isEmpty ? "Changes you made may not be saved." : message
        alert.addButton(withTitle: isReload ? "Reload" : "Leave")
        alert.addButton(withTitle: "Stay")
        dialogSheet = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            if self?.dialogSheet === alert { self?.dialogSheet = nil }
            callback.continue(success: response == .alertFirstButtonReturn)
        }
        return true
    }

    /// Where a dialog of `b` goes: a native child's own window, or this page's window while the page shows in it and
    /// the window has no other sheet. Nil: nowhere.
    private func dialogWindow(_ b: CefBrowser) -> NSWindow? {
        guard engine.isLive(self) else { return nil }
        guard b === browser else { return b.nativeView?.window.flatMap { $0.isVisible ? $0 : nil } }
        guard let window = surface.window, window.isVisible, !surface.isHiddenOrHasHiddenAncestor, window.attachedSheet == nil else { return nil }
        return window
    }

    /// The page's document or its place in the window went: its dialog's sheet goes, answered as dismissed.
    private func cancelDialog() {
        guard let alert = dialogSheet else { return }
        dialogSheet = nil
        alert.window.sheetParent?.endSheet(alert.window, returnCode: .abort)
    }

    /// The Chrome runtime opens a popup window at its default size in the screen's corner, ignoring the window
    /// features. The page asked for a content size and a screen position (top-left, points): the window is sized
    /// so its web content gets exactly that size, the toolbar and title bar on top of it.
    private func placePopup(_ popup: CefBrowser, _ features: CefPopupFeatures, attempt: Int) {
        guard features.width != nil || features.height != nil || features.x != nil || features.y != nil else { return }
        guard let window = popup.nativeView?.window, let content = window.contentView,
              let web = EmbeddedSurface.find("WebContentsViewCocoa", in: content), web.frame.width > 0 else {
            if attempt < 40 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak popup] in
                if let self, let popup { self.placePopup(popup, features, attempt: attempt + 1) } } }
            return
        }
        let chrome = CGSize(width: window.frame.width - web.frame.width, height: window.frame.height - web.frame.height)
        let size = CGSize(width: CGFloat(features.width ?? Int(web.frame.width)) + chrome.width,
                          height: CGFloat(features.height ?? Int(web.frame.height)) + chrome.height)
        let top = NSScreen.screens.first?.frame.maxY ?? window.frame.maxY
        let left = features.x.map(CGFloat.init) ?? window.frame.minX
        let originY = features.y.map { top - CGFloat($0) - size.height } ?? (window.frame.maxY - size.height)
        window.setFrame(NSRect(x: left, y: originY, width: size.width, height: size.height), display: true)
        recordAuxiliary("placed:\(window.windowNumber):\(Int(window.frame.minX)),\(Int(top - window.frame.maxY)),\(Int(web.frame.width))x\(Int(web.frame.height))")
    }

    func browser(_ b: CefBrowser, auxiliaryCountChanged count: Int) {
        engine.auxiliaryCountChanged(self, count: count)
        observePictureInPictureAuxiliaries()
    }
    func browser(_ b: CefBrowser, didCreateAuxiliary auxiliary: CefBrowser, kind: CefAuxiliaryKind) {
        guard engine.isLive(self) else { auxiliary.close(force: true); return }
        if case .popup(let request) = kind, request.disposition == .newPopup { placePopup(auxiliary, request.features, attempt: 0) }
        if case .devTools = kind { toolsBrowser = auxiliary; selectDeveloperPanel() }
        observePictureInPictureAuxiliary(auxiliary, kind: kind)
    }

    /// A link opened with a modifier (Cmd+click) arrives here (CEF's OnOpenURLFromTab), not as a popup. Handled the
    /// same way: a tab the domain creates; unhandled, CEF would make a Chrome-runtime browser without a client that
    /// nothing closes and that crashes cef_shutdown. The link menu's Open Link in New Window and Open Link in Incognito
    /// Window come this way too, with their own disposition.
    func browser(_ b: CefBrowser, openURLFromTab request: CefWindowOpenRequest) -> Bool {
        guard let url = request.targetURL else { return true }
        let disposition: OpenDisposition = switch request.disposition {
        case .newBackgroundTab: .backgroundTab
        case .newWindow: .newWindow
        case .offTheRecord: .incognitoWindow
        default: .foregroundTab
        }
        engine.pageDidEmit(self, .openRequested(url, disposition, metadata: openMetadata(request)))
        return true
    }

    func browser(_ b: CefBrowser, didRequestNewTab url: URL?) -> Bool {
        guard let url else { return false }
        engine.pageDidEmit(self, .openRequested(url, .backgroundTab))
        return true
    }

    /// Also the end of a page that closed itself (`window.close()`), which never goes through `close()`: its Allow this
    /// time grants go back to what Brk remembers, and its link previews stop.
    func browserDidClose(_ b: CefBrowser) { settlePermissionGrants(keeping: nil); linkPreviews.stop(); cancelDialog(); closeDeveloperWindows(); stopCasting(); cancelPermissions(); audio.invalidate(retire: true); audioTargetTransport?.invalidate(); find.invalidate(nativeAlive: false); contextMenu.cancel(); engine.pageDidClose(self) }

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
        if !isRedirect { currentLoadProgress = 0; cancelDialog() }
        cancelPermissions()
        configureRequestFilter(url)
        contextMenu.cancel()
        emit(mainDocument.allowed(url, redirect: isRedirect))
        return .allow
    }

    func browser(_ b: CefBrowser, download: CefDownload, suggestedName: String, decision: CefDownloadDecisionCallback) {
        guard !isAIReader else { decision.resolve(nil); return }
        Self.turnOffDownloadBubble(b)
        if b !== browser { recordAuxiliary("download:" + suggestedName) }
        engine.download(self, item: download, name: suggestedName, decision: decision)
    }
    func browser(_ b: CefBrowser, download: CefDownload, control: CefDownloadControl?) {
        guard !isAIReader else { control?.cancel(); control?.release(); return }
        engine.download(self, item: download, control: control)
    }

    /// Chromium's "Show downloads when they're done" (chrome/browser/download/bubble/download_bubble_prefs.cc).
    static let downloadBubblePreference = "download_bubble.partial_view_enabled"
    /// When a download finishes, Chromium's download bubble shows a card with the file ("report.pdf · 900 B · Done");
    /// in Brk's frameless Chrome window it sits at the window's top left. Arc 1.170 shows no such card (its Library
    /// badge, the flight and Little Arc's pill tell about downloads), so the preference is turned off in the
    /// request context of every browser that starts a download, before that download can finish.
    static func turnOffDownloadBubble(_ b: CefBrowser) {
        guard b.boolPreference(downloadBubblePreference) != false else { return }
        if let failure = b.setBoolPreference(downloadBubblePreference, false) {
            Logger(subsystem: "brk", category: "page").error("download bubble left on: \(failure, privacy: .public)")
        }
    }

    /// CEF's two key callbacks. Before the page (`OnPreKeyEvent`) the id is minted from the event being dispatched;
    /// after the page (`OnKeyEvent`, only when the page did not consume it) the id is the partner's, paired by
    /// `PressCorrelator`. Modifier-only keys and character events are not routed (Control reaches BrkApp as
    /// `WindowEvent.modifiersChanged` from the window's `flagsChanged` events).
    func browser(_ b: CefBrowser, preKeyEvent event: CefKeyEvent) -> CefKeyDisposition { route(event, before: true) }
    /// Chrome's own accelerators (CEF `OnChromeCommand`) reach a page only for chords the table left unbound or
    /// that both the app and the page declined. Arc has no Chrome tab strip, toolbar, avatar menu, tab search or
    /// downloads page for those commands to act on, so they are consumed here: the key either belongs to the table
    /// (and routing already dispatched it) or to the page. The receipt keeps the command id as evidence.
    func browser(_ b: CefBrowser, chromeCommand id: Int, disposition: CefWindowOpenDisposition) -> Bool {
        recordKey(PageKeyReceipt(stage: "chrome", handled: true, chromeCommand: id))
        log.notice("cef.chrome-command page \(self.id.description, privacy: .public) id=\(id, privacy: .public) consumed")
        return true
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
        if press.phase == .down, result.shortcut || !press.chord.modifiers.isDisjoint(with: [.command, .control]) || press.chord.key == .escape {
            recordKey(PageKeyReceipt(stage: isBeforePage ? "pre" : "post", chord: press.chord.description,
                                     press: pressID.raw, handled: handled, shortcut: result.shortcut, action: result.action, isRepeat: press.isRepeat))
            log.notice("cef.\(isBeforePage ? "pre" : "post", privacy: .public) page \(self.id.description, privacy: .public) \(press.chord.description, privacy: .public) native=\(event.nativeKeyCode, privacy: .public) editable=\(event.isEditableFieldFocused, privacy: .public) \(pressID.description, privacy: .public) consumed=\(handled, privacy: .public)")
        }
        return CefKeyDisposition(handled: handled, shortcutIntent: handled ? .unchanged : (result.shortcut ? .enabled : .disabled))
    }
}


extension ChromePage {
    func browser(_ b: CefBrowser, didChangeStatusMessage message: String) {
        guard !isAIReader else { return }
        if let host = chrome.nsWindow { HostWindows.hideStatusBubble(of: host) }
        engine.pageDidEmit(self, .linkHovered(URL(string: message)))
    }
}
