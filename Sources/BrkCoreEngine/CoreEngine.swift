import AppKit
import BrkBase
import BrkEngine
import CBrkCore
import os

/// `WebEngine` over BrkCore.framework, Brk's own Chromium build (docs/chromium/ARC-ENGINE.md). Pages are tabs of a Chrome `Browser`, one
/// `Browser` per native window and browsing context, and each page's view sits directly in its card. Chosen with `BRK_ENGINE=core`; CEF
/// stays the default. What it does not do yet falls to `WebEngine`'s defaults ("this engine has no ...") and is listed in engine/README.md.
@MainActor
public final class CoreEngine: NSObject, WebEngine, BrkCoreBrowserDelegate {
    public weak var delegate: (any WebEngineDelegate)?
    public private(set) var pageLog: [PageLogEntry] = []
    public var engineVersion: String? { runtime.application.version }

    private let runtime: BrkCoreRuntime
    private let resources = BrowserResources<CorePage>()
    private var live: [PageID: CorePage] {
        Dictionary(uniqueKeysWithValues: resources.entries.filter { $0.value.presented }.map { ($0.key.page, $0.value.resource) })
    }
    private var ledger = PageLedger()
    private var contexts = ContextLifetimes()
    private var wanted: [PageSpec] = []
    private let reconciliation = PageReconciliation()
    private let outputs = DocumentOutputs()
    private var outputPreparations: [OutputID: Task<Void, Never>] = [:]

    private struct BrowserKey: Hashable { let window: WindowID; let context: BrowsingContext }
    private var browsers: [BrowserKey: any BrkCoreBrowser] = [:]
    /// Loaded Chrome profiles, by Brk's id. Loading is asynchronous even for the default profile; a page waits for it.
    private var profiles: [ProfileID: any BrkCoreProfile] = [:]
    private var loading: Set<ProfileID> = []
    private var incognito: [BrowsingContext: any BrkCoreProfile] = [:]

    private struct FocusRequest { weak var window: NSWindow?; let page: PageID }
    private var focusRequests: [ObjectIdentifier: FocusRequest] = [:]
    private var running = true
    private var shutdownTask: Task<ShutdownOutcome, Never>?
    private let log = Logger(subsystem: "brk", category: "core")

    public init(runtime: BrkCoreRuntime) {
        self.runtime = runtime
        super.init()
        outputs.acquire = { [weak self] id, browser in self?.resources.acquire(.documentOutput(id.rawValue), browser: browser) ?? false }
        outputs.release = { [weak self] id, browser in
            guard let self else { return }
            self.resources.release(.documentOutput(id.rawValue), browser: browser)
            self.closeIfUnowned(browser)
        }
        outputs.available = { [weak self] request, epoch in
            guard let self, self.running, self.contexts.permitsWork(epoch.context),
                  let entry = self.resources.entries[request.document.browser], entry.context == epoch,
                  entry.presented, entry.resource.readyDocument == request.document,
                  self.delegate?.engine(self, ownerWindow: request.document.browser.page.window)?.isVisible == true else { return false }
            return true
        }
        outputs.publish = { [weak self] update in guard let self else { return }; self.delegate?.engine(self, output: update) }
        outputs.destination = { [weak self] prompt, reply in
            guard let self, let delegate = self.delegate else { reply(.ownerGone); return }
            delegate.engine(self, outputDestination: prompt, reply: reply)
        }
        outputs.print = { [weak self] request, url, reply in
            guard let self, let delegate = self.delegate else { reply(.ownerGone); return }
            delegate.engine(self, printOutput: request, pdf: url, reply: reply)
        }
        outputs.dismiss = { [weak self] id in guard let self else { return }; self.delegate?.engine(self, dismissOutput: id) }
        outputs.render = { [weak self] request, path, done in self?.render(request, to: path, done: done) }
    }

    // MARK: Pages

