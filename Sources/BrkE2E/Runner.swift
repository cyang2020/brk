import BrkBase
import BrkControl
import Foundation

/// Runs the selected scenarios, each in its own app launch with a fresh data directory, and collects the report.
final class Runner {
    let arguments: RunnerArguments
    private(set) var backingScale: Double?

    init(_ arguments: RunnerArguments) { self.arguments = arguments }

    func runAll() throws -> (results: [E2EResult], machine: E2EMachine, seconds: Double) {
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
        let scratch = URL(fileURLWithPath: "/tmp/brk-e2e-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: scratch)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        print("[e2e] fixture site \(server.baseURL.absoluteString), app \(arguments.executable.path), engine \(arguments.engine.rawValue)")

        let started = uptime()
        let selected = Scenarios.all.filter { arguments.only?.contains($0.id) ?? true }
        var results: [E2EResult] = []
        for (index, scenario) in selected.enumerated() {
            let result = run(scenario, index: index, server: server, scratch: scratch, shots: shots, logs: logs)
            print("[e2e] \(result.outcome.rawValue) \(result.id) (\(String(format: "%.1f", result.seconds)) s)\(result.message.map { ": \($0)" } ?? "")")
            results.append(result)
        }
        let seconds = uptime() - started
        if !results.contains(where: { $0.outcome == .fail }) { try? fm.removeItem(at: scratch) }
        return (results, machine(), seconds)
    }

    private func run(_ scenario: Scenario, index: Int, server: FixtureServer, scratch: URL, shots: URL, logs: URL) -> E2EResult {
        let engine: AppUnderTest.Engine = arguments.engine == .stub ? .stub : .cef
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
            if app.isRunning { _ = try? app.screenshot("failure") }
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
