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
    private var littleEntryPoints: LittleEntryPoints?
    private var pendingExternalURLs: [Input] = []
    private let menuTarget = MenuTarget()
    private var quitting = false
    private var askingQuit = false
    private var overlayEscapeMonitor: Any?
    private var dockTile: DockTile?
    /// Help > Restore Data's confirmed backup: put in place after the ordered quit, then the app starts again.
    private var pendingRestore: URL?
    private var clock: (any Clock)?
    private let log = Logger(subsystem: "brk", category: "lifecycle")

    public init(options: LaunchOptions, engine: any WebEngine, engineKind: String) {
        self.options = options
        self.engine = engine
        self.engineKind = engineKind
    }

    /// A window's row in the Window menu: its focused tab's title, else its space's (Little Brk for a Little Arc).
    static func menuTitle(of window: WindowSnapshot) -> String {
        let focused = window.content.panes.first { $0.focused }?.tab ?? window.content.panes.first?.tab
        func rows(_ list: [Row]) -> [TabRow] {
            list.flatMap { row -> [TabRow] in
                switch row {
                case .tab(let t): [t]
                case .folder(let f): rows(f.children)
                case .split(let s): s.panes
                }
            }
        }
        let tabs = window.favorites.tiles.map { (id: $0.id, title: $0.title) }
            + (rows(window.space.pinned.rows) + rows(window.space.today.rows) + rows(window.scratch?.rows ?? [])).map { (id: $0.id, title: $0.title) }
        if let focused, let title = tabs.first(where: { $0.id == focused })?.title, !title.isEmpty { return title }
        return window.kind == .little ? "Little \(Product.name)" : window.space.title
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // macOS would add its own "Enter Full Screen" (fn F) under View's table row; Arc's View menu has one (P19-a).
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
        installURLHandler()
    }

    private func installURLHandler() {
        guard getURL == nil else { return }
        let handler = GetURLHandler(send: { [weak self] input in
            guard let self else { return }
            if let store = self.store { store.dispatch(input) }
            else { self.pendingExternalURLs.append(input) }
        })
        handler.install()
        getURL = handler
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // CEF replaces signal handlers during bootstrap. Restore the app's crash trace after CEF initializes.
        CrashBacktrace.install()
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
        case .restored(let repairs):
            if !repairs.isEmpty { log.notice("restored with repairs: \(repairs.joined(separator: "; "))") }
            // Help > Restore Data's copies: the file as this launch found it, before the store writes anything.
            StateBackups(directory: directory).snapshot(now: ctx.now)
        case .rejected(let reason):
            log.error("state.json rejected (\(String(describing: reason))); quarantined")
            try? stateFile.quarantine(now: ctx.now)
        }

        let store = AppStore(restored: restored, clock: clock, engine: engine, stateFile: stateFile)
        self.clock = clock
        let router = KeyRouter(store: store)
        engine.delegate = router
        self.store = store
        self.router = router
        menuTarget.edits.window = { [weak store] in NSApp.keyWindow ?? store?.windowController(nil)?.window }

        menuTarget.perform = { [weak self] action, event in
            // Exit (Esc) closes an open icon popover first, as the Escape key does wherever it arrives.
            if action == .exit, TabIconPicker.isOpen { TabIconPicker.close(); return }
            guard let self, let window = self.store?.windowController(nil)?.id else { return }
            self.router?.menuAction(action, in: window, event: event)
        }
        menuTarget.isEnabled = { [weak self] action in
            if case .find = action.spec.command, let native = NSApp.keyWindow ?? self?.store?.inputWindow, !(native is any HostWindow) { return false }
            guard let self, let window = self.store?.windowController(nil)?.id,
                  let snapshot = self.store?.snapshot.windows[window] else { return true }
            return snapshot.enabledActions.contains(action)
        }
        menuTarget.isChecked = { [weak self] action in
            guard let self, let id = self.store?.windowController(nil)?.id, let window = self.store?.snapshot.windows[id] else { return nil }
            switch action {
            case .toggleStayOnTop: return window.stayOnTop
            case .appearanceAutomatic: return window.websiteAppearance == .automatic
            case .appearanceLight: return window.websiteAppearance == .light
            case .appearanceDark: return window.websiteAppearance == .dark
            case .allowJavaScriptFromAppleEvents: return self.store?.snapshot.settings.general.javaScriptFromAppleEvents == true
            default: return nil
            }
        }
        menuTarget.focusSpace = { [weak self] space in
            guard let self, let window = self.store?.windowController(nil)?.id else { return }
            self.store?.dispatch(.user(window, .space(.focus(space))))
        }
        menuTarget.windowList = { [weak self] in
            guard let store = self?.store else { return [] }
            return store.snapshot.windows.keys.sorted().compactMap { id in
                guard let window = store.snapshot.windows[id], let controller = store.windowController(id) else { return nil }
                let title = Lifecycle.menuTitle(of: window)
                return (id, title, controller.window.isKeyWindow)
            }
        }
        menuTarget.focusWindow = { [weak self] id in
            guard let window = self?.store?.windowController(id)?.window else { return }
            window.makeKeyAndOrderFront(nil)
        }
        menuTarget.current = { [weak self] in
            let controller = self?.store?.windowController(nil)
            return (controller.flatMap { self?.store?.snapshot.windows[$0.id] }, controller?.window.styleMask.contains(.fullScreen) ?? false)
        }
        NSApp.mainMenu = MainMenu.build(target: menuTarget)

        let entryPoints = LittleEntryPoints(target: menuTarget) { [weak store] status in store?.dispatch(.system(.globalShortcut(status))) }
        littleEntryPoints = entryPoints
        let dockTile = DockTile()
        self.dockTile = dockTile
        var menuShortcuts: [ShortcutRow]?
        store.didPublish = { [weak entryPoints, weak dockTile] in
            entryPoints?.update($0)
            dockTile?.update($0.dockTile)
            // AppKit matches the Edit items' keys without opening the menu, so a remap is written into the menu now.
            if menuShortcuts != $0.settings.shortcuts, let menu = NSApp.mainMenu {
                menuShortcuts = $0.settings.shortcuts
                MenuTarget.applyAll(Dictionary($0.settings.shortcuts.map { ($0.action, $0.state) }, uniquingKeysWith: { a, _ in a }), to: menu)
            }
        }
        store.help.restoreConfirmed = { [weak self] backup in
            self?.pendingRestore = backup
            Quit.request()
        }
        store.start()
        // AppKit can consume fullscreen Escape before it reaches NSWindow.sendEvent.
        overlayEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                guard event.keyCode == Key.escape.code else { return false }
                // The icon popover is open whichever window is key (the browser window usually stays key).
                if TabIconPicker.isOpen { TabIconPicker.close(); return true }
                // AppKit's fullscreen toolbar may be key while its owning browser still reports key status.
                let window = (NSApp.keyWindow as? any HostWindow)
                    ?? NSApp.windows.compactMap { $0 as? any HostWindow }.first { $0.isKeyWindow && $0.attachedSheet == nil }
                let handled = window?.attachedSheet == nil && window?.onEscapeBeforePage?(event) == true
                if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
                    let key = NSApp.keyWindow.map { NSStringFromClass(type(of: $0)) } ?? "nil"
                    FileHandle.standardError.write(Data("escape ingress key=\(key) host=\(window?.windowNumber ?? -1) handled=\(handled)\n".utf8))
                }
                return handled
            }
            return handled ? nil : event
        }

        // Links from other apps (F3) and the local AI tools on PATH (the Max pane, `.auto`).
        installURLHandler()
        let pending = pendingExternalURLs; pendingExternalURLs = []
        for input in pending { store.dispatch(input) }
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
        Quit.fixtureTrace("delegate entered")
        guard !quitting, !askingQuit else { return .terminateLater }
        // A quit that did not come through `AppEffect.quit` (the Dock menu, a quit Apple event) asks "Warn before
        // quitting" here; a logout, restart or shut down does not.
        if !Quit.confirmed, !Self.isSystemQuit(), let store, store.snapshot.settings.general.warnBeforeQuitting {
            askingQuit = true
            store.confirmQuit(on: NSApp.keyWindow ?? NSApp.mainWindow) { [weak self] go in
                guard let self else { return }
                self.askingQuit = false
                if go { Quit.confirmed = true; self.beginOrderedQuit() } else { NSApp.reply(toApplicationShouldTerminate: false) }
            }
            return .terminateLater
        }
        beginOrderedQuit()
        return .terminateLater
    }

    /// The quit Apple event of a logout, restart or shut down carries a reason (`kAEQuitReason`, 'why?').
    static func isSystemQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.attributeDescriptor(forKeyword: 0x7768_793F) != nil
    }

    private func beginOrderedQuit() {
        quitting = true
        if let overlayEscapeMonitor { NSEvent.removeMonitor(overlayEscapeMonitor); self.overlayEscapeMonitor = nil }
        store?.prepareForTermination()
        littleEntryPoints?.stop()
        sweep?.invalidate()
        control?.stopAccepting()
        let store = store, engine = engine, log = log
        Task { @MainActor in
            switch await Self.orderedQuit(store: store, engine: engine, dataDirectory: Product.dataDirectory(), log: log) {
            case .clean:
                if let backup = self.pendingRestore {
                    do {
                        try StateBackups(directory: Product.dataDirectory()).install(backup, now: self.clock?.now() ?? Instant(milliseconds: 0))
                        Self.relaunch()
                    } catch { log.error("restore of \(backup.path, privacy: .public) failed: \(error)") }
                }
                NSApp.reply(toApplicationShouldTerminate: true)
            case .timedOut:
                exit(Self.shutdownTimedOutStatus)
            }
        }
    }

    /// Arc keeps running with no windows; v1 quits when its only window closes, through the same ordered quit.
    /// Closing the window is not a quit asked for with Cmd+Q, so "Warn before quitting" does not ask.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Quit.confirmed = true
        return true
    }

    /// The Dock icon's menu (Arc opens windows from it: window source `dockMenu`): New Window and New Incognito
    /// Window, through the same actions as the File menu. macOS adds the window list above them.
    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Dock")
        for action in [ActionID.newWindow, .newIncognitoWindow] {
            let item = NSMenuItem(title: action.title(appName: Product.name), action: #selector(MenuTarget.performAction(_:)), keyEquivalent: "")
            item.target = menuTarget
            item.representedObject = action.rawValue
            menu.addItem(item)
        }
        return menu
    }

    /// Starts this executable again once this process has exited, with the same environment (so a test's data
    /// directory and control socket carry over). Restore Data's last step.
    static func relaunch() {
        guard let executable = Bundle.main.executablePath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; exec \"$2\"", "sh",
                             "\(ProcessInfo.processInfo.processIdentifier)", executable]
        var environment = ProcessInfo.processInfo.environment
        environment["MallocNanoZone"] = "0"
        process.environment = environment
        try? process.run()
    }

    /// Steps 2 and 3 of the quit, free of AppKit so a test can run them with a fake engine: `store.flush()` (state is
    /// on disk before anything risky), `await engine.shutdown()`, then the records in the data directory:
    /// `page-log.txt` (every created, closeRequested and closed entry, for the e2e report) and, on a timeout,
    /// `shutdown-incomplete.log` naming each unclosed page. The caller turns the outcome into the exit status.
    static func orderedQuit(store: AppStore?, engine: any WebEngine, dataDirectory: URL, log: Logger) async -> ShutdownOutcome {
        await store?.stopAI()
        store?.prepareSpaceToolsForShutdown()
        await store?.stopSidebarData()
        store?.flush()
        store?.cancelExports()
        Quit.fixtureTrace("engine shutdown starting")
        let outcome = await engine.shutdown()
        store?.flush()
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
    /// The quit under way needs no "Warn before quitting" question: it was answered, or it comes from SIGTERM or the
    /// control socket.
    public static var confirmed = false

    public static func request() {
        confirmed = true
        perform()
    }

    /// What `request()` does. The default is the real quit; tests replace it to observe that a quit was asked for
    /// without terminating the test process.
    public static var perform: @MainActor () -> Void = { enqueue {
        (NSApp.delegate as? Lifecycle)?.store?.prepareForTermination()
        enqueue { NSApp.terminate(nil) }
    } }

    static func fixtureTrace(_ message: String) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil { FileHandle.standardError.write(Data(("fixture quit: " + message + "\n").utf8)) }
    }

    static func enqueue(_ action: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.common, .modalPanel, .eventTracking]) { MainActor.assumeIsolated { fixtureTrace("run-loop block entered"); action() } }
    }
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
