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
    private var live: [PageID: ChromePage] = [:]
    private var closing: [PageLedger.Incarnation: ChromePage] = [:]
    /// Pages whose browser was asked to close and whose host window CEF has not destroyed yet.
    private var destroying: [PageLedger.Incarnation: ChromePage] = [:]
    private var ledger = PageLedger()
    /// One CEF request context per browsing context, created on first use (`profile(for:)`). The default profile
    /// is the runtime's own cache; a custom profile is `<rootCachePath>/Profile-<id>`; incognito is in memory.
    private var profiles: [BrowsingContext: CefProfile] = [:]
    /// Persistent profiles Chromium is loading or has loaded (`ProfileLoader`); a page in one waits for `ready`.
    private var loaders: [ProfileID: ProfileLoader] = [:]
    private var readyProfiles: Set<ProfileID> = []
    /// The last `reconcile` input, replayed when a profile finishes loading.
    private var wanted: [PageSpec] = []
    private var phase: ShutdownPhase = .running
    private var shutdownTask: Task<ShutdownOutcome, Never>?
    /// Resumed with true when the last closing browser reports OnBeforeClose, with false by the timeout.
    private var closeWaiter: CheckedContinuation<Bool, Never>?
    /// Resumed when the last host window is destroyed (or by a short timeout: not a failure).
    private var windowWaiter: CheckedContinuation<Void, Never>?
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
        config.defaultRuntimeStyle = .chrome
        try CefRuntime.shared.initialize(configuration: config)
        // CefSwift's terminate handler closes browsers while their views are still moved into our window, which
        // segfaulted on quit in every spike run. Remove it: -terminate: then reaches the app delegate's
        // applicationShouldTerminate, which returns .terminateLater and runs Lifecycle's ordered quit, which ends in
        // `shutdown()` below.
        CEFApplication.setTerminateHandler(nil)
        HostWindows.installKeyGuard()
        return CEFEngine()
    }

    private init() {}

    private static func realPath(of directory: URL) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let resolved = realpath(directory.path, nil) else { return directory }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    public func reconcile(_ pages: [PageSpec]) {
        guard phase == .running else { return }
        self.wanted = pages
        let wanted = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A page whose spec names another browsing context (its space changed profile) is replaced: Chromium binds a
        // page to its request context for life. The new incarnation inherits its window's request.
        focusRequests = focusRequests.filter { $0.value.window != nil && wanted[$0.value.page] != nil }
        for (id, page) in live where wanted[id]?.context != page.context {
            live[id] = nil
            retire(page)
        }
        for spec in pages where live[spec.id] == nil {
            guard let url = spec.initialURL, isReady(spec.context) else { continue }
            let incarnation = ledger.create(spec.id)
            let page = ChromePage(spec: spec, url: url, engine: self, incarnation: incarnation)
            live[spec.id] = page
            record(.created, page)
            delegate?.engine(self, page: incarnation, didEmit: .browserCreated(spec.context, .unavailable))
        }
    }

    public func surface(for page: PageID) -> PageSurfaceView? { live[page]?.surface }

    public func perform(_ action: PageAction, on page: PageID) {
        guard phase == .running, let live = live[page] else { return }
        let browser = live.browser
        switch action {
        case .navigate(let url): live.prepareNavigation(); browser.load(url)
        case .goBack: live.prepareNavigation(); browser.goBack()
        case .goForward: live.prepareNavigation(); browser.goForward()
        case .reload(let ignoringCache): live.prepareNavigation(); browser.reload(ignoreCache: ignoringCache)
        case .stop: browser.stopLoading()
        case .zoom(let step):
            // TODO(W2): Chrome's zoom presets instead of fixed 0.5 steps.
            switch step {
            case .zoomIn: browser.zoomLevel += 0.5
            case .zoomOut: browser.zoomLevel -= 0.5
            case .reset: browser.zoomLevel = 0
            }
        case .toggleDevTools: browser.toggleDevTools()
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

    /// Releases the context so Chromium drops it once its last page has closed (incognito: everything it held is
    /// in memory and goes with it; the next incognito page gets a fresh one). A deleted profile's directory is
    /// Chromium's while the runtime runs, so it is marked and removed at the next launch, before CEF starts
    /// (`ProfileDirectories`).
    public func forget(_ context: BrowsingContext) {
        guard phase == .running, context != .profile(.default) else { return }
        profiles[context] = nil
        if case .profile(let id) = context {
            loaders.removeValue(forKey: id)?.release()
            readyProfiles.remove(id)
            profileDirectories?.mark(id)
        }
    }

    /// Whether pages can be created in `context` now. The default profile and incognito (an off-the-record profile
    /// of the loaded default one) always can; a persistent profile once Chromium has loaded it (`ProfileLoader`),
    /// after which every waiting page is created by replaying the last `reconcile`.
    private func isReady(_ context: BrowsingContext) -> Bool {
        guard case .profile(let id) = context, id != .default else { return true }
        if readyProfiles.contains(id) { return true }
        if loaders[id] == nil, let root = CefRuntime.shared.configuration?.rootCachePath {
            let path = root.appendingPathComponent(ProfileDirectories.directoryName(id), isDirectory: true)
            loaders[id] = ProfileLoader(cachePath: path) { [weak self] in
                guard let self, self.phase == .running, self.loaders[id] != nil else { return }
                self.log.notice("profile \(id.rawValue, privacy: .public) loaded")
                self.readyProfiles.insert(id)
                self.reconcile(self.wanted)
            }
        }
        return false
    }

    /// The request context for a page's browsing context (BrkEngine/WebEngine.swift `BrowsingContext`): nil for the
    /// default profile (the runtime's own cache, `<rootCachePath>/Default`), one persistent context per other
    /// profile in `<rootCachePath>/Profile-<id>`, one shared off-the-record context for every incognito page.
    /// Created on first use and reused until `forget`.
    func profile(for context: BrowsingContext) -> CefProfile? {
        if let existing = profiles[context] { return existing }
        let profile: CefProfile
        switch context {
        case .profile(.default): return nil
        case .profile(let id): profile = .persistent(name: id.rawValue)
        case .incognito: profile = .incognito()
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
        log.notice("shutdown: \(self.live.count, privacy: .public) live, \(self.closing.count, privacy: .public) closing")
        phase = .restoringViews
        focusRequests.removeAll()
        for page in live.values { page.surface.returnViews() }
        for page in closing.values { page.surface.returnViews() }
        phase = .closingBrowsers
        for (id, page) in live {
            live[id] = nil
            retire(page)
        }
        let closedAll = await waitForBrowsersToClose(timeout: Metrics.persistence.shutdownTimeout.value)
        guard closedAll else {
            let unclosed = closing.values.map(\.id).sorted()
            for page in closing.values {
                log.fault("shutdown: page \(page.id.description, privacy: .public) generation \(page.incarnation.generation, privacy: .public) (browser \(page.browser.id, privacy: .public)) never reported OnBeforeClose")
            }
            phase = .done
            return .timedOut(unclosed: unclosed)
        }
        await waitForHostWindows(timeout: 1.0)
        HostWindows.closeAuxiliaryWindows()
        phase = .shuttingDownRuntime
        log.notice("shutdown: every browser closed (\(self.destroying.count, privacy: .public) host windows still alive); cef_shutdown")
        CefRuntime.shared.shutdown()
        phase = .done
        log.notice("shutdown: clean")
        return .clean
    }

    private func waitForBrowsersToClose(timeout: Double) async -> Bool {
        if closing.isEmpty { return true }
        return await withCheckedContinuation { continuation in
            closeWaiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let waiter = self.closeWaiter {
                    self.closeWaiter = nil
                    waiter.resume(returning: false)
                }
            }
        }
    }

    private func waitForHostWindows(timeout: Double) async {
        if destroying.isEmpty { return }
        await withCheckedContinuation { continuation in
            windowWaiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let waiter = self.windowWaiter {
                    self.windowWaiter = nil
                    waiter.resume()
                }
            }
        }
    }

    // MARK: Called by ChromePage

    func isLive(_ page: ChromePage) -> Bool {
        phase == .running && ledger.isLive(page.incarnation) && live[page.id] === page
    }

    func pageDidEmit(_ page: ChromePage, _ event: PageEvent) {
        guard isLive(page) else { return }
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

    func pageKey(_ page: ChromePage, _ press: KeyPress, stage: KeyStage, pressID: PressID) -> Bool {
        guard phase == .running, ledger.isLive(page.incarnation), live[page.id] === page,
              let window = page.surface.window, window.isVisible,
              !page.surface.isHiddenOrHasHiddenAncestor else { return false }
        return delegate?.engine(self, page: page.id, key: press, stage: stage, pressID: pressID) ?? false
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
        switch ledger.closed(page.incarnation) {
        case .retiredClosed(let idLiveAgain):
            closing[page.incarnation] = nil
            if !idLiveAgain, phase == .running { delegate?.engine(self, page: page.incarnation, didEmit: .closed) }
        case .liveClosedByPage:
            if live[page.id] === page { live[page.id] = nil }
            focusRequests = focusRequests.filter { $0.value.page != page.id }
            page.surface.returnViews()
            destroying[page.incarnation] = page
            if phase == .running {
                delegate?.engine(self, page: page.incarnation, didEmit: .closedByPage)
                delegate?.engine(self, page: page.incarnation, didEmit: .closed)
            }
        case .stale:
            log.error("OnBeforeClose for unknown incarnation \(page.id.description, privacy: .public)#\(page.incarnation.generation, privacy: .public)")
        }
        if closing.isEmpty, let waiter = closeWaiter {
            closeWaiter = nil
            waiter.resume(returning: true)
        }
    }

    /// CEF destroyed the page's host window: the last trace of the browser is gone.
    func pageWindowDidClose(_ page: ChromePage) {
        destroying[page.incarnation] = nil
        if destroying.isEmpty, let waiter = windowWaiter {
            windowWaiter = nil
            waiter.resume()
        }
    }

    // MARK: Private

    private func retire(_ page: ChromePage) {
        guard let incarnation = ledger.retire(page.id), incarnation == page.incarnation else { return }
        closing[incarnation] = page
        destroying[incarnation] = page
        record(.closeRequested, page)
        page.close()
    }

    private func record(_ kind: PageLogEntry.Kind, _ page: ChromePage) {
        let entry = PageLogEntry(page: page.id, generation: page.incarnation.generation, kind: kind,
                                 browserID: Int(page.browser.id), uptime: ProcessInfo.processInfo.systemUptime)
        pageLog.append(entry)
        log.notice("pagelog \(kind.rawValue, privacy: .public) page=\(page.id.description, privacy: .public) generation=\(page.incarnation.generation, privacy: .public) browser=\(page.browser.id, privacy: .public)")
    }
}
