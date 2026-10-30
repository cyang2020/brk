import AppKit
import BrkBase
import BrkControl
import BrkDomain
import BrkEngine

/// Launch and quit order. The app delegate.
///
/// Launch (main.swift has already created the engine, which for CEF installed CEFApplication as NSApp):
/// 1. data directory; `StateFile.read()`; `StateCodec.restore` (quarantine on `.rejected`).
/// 2. `AppStore`, `KeyRouter` as the engine's delegate, `MainMenu`.
/// 3. first dispatch-free render: windows from the restored snapshot, `engine.reconcile(snapshot.pages)` (only
///    visible tabs are loaded: lazy restore).
/// 4. sweep timer (Metrics.Persistence.sweepInterval) dispatching `.system(.clockTick)`.
/// 5. control server, when LaunchOptions.controlSocket is set.
///
/// Quit (Cmd+Q through the reducer as `AppEffect.quit`, the Dock menu, logout - every path reaches
/// `applicationShouldTerminate`, because CEFEngine removed CefSwift's terminate handler):
/// 1. `.terminateLater`; stop the sweep timer and the control server's accept loop (the in-flight `quit` reply is
///    already written).
/// 2. `store.flush()` - state is saved before anything risky happens.
/// 3. `await engine.shutdown()` - views back, browsers closed (awaiting OnBeforeClose), CEF shut down.
/// 4. `NSApp.reply(toApplicationShouldTerminate: true)`.
@MainActor
public final class Lifecycle: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let engine: any WebEngine
    private let engineKind: String
    private(set) var store: AppStore?
    private var router: KeyRouter?
    private var control: ControlServer?
    private var sweep: Timer?
    private var quitting = false

    public init(options: LaunchOptions, engine: any WebEngine, engineKind: String) {
        self.options = options
        self.engine = engine
        self.engineKind = engineKind
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // TODO(W2): launch steps 1 to 5.
        fatalError("not implemented")
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        sweep?.invalidate()
        control?.stopAccepting()
        store?.flush()
        Task { @MainActor in
            await engine.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Arc keeps running with no windows; v1 quits when its only window closes, through the same ordered quit.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
