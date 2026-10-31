import AppKit
import BrkBase
import BrkEngine
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

    /// Which incarnation of each id is live or closing (BrkEngine/PageLedger.swift). The browsers themselves:
    let resources = BrowserResources<ChromePage>()
    var live: [PageID: ChromePage] {
        Dictionary(uniqueKeysWithValues: resources.entries.filter { $0.value.presented }.map { ($0.key.page, $0.value.resource) })
    }
    let transfers = Transfers()
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
    /// The last `reconcile` input, replayed when a profile finishes loading.
    var wanted: [PageSpec] = []
    var phase: ShutdownPhase = .running
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
        config.logFile = root.deletingLastPathComponent().appendingPathComponent("cef-debug.log")
        config.remoteDebuggingPort = configuration.remoteDebuggingPort
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            config.safeStorage = .mockKeychain
            config.extraCommandLineSwitches["host-resolver-rules"] = "MAP *.brk.test 127.0.0.1"
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
        let pages = pages.filter { contexts.permitsWork($0.context) }
        self.wanted = pages
        let wanted = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A page whose spec names another browsing context (its space changed profile) is replaced: Chromium binds a
        // page to its request context for life. The new incarnation inherits its window's request.
        focusRequests = focusRequests.filter { $0.value.window != nil && wanted[$0.value.page] != nil }
        for (id, page) in live where wanted[id]?.context != page.context {
            retire(page)
        }
        for spec in pages {
            if let page = live[spec.id] { page.downloadPolicy = spec.downloadPolicy; page.setMuted(spec.muted); page.applyWebsitePolicy(spec.websitePolicy); continue }
            guard let url = spec.initialURL, isReady(spec.context) else { continue }
            let incarnation = ledger.create(spec.id)
            let page = ChromePage(spec: spec, url: url, engine: self, incarnation: incarnation)
            resources.insert(page, browser: incarnation, context: contexts.epoch(for: spec.context))
            record(.created, page)
            delegate?.engine(self, page: incarnation, didEmit: .browserCreated(spec.context, .unavailable))
        }
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
            let requests = pages.compactMap { page in page.audio.ticket.map { (page, $0) } }
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
        case .developer(let operation):
            switch operation {
            case .source: browser.viewSource()
            case .inspect: browser.inspectElement(at: CGPoint(x: live.surface.bounds.midX, y: live.surface.bounds.midY))
            case .console: _ = browser.executeChromeCommand(named: "IDC_DEV_TOOLS_CONSOLE")
            case .network: _ = browser.executeChromeCommand(named: "IDC_DEV_TOOLS_NETWORK")
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

    public func facts(for page: PageID) -> PageFacts? { live[page]?.facts }

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
                !self.resources.entries.values.contains { $0.context.context == request.context }
                    && !self.outputs.contains(context: request.context)
                    && !self.transfers.contains(context: request.context)
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
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil { FileHandle.standardError.write(Data("fixture cef: shutdown started\n".utf8)) }
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
            self.outputs.isEmpty && self.outputPreparations.isEmpty && self.transfers.isEmpty && self.resources.entries.isEmpty && self.contexts.readinessDrained && self.disposals.isEmpty
                && self.audioObservers.values.allSatisfy(\.drained)
        }
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
        HostWindows.closeAuxiliaryWindows()
        phase = .shuttingDownRuntime
        CefRuntime.shared.shutdown()
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

    func pageDidEmit(_ page: ChromePage, _ event: PageEvent) {
        guard isLive(page) else { return }
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

    private func retire(_ page: ChromePage) {
        guard ledger.retire(page.id) == page.incarnation else { return }
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