    public func reconcile(_ pages: [PageSpec]) {
        guard running else { return }
        wanted = pages.filter { contexts.permitsWork($0.context) }
        reconciliation.submit(wanted, invalidate: {
            for page in Array(self.live.values) where !self.wanted.contains(where: { $0.id == page.id && $0.context == page.context }) {
                self.retire(page)
            }
        }) { self.applyDemand($0) }
    }

    private func applyDemand(_ pages: [PageSpec]) {
        guard running else { return }
        let pages = pages.filter { contexts.permitsWork($0.context) }
        let ids = Set(pages.map(\.id))
        focusRequests = focusRequests.filter { $0.value.window != nil && ids.contains($0.value.page) }
        for spec in pages {
            guard running, contexts.permitsWork(spec.context),
                  wanted.contains(where: { $0.id == spec.id && $0.context == spec.context }) else { continue }
            if let page = live[spec.id] { page.setMuted(spec.muted); continue }
            guard let url = spec.initialURL, let browser = browser(window: spec.id.window, context: spec.context) else { continue }
            let incarnation = ledger.create(spec.id)
            let page = CorePage(spec: spec, url: url, engine: self, incarnation: incarnation, browser: browser)
            resources.insert(page, browser: incarnation, context: contexts.epoch(for: spec.context))
            // There is no host window to wait for, only the page itself.
            resources.hostClosed(incarnation)
            record(.created, page)
            delegate?.engine(self, page: incarnation, didEmit: .browserCreated(spec.context, .unavailable))
            page.reportInitialLoading()
        }
    }

    /// The `Browser` of this window and context; nil while its profile loads, and the demand replays when it has.
    private func browser(window: WindowID, context: BrowsingContext) -> (any BrkCoreBrowser)? {
        let key = BrowserKey(window: window, context: context)
        let native = delegate?.engine(self, ownerWindow: window)
        if let existing = browsers[key], existing.isAlive {
            if existing.window !== native { existing.window = native }
            return existing
        }
        guard let profile = profile(for: context) else { return nil }
        let created = profile.createBrowser(for: native, delegate: self)
        browsers[key] = created
        return created
    }

    private func profile(for context: BrowsingContext) -> (any BrkCoreProfile)? {
        switch context {
        case .profile(let id): return loadedProfile(id)
        case .incognito:
            if let existing = incognito[context] { return existing }
            guard let base = loadedProfile(.default) else { return nil }
            let created = base.incognito()
            incognito[context] = created
            return created
        }
    }

    private func loadedProfile(_ id: ProfileID) -> (any BrkCoreProfile)? {
        if let loaded = profiles[id] { return loaded }
        if loading.insert(id).inserted {
            let directory = id == .default ? "Default" : "Profile-" + id.rawValue.replacingOccurrences(of: "/", with: "_")
            runtime.application.loadProfile(directory) { [weak self] profile in
                guard let self else { return }
                self.loading.remove(id)
                if let profile {
                    self.profiles[id] = profile
                    if self.running { self.reconcile(self.wanted) }
                } else {
                    self.log.fault("profile \(directory, privacy: .public) did not load")
                }
            }
        }
        return profiles[id]
    }

    public func surface(for page: PageID) -> PageSurfaceView? { live[page]?.surface }

    /// Downloads are Chromium's own on this engine for now (engine/README.md), so there is nothing of Brk's to cancel.
    public func cancelDownload(_ id: DownloadID) {}

