import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// An assertion failed: the scenario stops and the report shows the message.
struct Check: Error, CustomStringConvertible { let description: String }

/// The scenario cannot be judged on this engine (or machine); the report shows SKIPPED with the reason.
struct Skipped: Error, CustomStringConvertible { let description: String }

/// The app process went away mid-scenario. `fatal` is the Swift fatal-error line from its stderr, if any.
struct AppDied: Error, CustomStringConvertible {
    let during: String
    let exit: String
    let fatal: String?
    var description: String { "the app exited during \(during): \(exit)" + (fatal.map { "; \($0)" } ?? "") }
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Check(description: message()) }
}

/// Max channel distance between two RGBA samples (pixel checks tolerate compositing and color-space rounding).
func distance(_ a: [Int], _ b: [Int]) -> Int {
    zip(a.prefix(3), b.prefix(3)).map { abs($0 - $1) }.max() ?? 0
}

func near(_ a: CGRect, _ b: CGRect, tolerance: Double = 0.5) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance && abs(a.width - b.width) <= tolerance
        && abs(a.height - b.height) <= tolerance
}

func uptime() -> Double { ProcessInfo.processInfo.systemUptime }

// MARK: - The process

/// The launched app binary. The runner owns it (launched directly, not through `open`), so it sees the exit status.
final class AppProcess {
    let process = Process()
    let log: URL

    init(executable: URL, environment: [String: String], log: URL) {
        self.log = log
        process.executableURL = executable
        process.environment = environment
    }

    func start() throws {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    /// Waits up to `timeout` seconds; true when the process has exited.
    @discardableResult
    func waitForExit(timeout: Double) -> Bool {
        let deadline = uptime() + timeout
        while process.isRunning, uptime() < deadline { usleep(50_000) }
        return !process.isRunning
    }

    func kill() {
        guard process.isRunning else { return }
        process.terminate()
        if !waitForExit(timeout: 3) { Foundation.kill(process.processIdentifier, SIGKILL) }
        waitForExit(timeout: 3)
    }

    /// "status 0", "status 3", "signal 5 (SIGTRAP)".
    var exitDescription: String {
        guard !process.isRunning else { return "still running" }
        switch process.terminationReason {
        case .exit: return "status \(process.terminationStatus)"
        case .uncaughtSignal:
            let names: [Int32: String] = [SIGILL: "SIGILL", SIGTRAP: "SIGTRAP", SIGABRT: "SIGABRT", SIGKILL: "SIGKILL", SIGBUS: "SIGBUS",
                                          SIGSEGV: "SIGSEGV", SIGTERM: "SIGTERM"]
            return "signal \(process.terminationStatus) (\(names[process.terminationStatus] ?? String(cString: strsignal(process.terminationStatus))))"
        @unknown default: return "status \(process.terminationStatus)"
        }
    }

    var exitedCleanly: Bool { !process.isRunning && process.terminationReason == .exit && process.terminationStatus == 0 }

    /// The last "Fatal error" line the Swift runtime wrote to stderr: "BrkDomain/CommandBar.swift:15: Fatal error: ...".
    var fatalLine: String? {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).last { $0.contains("Fatal error") }.map(String.init)
    }

    /// "W1: BrkDomain/CommandBar.swift:15", from `fatalLine`.
    var fatalOwner: String? {
        guard let line = fatalLine, let fileID = line.split(separator: ":").first.map(String.init), fileID.hasSuffix(".swift") else { return nil }
        let location = line.split(separator: ":").prefix(2).joined(separator: ":")
        return "\(E2EReport.owner(ofFileID: fileID)): \(location)"
    }
}

/// ~/Library/Logs/DiagnosticReports entries for the product (the app and its helpers share the name prefix).
enum CrashReports {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    static func names(prefix: String) -> Set<String> {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(all.filter { $0.hasPrefix(prefix) && ($0.hasSuffix(".ips") || $0.hasSuffix(".crash")) })
    }
}

// MARK: - The app under test

/// One scenario's app: launches, relaunches on the same data directory, and drives it only through the control
/// socket. Nothing here reads the app's windows; the app's files are read only for the final page log, the crash
/// reports and the stderr log.
final class AppUnderTest {
    enum Engine: String { case cef, stub }

