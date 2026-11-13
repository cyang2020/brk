import Foundation

// The e2e report's content and its Markdown, as pure values and one pure function, so the runner (BrkE2E, an
// executable) only collects facts and writes a file, and BrkControlTests can pin the format. Lives here because
// BrkControl is the module both the runner and the tests already import.

public enum E2EOutcome: String, Sendable, Equatable, CaseIterable {
    case pass = "PASS", fail = "FAIL", skipped = "SKIPPED"
}

public struct E2EResult: Sendable, Equatable {
    /// "0" to "9", "R2" to "R10", "N1" to "N4".
    public var id: String
    public var title: String
    public var outcome: E2EOutcome
    public var seconds: Double
    /// FAIL: the assertion that failed (or how the app died). SKIPPED: why.
    public var message: String?
    /// Caveats on a PASS, such as external hardware that was not exercised.
    public var notes: [String]
    /// Paths relative to the report's directory.
    public var screenshots: [String]
    public var log: String?
    /// Owners whose unfinished code stopped this scenario: "W1: BrkDomain/CommandBar.swift:15".
    public var needs: [String]

    public init(id: String, title: String, outcome: E2EOutcome, seconds: Double, message: String? = nil, notes: [String] = [],
                screenshots: [String] = [], log: String? = nil, needs: [String] = []) {
        self.id = id
        self.title = title
        self.outcome = outcome
        self.seconds = seconds
        self.message = message
        self.notes = notes
        self.screenshots = screenshots
        self.log = log
        self.needs = needs
    }
}

public struct E2EMachine: Sendable, Equatable {
    public var date: String
    public var macOS: String
    public var model: String
    /// The engine used by the run ("core").
    public var engine: String
    public var chromiumVersion: String
    /// e.g. "locked, backing scale 2".
    public var display: String
    public var app: String

    public init(date: String, macOS: String, model: String, engine: String, chromiumVersion: String, display: String, app: String) {
        self.date = date
        self.macOS = macOS
        self.model = model
        self.engine = engine
        self.chromiumVersion = chromiumVersion
        self.display = display
        self.app = app
    }
}

public enum E2EReport {
    /// REPORT.md (brk-e2e --out): a header line with the machine, engine, total time and counts; one list line per
    /// scenario (`- PASS 0 title · 1.2 s · notes · shots`, with ` — message` on FAIL and SKIPPED); then the owners
    /// whose unfinished code failed scenarios, grouped.
    public static func markdown(_ results: [E2EResult], machine: E2EMachine, totalSeconds: Double) -> String {
        let counts = E2EOutcome.allCases.map { outcome in "\(results.filter { $0.outcome == outcome }.count) \(outcome.rawValue)" }
        var out = "# Brk e2e report\n\n"
        out += "\(machine.date) · \(machine.macOS) · \(machine.model) · engine \(machine.engine) (Chromium \(machine.chromiumVersion)) · "
        out += "display \(machine.display) · \(results.count) scenarios in \(seconds(totalSeconds)) · \(counts.joined(separator: ", "))\n\n"
        out += "App: `\(machine.app)`\n\n"
        for r in results {
            var line = "- \(r.outcome.rawValue) \(r.id) \(r.title) · \(seconds(r.seconds))"
            if let message = r.message { line += " — \(oneLine(message))" }
            for note in r.notes { line += " · note: \(oneLine(note))" }
            if !r.screenshots.isEmpty {
                line += " · " + r.screenshots.map { "[\(($0 as NSString).lastPathComponent)](\($0))" }.joined(separator: " ")
            }
            if let log = r.log { line += " · [log](\(log))" }
            out += line + "\n"
        }
        var needs: [String: [String]] = [:]
        for r in results where r.outcome == .fail {
            for need in r.needs where !(needs[need]?.contains(r.id) ?? false) { needs[need, default: []].append(r.id) }
        }
        if !needs.isEmpty {
            out += "\n## Needs\n\n"
            for need in needs.keys.sorted() { out += "- \(need) (scenarios \(needs[need]!.joined(separator: ", ")))\n" }
        }
        return out
    }

    /// The worker who owns a source file, from the module map's ownership table: `#fileID` paths as Swift prints them
    /// in a fatal error ("BrkDomain/CommandBar.swift").
    public static func owner(ofFileID fileID: String) -> String {
        let module = fileID.split(separator: "/").first.map(String.init) ?? fileID
        switch module {
        case "BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit": return fileID.hasPrefix("BrkDomain/SpaceTheme.swift") ? "W5" : "W1"
        case "BrkApp" where controlFiles.contains(String(fileID.dropFirst("BrkApp/".count))): return "W6"
        case "BrkEngine", "BrkCoreEngine", "CBrkCore", "BrkApp", "BrkContent", "Brk": return "W2"
        case "BrkSidebar": return "W3"
        case "BrkOverlays": return "W4"
        case "BrkTheme": return "W5"
        case "BrkControl", "BrkE2E": return "W6"
        case "BrkSettings": return "F1"
        case "BrkLibrary": return "F5"
        default: return "unknown owner"
        }
    }

    /// BrkApp/Control/ (W6) as Swift's `#fileID` spells it: module and file name, no directory.
    private static let controlFiles: Set<String> = ["ControlServer.swift", "ControlExecutor.swift", "EventInjector.swift", "ViewTree.swift"]

    private static func seconds(_ s: Double) -> String { String(format: "%.1f s", s) }
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
