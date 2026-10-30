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
    private var ledger = PageLedger()
    private var phase: ShutdownPhase = .running
    private var shutdownTask: Task<ShutdownOutcome, Never>?
    /// Resumed with true when the last closing browser reports OnBeforeClose, with false by the timeout.
    private var closeWaiter: CheckedContinuation<Bool, Never>?
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
        config.rootCachePath = configuration.cacheDirectory
        config.cachePath = configuration.cacheDirectory.appendingPathComponent("Default", isDirectory: true)
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

    public func reconcile(_ pages: [PageSpec]) {
        guard phase == .running else { return }
        let wanted = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, page) in live where wanted[id] == nil {
            live[id] = nil
            retire(page)
        }
        for spec in pages where live[spec.id] == nil {
            guard let url = spec.initialURL else { continue }
            let incarnation = ledger.create(spec.id)
            // TODO(W2): profiles: spec.profile != .default -> a CefProfile (request context) per profile, created lazily.
            let page = ChromePage(spec: spec, url: url, engine: self, incarnation: incarnation)
            live[spec.id] = page
            record(.created, page)
        }
    }

    public func surface(for page: PageID) -> PageSurfaceView? { live[page]?.surface }

    public func perform(_ action: PageAction, on page: PageID) {
        guard phase == .running, let live = live[page] else { return }
        let browser = live.browser
        switch action {
        case .navigate(let url): browser.load(url)
        case .goBack: browser.goBack()
        case .goForward: browser.goForward()
        case .reload(let ignoringCache): browser.reload(ignoreCache: ignoringCache)
        case .stop: browser.stopLoading()
        case .zoom(let step):
            // TODO(W2): Chrome's zoom presets instead of fixed 0.5 steps.
            switch step {
            case .zoomIn: browser.zoomLevel += 0.5
            case .zoomOut: browser.zoomLevel -= 0.5
            case .reset: browser.zoomLevel = 0
            }
        case .toggleDevTools: browser.toggleDevTools()
        case .recover: browser.reload()
        }
    }

    public func focus(_ page: PageID?) {
        // TODO(W2): nil -> every live page setFocus(false). Otherwise: surface.window?.makeKey() (our window, never
        // the host window), makeFirstResponder(the RenderWidgetHostViewCocoa inside the surface, else the surface),
        // browser.setFocus(true). The spike's focus sequence (u2-bar): bar field <-> RenderWidgetHostViewCocoa.
        // If the page's Chromium views are not embedded yet (a page created in this same render), remember the
        // request and apply it when EmbeddedSurface.adopt finishes; a later focus() call replaces it.
        fatalError("not implemented")
    }

    public func evaluate(_ script: String, in page: PageID) {
        guard phase == .running else { return }
        live[page]?.browser.executeJavaScript(script)
    }

    public func facts(for page: PageID) -> PageFacts? { live[page]?.facts }

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
    ///    each `browserDidClose` (OnBeforeClose), bounded by Metrics.persistence.shutdownTimeout.
    /// 3. On time: shuttingDownRuntime, `CefRuntime.shared.shutdown()`, `.clean`. Timed out: log each unclosed page,
    ///    skip the runtime shutdown (cef_shutdown with browsers alive is the crash), `.timedOut`. Nothing touches CEF
    ///    after this either way.
    private func runShutdown() async -> ShutdownOutcome {
        phase = .restoringViews
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
                log.fault("shutdown: page \(page.id.description) generation \(page.incarnation.generation) (browser \(page.browser.id)) never reported OnBeforeClose")
            }
            phase = .done
            return .timedOut(unclosed: unclosed)
        }
        phase = .shuttingDownRuntime
        CefRuntime.shared.shutdown()
        phase = .done
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

    // MARK: Called by ChromePage

    func pageDidEmit(_ page: ChromePage, _ event: PageEvent) {
        guard phase == .running, live[page.id] === page else { return }  // events from a retired incarnation are dropped
        delegate?.engine(self, page: page.id, didEmit: event)
    }

    func pageKey(_ page: ChromePage, _ press: KeyPress, stage: KeyStage, pressID: PressID) -> Bool {
        guard phase == .running, live[page.id] === page else { return false }
        return delegate?.engine(self, page: page.id, key: press, stage: stage, pressID: pressID) ?? false
    }

    /// OnBeforeClose for any incarnation. The ledger says what it may do: a retired incarnation's close never removes
    /// or reports closure for a newer incarnation of the same id; a close the engine did not start is page-initiated
    /// (`window.close()`), reported as `.closedByPage` so the domain drops the page demand, then `.closed`.
    func pageDidClose(_ page: ChromePage) {
        record(.closed, page)
        switch ledger.closed(page.incarnation) {
        case .retiredClosed(let idLiveAgain):
            closing[page.incarnation] = nil
            if !idLiveAgain, phase == .running { delegate?.engine(self, page: page.id, didEmit: .closed) }
        case .liveClosedByPage:
            if live[page.id] === page { live[page.id] = nil }
            if phase == .running {
                delegate?.engine(self, page: page.id, didEmit: .closedByPage)
                delegate?.engine(self, page: page.id, didEmit: .closed)
            }
        case .stale:
            log.error("OnBeforeClose for unknown incarnation \(page.id.description)#\(page.incarnation.generation)")
        }
        if closing.isEmpty, let waiter = closeWaiter {
            closeWaiter = nil
            waiter.resume(returning: true)
        }
    }

    // MARK: Private

    private func retire(_ page: ChromePage) {
        guard let incarnation = ledger.retire(page.id), incarnation == page.incarnation else { return }
        closing[incarnation] = page
        record(.closeRequested, page)
        page.close()
    }

    private func record(_ kind: PageLogEntry.Kind, _ page: ChromePage) {
        pageLog.append(PageLogEntry(page: page.id, generation: page.incarnation.generation, kind: kind,
                                    browserID: Int(page.browser.id), uptime: ProcessInfo.processInfo.systemUptime))
    }
}