    let executable: URL
    let dataDirectory: URL
    let site: FixtureServer
    let engine: Engine
    let scenarioID: String
    let shotsDirectory: URL
    private(set) var client: ControlClient
    private(set) var process: AppProcess?
    private(set) var hello: Hello?
    private(set) var launches = 0
    var remoteDebuggingPort: Int?
    private(set) var logs: [URL] = []
    private(set) var screenshots: [URL] = []
    private(set) var notes: [String] = []
    /// Host windows seen key in any `native()` reply during the scenario.
    private(set) var hostKeyViolations: [String] = []
    private var crashBaseline: Set<String> = []
    private var quitOutcome: QuitOutcome?

    struct QuitOutcome {
        let exit: String
        let clean: Bool
        let crashReports: [String]
        let finalPageLog: [PageLogEntry]?
    }

    init(executable: URL, dataDirectory: URL, site: FixtureServer, engine: Engine, scenarioID: String, shotsDirectory: URL) {
        self.executable = executable
        self.dataDirectory = dataDirectory
        self.site = site
        self.engine = engine
        self.scenarioID = scenarioID
        self.shotsDirectory = shotsDirectory
        client = ControlClient(path: dataDirectory.appendingPathComponent("control.sock").path)
    }

    private var targetWindow: WindowID?
    var window: WindowID? {
        get { targetWindow ?? hello?.windows.first }
        set { targetWindow = newValue }
    }
    var productPrefix: String { executable.lastPathComponent }
    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: Launch and quit

    /// Launches the binary with the e2e environment and waits for `hello` (10 s) and the first rendered snapshot.
    func launch() throws {
        if launches == 0 { crashBaseline = CrashReports.names(prefix: productPrefix) }
        launches += 1
        quitOutcome = nil
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("BRK_") }
        environment["BRK_CONTROL_SOCKET"] = client.path
        environment["BRK_DATA_DIR"] = dataDirectory.path
        environment["BRK_TEST_CLOCK"] = "1"
        environment["BRK_TEST_FILE_PANEL_DIRECTORY"] = dataDirectory.path
        if let remoteDebuggingPort { environment["BRK_REMOTE_DEBUGGING_PORT"] = String(remoteDebuggingPort) }
        if scenarioID != "ImportSync-Onboarding" { environment["BRK_START_URL"] = site.url("index.html").absoluteString }
        if scenarioID == "I5" { environment["BRK_MAIN_FRAME_TRACE"] = dataDirectory.appendingPathComponent("main-frame-trace.jsonl").path }
        if scenarioID.hasPrefix("AI") {
            environment["BRK_AI_FIXTURE_EXECUTABLE"] = site.root.deletingLastPathComponent().appendingPathComponent("Fixtures/ai-provider").path
            environment["BRK_AI_FIXTURE_LOG"] = dataDirectory.appendingPathComponent("ai-fixture.jsonl").path
        }
        environment["BRK_SUGGEST_URL"] = site.url("suggest").absoluteString
        if scenarioID.hasPrefix("TabTools") || scenarioID.hasPrefix("SidebarTools") { environment["BRK_GITHUB_FIXTURE_BASE"] = site.baseURL.absoluteString }
        if scenarioID.hasPrefix("SiteFilters") {
            // Port 9 (discard) refuses connections: the offline scenario's downloads find no server.
            environment["BRK_TEST_FILTER_BASE"] = scenarioID == "SiteFilters-offline" ? "http://127.0.0.1:9/filter-lists" : site.url("filter-lists").absoluteString
        }
        if scenarioID.hasPrefix("SiteSecurity"), let spki = HTTPSFixture.trustedSPKI(siteRoot: site.root) { environment["BRK_TEST_TRUSTED_SPKI"] = spki }
        if engine == .stub { environment["BRK_ENGINE"] = "stub" }
        let log = dataDirectory.appendingPathComponent("app-\(launches).log")
        logs.append(log)
        let process = AppProcess(executable: executable, environment: environment, log: log)
        self.process = process
        try process.start()
        Trap.appPID = process.process.processIdentifier

