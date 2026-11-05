import BrkBase
import BrkControl
import CoreGraphics
import Foundation

/// Runs the selected scenarios, each in its own app launch with a fresh data directory, and collects the report.
final class Runner {
    let arguments: RunnerArguments
    private(set) var backingScale: Double?

    init(_ arguments: RunnerArguments) { self.arguments = arguments }

    /// Runs the scenarios and writes `<out>/REPORT.md` after each one (see main.swift); returns the results.
    func runAll() throws -> [E2EResult] {
        signal(SIGPIPE, SIG_IGN)
        let fm = FileManager.default
        let out = arguments.outputDirectory
        let shots = out.appendingPathComponent("shots", isDirectory: true)
        let logs = out.appendingPathComponent("logs", isDirectory: true)
        for directory in [shots, logs] {
            try? fm.removeItem(at: directory)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let server = FixtureServer(root: arguments.site)
        try server.start()
        defer { server.stop() }
        // Keep the chosen root short enough for the control socket's Unix path limit.
        let scratchRoot = ProcessInfo.processInfo.environment["BRK_E2E_DATA_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let scratch = scratchRoot.appendingPathComponent("brk-e2e-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: scratch)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        print("[e2e] fixture site \(server.baseURL.absoluteString), app \(arguments.executable.path), engine \(arguments.engine.rawValue)")

        let started = uptime()
        let selected = Scenarios.all.filter { arguments.only?.contains($0.id) ?? true }
        var results: [E2EResult] = []
        /// The report so far; while `running` is set, that scenario is listed as FAIL (a runner that dies in it never
        /// gets to replace the line).
        func writeReport(running: Scenario?) throws {
            var listed = results
            if let running {
                listed.append(E2EResult(id: running.id, title: running.title, outcome: .fail, seconds: 0,
                                        message: Trap.unfinishedMessage, log: "logs/\(running.id).log"))
            }
            let report = E2EReport.markdown(listed, machine: machine(), totalSeconds: uptime() - started)
            try report.write(to: out.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
        }
        for (index, scenario) in selected.enumerated() {
            Trap.entering(scenario.id)
            try writeReport(running: scenario)
            let result = run(scenario, index: index, server: server, scratch: scratch, shots: shots, logs: logs)
            print("[e2e] \(result.outcome.rawValue) \(result.id) (\(String(format: "%.1f", result.seconds)) s)\(result.message.map { ": \($0)" } ?? "")")
            results.append(result)
            try writeReport(running: nil)
        }
        Trap.entering(nil)
        if !results.contains(where: { $0.outcome == .fail }) { try? fm.removeItem(at: scratch) }
        return results
    }

    /// The real pointer goes to the screen's bottom right corner before each scenario. A scenario that hovers through
    /// the control socket depends on where the real pointer rests: left inside the app's window by a real-pointer
    /// scenario before it (N3R, the R53 drags), AppKit's own tracking of that pointer undoes the hover, and
    /// R36-HoverCards, R49-MailCard and SidebarToolsPreview fail; parked at the corner they pass (2026-11-05, four runs).
    private static func parkPointer() {
        guard CGPreflightPostEventAccess() else { return }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let corner = CGPoint(x: bounds.maxX - 2, y: bounds.maxY - 2)
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: corner, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(150_000)
    }

    private func run(_ scenario: Scenario, index: Int, server: FixtureServer, scratch: URL, shots: URL, logs: URL) -> E2EResult {
        let engine: AppUnderTest.Engine = arguments.engine == .stub ? .stub : .cef
        if let owner = scenario.pending {
            return E2EResult(id: scenario.id, title: scenario.title, outcome: .skipped, seconds: 0, message: "pending \(owner) (wave 2)")
        }
        if engine == .stub, let reason = scenario.cefOnly {
            return E2EResult(id: scenario.id, title: scenario.title, outcome: .skipped, seconds: 0, message: "needs CEF engine (\(reason))")
        }
        let data = scratch.appendingPathComponent("\(index)-\(scenario.id)", isDirectory: true)
        let app = AppUnderTest(executable: arguments.executable, dataDirectory: data, site: server, engine: engine,
                               scenarioID: scenario.id, shotsDirectory: shots)
        let start = uptime()
        var outcome = E2EOutcome.pass
        var message: String?
        var died = false
        do {
            Self.parkPointer()
            try app.launch()
            if backingScale == nil { backingScale = try? app.native().backingScale }
            try scenario.run(app)
        } catch let skip as Skipped {
            outcome = .skipped
            message = skip.description
        } catch {
            outcome = .fail
            message = "\(error)"
            died = error is AppDied
            if app.isRunning {
                try? app.recordWindows("failure")
                _ = try? app.screenshot("failure")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let native = try? app.native(), let json = try? encoder.encode(native) {
                    try? json.write(to: logs.appendingPathComponent("\(scenario.id)-native.json"))
                }
                if let view = try? app.view(), let json = try? encoder.encode(view) {
                    try? json.write(to: logs.appendingPathComponent("\(scenario.id)-view.json"))
                }
            }
        }
        if outcome == .fail, !app.checkpoints.isEmpty, let failure = message {
            message = "\(failure) (passed before it: \(app.checkpoints.joined(separator: "; ")))"
        }
        let (problems, needs) = app.finish(exitAlreadyReported: died)
        if !problems.isEmpty {
            let after = "after the scenario: " + problems.joined(separator: "; ")
            message = outcome == .fail ? [message, after].compactMap { $0 }.joined(separator: "; ") : after
            outcome = .fail
        }
        let logName = "logs/\(scenario.id).log"
        let combined = app.logs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n--- relaunch ---\n")
        try? combined.write(to: logs.appendingPathComponent("\(scenario.id).log"), atomically: true, encoding: .utf8)
        if outcome != .fail { try? FileManager.default.removeItem(at: data) }
        return E2EResult(id: scenario.id, title: scenario.title, outcome: outcome, seconds: uptime() - start, message: message,
                         notes: outcome == .pass ? app.notes : [],
                         screenshots: app.screenshots.map { "shots/\($0.lastPathComponent)" }, log: logName,
                         needs: outcome == .fail ? needs : [])
    }

    private func machine() -> E2EMachine {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "macOS ").replacingOccurrences(of: "Build ", with: "")
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelName = String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var cef = "n/a"
        if arguments.app.pathExtension == "app" {
            let plist = arguments.app.appendingPathComponent("Contents/Frameworks/Chromium Embedded Framework.framework/Resources/Info.plist")
            if let info = NSDictionary(contentsOf: plist) {
                cef = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "unknown"
            }
        }
        let display = "\(Self.screenLocked() ? "locked" : "unlocked")\(backingScale.map { ", backing scale \(Int($0))" } ?? "")"
        let cwd = FileManager.default.currentDirectoryPath + "/"
        let app = arguments.app.path.hasPrefix(cwd) ? String(arguments.app.path.dropFirst(cwd.count)) : arguments.app.path
        return E2EMachine(date: ISO8601DateFormatter().string(from: Date()), macOS: os, model: modelName, engine: arguments.engine.rawValue,
                          cefVersion: cef, display: display, app: app)
    }

    /// The console session's lock state (`CGSSessionScreenIsLocked` in the IORegistry root).
    static func screenLocked() -> Bool {
        let ioreg = Process()
        ioreg.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        ioreg.arguments = ["-n", "Root", "-d1", "-a"]
        let pipe = Pipe()
        ioreg.standardOutput = pipe
        ioreg.standardError = FileHandle.nullDevice
        guard (try? ioreg.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ioreg.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: "<key>CGSSessionScreenIsLocked</key>") else { return false }
        return text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<true/>")
    }
}

/// A fatal signal in the runner (a Swift runtime trap is SIGTRAP, and a release build prints nothing for it) writes
/// one line naming the scenario it happened in, then takes the default action, so the shell still reports the
/// signal. The line is prepared outside the handler: a signal handler may only call async-signal-safe functions.
enum Trap {
    static let unfinishedMessage = "the runner stopped inside this scenario (a trap or a kill; its stderr names the signal)"
    private static let capacity = 256
    nonisolated(unsafe) private static let line = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
    /// The app under test, killed with the runner so it does not outlive it holding the display (0: none).
    nonisolated(unsafe) static var appPID: pid_t = 0

    static func install() {
        line.initialize(repeating: 0, count: capacity)
        for sig in [SIGTRAP, SIGILL, SIGABRT, SIGSEGV, SIGBUS, SIGFPE] {
            signal(sig) { sig in
                _ = write(STDERR_FILENO, Trap.line, strlen(Trap.line))
                if Trap.appPID > 0 { kill(Trap.appPID, SIGKILL) }
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
    }

    /// The scenario now running, or nil between scenarios.
    static func entering(_ id: String?) {
        let text = id.map { "brk-e2e: fatal signal inside scenario \($0); REPORT.md lists it as FAIL\n" }
            ?? "brk-e2e: fatal signal between scenarios; REPORT.md is complete\n"
        _ = strlcpy(line, text, capacity)
    }
}
