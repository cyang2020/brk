import AppKit
import BrkBase
import BrkControl
import BrkDomain
import BrkEngine
import os

/// Launch and quit order. The app delegate.
///
/// Launch (main.swift has already created the engine, which for CEF installed CEFApplication as NSApp):
/// 1. data directory; `StateFile.read()`; `StateCodec.restore` (quarantine on `.rejected` or an unreadable file).
/// 2. `AppStore`, `KeyRouter` as the engine's delegate, `MainMenu`.
/// 3. `store.start()`: windows from the restored snapshot, `engine.reconcile(snapshot.pages)` (only visible tabs are
///    loaded: lazy restore).
/// 4. sweep timer (Metrics.persistence.sweepInterval) dispatching `.system(.clockTick)`.
/// 5. control server, when LaunchOptions.controlSocket is set; SIGTERM -> the same ordered quit as Cmd+Q.
///
/// Quit (Cmd+Q through the reducer as `AppEffect.quit`, the Dock menu, logout, SIGTERM - every path reaches
/// `applicationShouldTerminate`, because CEFEngine removed CefSwift's terminate handler):
/// 1. `.terminateLater`; stop the sweep timer and the control server's accept loop (the in-flight `quit` reply is
///    already written).
/// 2. `store.flush()` - state is saved before anything risky happens.
/// 3. `await engine.shutdown()` - views back, browsers closed (awaiting OnBeforeClose), CEF shut down.
/// 4. `.clean` -> `NSApp.reply(toApplicationShouldTerminate: true)`, exit status 0.
///    `.timedOut(unclosed)` -> the controlled failure: log every unclosed page, write `shutdown-incomplete.log` in
///    the data directory (what the next launch and the e2e report can read), and `exit(Lifecycle.shutdownTimedOutStatus)`.
///    The runtime is left un-shut-down on purpose; the OS reclaims the helpers. N4 and the per-scenario quit check
///    see the status and fail.
@MainActor
public final class Lifecycle: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let engine: any WebEngine
    private let engineKind: String
    private(set) var store: AppStore?
    private var router: KeyRouter?
    private var control: ControlServer?
    private var sweep: Timer?
    private var termination: DispatchSourceSignal?
    private var getURL: GetURLHandler?
    private let menuTarget = MenuTarget()
    private var quitting = false
    private let log = Logger(subsystem: "brk", category: "lifecycle")

    public init(options: LaunchOptions, engine: any WebEngine, engineKind: String) {
        self.options = options
        self.engine = engine
        self.engineKind = engineKind
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = Product.dataDirectory()
        let stateFile = StateFile(directory: directory)
        let clock: any Clock = options.testClock ? OffsetClock() : SystemClock()
        let ctx = Context(now: clock.now(), newID: { UUID().uuidString })
        let seed = RestoreSeed(startURL: options.startURL, contentSize: Metrics.window.defaultSize.value)

        var data: Data?
        switch stateFile.read() {
        case .absent: break
        case .data(let d): data = d
        case .unreadable(let why):
            log.error("state.json unreadable (\(why)); quarantining and starting fresh")
            try? stateFile.quarantine(now: ctx.now)
        }
        let restored = StateCodec.restore(data, seed: seed, ctx: ctx)
        switch restored.outcome {
        case .fresh: log.notice("fresh profile in \(directory.path)")
        case .restored(let repairs): if !repairs.isEmpty { log.notice("restored with repairs: \(repairs.joined(separator: "; "))") }
        case .rejected(let reason):
            log.error("state.json rejected (\(String(describing: reason))); quarantined")
            try? stateFile.quarantine(now: ctx.now)
        }

        let store = AppStore(restored: restored, clock: clock, engine: engine, stateFile: stateFile)
        let router = KeyRouter(store: store)
        engine.delegate = router
        self.store = store
        self.router = router

        menuTarget.perform = { [weak self] action, event in
            guard let self, let window = self.store?.windowController(nil)?.id else { return }
            self.router?.menuAction(action, in: window, event: event)
        }
        menuTarget.isEnabled = { [weak self] action in
            guard let self, let window = self.store?.windowController(nil)?.id,
                  let snapshot = self.store?.snapshot.windows[window] else { return true }
            return snapshot.enabledActions.contains(action)
        }
        NSApp.mainMenu = MainMenu.build(target: menuTarget)

        store.start()

        // Links from other apps (F3) and the local AI tools on PATH (the Max pane, `.auto`).
        let handler = GetURLHandler(send: { [weak store] in store?.dispatch($0) })
        handler.install()
        getURL = handler
        store.dispatch(.system(.aiProvidersDetected(AIProviderSeam.detect())))

        sweep = Timer.scheduledTimer(withTimeInterval: Metrics.persistence.sweepInterval.value, repeats: true) { _ in
            MainActor.assumeIsolated { store.dispatch(.system(.clockTick)) }
        }

        if let path = options.controlSocket {
            let server = ControlServer(path: path, executor: ControlExecutor(store: store, engine: engine, clock: clock as? OffsetClock))
            do { try server.start(); control = server } catch { log.error("control server failed to start: \(error)") }
        }

        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { Quit.request() } }
        source.resume()
        termination = source

        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        sweep?.invalidate()
        control?.stopAccepting()
        let store = store, engine = engine, log = log
        Task { @MainActor in
            switch await Self.orderedQuit(store: store, engine: engine, dataDirectory: Product.dataDirectory(), log: log) {
            case .clean:
                NSApp.reply(toApplicationShouldTerminate: true)
            case .timedOut:
                exit(Self.shutdownTimedOutStatus)
            }
        }
        return .terminateLater
    }

    /// Arc keeps running with no windows; v1 quits when its only window closes, through the same ordered quit.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Steps 2 and 3 of the quit, free of AppKit so a test can run them with a fake engine: `store.flush()` (state is
    /// on disk before anything risky), `await engine.shutdown()`, then the records in the data directory:
    /// `page-log.txt` (every created, closeRequested and closed entry, for the e2e report) and, on a timeout,
    /// `shutdown-incomplete.log` naming each unclosed page. The caller turns the outcome into the exit status.
    static func orderedQuit(store: AppStore?, engine: any WebEngine, dataDirectory: URL, log: Logger) async -> ShutdownOutcome {
        store?.flush()
        let outcome = await engine.shutdown()
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let pageLog = engine.pageLog.map {
            String(format: "%.3f %@ page=%@ generation=%llu browser=%@", $0.uptime, $0.kind.rawValue, $0.page.description, $0.generation,
                   $0.browserID.map(String.init) ?? "-")
        }
        try? (pageLog.joined(separator: "\n") + "\n").write(to: dataDirectory.appendingPathComponent("page-log.txt"), atomically: true, encoding: .utf8)
        if case .timedOut(let unclosed) = outcome {
            log.fault("shutdown timed out: \(unclosed.count) browsers never reported OnBeforeClose: \(unclosed.map(\.description).joined(separator: ", "))")
            let marker = dataDirectory.appendingPathComponent("shutdown-incomplete.log")
            try? (unclosed.map(\.description).joined(separator: "\n") + "\n").write(to: marker, atomically: true, encoding: .utf8)
        }
        return outcome
    }

    /// Exit status of a quit whose browsers did not close in time. Distinct from a crash (signal) and from 0.
    public static let shutdownTimedOutStatus: Int32 = 3
}

