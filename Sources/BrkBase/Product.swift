import Foundation

/// The product's name and data location, derived at run time from the one definition in Package.swift
/// (`productName`): the bundle's CFBundleName when running as the .app, else the executable name (swift run).
/// Nothing else in Sources/ spells the name.
public enum Product {
    public static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ProcessInfo.processInfo.processName
    }

    /// `~/Library/Application Support/<name>/`, or `$BRK_DATA_DIR` (e2e runs give every launch its own profile).
    /// Holds `state.json` (the one state file), quarantined files, and `Chromium/` (CEF's cache root).
    public static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["BRK_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(name, isDirectory: true)
    }
}

/// Launch-time switches, read once in main.swift. Every e2e hook is off unless its variable is set.
public struct LaunchOptions: Sendable, Equatable {
    public enum EngineKind: String, Sendable { case cef, stub, core }

    /// `BRK_ENGINE=stub` runs the whole shell without Chromium (placeholder page views), so sidebar, command
    /// bar and theme work can be run and screenshotted without downloading CEF. `BRK_ENGINE=core` runs on BrkCore.framework, Brk's own
    /// Chromium build (engine/), when the bundle has it.
    public var engine: EngineKind
    /// `BRK_CONTROL_SOCKET=/path`: start the control server on this Unix socket.
    public var controlSocket: String?
    /// `BRK_TEST_CLOCK=1`: the clock is real time plus an offset that only `advanceClock` moves.
    public var testClock: Bool
    /// `BRK_START_URL`: the single tab of a fresh profile (default: none, the command bar opens).
    public var startURL: URL?
    /// `BRK_REMOTE_DEBUGGING_PORT`: CEF DevTools port, for debugging the e2e fixture pages.
    public var remoteDebuggingPort: Int?
    /// `BRK_SUGGEST_URL`: replaces every search engine's suggest endpoint (the query is appended as `q`, the engine's
    /// own suggest host as `engine`), so the e2e fixture server can answer W2-10 without the network and tell which
    /// engine asked.
    public var suggestOverride: URL?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        engine = EngineKind(rawValue: environment["BRK_ENGINE"] ?? "") ?? .cef
        controlSocket = environment["BRK_CONTROL_SOCKET"].flatMap { $0.isEmpty ? nil : $0 }
        testClock = environment["BRK_TEST_CLOCK"] == "1"
        startURL = environment["BRK_START_URL"].flatMap(URL.init(string:))
        remoteDebuggingPort = environment["BRK_REMOTE_DEBUGGING_PORT"].flatMap(Int.init)
        suggestOverride = environment["BRK_SUGGEST_URL"].flatMap(URL.init(string:))
    }
}
