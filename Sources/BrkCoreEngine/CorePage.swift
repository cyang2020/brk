import AppKit
import BrkBase
import BrkEngine
import CBrkCore
import os

/// One page on BrkCore. As `ChromePage` on CEF: turns what the framework reports into `PageEvent`s and key presses, with the same
/// document state and press pairing, one instance per incarnation of a page id.
@MainActor
final class CorePage: NSObject, BrkCoreWebContentsDelegate {
    let id: PageID
    let context: BrowsingContext
    let incarnation: PageLedger.Incarnation
    let contents: any BrkCoreWebContents
    let surface: CoreSurface
    private unowned let engine: CoreEngine
    private(set) var mainDocument: MainDocumentState
    private var reloadSequence = ReloadSequence()
    private var expectedReloadBrowse: URL?
    private var presses = PressCorrelator()
    private var keyReceipts: [PageKeyReceipt] = []
    private var currentProgress: Double = 0
    private var progressSamples: [Double] = []
    private var requestedReloads = 0
    private var desiredMuted: Bool
    /// The browser whose tab this is; what extensions see.
    let browser: any BrkCoreBrowser
    private let log = Logger(subsystem: "brk", category: "core-page")

    var readyDocument: DocumentToken? { mainDocument.readyDocument }

    /// A page Chromium made by itself for this address (target=_blank) is taken over, keeping its opener; otherwise a new one loads it.
    init(spec: PageSpec, url: URL, engine: CoreEngine, incarnation: PageLedger.Incarnation, browser: any BrkCoreBrowser) {
        id = spec.id
        context = spec.context
        self.incarnation = incarnation
        self.engine = engine
        self.browser = browser
        desiredMuted = spec.muted
        mainDocument = MainDocumentState(browser: incarnation)
        let adopted = browser.adoptWebContents(with: url)
        contents = adopted ?? browser.createWebContents()
        surface = CoreSurface(page: spec.id, contents: contents)
        super.init()
        contents.delegate = self
        contents.audioMuted = spec.muted
        surface.onReadyForFocus = { [weak self] in
            guard let self else { return }
            self.engine.pageReadyForFocus(self)
        }
        if adopted == nil { contents.load(url) }
    }

    var facts: PageFacts {
        var facts = PageFacts(surfaceFrame: surface.frameInWindow, embeddedViews: surface.subviews.map { NSStringFromClass(type(of: $0)) },
                              browserID: Int(contents.tabID), hostWindowNumber: nil, hasKeyboardFocus: surface.containsFirstResponder,
                              audioMuted: contents.audioMuted)
        facts.loadProgressSamples = progressSamples
        facts.requestedReloads = requestedReloads
        facts.keyReceipts = keyReceipts
        facts.inputViewHidden = contents.inputView?.isHiddenOrHasHiddenAncestor
        return facts
    }

    func setMuted(_ value: Bool) {
        desiredMuted = value
        if contents.audioMuted != value { contents.audioMuted = value }
    }

    func takeFocus() {
        guard let window = surface.window else { return }
        let accepted = window.makeFirstResponder(surface.keyboardTarget)
        contents.setPageFocused(true)
        browser.activate(contents)
        log.notice("page \(self.id.description, privacy: .public): takeFocus accepted=\(accepted, privacy: .public)")
    }

    func dropFocus() { contents.setPageFocused(false) }

    func close() {
        reloadSequence.cancel()
        surface.retire()
        contents.close()
    }

    func park() {
        reloadSequence.cancel()
        surface.retire()
        surface.removeFromSuperview()
        contents.setHidden(true)
    }

    func prepareNavigation() {
        expectedReloadBrowse = nil
        reloadSequence.cancel()
        prepareDocumentNavigation()
    }

    private func prepareDocumentNavigation() {
        currentProgress = 0
        engine.pageDidEmit(self, .audioChanged(false))
        mainDocument.prepareNavigation()
    }

    func prepareStop() { reloadSequence.cancel(); emit(mainDocument.stopped()) }

    func reportZoom() { engine.pageDidEmit(self, .zoomChanged(BrowserZoom.percentage(level: contents.zoomLevel))) }

