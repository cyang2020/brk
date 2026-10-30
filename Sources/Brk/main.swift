// Composition root. The only file that knows which engine runs.
//
// Order matters: CEF must install its NSApplication subclass before anything touches NSApp, so the engine is
// created first, then the delegate, then the run loop. With BRK_ENGINE=stub nothing loads Chromium and the shell
// runs from `swift run Brk` without a .app bundle.
import AppKit
import BrkApp
import BrkBase
import BrkCEF
import BrkEngine

MainActor.assumeIsolated {
    CrashBacktrace.install()
    let options = LaunchOptions()
    let engine: any WebEngine
    switch options.engine {
    case .cef:
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
    }
    let lifecycle = Lifecycle(options: options, engine: engine, engineKind: options.engine.rawValue)
    let app = NSApplication.shared
    app.delegate = lifecycle
    app.setActivationPolicy(.regular)
    app.run()
}
