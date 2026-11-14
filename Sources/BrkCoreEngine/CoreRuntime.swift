import AppKit
import BrkBase
import CBrkCore
import Foundation

/// Loads the bundled BrkCore.framework before anything touches NSApp: Chromium installs its NSApplication class.
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
        guard application.responds(to: NSSelectorFromString("embeddingInterfaceVersion")), application.embeddingInterfaceVersion >= 2 else {
            throw Unavailable(description: "BrkCore.framework predates page resource management and store installation. Rebuild the engine before bundling this app.")
        }
        self.application = application
    }

    /// What Chrome's own `main` does first (chrome/app/chrome_exe_main_mac.cc): a stand-in default malloc zone, registered while the process
    /// has one thread, which Chromium's allocator swaps for its own when the framework loads. Call before anything else. Without the library
    /// (a bundle assembled before it existed) the framework still swaps the zones itself, as it did before.
    public static func registerAllocatorZone() {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libBrkCoreEarly.dylib").path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL), let entry = dlsym(handle, "BrkCoreEarlyMallocZoneRegistration") else { return }
        typealias Entry = @convention(c) () -> Void
        unsafeBitCast(entry, to: Entry.self)()
    }

    /// Runs Chromium's main, which runs NSApp, until Chromium has shut down. The exit code.
    public func run() -> Int32 { Int32(application.run()) }

    /// Chromium's command line. Controlled test launches use an isolated keychain and local fixture hosts.
    static func arguments(userData: URL, debugPort: Int?, environment: [String: String]) -> [String] {
        var out = [CommandLine.arguments[0], "--user-data-dir=\(userData.path)", "--profile-directory=Default", "--no-startup-window",
                   "--no-first-run", "--no-default-browser-check", "--disable-background-networking",
                   "--disable-component-update", "--disable-sync", "--disable-domain-reliability"]
        if let debugPort { out.append("--remote-debugging-port=\(debugPort)") }
        if LaunchOptions(environment: environment).controlSocket != nil {
            out += ["--use-mock-keychain", "--host-resolver-rules=MAP *.brk.test 127.0.0.1, MAP *.localhost 127.0.0.1"]
            if let spki = environment["BRK_TEST_TRUSTED_SPKI"], !spki.isEmpty { out.append("--ignore-certificate-errors-spki-list=\(spki)") }
            if let log = environment["BRK_TEST_CHROMIUM_LOG"], !log.isEmpty { out += ["--enable-logging", "--log-file=\(log)", "--v=0"] }
        }
        return out
    }
}