    func reportInitialLoading() {
        engine.pageDidEmit(self, .loadingChanged(isLoading: contents.isLoading, canGoBack: contents.canGoBack, canGoForward: contents.canGoForward))
        if contents.isLoading { engine.pageLoadProgress(self, progress: currentProgress) }
    }

    func requestReload(ignoringCache: Bool) {
        requestedReloads += 1
        if let request = reloadSequence.request(ignoringCache: ignoringCache, after: mainDocument.lastSequence) { issueReload(request) }
    }

    private func issueReload(_ request: ReloadSequence.Request) {
        guard engine.isLive(self), reloadSequence.current == request else { return }
        guard mainDocument.lastSequence == request.afterDocumentSequence else { reloadSequence.cancel(); return }
        prepareDocumentNavigation()
        expectedReloadBrowse = contents.visibleURL
        contents.reloadBypassingCache(request.ignoringCache)
    }

    private func emit(_ events: [PageEvent]) {
        for event in events { engine.pageDidEmit(self, event) }
    }

    // MARK: BrkCoreWebContentsDelegate

    func webContents(_ contents: any BrkCoreWebContents, decideNavigationTo url: URL, isRedirect: Bool, userGesture: Bool) -> Bool {
        guard isRedirect || engine.pageShouldNavigate(self, to: url, userGesture: userGesture) else { return false }
        if !isRedirect, reloadSequence.current != nil {
            if expectedReloadBrowse == url { expectedReloadBrowse = nil }
            else { reloadSequence.cancel(); expectedReloadBrowse = nil }
        }
        if !isRedirect { currentProgress = 0 }
        emit(mainDocument.allowed(url, redirect: isRedirect))
        return true
    }

    func webContents(_ contents: any BrkCoreWebContents, didChangeAddress url: URL?) {
        emit(mainDocument.addressChanged(url, loading: contents.isLoading))
    }

    func webContents(_ contents: any BrkCoreWebContents, didStartDocument url: URL?) {
        emit(mainDocument.started(url))
        if contents.isLoading { engine.pageLoadProgress(self, progress: currentProgress) }
    }

    func webContents(_ contents: any BrkCoreWebContents, didFinishDocument url: URL?) {
        setMuted(desiredMuted)
        emit(mainDocument.finished(url))
        reportZoom()
        if case .ready(let document) = mainDocument.availability, let request = reloadSequence.finished(documentSequence: document.sequence) {
            Task { @MainActor [weak self] in self?.issueReload(request) }
        }
    }

    func webContents(_ contents: any BrkCoreWebContents, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        engine.pageDidEmit(self, .loadingChanged(isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward))
        emit(mainDocument.loadingChanged(isLoading))
        if isLoading { engine.pageLoadProgress(self, progress: currentProgress) } else { currentProgress = 0 }
    }

    func webContents(_ contents: any BrkCoreWebContents, didChangeProgress progress: Double) {
        guard progress.isFinite else { return }
        currentProgress = progress
        progressSamples.append(progress)
        if progressSamples.count > 24 { progressSamples.removeFirst() }
        engine.pageLoadProgress(self, progress: progress)
    }

    func webContents(_ contents: any BrkCoreWebContents, didFailLoadCode code: Int, description: String, url: String) {
        reloadSequence.cancel()
        emit(mainDocument.loadFailed(code: code, description: description, url: url))
    }

    func webContents(_ contents: any BrkCoreWebContents, didChangeTitle title: String) {
        engine.pageDidEmit(self, .titleChanged(title))
    }

    func webContents(_ contents: any BrkCoreWebContents, didChangeFavicon url: URL?) {
        engine.pageDidEmit(self, .faviconChanged(url))
    }

    func webContents(_ contents: any BrkCoreWebContents, didHoverLink url: URL?) {
        engine.pageDidEmit(self, .linkHovered(url))
    }

    func webContentsRendererGone(_ contents: any BrkCoreWebContents) {
        reloadSequence.cancel()
        emit(mainDocument.rendererGone())
        engine.pageDidEmit(self, .rendererGone)
    }

