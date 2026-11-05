import AppKit
import BrkBase
import BrkEngine
import CCef
import CCefAppKit
import CefKit
import os

/// `WebEngine` over CEF's Chrome runtime with the embed technique the hosting spike verified
/// (docs/swift/cef-hosting-results.md, "Mode B embed"): each page is a frameless Chrome-runtime browser in its own
/// CEF-owned host window; Chromium's `ViewsCompositorSuperview` and `WebContentsViewCocoa` are moved out of that
/// window into our `EmbeddedSurface`, which sits in a clipped, rounded card. The host window stays alive as a
/// click-through child window that can never become key.
///
/// Everything here runs on the main actor: CefKit is `@MainActor` end to end and CEF's UI thread is the main thread
/// (external message pump).
@MainActor
public final class CEFEngine: WebEngine {
    public struct Configuration: Sendable {
        /// CEF's root cache path: `<data dir>/Chromium` (profiles live under it).
        public var cacheDirectory: URL
        public var remoteDebuggingPort: Int?
        public init(cacheDirectory: URL, remoteDebuggingPort: Int?) {
            self.cacheDirectory = cacheDirectory
            self.remoteDebuggingPort = remoteDebuggingPort
        }
    }

    public weak var delegate: (any WebEngineDelegate)?
    public private(set) var pageLog: [PageLogEntry] = []
    /// The Chromium the pinned CEF headers (and so the downloaded binary) were built from.
    public var engineVersion: String? { "\(CHROME_VERSION_MAJOR).\(CHROME_VERSION_MINOR).\(CHROME_VERSION_BUILD).\(CHROME_VERSION_PATCH)" }

    /// Which incarnation of each id is live or closing (BrkEngine/PageLedger.swift). The browsers themselves:
    var pictureInPictureWindows: [CefBrowser] {
        resources.entries.values.flatMap { $0.resource.pictureInPictureAuxiliaries }
    }
    let resources = BrowserResources<ChromePage>()
    var live: [PageID: ChromePage] {
        Dictionary(uniqueKeysWithValues: resources.entries.filter { $0.value.presented }.map { ($0.key.page, $0.value.resource) })
    }
    let transfers = Transfers()
    let filterLists = FilterListCache()
    private let outputs = DocumentOutputs()
    private var outputAdapters: [OutputID: AnyObject] = [:]
    private var outputPreparations: [OutputID: Task<Void, Never>] = [:]
    var contexts = ContextLifetimes()
    var cancelledSiteClears: Set<String> = []
    var clearingContexts: [BrowsingContext: String] = [:]
    private var disposals: [DisposalID: ContextDisposal] = [:]
    private var disposalResults: [DisposalID: ContextDisposalResult] = [:]
    private var ledger = PageLedger()
    /// One CEF request context per browsing context, created on first use (`profile(for:)`). The default profile
    /// is the runtime's own cache; a custom profile is `<rootCachePath>/Profile-<id>`; incognito is in memory.
    private var profiles: [BrowsingContext: CefProfile] = [:]
    private var audioObservers: [BrowsingContext: ChromeAudibility] = [:]
    private var audioLoop: Task<Void, Never>?
    /// Persistent profiles Chromium is loading or has loaded (`ProfileLoader`); a page in one waits for `ready`.
    private var loaders: [ProfileID: ProfileLoader] = [:]
    /// Cast receiver discovery for Default-profile pages (`PageCast`): an owned persistent context of its own,
    /// `<rootCachePath>/Profile-brk-cast-receivers`, created on the first Cast and released with the profiles at
    /// shutdown. Nil context until Chromium reports it initialized.
    private var castService: ProfileLoader?
    private var castServiceReady = false
    private var castServiceWaiters: [@MainActor (UnsafeMutablePointer<cef_request_context_t>?) -> Void] = []
    /// The last `reconcile` input, replayed when a profile finishes loading.
    var wanted: [PageSpec] = []
    private let reconciliation = PageReconciliation()
    var phase: ShutdownPhase = .running
    /// Help > Open Task Manager's CEF task manager, kept from its first use until shutdown: Chromium measures CPU and
    /// memory only while an observer stays registered (EngineDiagnostics.swift).
    var taskManager: UnsafeMutablePointer<cef_task_manager_t>?
    private var appearanceObservation: NSKeyValueObservation?
    private var shutdownTask: Task<ShutdownOutcome, Never>?
    /// Each native window keeps its own page intent, including while a profile or input view is being created.
    /// A native editor in another window must not cancel this request. Weak ownership permits window teardown.
    private struct FocusRequest {
        weak var window: NSWindow?
        let page: PageID
    }
    private var focusRequests: [ObjectIdentifier: FocusRequest] = [:]
    private let log = Logger(subsystem: "brk", category: "cef")

    enum ShutdownPhase: Equatable {
        case running
        /// Moved Chromium views are going back into their host windows; host windows leave our window.
        case restoringViews
        /// `close(force: true)` sent to every browser; waiting for each `OnBeforeClose`.
        case closingBrowsers
        /// `CefRuntime.shared.shutdown()` (cef_shutdown + framework unload).
        case shuttingDownRuntime
        case done
    }

