import AppKit
import BrkBase
import BrkEngine
import CCefAppKit
import CefKit

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

    /// Live pages by id. A page leaves this map the moment `reconcile` stops listing it, even though its browser
    /// closes asynchronously, so the same id can be recreated at once (Cmd+W on a pinned tab, then click it).
    private var live: [PageID: ChromePage] = [:]
    /// Pages whose browsers are closing, until `OnBeforeClose`.
    private var closing: [ObjectIdentifier: ChromePage] = [:]
    private var phase: ShutdownPhase = .running
    private var shutdownTask: Task<Void, Never>?

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
        // TODO(W2):
        // let wanted = Dictionary(pages.map { ($0.id, $0) })
        // for (id, page) in live where wanted[id] == nil { live[id] = nil; beginClose(page) }
        // for spec in pages where live[spec.id] == nil, let url = spec.initialURL {
        //     live[spec.id] = ChromePage(spec: spec, url: url, engine: self)   // creates the browser + surface
        // }
        // Profiles: spec.profile != .default -> a CefProfile (request context) per profile, created lazily (later).
        fatalError("not implemented")
    }

    public func surface(for page: PageID) -> PageSurfaceView? { live[page]?.surface }

    public func perform(_ action: PageAction, on page: PageID) {
        // TODO(W2): map to CefBrowser: navigate -> load(url); goBack/goForward; reload(ignoringCache:); stopLoading;
        // zoom: zoomLevel += 0.5 / -= 0.5 / = 0 (Chrome's steps later); toggleDevTools; recover -> reload().
        fatalError("not implemented")
    }

    public func focus(_ page: PageID?) {
        // TODO(W2): nil -> every live page setFocus(false). Otherwise: surface.window?.makeKey() (our window, never
        // the host window), makeFirstResponder(the RenderWidgetHostViewCocoa inside the surface, else the surface),
        // browser.setFocus(true). The spike's focus sequence (u2-bar): bar field <-> RenderWidgetHostViewCocoa.
        // If the page's Chromium views are not embedded yet (a page created in this same render), remember the
        // request and apply it when EmbeddedSurface.adopt finishes; a later focus() call replaces it.
        fatalError("not implemented")
    }

    public func facts(for page: PageID) -> PageFacts? { live[page]?.facts }

    public func shutdown() async {
        if let shutdownTask { return await shutdownTask.value }
        let task = Task { @MainActor in await self.runShutdown() }
        shutdownTask = task
        await task.value
    }

    /// The order is the fix for the spike's crash at quit (cef-hosting-results.md, risk 1):
    /// 1. restoringViews: every surface gives Chromium's views back to their host window's content view, and every
    ///    host window is removed from our window's children (`EmbeddedSurface.returnViews()`).
    /// 2. closingBrowsers: `browser.close(force: true)` for every live and closing page; await each
    ///    `browserDidClose` (OnBeforeClose), bounded by Metrics.persistence.shutdownTimeout (log what did not close).
    /// 3. shuttingDownRuntime: `CefRuntime.shared.shutdown()`; nothing touches CEF after this.
    /// 4. done. Lifecycle then replies to applicationShouldTerminate.
    private func runShutdown() async {
        // TODO(W2): the four phases above; use a CheckedContinuation resumed from `pageDidClose` when `closing` is
        // empty, raced against a Task.sleep timeout. Never call into a page after phase 1 except close().
        fatalError("not implemented")
    }

    // MARK: Called by ChromePage

    func pageDidEmit(_ page: ChromePage, _ event: PageEvent) {
        guard phase == .running, live[page.id] === page else { return }  // events from a retired browser are dropped
        delegate?.engine(self, page: page.id, didEmit: event)
    }

    func pageKey(_ page: ChromePage, _ press: KeyPress, stage: KeyStage, pressID: UInt64) -> Bool {
        guard phase == .running, live[page.id] === page else { return false }
        return delegate?.engine(self, page: page.id, key: press, stage: stage, pressID: pressID) ?? false
    }

    /// OnBeforeClose for any page, live or closing.
    func pageDidClose(_ page: ChromePage) {
        // TODO(W2): remove from `closing`; if it was still live (closed by the page itself), drop it from `live`;
        // emit .closed to the delegate (also for closedByPage); resume the shutdown continuation when empty.
        fatalError("not implemented")
    }

    private func beginClose(_ page: ChromePage) {
        closing[ObjectIdentifier(page)] = page
        page.close()
    }
}