    func webContentsDidGainFocus(_ contents: any BrkCoreWebContents) {
        engine.pageDidEmit(self, .gainedFocus)
        reportZoom()
    }

    func webContents(_ contents: any BrkCoreWebContents, didChangeZoomLevel level: Double) { reportZoom() }

    func webContentsClosed(byPage contents: any BrkCoreWebContents) {}

    /// Later: the framework calls this from inside Chromium's tab strip, which refuses any change while it notifies.
    func webContentsDidClose(_ contents: any BrkCoreWebContents) {
        reloadSequence.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.engine.pageDidClose(self)
        }
    }

    func webContents(_ contents: any BrkCoreWebContents, keyBeforePage key: BrkCoreKeyPress) -> BrkCoreKeyAnswer {
        let answer = route(key, before: true)
        return BrkCoreKeyAnswer(handled: answer.handled, shortcut: answer.shortcut)
    }

    func webContents(_ contents: any BrkCoreWebContents, keyAfterPage key: BrkCoreKeyPress) -> Bool {
        route(key, before: false).handled
    }

    func webContents(_ contents: any BrkCoreWebContents, requestsOpening url: URL, disposition: BrkCoreDisposition, userGesture: Bool) {
        let opening: OpenDisposition = switch disposition {
        case .backgroundTab: .backgroundTab
        case .newWindow: .newWindow
        default: .foregroundTab
        }
        engine.pageDidEmit(self, .openRequested(url, opening, metadata: PageOpenMetadata(userGesture: userGesture)))
    }

    /// As `ChromePage.route`: before the page the id comes from the event, after it the id is the partner's.
    private func route(_ key: BrkCoreKeyPress, before isBeforePage: Bool) -> KeyHandling {
        let phase: KeyPress.Phase = key.isDown ? .down : .up
        guard key.nativeKeyCode >= 0, key.nativeKeyCode <= Int32(UInt16.max), let code = Key.byCode(UInt16(key.nativeKeyCode)) else {
            return KeyHandling(handled: false, shortcut: false)
        }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(key.modifierFlags))
        var modifiers = Modifiers()
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        let press = KeyPress(chord: KeyChord(modifiers, code), phase: phase, isRepeat: key.isRepeat, editableFieldFocused: key.editableFocused)
        let uptime = ProcessInfo.processInfo.systemUptime
        let now = Instant(milliseconds: Int64(uptime * 1000))
        let native = key.timestamp > 0 ? PressID(eventTimestamp: key.timestamp) : nil
        let pressID: PressID
        if isBeforePage {
            pressID = native ?? PressID(eventTimestamp: NSApp.currentEvent?.timestamp ?? uptime)
        } else {
            pressID = presses.afterPage(press, nativeID: native, at: now) ?? PressID(eventTimestamp: uptime)
        }
        let result = engine.pageKeyHandling(self, press, stage: isBeforePage ? .beforePage : .afterPage, pressID: pressID)
        var handled = result.handled
        if !isBeforePage, !handled, press.phase == .down, key.editableFocused, press.chord.key == .z {
            if press.chord.modifiers == .command { contents.undoEdit(); handled = true }
            else if press.chord.modifiers == [.command, .shift] { contents.redoEdit(); handled = true }
        }
        if isBeforePage { presses.beforePage(press, id: pressID, handled: handled, at: now) }
        if press.phase == .down, result.shortcut || !press.chord.modifiers.isDisjoint(with: [.command, .control]) || press.chord.key == .escape {
            record(PageKeyReceipt(stage: isBeforePage ? "pre" : "post", chord: press.chord.description, press: pressID.raw, handled: handled,
                                  shortcut: result.shortcut, action: result.action, isRepeat: press.isRepeat))
        }
        return KeyHandling(handled: handled, shortcut: handled ? false : result.shortcut)
    }

    private func record(_ receipt: PageKeyReceipt) {
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        keyReceipts.append(receipt)
        if keyReceipts.count > 64 { keyReceipts.removeFirst(keyReceipts.count - 64) }
    }
}