    /// Initializes CEF. Must run in main.swift before anything touches `NSApp`: it installs `CEFApplication` as the
    /// application class, which CEF requires from the first event. Throws if the framework cannot be loaded (for
    /// example `swift run` outside the .app); main.swift then exits with a message pointing at scripts/build.sh.
    public static func bootstrap(_ configuration: Configuration) throws -> CEFEngine {
        var config = CefConfiguration()
        // CEF compares cache_path against the real path of root_cache_path, so /tmp must become /private/tmp here too
        // or it rejects the pair and falls back to in-memory storage. Foundation's symlink resolution strips
        // /private on purpose, so this is realpath(3) on the created directory.
        let root = Self.realPath(of: configuration.cacheDirectory)
        ProfileDirectories(root: root).deleteMarked()
        config.rootCachePath = root
        config.cachePath = root.appendingPathComponent("Default", isDirectory: true)
        // Chrome otherwise restores last_used as its global profile, including a custom Brk profile.
        config.extraCommandLineSwitches["profile-directory"] = "Default"
        config.logFile = root.deletingLastPathComponent().appendingPathComponent("cef-debug.log")
        config.remoteDebuggingPort = configuration.remoteDebuggingPort
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            // Chromium's own log, for looking into what a slow quit waits for (r5-2/quit-probe.py).
            if let log = ProcessInfo.processInfo.environment["BRK_TEST_CEF_LOG"], !log.isEmpty {
                config.logFile = URL(fileURLWithPath: log)
                config.logSeverity = .verbose
            }
            config.safeStorage = .mockKeychain
            config.extraCommandLineSwitches["host-resolver-rules"] = "MAP *.brk.test 127.0.0.1, MAP *.localhost 127.0.0.1"
            // The https fixture's certificate (verify/visual-pairs/https-fixture): Chromium accepts this one public key
            // as if a trusted root had issued it. Test launches only; no keychain or system trust setting changes.
            if let spki = ProcessInfo.processInfo.environment["BRK_TEST_TRUSTED_SPKI"], !spki.isEmpty {
                config.extraCommandLineSwitches["ignore-certificate-errors-spki-list"] = spki
            }
        }
        config.defaultRuntimeStyle = .chrome
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            config.extraCommandLineSwitches["use-mock-keychain"] = .some(nil)
        }
        AudioExtension.configure(&config)
        try CefRuntime.shared.initialize(configuration: config)
        // CefSwift's terminate handler closes browsers while their views are still moved into our window, which
        // segfaulted on quit in every spike run. Replace it with auxiliary-dialog cancellation only. Once those
        // choices are dismissed, -terminate: reaches applicationShouldTerminate and Lifecycle's ordered shutdown.
        CEFApplication.setTerminateHandler { () -> ObjCBool in
            ObjCBool(MainActor.assumeIsolated { HostWindows.prepareForApplicationTermination() })
        }
        HostWindows.installKeyGuard()
        return CEFEngine()
    }

    private init() {
        filterLists.loaded = { [weak self] in
            guard let self, self.phase == .running else { return }
            for page in self.live.values { page.configureRequestFilter(page.browser.url); page.refreshWebsitePolicy() }
        }
        resources.leasesDidChange = { [weak self] browser in
            guard let self, self.phase == .running, let page = self.resources.entries[browser]?.resource else { return }
            page.refreshWebsitePolicy()
        }
        outputs.acquire = { [weak self] id, browser in self?.resources.acquire(.documentOutput(id.rawValue), browser: browser) ?? false }
        outputs.release = { [weak self] id, browser in
            guard let self else { return }
            self.resources.release(.documentOutput(id.rawValue), browser: browser)
            self.closeIfUnowned(browser)
        }
        outputs.available = { [weak self] request, epoch in
            guard let self, self.phase == .running, self.contexts.permitsWork(epoch.context),
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
        outputs.render = { [weak self] request, path, done in
            guard let self, let page = self.resources.entries[request.document.browser]?.resource,
                  page.readyDocument == request.document else { done(.failure(CocoaError(.userCancelled))); return }
            let preparation = Task { @MainActor [weak self] in
                guard let self else { done(.failure(CocoaError(.userCancelled))); return }
                do {
                    try await page.resumeForOperation(request.document)
                    guard self.phase == .running, self.outputs.permitsRender(request.id),
                          page.readyDocument == request.document else {
                        self.outputPreparations[request.id] = nil
                        done(.failure(CocoaError(.userCancelled))); return
                    }
                    self.outputPreparations[request.id] = nil
                    let adapter: AnyObject
                    if request.intent == .mhtml {
                        adapter = page.browser.captureMHTML { [weak self] result in
                            self?.outputAdapters[request.id] = nil
                            do { try result.get().write(to: path, options: .withoutOverwriting); done(.success(())) }
                            catch { done(.failure(error)) }
                        }
                    } else {
                        adapter = page.browser.printPDF(to: path) { [weak self] ok in
                            self?.outputAdapters[request.id] = nil
                            done(ok ? .success(()) : .failure(CocoaError(.fileWriteUnknown)))
                        }
                    }
                    if self.outputs.contains(request.id) { self.outputAdapters[request.id] = adapter }
                } catch {
                    self.outputPreparations[request.id] = nil
                    done(.failure(error))
                }
            }
            self.outputPreparations[request.id] = preparation
        }

        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.phase == .running else { return }
                for page in self.live.values where page.websitePolicy.appearance == .automatic { page.refreshWebsitePolicy() }
            }
        }
        transfers.publish = { [weak self] update in
            guard let self else { return }
            self.delegate?.engine(self, download: update)
        }
        transfers.prompt = { [weak self] prompt, reply in
            guard let self, let delegate = self.delegate else { reply(.ownerGone); return }
            delegate.engine(self, destination: prompt, reply: reply)
        }
        transfers.dismiss = { [weak self] ticket in
            guard let self else { return }; self.delegate?.engine(self, dismissDestination: ticket)
        }
        transfers.acquire = { [weak self] id, browser in self?.resources.acquire(.transfer(id), browser: browser) ?? false }
        transfers.release = { [weak self] id, browser in
            guard let self else { return }
            self.resources.release(.transfer(id), browser: browser)
            self.closeIfUnowned(browser)
        }
    }

    private static func realPath(of directory: URL) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let resolved = realpath(directory.path, nil) else { return directory }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    public func reconcile(_ pages: [PageSpec]) {
        guard phase == .running else { return }
        wanted = pages.filter { contexts.permitsWork($0.context) }
        reconciliation.submit(wanted, invalidate: {
            for page in Array(self.live.values) where !self.wanted.contains(where: { $0.id == page.id && $0.context == page.context }) {
                self.retire(page)
            }
        }) { self.applyDemand($0) }
    }

    private func applyDemand(_ pages: [PageSpec]) {
        guard phase == .running else { return }
        let pages = pages.filter { contexts.permitsWork($0.context) }
        let wanted = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        focusRequests = focusRequests.filter { $0.value.window != nil && wanted[$0.value.page] != nil }
        for spec in pages {
            guard phase == .running, contexts.permitsWork(spec.context),
                  self.wanted.contains(where: { $0.id == spec.id && $0.context == spec.context }) else { continue }
            if let page = live[spec.id] { page.downloadPolicy = spec.downloadPolicy; page.setMuted(spec.muted); page.applyWebsitePolicy(spec.websitePolicy); page.linkPreviews.setEnabled(spec.hoverPreviews); page.applyBoostPolicy(spec.boostPolicy); continue }
            guard let url = spec.initialURL, isReady(spec.context) else { continue }
            let context = contexts.epoch(for: spec.context)
            let incarnation = ledger.create(spec.id)
            let page = ChromePage(spec: spec, url: url, engine: self, incarnation: incarnation, adopting: claimPopupHost(url, context: spec.context))
            resources.insert(page, browser: incarnation, context: context)
            record(.created, page)
            guard phase == .running, contexts.permitsWork(spec.context),
                  self.wanted.contains(where: { $0.id == spec.id && $0.context == spec.context && $0.initialURL == spec.initialURL }) else {
                retire(page)
                continue
            }
            delegate?.engine(self, page: incarnation, didEmit: .browserCreated(spec.context, .unavailable))
            page.reportInitialLoading()
        }
        guard phase == .running else { return }
        if audioLoop == nil {
            audioLoop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    await self?.pollAudio()
                }
            }
        }
    }

    private func pollAudio() async {
        guard phase == .running else { return }
        let grouped = Dictionary(grouping: Array(live.values), by: \.context)
        for (context, observer) in audioObservers where observer.drained { audioObservers[context] = nil }
        for (context, observer) in audioObservers where grouped[context] == nil {
            observer.stop()
            if observer.drained { audioObservers[context] = nil }
        }
        for (context, pages) in grouped {
            guard phase == .running, contexts.permitsWork(context) else { continue }
            let observer: ChromeAudibility
            if let existing = audioObservers[context] {
                guard !existing.stopping else { continue }
                observer = existing
            }
            else {
                observer = ChromeAudibility(context: context, profile: profile(for: context))
                audioObservers[context] = observer
            }
            for page in pages { await page.resolveAudioTarget() }
            // A frozen page cannot change until it is thawed, and reading it would stall the whole context's reading.
            let requests = pages.filter { !$0.frozen }.compactMap { page in page.audio.ticket.map { (page, $0) } }
            do {
                let readings = try await observer.read(targets: requests.map { $0.1.target })
                guard phase == .running, contexts.permitsWork(context), audioObservers[context] === observer else { continue }
                for (page, ticket) in requests {
                    let matches = readings.filter { $0.target == ticket.target }
                    if matches.count == 1 { page.applyAudio(matches[0], ticket: ticket, observer: observer.browserID) }
                    else if isLive(page) { page.audioUnavailable("No current target in the context's audio observer") }
                }
            } catch { for page in pages where isLive(page) { page.audioUnavailable(String(describing: error)) } }
        }
    }

    public func surface(for page: PageID) -> PageSurfaceView? { live[page]?.surface }

    public func perform(_ action: PageAction, on page: PageID) {
        guard phase == .running, let live = live[page] else { return }
        let browser = live.browser
        switch action {
        case .navigate, .goBack, .goForward, .reload, .recover: outputs.sourceGone(live.incarnation)
        default: break
        }
        switch action {
        case .navigate(let url): live.prepareNavigation(); browser.load(url)
        case .goBack: live.prepareNavigation(); browser.goBack()
        case .goForward: live.prepareNavigation(); browser.goForward()
        case .reload(let ignoringCache): live.requestReload(ignoringCache: ignoringCache)
        case .stop: live.prepareStop(); browser.stopLoading()
        case .zoom(let step):
            browser.zoomLevel = BrowserZoom.next(step, level: browser.zoomLevel)
            live.reportZoom()
            DispatchQueue.main.async { [weak live] in live?.reportZoom() }
        case .toggleDevTools: browser.toggleDevTools()
        case .cast: live.showCast()
        case .developer(let operation): live.developer(operation)
        case .documentPictureInPicture(let request):
            live.controlDocumentPiP(request)
        case .media(let request):
            guard request.document == live.readyDocument, live.mediaPlayers.contains(where: { $0.id == request.player }),
                  let target = live.audio.target, let tab = live.audio.tab,
                  let observer = audioObservers[live.context], contexts.permitsWork(live.context) else { return }
            Task { @MainActor [weak self, weak live] in
                var error: String?
                do {
                    // Automatic entry (Arc's "auto picture in picture" when the user leaves a playing video tab) is
                    // the browser acting on that user's tab switch, as Chromium's own automatic entry is: it runs
                    // with the browser's gesture, so it no longer depends on the page's transient activation, which
                    // expires five seconds after the user last touched the page. As with an explicit PiP request, the
                    // injected call runs with that gesture inside the page.
                    let gesture = request.userInitiated || request.operation == .enterPictureInPicture
                    try await observer.control(target: target, tab: tab, player: request.player, operation: request.operation, volume: request.volume, userInitiated: gesture)
                    if !request.userInitiated, request.operation == .enterPictureInPicture, let self, let live,
                       !self.isLive(live) || live.readyDocument != request.document || live.websitePolicy.visible {
                        try? await observer.control(target: target, tab: tab, player: request.player, operation: .exitPictureInPicture, userInitiated: false)
                    }
                }
                catch let failure { error = String(describing: failure) }
                guard let self, let live, self.isLive(live), live.readyDocument == request.document else { return }
                live.mediaControlFinished(error)
            }
        case .exitFullscreen: browser.exitFullscreen()
        case .recover: live.prepareNavigation(); browser.reload()
        }
    }

    public func focus(_ page: PageID?, in window: NSWindow) {
        guard phase == .running else { return }
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

    /// Readiness and page callbacks may complete a request after the store has rendered. They cannot take focus
    /// from a native responder or follow a surface that moved to a different window.
    private func restoreFocus(_ page: ChromePage) {
        guard phase == .running, live[page.id] === page, let window = page.surface.window, window.isVisible,
              let request = focusRequests[ObjectIdentifier(window)], request.window === window, request.page == page.id,
              window.firstResponder == nil || window.firstResponder === window,
              !page.surface.isHiddenOrHasHiddenAncestor, page.surface.isReadyForFocus else { return }
        page.takeFocus()
    }

    public func evaluate(_ script: String, in page: PageID) {
        guard phase == .running else { return }
        live[page]?.browser.executeJavaScript(script)
    }

    /// Shared Quotes: the focused frame's highlighted text (same-origin iframes followed), through DevTools.
    public func selectedText(_ page: PageID) async -> String? {
        guard phase == .running, let browser = live[page]?.browser, let transport = CefDevTools(browser: browser) else { return nil }
        defer { transport.invalidate() }
        let script = "(()=>{try{let d=document;while(d.activeElement?.tagName==='IFRAME'&&d.activeElement.contentDocument)d=d.activeElement.contentDocument;return d.getSelection().toString().slice(0,4000)}catch{return ''}})()"
        guard let result = try? await transport.call("Runtime.evaluate", parameters: ["expression": script, "returnByValue": true]),
              let json = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
              let text = (json["result"] as? [String: Any])?["value"] as? String, !text.isEmpty else { return nil }
        return text
    }

    public func checkSelection(_ id: PageID) {
        guard phase == .running, let page = live[id], !page.isAIReader, let document = page.readyDocument else { return }
        Task { @MainActor [weak self, weak page] in
            let text = await self?.selectedText(id)
            guard let self, let page, self.isLive(page), page.readyDocument == document else { return }
            let selected = !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard page.reportedSelection != selected else { return }
            page.reportedSelection = selected
            self.pageDidEmit(page, .selectionChanged(document, selected))
        }
    }

    public func facts(for id: PageID) -> PageFacts? {
        guard let page = live[id] else { return nil }
        var facts = page.facts
        facts.context = page.context
        let native = ProfileDataStore.inspect(browser: Int(page.browser.id))
        facts.nativeContextPath = native?.path
        facts.nativeContextIsGlobal = native?.global
        return facts
    }
    public func isPageHostWindow(_ window: NSWindow) -> Bool { HostWindows.isHost(window) }

    public func find(_ request: FindRequest) {
        guard phase == .running, let page = live[request.document.browser.page], page.incarnation == request.document.browser else { return }
        page.find.perform(request)
    }
    func findUpdated(_ update: FindUpdate) { delegate?.engine(self, find: update) }
    public func output(_ request: OutputRequest) {
        guard let entry = resources.entries[request.document.browser] else {
            delegate?.engine(self, output: OutputUpdate(id: request.id, document: request.document, stage: .terminal(.failed("Document has closed", .absent))))
            return
        }
        outputs.start(request, context: entry.context)
    }
    public func cancelOutput(_ id: OutputID) { outputs.cancel(id) }

    public func cancelDownload(_ id: DownloadID) { transfers.cancel(id) }

    public func disposeContext(_ request: ContextDisposal) {
        guard disposalResults[request.id] == nil, disposals[request.id] == nil else { return }
        guard request.context != .profile(.default) else {
            finishDisposal(request, .failed(request.id, request.context, reason: "Default profile cannot be disposed"))
            return
        }
        // No asynchronous hop before revocation. A late loader may finish but cannot publish new demand.
        contexts.revoke(request.context)
        audioObservers[request.context]?.stop()
        wanted.removeAll { $0.context == request.context }
        disposals[request.id] = request
        outputs.revoke(request.context)
        transfers.revoke(request.context)
        for page in live.values where page.context == request.context { retire(page) }
        Task { @MainActor in
            let drained = await self.waitUntil(timeout: Metrics.persistence.shutdownTimeout.value) {
                !self.reconciliation.isApplying && !self.resources.entries.values.contains { $0.context.context == request.context }
                    && !self.outputs.contains(context: request.context)
                    && !self.transfers.contains(context: request.context)
                    && self.clearingContexts[request.context] == nil
                    && self.contexts.isDrained(request.context)
                    && (self.audioObservers[request.context]?.drained ?? true)
            }
            guard drained else {
                self.transfers.reportTimeout(context: request.context)
                self.finishDisposal(request, .failed(request.id, request.context, reason: "Context callbacks or native hosts did not drain"))
                return
            }
            self.profiles[request.context]?.release()
            self.audioObservers[request.context] = nil
            self.profiles[request.context] = nil
            do {
                let disposition: DataDisposition
                switch request.context {
                case .profile(let id):
                    self.loaders.removeValue(forKey: id)?.release()
                    guard let directories = self.profileDirectories else { throw CocoaError(.fileWriteUnknown) }
                    try directories.mark(id)
                    disposition = .deletionScheduledForNextLaunch
                case .incognito: disposition = .memoryReleased
                }
                self.finishDisposal(request, .completed(request.id, request.context, disposition))
            } catch { self.finishDisposal(request, .failed(request.id, request.context, reason: error.localizedDescription)) }
        }
    }

    private func finishDisposal(_ request: ContextDisposal, _ result: ContextDisposalResult) {
        guard disposalResults[request.id] == nil else { return }
        disposals[request.id] = nil
        disposalResults[request.id] = result
        Task { @MainActor [weak self] in
            guard let self else { return }; self.delegate?.engine(self, contextDisposed: result)
        }
    }
    /// Whether pages can be created in `context` now. The default profile and incognito (an off-the-record profile
    /// of the loaded default one) always can; a persistent profile once Chromium has loaded it (`ProfileLoader`),
    /// after which every waiting page is created by replaying the last `reconcile`.
    private func isReady(_ context: BrowsingContext) -> Bool {
        guard phase == .running, contexts.permitsWork(context) else { return false }
        if contexts.isReady(context) { return true }
        guard case .profile(let id) = context, let root = CefRuntime.shared.configuration?.rootCachePath else { return false }
        if contexts.beginLoading(context) {
            let path = root.appendingPathComponent(ProfileDirectories.directoryName(id), isDirectory: true)
            loaders[id] = ProfileLoader(cachePath: path) { [weak self] in
                guard let self else { return }
                self.contexts.initialized(context)
                // A synchronous readiness callback cannot replay until the loader has been installed.
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .running, self.contexts.isReady(context) else { return }
                    self.reconcile(self.wanted)
                }
            }
        }
        return false
    }

    /// The receiver-service request context, after Chromium has initialized it; nil when the engine is not running.
    func castServiceContext(_ done: @escaping @MainActor (UnsafeMutablePointer<cef_request_context_t>?) -> Void) {
        guard phase == .running, let root = CefRuntime.shared.configuration?.rootCachePath else { done(nil); return }
        if castServiceReady { done(castService?.context); return }
        castServiceWaiters.append(done)
        guard castService == nil else { return }
        let path = root.appendingPathComponent(ProfileDirectories.directoryName(ProfileID("brk-cast-receivers")), isDirectory: true)
        castService = ProfileLoader(cachePath: path) { [weak self] in
            // The readiness callback can arrive inside the loader's initializer; finish after it is installed.
            Task { @MainActor [weak self] in
                guard let self, self.castService != nil else { return }
                self.castServiceReady = true
                let waiters = self.castServiceWaiters; self.castServiceWaiters = []
                for waiter in waiters { waiter(self.phase == .running ? self.castService?.context : nil) }
            }
        }
    }

    func dataStore(for profile: ProfileID) async throws -> ProfileDataStore {
        let context = BrowsingContext.profile(profile)
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while !isReady(context) {
            guard phase == .running, contexts.permitsWork(context), ProcessInfo.processInfo.systemUptime < deadline else {
                throw CocoaError(.userCancelled)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let raw: UnsafeMutablePointer<cef_request_context_t>?
        if profile == .default { raw = cef_request_context_get_global_context() }
        else {
            raw = loaders[profile]?.context
            if let raw {
                let base = UnsafeMutableRawPointer(raw).assumingMemoryBound(to: cef_base_ref_counted_t.self)
                base.pointee.add_ref?(base)
            }
        }
        guard let raw else { throw CocoaError(.featureUnsupported) }
        return ProfileDataStore(context: raw)
    }

    /// The request context for a page's browsing context (BrkEngine/WebEngine.swift `BrowsingContext`): nil for the
    /// default profile (the runtime's own cache, `<rootCachePath>/Default`), one persistent context per other
    /// profile in `<rootCachePath>/Profile-<id>`, one shared off-the-record context for every incognito page.
    /// Created on first use and released only after context disposal drains its owners.
    func profile(for context: BrowsingContext) -> CefProfile? {
        precondition(contexts.permitsWork(context) && phase == .running)
        if let existing = profiles[context] { return existing }
        let profile: CefProfile
        switch context {
        case .profile(.default): return nil
        case .profile(let id): profile = .persistent(name: id.rawValue)
        case .incognito:
            let enabled = AudioExtension.allowPrivateAccess()
            log.notice("bundled audio extension private permission=\(enabled, privacy: .public)")
            profile = .incognito()
        }
        profiles[context] = profile
        return profile
    }

    /// Where CefSwift puts persistent profiles: the runtime's root cache path, the one `CefProfile` reads.
    private var profileDirectories: ProfileDirectories? {
        CefRuntime.shared.configuration?.rootCachePath.map(ProfileDirectories.init(root:))
    }

    public func shutdown() async -> ShutdownOutcome {
        if let shutdownTask { return await shutdownTask.value }
        let task = Task { @MainActor in await self.runShutdown() }
        shutdownTask = task
        return await task.value
    }

    /// The order is the fix for the spike's crash at quit (cef-hosting-results.md, risk 1):
    /// 1. restoringViews: every surface gives Chromium's views back to their host window's content view, and every
    ///    host window is removed from our window's children (`EmbeddedSurface.returnViews()`).
    /// 2. closingBrowsers: `close(force: true)` for every live page (closing ones are already on their way); await
    ///    each `browserDidClose` (OnBeforeClose), bounded by Metrics.persistence.shutdownTimeout. Then give CEF a
    ///    moment to destroy the emptied host windows (every `onWindowDestroyed`, or 1 s).
    /// 3. Close Chromium's auxiliary native widgets before their observers and runtime disappear.
    /// 4. On time: shuttingDownRuntime, `CefRuntime.shared.shutdown()`, `.clean`. Timed out: log each unclosed page,
    ///    skip the runtime shutdown (cef_shutdown with browsers alive is the crash), `.timedOut`. Nothing touches CEF
    ///    after this either way.
    private func runShutdown() async -> ShutdownOutcome {
        // Test instances log each step's time: R4-7 and R4-10 saw quits pass 10 s under load, ending in Chromium's
        // own "Teardown watchdog expired" (chrome/browser/shutdown_watchdog_mac.cc) inside cef_shutdown.
        let traced = ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil, began = ProcessInfo.processInfo.systemUptime
        func trace(_ step: String) {
            guard traced else { return }
            FileHandle.standardError.write(Data(String(format: "fixture cef: %@ at +%.2f s\n", step, ProcessInfo.processInfo.systemUptime - began).utf8))
        }
        if traced { FileHandle.standardError.write(Data("fixture cef: shutdown started\n".utf8)) }
        appearanceObservation = nil
        phase = .restoringViews
        audioLoop?.cancel(); audioLoop = nil
        for observer in audioObservers.values { observer.stop() }
        focusRequests.removeAll()
        wanted = []
        contexts.stop()
        outputs.stop()
        transfers.stop()
        for page in live.values { retire(page) }
        let drained = await waitUntil(timeout: Metrics.persistence.shutdownTimeout.value) {
            !self.reconciliation.isApplying && self.pictureInPictureWindows.isEmpty && self.outputs.isEmpty && self.outputPreparations.isEmpty && self.transfers.isEmpty && self.resources.entries.isEmpty && self.contexts.readinessDrained && self.disposals.isEmpty
                && self.audioObservers.values.allSatisfy(\.drained) && self.clearingContexts.isEmpty
        }
        trace(drained ? "browsers closed" : "browsers did not close")
        guard drained else {
            outputs.reportTimeout()
            transfers.reportTimeout()
            log.fault("shutdown did not drain: \(self.resources.entries.count, privacy: .public) browser/host records; transfers empty=\(self.transfers.isEmpty, privacy: .public); readiness drained=\(self.contexts.readinessDrained, privacy: .public)")
            phase = .done
            return .timedOut(unclosed: resources.entries.keys.map(\.page).sorted())
        }
        phase = .closingBrowsers
        audioObservers.removeAll()
        for profile in profiles.values { profile.release() }
        profiles.removeAll()
        for loader in loaders.values { loader.release() }
        loaders.removeAll()
        let castWaiters = castServiceWaiters; castServiceWaiters = []
        for waiter in castWaiters { waiter(nil) }
        castService?.release(); castService = nil; castServiceReady = false
        HostWindows.closeAuxiliaryWindows()
        phase = .shuttingDownRuntime
        releaseTaskManager()
        // r5-2/quit-probe.py --no-raise measures a test instance without this.
        if !traced || ProcessInfo.processInfo.environment["BRK_TEST_NO_QOS_RAISE"] == nil { ShutdownThreads.raiseBackgroundWorkers() }
        trace("runtime shutdown starting")
        CefRuntime.shared.shutdown()
        trace("runtime shut down")
        phase = .done
        log.notice("shutdown: clean")
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

    // MARK: Called by ChromePage

    func isLive(_ page: ChromePage) -> Bool {
        phase == .running && ledger.isLive(page.incarnation) && live[page.id] === page
    }

    func pageLoadProgress(_ page: ChromePage, progress: Double) {
        guard progress.isFinite else { return }
        pageDidEmit(page, .loadProgress(min(1, max(0, progress))))
    }

    func pageRendererTerminated(_ page: ChromePage) { pageDidEmit(page, .rendererGone) }

    func pageDidEmit(_ page: ChromePage, _ event: PageEvent) {
        guard isLive(page) else { return }
        page.linkPreviews.observe(event)
        if case .committed = event, let document = page.readyDocument { page.linkPreviews.observe(.documentChanged(.ready(document))) }
        switch event {
        case .navigationRequested, .rendererGone: outputs.sourceGone(page.incarnation)
        default: break
        }
        if case .gainedFocus = event {
            guard page.surface.window?.isVisible == true, !page.surface.isHiddenOrHasHiddenAncestor else { return }
        }
        delegate?.engine(self, page: page.incarnation, didEmit: event)
        switch event {
        case .committed, .loadingChanged, .titleChanged:
            restoreFocus(page)
        default:
            break
        }
    }

    func pageKeyHandling(_ page: ChromePage, _ press: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling {
        guard isLive(page), page.surface.window?.isVisible == true, !page.surface.isHiddenOrHasHiddenAncestor else { return KeyHandling(handled: false, shortcut: false) }
        return delegate?.engine(self, page: page.id, keyHandling: press, stage: stage, pressID: pressID) ?? KeyHandling(handled: false, shortcut: false)
    }

    /// OnBeforeBrowse for a live page: the delegate decides (Peek from Pinned and Favorites, F3).
    func pageShouldNavigate(_ page: ChromePage, to url: URL, userGesture: Bool) -> Bool {
        guard phase == .running, live[page.id] === page else { return true }
        return delegate?.engine(self, page: page.id, shouldNavigateTo: url, userGesture: userGesture) ?? true
    }

    /// The page's input view arrived in its surface: apply the focus that was waiting for it.
    func pageReadyForFocus(_ page: ChromePage) {
        restoreFocus(page)
    }

    /// OnBeforeClose for any incarnation. The ledger says what it may do: a retired incarnation's close never removes
    /// or reports closure for a newer incarnation of the same id; a close the engine did not start is page-initiated
    /// (`window.close()`), reported as `.closedByPage` so the domain drops the page demand, then `.closed`.
    func pageDidClose(_ page: ChromePage) {
        record(.closed, page)
        let effect = ledger.closed(page.incarnation)
        resources.unpresent(page.incarnation)
        resources.browserClosed(page.incarnation)
        switch effect {
        case .retiredClosed(let liveAgain):
            if !liveAgain, phase == .running { delegate?.engine(self, page: page.incarnation, didEmit: .closed) }
        case .liveClosedByPage:
            focusRequests = focusRequests.filter { $0.value.page != page.id }
            page.surface.returnViews()
            if phase == .running {
                delegate?.engine(self, page: page.incarnation, didEmit: .closedByPage)
                delegate?.engine(self, page: page.incarnation, didEmit: .closed)
            }
        case .stale: break
        }
        // A transfer result can synchronously publish/reconcile. Remove page demand before publishing it.
        outputs.sourceGone(page.incarnation)
        transfers.browserClosed(page.incarnation)
    }

    func pageWindowDidClose(_ page: ChromePage) { resources.hostClosed(page.incarnation) }

    /// A popup Chromium is about to create, offered to the page the domain makes for it while `open` runs (the
    /// domain reduces and reconciles synchronously). True when a page in the same context for the same address
    /// took it; the popup then keeps its opener.
    private var offeredPopup: (host: CefChromeBrowser, url: URL, context: BrowsingContext)?
    func offerPopupHost(_ host: CefChromeBrowser, url: URL, context: BrowsingContext, open: () -> Void) -> Bool {
        offeredPopup = (host, url, context)
        open()
        let taken = offeredPopup == nil
        offeredPopup = nil
        return taken
    }
    private func claimPopupHost(_ url: URL, context: BrowsingContext) -> CefChromeBrowser? {
        guard let offer = offeredPopup, offer.url.absoluteString == url.absoluteString, offer.context == context else { return nil }
        offeredPopup = nil
        return offer.host
    }

    func auxiliaryCountChanged(_ page: ChromePage, count: Int) {
        let lease = BrowserResources<ChromePage>.Lease.auxiliary("native-children")
        if count > 0 { _ = resources.acquire(lease, browser: page.incarnation) }
        else { resources.release(lease, browser: page.incarnation); closeIfUnowned(page.incarnation) }
    }

    private func retire(_ page: ChromePage) {
        guard ledger.isLive(page.incarnation), ledger.retire(page.id) == page.incarnation else { return }
        resources.unpresent(page.incarnation)
        page.park()
        outputs.sourceGone(page.incarnation)
        transfers.sourceGone(page.incarnation)
        closeIfUnowned(page.incarnation)
    }
    func closeIfUnowned(_ browser: BrowserToken) {
        guard resources.beginClose(browser), let page = resources.entries[browser]?.resource else { return }
        record(.closeRequested, page)
        page.close()
    }

    private func downloadOwner(_ page: ChromePage) -> DownloadOwner {
        DownloadOwner(browser: page.incarnation, context: contexts.epoch(for: page.context), policy: page.downloadPolicy)
    }
    func download(_ page: ChromePage, item: CefDownload, name: String, decision: CefDownloadDecisionCallback) {
        let owner = delegate?.engine(self, ownerWindow: page.id.window)
        transfers.decision(item, name: name, owner: downloadOwner(page), available: { [weak self, weak page, weak owner] in
            guard let self, let page, let owner else { return false }
            return self.isLive(page) && owner.isVisible
        }, callback: decision)
    }
    func download(_ page: ChromePage, item: CefDownload, control: CefDownloadControl?) {
        let owner = delegate?.engine(self, ownerWindow: page.id.window)
        transfers.update(item, owner: downloadOwner(page), available: { [weak self, weak page, weak owner] in
            guard let self, let page, let owner else { return false }
            return self.isLive(page) && owner.isVisible
        }, control: control)
    }

    private func record(_ kind: PageLogEntry.Kind, _ page: ChromePage) {
        let entry = PageLogEntry(page: page.id, generation: page.incarnation.generation, kind: kind,
                                 browserID: Int(page.browser.id), uptime: ProcessInfo.processInfo.systemUptime)
        pageLog.append(entry)
        log.notice("pagelog \(kind.rawValue, privacy: .public) page=\(page.id.description, privacy: .public) generation=\(page.incarnation.generation, privacy: .public) browser=\(page.browser.id, privacy: .public)")
    }
}

/// cef_shutdown waits for Chromium's thread pool to finish its last writes (fsync and ftruncate on the profile's
/// files, r5-2/REPORT.md). The pool's "ThreadPoolBackgroundWorker" threads run at macOS's background QoS, which on a busy
/// machine gets almost no CPU, so the wait reached Chromium's own 10 s teardown watchdog. The quit has already been
/// asked for and nothing else competes with it in this process: those threads go at user-initiated QoS for the end.
enum ShutdownThreads {
    static func raiseBackgroundWorkers() {
        var threads: thread_act_array_t?, count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return }
        defer {
            for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, threads[index]) }
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
        }
        for index in 0..<Int(count) where name(of: threads[index]).hasPrefix("ThreadPoolBackground") || name(of: threads[index]).hasPrefix("ThreadPoolSingleThreadSharedBackground") {
            // The public way to lift another thread (<pthread/qos.h>); the process ends with the wait, so it is never ended.
            guard let thread = pthread_from_mach_thread_np(threads[index]) else { continue }
            _ = pthread_override_qos_class_start_np(thread, QOS_CLASS_USER_INITIATED, 0)
        }
    }

    private static func name(of thread: thread_act_t) -> String {
        var info = thread_extended_info_data_t(), size = mach_msg_type_number_t(MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { thread_info(thread, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &size) }
        }
        guard result == KERN_SUCCESS else { return "" }
        return withUnsafeBytes(of: info.pth_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