    public func perform(_ action: PageAction, on page: PageID) {
        guard running, let live = live[page] else { return }
        switch action {
        case .navigate, .goBack, .goForward, .reload, .recover: outputs.sourceGone(live.incarnation)
        default: break
        }
        switch action {
        case .navigate(let url): live.prepareNavigation(); live.contents.load(url)
        case .goBack: live.prepareNavigation(); live.contents.goBack()
        case .goForward: live.prepareNavigation(); live.contents.goForward()
        case .reload(let ignoringCache): live.requestReload(ignoringCache: ignoringCache)
        case .stop: live.prepareStop(); live.contents.stopLoading()
        case .zoom(let step):
            live.contents.zoomLevel = BrowserZoom.next(step, level: live.contents.zoomLevel)
            live.reportZoom()
            DispatchQueue.main.async { [weak live] in live?.reportZoom() }
        case .recover: live.prepareNavigation(); live.contents.reloadBypassingCache(false)
        case .toggleDevTools, .cast, .developer, .documentPictureInPicture, .media, .exitFullscreen:
            log.notice("page action not available on this engine yet")
        }
    }

    public func focus(_ page: PageID?, in window: NSWindow) {
        guard running else { return }
        let owner = ObjectIdentifier(window)
        if let request = focusRequests[owner], request.window === window, request.page != page,
           let previous = live[request.page], previous.surface.window == nil || previous.surface.window === window {
            previous.dropFocus()
        }
        guard let page, wanted.contains(where: { $0.id == page }) else {
            focusRequests[owner] = nil
            for live in live.values where live.surface.window === window && live.surface.containsFirstResponder { live.dropFocus() }
            return
        }
        focusRequests[owner] = FocusRequest(window: window, page: page)
        guard let target = live[page], target.surface.window === window, target.surface.isReadyForFocus else { return }
        if !target.surface.containsFirstResponder { target.takeFocus() }
    }

    private func restoreFocus(_ page: CorePage) {
        guard running, live[page.id] === page, let window = page.surface.window, window.isVisible,
              let request = focusRequests[ObjectIdentifier(window)], request.window === window, request.page == page.id,
              window.firstResponder == nil || window.firstResponder === window,
              !page.surface.isHiddenOrHasHiddenAncestor, page.surface.isReadyForFocus else { return }
        page.takeFocus()
    }

    public func evaluate(_ script: String, in page: PageID) {
        guard running else { return }
        live[page]?.contents.evaluateJavaScript(script, completion: nil)
    }

