import AppKit
import BrkBase
import CBrkCore
import Foundation

/// BrkCore.framework, Brk's own Chromium build (engine/, docs/chromium/ARC-ENGINE.md). Found at run time, so a build without it still
/// links and runs on CEF. `load` must run before anything touches NSApp: it installs Chromium's NSApplication class.
@MainActor
public final class BrkCoreRuntime {
    public struct Unavailable: Error, CustomStringConvertible {
        public let description: String
    }

    public let application: any BrkCoreApplication
    /// Chromium's user data folder; a profile's data is `Profile-<id>` in it (`ProfileDirectories.directoryName`).
    let userDataDirectory: URL

    public init(userDataDirectory: URL, remoteDebuggingPort: Int?) throws {
        try? FileManager.default.createDirectory(at: userDataDirectory, withIntermediateDirectories: true)
        // Profiles deleted in the last run go before Chromium can hold their folders, as on CEF.
        ProfileDirectories(root: userDataDirectory).deleteMarked()
        self.userDataDirectory = userDataDirectory
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/BrkCore.framework/BrkCore").path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw Unavailable(description: "BrkCore.framework did not load: \(String(cString: dlerror()))")
        }
        guard let prepare = dlsym(handle, "BrkCoreApplicationPrepare"), let shared = dlsym(handle, "BrkCoreApplicationShared") else {
            throw Unavailable(description: "BrkCore.framework has no entry points")
        }
        typealias Prepare = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>>) -> Void
        typealias Shared = @convention(c) () -> UnsafeMutableRawPointer
        let arguments = Self.arguments(userData: userDataDirectory, debugPort: remoteDebuggingPort, environment: ProcessInfo.processInfo.environment)
        let copies = arguments.map { UnsafePointer<CChar>(strdup($0)!) }
        copies.withUnsafeBufferPointer { unsafeBitCast(prepare, to: Prepare.self)(Int32(copies.count), $0.baseAddress!) }
        copies.forEach { free(UnsafeMutablePointer(mutating: $0)) }
        let object = Unmanaged<AnyObject>.fromOpaque(unsafeBitCast(shared, to: Shared.self)()).takeUnretainedValue()
        guard let application = object as? any BrkCoreApplication else {
            throw Unavailable(description: "BrkCore.framework's application has another interface")
        }
        self.application = application
    }

    /// Runs Chromium's main, which runs NSApp, until Chromium has shut down. The exit code.
    public func run() -> Int32 { Int32(application.run()) }

    /// Chromium's command line. Test launches get what CEFEngine gives them, with no calls home on top.
    static func arguments(userData: URL, debugPort: Int?, environment: [String: String]) -> [String] {
        var out = [CommandLine.arguments[0], "--user-data-dir=\(userData.path)", "--profile-directory=Default", "--no-startup-window",
                   "--no-first-run", "--no-default-browser-check"]
        if let debugPort { out.append("--remote-debugging-port=\(debugPort)") }
        if environment["BRK_CONTROL_SOCKET"] != nil {
            out += ["--use-mock-keychain", "--host-resolver-rules=MAP *.brk.test 127.0.0.1, MAP *.localhost 127.0.0.1",
                    "--disable-background-networking", "--disable-component-update", "--disable-sync"]
            if let spki = environment["BRK_TEST_TRUSTED_SPKI"], !spki.isEmpty { out.append("--ignore-certificate-errors-spki-list=\(spki)") }
            if let log = environment["BRK_TEST_CEF_LOG"], !log.isEmpty { out += ["--enable-logging", "--log-file=\(log)", "--v=0"] }
        }
        return out
    }
}