        let deadline = uptime() + 10
        while true {
            do {
                try client.connect(timeout: 0.3)
                break
            } catch {
                if !process.isRunning { throw died(during: "launch") }
                if uptime() >= deadline { throw Check(description: "no control socket within 10 s of launch (\(error))") }
            }
        }
        guard case .hello(let h) = try send(.hello, timeout: 10) else { throw Check(description: "hello did not answer with hello") }
        hello = h
        print("[e2e] launch \(scenarioID) #\(launches), pid \(h.pid)")
        try expect(h.engine == engine.rawValue, "hello says engine \(h.engine), the runner launched \(engine.rawValue)")
        try waitUntil("the first window render", timeout: 10) { (try? self.view()) != nil }
    }

    /// `quit` over the socket, then waits up to 10 s for the exit. A process that does not exit is killed and the
    /// outcome says so. Idempotent: a second call returns the first outcome.
    @discardableResult
    func quit() throws -> QuitOutcome {
        if let quitOutcome { return quitOutcome }
        guard let process else { throw Check(description: "quit before launch") }
        var exit: String
        if process.isRunning {
            let reply = try? client.send(.quit, timeout: 5)
            client.close()
            if reply != .ok { notes.append("quit did not reply ok (\(reply.map { "\($0)" } ?? "no reply"))") }
            if process.waitForExit(timeout: 10) {
                exit = process.exitDescription
            } else {
                process.kill()
                exit = "did not exit within 10 s of quit (killed)"
            }
        } else {
            client.close()
            exit = process.exitDescription
        }
        if !process.exitedCleanly, let fatal = process.fatalLine { exit += "; \(fatal)" }
        if process.process.terminationReason == .exit, process.process.terminationStatus == 3,
           let incomplete = try? String(contentsOf: dataDirectory.appendingPathComponent("shutdown-incomplete.log"), encoding: .utf8) {
            exit += "; shutdown-incomplete.log: \(incomplete.split(whereSeparator: \.isNewline).joined(separator: ", "))"
        }
        Trap.appPID = 0
        let pageLogFile = dataDirectory.appendingPathComponent("control-pagelog.json")
        let finalLog = (try? Data(contentsOf: pageLogFile)).flatMap { try? ControlWire.decode([PageLogEntry].self, line: $0.dropLast()) }
        try? FileManager.default.removeItem(at: pageLogFile)
        let outcome = QuitOutcome(exit: exit, clean: process.exitedCleanly, crashReports: newCrashReports(waitIfCrashed: !process.exitedCleanly),
                                  finalPageLog: finalLog)
        quitOutcome = outcome
        return outcome
    }

    /// quit() (which must be clean) then launch() with the same data directory.
    func restart() throws {
        let outcome = try quit()
        try expect(outcome.clean, "quit before restart: \(outcome.exit)")
        try expect(outcome.crashReports.isEmpty, "quit before restart left crash reports: \(outcome.crashReports.joined(separator: ", "))")
        try launch()
    }

    /// After every scenario: one more `native()` for the host-window rule, then a quit; problems are what fails a
    /// scenario that otherwise passed: a host window seen key, a non-zero exit, a new crash report.
    func finish(exitAlreadyReported: Bool = false) -> (problems: [String], needs: [String]) {
        var problems: [String] = []
        if isRunning, quitOutcome == nil, client.isConnected { _ = try? native() }
        if !hostKeyViolations.isEmpty { problems.append("a CEF host window was key: \(hostKeyViolations.joined(separator: "; "))") }
        if process != nil {
            if let outcome = try? quit() {
                if !outcome.clean, !exitAlreadyReported { problems.append("exit \(outcome.exit)") }
                if !outcome.crashReports.isEmpty { problems.append("new crash reports: \(outcome.crashReports.joined(separator: ", "))") }
            }
        }
        return (problems, process?.fatalOwner.map { [$0] } ?? [])
    }

    private func newCrashReports(waitIfCrashed: Bool) -> [String] {
        let deadline = uptime() + (waitIfCrashed ? 3 : 0.5)
        repeat {
            let fresh = CrashReports.names(prefix: productPrefix).subtracting(crashBaseline)
            if !fresh.isEmpty { return fresh.sorted() }
            usleep(250_000)
        } while uptime() < deadline
        return []
    }

    private func died(during: String) -> AppDied {
        process?.waitForExit(timeout: 3)
        return AppDied(during: during, exit: process?.exitDescription ?? "never launched", fatal: process?.fatalLine)
    }

    // MARK: Ops

    /// One request. A closed connection or a dead process becomes `AppDied` naming the op.
    @discardableResult
    func send(_ op: ControlOp, timeout: Double = 30) throws -> ControlResult {
        guard let process else { throw Check(description: "\(Self.describe(op)) before launch") }
        if let result = try nativePickerReply(op) { return result }
        do {
            return try client.send(op, timeout: timeout)
        } catch let error as ControlClientError {
            if case .closed = error { throw died(during: Self.describe(op)) }
            if !process.isRunning { throw died(during: Self.describe(op)) }
            throw Check(description: "control socket: \(error) during \(Self.describe(op))")
        }
    }

    /// An op that answers `ok`.
    func perform(_ op: ControlOp, timeout: Double = 30) throws {
        let result = try send(op, timeout: timeout)
        guard result == .ok else { throw Check(description: "\(Self.describe(op)) answered \(Self.describe(result))") }
    }

    func view() throws -> WindowSnapshot { try view(window) }

    /// Another window's snapshot (wave 2: a second standard window, an incognito or Little Arc window).
    func view(_ id: WindowID?) throws -> WindowSnapshot {
        let result = try send(.view(window: id))
        guard case .view(let snapshot) = result else { throw Check(description: "view answered \(Self.describe(result))") }
        return snapshot
    }

    func native() throws -> NativeFacts { try native(window) }

    func native(_ id: WindowID?) throws -> NativeFacts {
        let result = try send(.native(window: id))
        guard case .native(let facts) = result else { throw Check(description: "native answered \(Self.describe(result))") }
        let hostNumbers = Set(facts.pages.values.compactMap(\.hostWindowNumber))
        let auxiliaryNumbers = Set(facts.auxiliaryWindows ?? facts.pages.values.flatMap { $0.auxiliaryWindows ?? [] })
        for w in facts.appWindows where w.isKey && (hostNumbers.contains(w.number) || ((w.isPageHost ?? w.className.contains("NativeWidget")) && !auxiliaryNumbers.contains(w.number))) {
            let entry = "window \(w.number) (\(w.className))"
            if !hostKeyViolations.contains(entry) {
                hostKeyViolations.append(entry)
                let path = shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(scenarioID)-host-key-\(w.number)-native.json")
                try? ControlWire.encode(facts).write(to: path)
            }
        }
        return facts
    }

    /// Keep every window's model and native responder together, including windows created after launch.
    func recordWindows(_ label: String) throws {
        struct WindowEvidence: Encodable {
            let view: WindowSnapshot
            let native: NativeFacts
        }
        guard case .hello(let current) = try send(.hello) else { throw Check(description: "hello did not answer") }
        let evidence = try current.windows.map { try WindowEvidence(view: view($0), native: native($0)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let path = shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(scenarioID)-\(label)-windows.json")
        try encoder.encode(evidence).write(to: path)
    }

    /// Observe across deferred layout turns. Every sample must retain the requested native page responder;
    /// waiting for a later good sample cannot hide an intermittent loss.
    func verifyStablePageFocus(_ label: String) throws {
        struct Sample: Encodable {
            let elapsed: Double
            let window: WindowID
            let isKey: Bool
            let expected: PageID
            let focused: PageID?
            let firstResponder: String
            let hasKeyboardFocus: Bool
        }
        var samples: [Sample] = []
        let start = uptime()
        defer {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let path = shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(scenarioID)-\(label)-focus.json")
            if let data = try? encoder.encode(samples) { try? data.write(to: path) }
        }
        try waitUntil("native page focus to remain stable across layout updates") {
            guard case .hello(let current) = try send(.hello) else { return false }
            for id in current.windows {
                guard case .page(let page) = try view(id).focus else { continue }
                let facts = try native(id)
                let holds = facts.pages[page]?.hasKeyboardFocus == true
                samples.append(Sample(elapsed: uptime() - start, window: id, isKey: facts.isKey, expected: page,
                                      focused: facts.focusedPage, firstResponder: facts.firstResponder, hasKeyboardFocus: holds))
                try expect(facts.focusedPage == page && holds,
                           "window \(id) lost page \(page) during layout; first responder \(facts.firstResponder)")
            }
            return uptime() - start >= 0.5
        }
    }

    @discardableResult
    func dispatch(_ command: Command) throws -> Int {
        let result = try send(.dispatch(window: window, command: command))
        guard case .dispatched(let rev) = result else { throw Check(description: "dispatch answered \(Self.describe(result))") }
        return rev
    }

    /// Opens `url` as a new Today tab through the command-bar commands (scenario setup, not a key path).
    func load(_ url: URL) throws -> ItemID {
        let result = try send(.load(window: window, url: url))
        guard case .loaded(let tab) = result else { throw Check(description: "load answered \(Self.describe(result))") }
        return tab
    }

    /// Fixture setup must finish before synthetic page input. A load command or title alone is not a ready document.
    func waitForPageInput(_ page: PageID, at url: URL) throws {
        _ = try send(.activate(window: page.window))
        do {
            try waitUntil("ready document and native focus for \(page)") {
                guard case .pageObservations(let values) = try send(.pageObservations),
                      let state = values[page], case .ready = state.document, state.committedURL == url else { return false }
                let facts = try native(page.window)
                return facts.focusedPage == page && facts.pages[page]?.hasKeyboardFocus == true
            }
        } catch {
            // Say what held focus instead, so a timeout here can be attributed without a rerun.
            let facts = try? native(page.window)
            let keyWindows = facts?.appWindows.filter(\.isKey).map { "\($0.number) (\($0.className))" }.joined(separator: ", ") ?? "?"
            throw Check(description: "\(error): focusedPage=\(facts?.focusedPage.map { "\($0)" } ?? "nil") firstResponder=\(facts?.firstResponder ?? "nil") keyWindows=[\(keyWindows)] documentReady=\((try? send(.pageObservations)).map { if case .pageObservations(let v) = $0, case .ready? = v[page]?.document { return true } else { return false } } ?? false)")
        }
    }

    func press(_ chord: String) throws { try perform(.press(chord: chord)) }
    func hold(_ modifiers: String, _ chord: String, times: Int = 1) throws { try perform(.hold(modifiers: modifiers, chord: chord, times: times)) }
    func type(_ text: String) throws { try perform(.type(text: text)) }
    func click(_ view: ViewID, modifiers: String? = nil, count: Int = 1) throws {
        try perform(.click(view: view, point: nil, modifiers: modifiers, count: count))
    }
    func click(at point: CGPoint, modifiers: String? = nil, count: Int = 1) throws {
        try perform(.click(view: nil, point: point, modifiers: modifiers, count: count))
    }
    func hover(_ point: CGPoint) throws { try perform(.hover(point: point)) }
    func flush() throws { try perform(.flush) }
    func settle(timeout: Double = 10) throws { try perform(.settle(timeout: timeout), timeout: timeout + 5) }
    func evaluate(_ page: PageID, _ script: String) throws { try perform(.evaluate(page: page, script: script)) }
    func crash(_ page: PageID, _ target: CrashTarget) throws { try perform(.crash(page: page, process: target)) }
    func setWindowFrame(_ frame: CGRect) throws { try perform(.setWindowFrame(window: window, frame: frame)) }

    /// [r, g, b, a] of a fresh capture at a window point (top-left, points).
    func pixel(_ point: CGPoint) throws -> [Int] {
        let result = try send(.pixel(window: window, point: point))
        guard case .pixel(let r, let g, let b, let a) = result else { throw Check(description: "pixel(\(point)) answered \(Self.describe(result))") }
        return [r, g, b, a]
    }

    /// `<out>/shots/<scenario>-<name>.png`; returns its path and pixel size.
    @discardableResult
    func panelScreenshot(_ name: String) throws -> URL {
        let url = shotsDirectory.appendingPathComponent("\(scenarioID)-\(name).png")
        guard case .screenshot(_, _, _) = try send(.sidebarPanel(window: window, action: .capture(path: url.path))) else {
            throw Check(description: "Native sheet screenshot failed")
        }
        screenshots.append(url)
        return url
    }

    func screenshot(_ name: String, window id: WindowID? = nil) throws -> (url: URL, width: Int, height: Int) {
        let url = shotsDirectory.appendingPathComponent("\(scenarioID)-\(name).png")
        let result = try send(.screenshot(window: id ?? window, path: url.path))
        guard case .screenshot(_, let w, let h) = result else { throw Check(description: "screenshot answered \(Self.describe(result))") }
        if !screenshots.contains(url) { screenshots.append(url) }
        return (url, w, h)
    }

    @discardableResult
    func screenshotSheet(_ name: String, window id: WindowID? = nil) throws -> URL {
        let url = shotsDirectory.appendingPathComponent("\(scenarioID)-\(name).png")
        guard case .screenshot = try send(.screenshotSheet(window: id ?? window, path: url.path)) else { throw Check(description: "Sheet capture failed") }
        screenshots.append(url)
        return url
    }

    func screenshotSiteControls(_ name: String) throws -> URL {
        guard let window else { throw Check(description: "no screenshot owner") }
        let url = shotsDirectory.appendingPathComponent("\(scenarioID)-\(name).png")
        try waitUntil("the real native site controls capture") {
            let result = try self.send(.siteControlsScreenshot(window: window, path: url.path))
            guard case .screenshot = result else { throw Check(description: "site capture answered \(result)") }
            return true
        }
        if !screenshots.contains(url) { screenshots.append(url) }
        return url
    }

    @discardableResult
    func advanceClock(seconds: Double) throws -> Instant {
        let result = try send(.advanceClock(seconds: seconds))
        guard case .clock(let now) = result else { throw Check(description: "advanceClock(\(seconds)) answered \(Self.describe(result))") }
        return now
    }

    func pageLog() throws -> [PageLogEntry] {
        let result = try send(.pageLog)
        guard case .pageLog(let entries) = result else { throw Check(description: "pageLog answered \(Self.describe(result))") }
        return entries
    }

    // MARK: Polling, notes, engine

    /// Polls `condition` every 100 ms until it returns true or `timeout` passes. A `Check` thrown by the condition
    /// counts as "not yet" and its message is kept for the timeout report; `AppDied` ends the wait at once.
    func waitUntil(_ message: String, timeout: Double = 8, _ condition: () throws -> Bool) throws {
        let deadline = uptime() + timeout
        var last: String?
        while true {
            do {
                if try condition() { return }
                last = nil
            } catch let error as AppDied {
                throw error
            } catch {
                last = "\(error)"
            }
            if uptime() >= deadline {
                throw Check(description: "timed out after \(timeout) s waiting for \(message)" + (last.map { " (last: \($0))" } ?? ""))
            }
            usleep(100_000)
        }
    }

    func sleep(_ seconds: Double) { usleep(useconds_t(seconds * 1_000_000)) }

    /// A caveat shown next to a PASS.
    func note(_ text: String) { if !notes.contains(text) { notes.append(text) } }

    /// Checks that passed so far; a FAIL lists them, so a scenario stopped by someone else's unfinished code still
    /// shows what it proved before.
    private(set) var checkpoints: [String] = []
    func passed(_ what: String) { checkpoints.append(what) }

    /// The rest of the scenario needs Chromium: on the stub engine it ends here as SKIPPED.
    func requireCEF(_ what: String) throws {
        if engine == .stub { throw Skipped(description: "needs CEF engine (\(what)); the stub-capable checks before it passed") }
    }

    /// Runs `body` only on the CEF engine; on the stub records `what` as not checked.
    func onCEF(_ what: String, _ body: () throws -> Void) throws {
        if engine == .cef { try body() } else { note("\(what) not checked on the stub engine") }
    }

    static func describe(_ op: ControlOp) -> String {
        let text: String
        switch op {
        case .press(let chord): text = "press(\"\(chord)\")"
        case .hold(let m, let c, let n): text = "hold(\"\(m)\", \"\(c)\", \(n))"
        case .type(let t): text = "type(\"\(t)\")"
        case .click(let v, let p, let m, _): text = "click(\(v.map(\.identifier) ?? p.map { "\($0)" } ?? "?")\(m.map { ", \($0)" } ?? ""))"
        case .load(_, let url): text = "load(\(url.absoluteString))"
        case .dispatch(_, let command):
            text = "dispatch(\(command))".replacingOccurrences(of: "BrkDomain.", with: "").replacingOccurrences(of: "BrkBase.", with: "")
        case .view: text = "view"
        case .native: text = "native"
        default: text = "\(op)"
        }
        return text.count > 160 ? String(text.prefix(157)) + "..." : text
    }

    static func describe(_ result: ControlResult) -> String {
        let text = "\(result)"
        return text.count > 200 ? String(text.prefix(197)) + "..." : text
    }
}
