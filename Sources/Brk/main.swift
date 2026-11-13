// Composition root. Brk runs on BrkCore.framework, its own Chromium build (engine/, docs/chromium/ARC-ENGINE.md), and on
// nothing else: there is no engine switch.
//
// Order matters: the framework installs Chromium's NSApplication class before anything touches NSApp, so the runtime is
// created first, then the delegate; Chromium's main then runs NSApp itself.
import AppKit
import BrkApp
import BrkBase
import BrkCoreEngine
import BrkEngine

// An agent's MCP server for Brk's tab tools is this program too (`Brk --brk-tools …`): it pipes and exits, before anything loads.
BrkToolBridge.runIfAsked()

MainActor.assumeIsolated {
    let options = LaunchOptions()
    // Before anything else, while this is the only thread (BrkCoreRuntime.registerAllocatorZone).
    BrkCoreRuntime.registerAllocatorZone()
    CrashBacktrace.install()
    // Logins an import staged while Chromium held a profile's Login Data go in now, before Chromium opens it.
    BrowserImportStartup.applyPendingLogins()
    let runtime: BrkCoreRuntime
    do {
        runtime = try BrkCoreRuntime(userDataDirectory: Product.dataDirectory().appendingPathComponent("Chromium", isDirectory: true),
                                     remoteDebuggingPort: options.remoteDebuggingPort)
    } catch {
        FileHandle.standardError.write(Data("""
        \(Product.name): BrkCore could not start (\(error)).
        Run the bundled app built by scripts/build.sh: it carries BrkCore.framework in Contents/Frameworks.

        """.utf8))
        exit(1)
    }
    let lifecycle = Lifecycle(options: options, engine: CoreEngine(runtime: runtime))
    let app = NSApplication.shared
    app.delegate = lifecycle
    app.setActivationPolicy(.regular)
    // Chromium's main runs NSApp itself and returns when it has shut down.
    exit(runtime.run())
}