    public func evaluateForResult(_ script: String, in page: PageID) async throws -> String? {
        guard running, let live = live[page] else { throw CocoaError(.featureUnsupported) }
        let parameters = try String(decoding: JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true, "awaitPromise": true]), as: UTF8.self)
        let result = try await devTools(live, "Runtime.evaluate", parameters)
        guard let value = (result["result"] as? [String: Any])?["value"], !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        return String(decoding: try JSONSerialization.data(withJSONObject: [value]).dropFirst().dropLast(), as: UTF8.self)
    }

    public func selectedText(_ page: PageID) async -> String? {
        guard running, let live = live[page] else { return nil }
        let script = "(()=>{try{let d=document;while(d.activeElement?.tagName==='IFRAME'&&d.activeElement.contentDocument)d=d.activeElement.contentDocument;return d.getSelection().toString().slice(0,4000)}catch{return ''}})()"
        guard let text = try? await evaluateForResult(script, in: live.id), !text.isEmpty else { return nil }
        return text
    }

    private func devTools(_ page: CorePage, _ method: String, _ parameters: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            page.contents.sendDevToolsCommand(method, parameters: parameters) { result, error in
                if let result, let data = result.data(using: .utf8),
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    continuation.resume(returning: json)
                } else {
                    continuation.resume(throwing: NSError(domain: "BrkCore", code: 1, userInfo: [NSLocalizedDescriptionKey: error ?? "DevTools gave no answer"]))
                }
            }
        }
    }

    public func facts(for id: PageID) -> PageFacts? {
        guard let page = live[id] else { return nil }
        var facts = page.facts
        facts.context = page.context
        return facts
    }

    // MARK: Output

    public func output(_ request: OutputRequest) {
        guard let entry = resources.entries[request.document.browser] else {
            delegate?.engine(self, output: OutputUpdate(id: request.id, document: request.document, stage: .terminal(.failed("Document has closed", .absent))))
            return
        }
        outputs.start(request, context: entry.context)
    }

    public func cancelOutput(_ id: OutputID) { outputs.cancel(id) }

    /// MHTML and PDF from the page's DevTools session, the same call Chrome's own "print to PDF" path answers.
    private func render(_ request: OutputRequest, to path: URL, done: @escaping (Result<Void, Error>) -> Void) {
        guard let page = resources.entries[request.document.browser]?.resource, page.readyDocument == request.document else {
            done(.failure(CocoaError(.userCancelled))); return
        }
        outputPreparations[request.id] = Task { @MainActor [weak self] in
            guard let self else { done(.failure(CocoaError(.userCancelled))); return }
            defer { self.outputPreparations[request.id] = nil }
            do {
                guard self.running, self.outputs.permitsRender(request.id), page.readyDocument == request.document else { throw CocoaError(.userCancelled) }
                let data: Data
                if request.intent == .mhtml {
                    let result = try await self.devTools(page, "Page.captureSnapshot", #"{"format":"mhtml"}"#)
                    guard let text = result["data"] as? String else { throw CocoaError(.fileWriteUnknown) }
                    data = Data(text.utf8)
                } else {
                    let result = try await self.devTools(page, "Page.printToPDF", #"{"printBackground":true}"#)
                    guard let text = result["data"] as? String, let decoded = Data(base64Encoded: text) else { throw CocoaError(.fileWriteUnknown) }
                    data = decoded
                }
                try data.write(to: path, options: .withoutOverwriting)
                done(.success(()))
            } catch { done(.failure(error)) }
        }
    }

    // MARK: Closing

    public func disposeContext(_ request: ContextDisposal) {
        contexts.revoke(request.context)
        wanted.removeAll { $0.context == request.context }
        outputs.revoke(request.context)
        for page in live.values where page.context == request.context { retire(page) }
        Task { @MainActor in
            let drained = await self.waitUntil(timeout: Metrics.persistence.shutdownTimeout.value) {
                !self.reconciliation.isApplying && !self.resources.entries.values.contains { $0.context.context == request.context }
                    && !self.outputs.contains(context: request.context)
            }
            let result: ContextDisposalResult
            if drained {
                if case .incognito = request.context { self.incognito[request.context] = nil }
                result = .completed(request.id, request.context, .memoryReleased)
            } else {
                result = .failed(request.id, request.context, reason: "Context callbacks did not drain")
            }
            self.delegate?.engine(self, contextDisposed: result)
        }
    }

    public func shutdown() async -> ShutdownOutcome {
        if let shutdownTask { return await shutdownTask.value }
        let task = Task { @MainActor in await self.runShutdown() }
        shutdownTask = task
        return await task.value
    }

    /// Every page closes first. Chromium's own shutdown comes after the app replies to `applicationShouldTerminate`, which is what ends
    /// `BrkCoreRuntime.run` and so the process (`-[BrowserCrApplication replyToApplicationShouldTerminate:]`).
    private func runShutdown() async -> ShutdownOutcome {
        running = false
        focusRequests.removeAll()
        wanted = []
        contexts.stop()
        outputs.stop()
        for page in live.values { retire(page) }
        // Test instances say what the quit waits for, once a second (as CEFEngine's "fixture cef" lines).
        let traced = ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil, began = ProcessInfo.processInfo.systemUptime
        var said = began
        let drained = await waitUntil(timeout: Metrics.persistence.shutdownTimeout.value) {
            if traced, ProcessInfo.processInfo.systemUptime - said >= 1 {
                said = ProcessInfo.processInfo.systemUptime
                let pending = self.resources.entries.map { "\($0.key.page.item.rawValue.prefix(8)) presented=\($0.value.presented) leases=\($0.value.leases.count) closing=\($0.value.closing) closed=\($0.value.browserClosed)" }
                FileHandle.standardError.write(Data("fixture core: waiting at +\(Int(said - began)) s: outputs empty=\(self.outputs.isEmpty) preparing=\(self.outputPreparations.count) pages=\(pending)\n".utf8))
            }
            return !self.reconciliation.isApplying && self.outputs.isEmpty && self.outputPreparations.isEmpty && self.resources.entries.isEmpty
        }
        if traced { FileHandle.standardError.write(Data("fixture core: pages \(drained ? "closed" : "did not close") at +\(String(format: "%.2f", ProcessInfo.processInfo.systemUptime - began)) s\n".utf8)) }
        guard drained else {
            outputs.reportTimeout()
            return .timedOut(unclosed: resources.entries.keys.map(\.page).sorted())
        }
        for browser in browsers.values where browser.isAlive { browser.close() }
        browsers.removeAll()
        return .clean
    }

    private func waitUntil(timeout: Double, _ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() {
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func retire(_ page: CorePage) {
        guard ledger.isLive(page.incarnation), ledger.retire(page.id) == page.incarnation else { return }
        resources.unpresent(page.incarnation)
        page.park()
        outputs.sourceGone(page.incarnation)
        closeIfUnowned(page.incarnation)
    }

    private func closeIfUnowned(_ browser: BrowserToken) {
        guard resources.beginClose(browser), let page = resources.entries[browser]?.resource else { return }
        record(.closeRequested, page)
        page.close()
    }

    private func record(_ kind: PageLogEntry.Kind, _ page: CorePage) {
        pageLog.append(PageLogEntry(page: page.id, generation: page.incarnation.generation, kind: kind,
                                    browserID: Int(page.contents.tabID), uptime: ProcessInfo.processInfo.systemUptime))
    }

    // MARK: Called by CorePage

    func isLive(_ page: CorePage) -> Bool { running && ledger.isLive(page.incarnation) && live[page.id] === page }

    func pageLoadProgress(_ page: CorePage, progress: Double) {
        guard progress.isFinite else { return }
        pageDidEmit(page, .loadProgress(min(1, max(0, progress))))
    }

    func pageDidEmit(_ page: CorePage, _ event: PageEvent) {
        guard isLive(page) else { return }
        switch event {
        case .navigationRequested, .rendererGone: outputs.sourceGone(page.incarnation)
        case .gainedFocus:
            guard page.surface.window?.isVisible == true, !page.surface.isHiddenOrHasHiddenAncestor else { return }
        default: break
        }
        delegate?.engine(self, page: page.incarnation, didEmit: event)
        switch event {
        case .committed, .loadingChanged, .titleChanged: restoreFocus(page)
        default: break
        }
    }

    func pageKeyHandling(_ page: CorePage, _ press: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling {
        guard isLive(page), page.surface.window?.isVisible == true, !page.surface.isHiddenOrHasHiddenAncestor else { return KeyHandling(handled: false, shortcut: false) }
        return delegate?.engine(self, page: page.id, keyHandling: press, stage: stage, pressID: pressID) ?? KeyHandling(handled: false, shortcut: false)
    }

    func pageShouldNavigate(_ page: CorePage, to url: URL, userGesture: Bool) -> Bool {
        guard running, live[page.id] === page else { return true }
        return delegate?.engine(self, page: page.id, shouldNavigateTo: url, userGesture: userGesture) ?? true
    }

    func pageReadyForFocus(_ page: CorePage) { restoreFocus(page) }

    func pageDidClose(_ page: CorePage) {
        record(.closed, page)
        let effect = ledger.closed(page.incarnation)
        resources.unpresent(page.incarnation)
        resources.browserClosed(page.incarnation)
        switch effect {
        case .retiredClosed(let liveAgain):
            if !liveAgain, running { delegate?.engine(self, page: page.incarnation, didEmit: .closed) }
        case .liveClosedByPage:
            focusRequests = focusRequests.filter { $0.value.page != page.id }
            if running {
                delegate?.engine(self, page: page.incarnation, didEmit: .closedByPage)
                delegate?.engine(self, page: page.incarnation, didEmit: .closed)
            }
        case .stale: break
        }
        outputs.sourceGone(page.incarnation)
    }

    // MARK: Extensions

    public func invokeExtension(_ id: String, target: SiteTarget) async -> String? {
        guard running, let page = live[target.page], page.readyDocument == target.document else { return "The originating website changed" }
        page.browser.activate(page.contents)
        return page.browser.executeExtensionAction(id)
    }

    public func extensionCatalog(context: BrowsingContext) async -> ExtensionCatalog {
        guard case .profile(let id) = context else {
            return ExtensionCatalog(context: context, extensions: [], error: "Extension management is unavailable in private windows")
        }
        guard let profile = await ensuredProfile(id) else {
            return ExtensionCatalog(context: context, extensions: [], error: "The profile did not load")
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            profile.whenExtensionsReady { continuation.resume() }
        }
        let values = profile.installedExtensions().map { item in
            BrowserExtension(id: item.extensionID, name: item.name, version: item.version, enabled: item.enabled,
                             supportsNativeAction: item.hasAction, icon: item.iconData)
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return ExtensionCatalog(context: context, extensions: values, error: nil)
    }

    private func ensuredProfile(_ id: ProfileID) async -> (any BrkCoreProfile)? {
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let profile = loadedProfile(id) { return profile }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    public func installExtension(at directory: URL, context: BrowsingContext, in page: PageID) async -> String? {
        guard case .profile(let id) = context, let profile = await ensuredProfile(id) else { return "Private installation is disabled" }
        return await withCheckedContinuation { continuation in
            profile.installUnpackedExtension(atPath: directory.path) { _, error in continuation.resume(returning: error) }
        }
    }

    // MARK: BrkCoreBrowserDelegate: an extension's action popup

    private var popupPanel: NSPanel?
    private var popupObserver: NSObjectProtocol?
    private weak var popupBrowser: (any BrkCoreBrowser)?

    public func browser(_ browser: any BrkCoreBrowser, didOpenExtensionPopup extensionID: String, view: NSView) {
        closePopupPanel()
        let panel = ExtensionPopupPanel(contentRect: NSRect(x: 0, y: 0, width: 25, height: 25),
                                        styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        placePopup(panel, for: browser, size: NSSize(width: 25, height: 25))
        panel.makeKeyAndOrderFront(nil)
        browser.focusExtensionPopup()
        popupPanel = panel
        popupBrowser = browser
        // As Chrome's bubble: it closes when it loses focus.
        popupObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { [weak browser] in browser?.closeExtensionPopup() }
        }
    }

    public func browser(_ browser: any BrkCoreBrowser, didResizeExtensionPopup extensionID: String, size: NSSize) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            FileHandle.standardError.write(Data("fixture core: popup \(extensionID.prefix(8)) size \(Int(size.width))x\(Int(size.height)) panel=\(popupPanel != nil)\n".utf8))
        }
        guard let popupPanel else { return }
        placePopup(popupPanel, for: browser, size: size)
    }

    public func browser(_ browser: any BrkCoreBrowser, didCloseExtensionPopup extensionID: String) { closePopupPanel() }

    private func closePopupPanel() {
        if let popupObserver { NotificationCenter.default.removeObserver(popupObserver) }
        popupObserver = nil
        popupPanel?.contentView = nil
        popupPanel?.orderOut(nil)
        popupPanel = nil
    }

    /// Under the owner window's top right, where Arc's toolbar opens it.
    private func placePopup(_ panel: NSPanel, for browser: any BrkCoreBrowser, size: NSSize) {
        let content = NSSize(width: size.width, height: size.height)
        let frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        let owner = browser.window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: owner.maxX - frame.width - 12, y: owner.maxY - frame.height - 48, width: frame.width, height: frame.height), display: true)
    }
}

/// Keeps key status while it hosts Chromium's popup page.
private final class ExtensionPopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
