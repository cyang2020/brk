// Composition root. The only file that knows which engine runs.
//
// Order matters: CEF must install its NSApplication subclass before anything touches NSApp, so the engine is
// created first, then the delegate, then the run loop. With BRK_ENGINE=stub nothing loads Chromium and the shell
// runs from `swift run Brk` without a .app bundle.
import AppKit
import BrkApp
import BrkBase
import BrkCEF
import BrkCoreEngine
import BrkEngine

// An agent's MCP server for Brk's tab tools is this program too (`Brk --brk-tools …`): it pipes and exits, before anything loads.
BrkToolBridge.runIfAsked()

MainActor.assumeIsolated {
    CrashBacktrace.install()
    let options = LaunchOptions()
    let engine: any WebEngine
    var coreRuntime: BrkCoreRuntime?
    switch options.engine {
    case .cef:
        // Logins an import staged while Chromium held a profile's Login Data go in now, before CEF opens it.
        BrowserImportStartup.applyPendingLogins()
        do {
            engine = try CEFEngine.bootstrap(.init(
                cacheDirectory: Product.dataDirectory().appendingPathComponent("Chromium", isDirectory: true),
                remoteDebuggingPort: options.remoteDebuggingPort
            ))
        } catch {
            FileHandle.standardError.write(Data("""
            \(Product.name): Chromium could not start (\(error)).
            Run the bundled app built by scripts/build.sh, or set BRK_ENGINE=stub to run the shell without Chromium.

            """.utf8))
            exit(1)
        }
    case .stub:
        engine = StubEngine()
    case .core:
        do {
            let runtime = try BrkCoreRuntime(userDataDirectory: Product.dataDirectory().appendingPathComponent("Chromium", isDirectory: true),
                                             remoteDebuggingPort: options.remoteDebuggingPort)
            coreRuntime = runtime
            engine = CoreEngine(runtime: runtime)
        } catch {
            FileHandle.standardError.write(Data("\(Product.name): BrkCore could not start (\(error)).\n".utf8))
            exit(1)
        }
    }
    let lifecycle = Lifecycle(options: options, engine: engine, engineKind: options.engine.rawValue)
    let app = NSApplication.shared
    app.delegate = lifecycle
    app.setActivationPolicy(.regular)
    if let coreRuntime {
        // Chromium's main runs NSApp itself and returns when it has shut down.
        exit(coreRuntime.run())
    }
    app.run()
}