/// The one way code asks the app to quit. `NSApp.terminate` must not be called from inside a main-dispatch-queue
/// callout (a `Task` on the main actor, a signal source, a control-socket op): `applicationShouldTerminate` answers
/// `.terminateLater` and AppKit spins a nested event loop inside `terminate` until `reply(toApplicationShouldTerminate:)`,
/// which arrives as another main-queue job that cannot run while the first callout is still on the stack. Sampled
/// deadlock, first stub run. A run-loop block runs outside the dispatch drain, so the nested loop can service the queue.
@MainActor
public enum Quit {
    public static func request() { perform() }

    /// What `request()` does. The default is the real quit; tests replace it to observe that a quit was asked for
    /// without terminating the test process.
    public static var perform: @MainActor () -> Void = { RunLoop.main.perform { NSApp.terminate(nil) } }
}

/// A fatal signal in the browser process writes a backtrace to stderr before the default action, so an e2e log
/// (the runner keeps each scenario's stderr) or a terminal shows where a crash came from even when no crash report
/// is written. `backtrace_symbols_fd` writes straight to the descriptor; the handler allocates nothing else.
public enum CrashBacktrace {
    public static func install() {
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { sig in
                let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 128)
                let count = backtrace(frames, 128)
                let header = "\(Product.name): fatal signal \(sig), backtrace:\n"
                _ = header.withCString { write(STDERR_FILENO, $0, strlen($0)) }
                backtrace_symbols_fd(frames, count, STDERR_FILENO)
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
    }
}
