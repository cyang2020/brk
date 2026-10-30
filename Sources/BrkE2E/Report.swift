import Foundation

struct ScenarioResult {
    enum Outcome: String { case passed = "PASS", failed = "FAIL", skipped = "SKIPPED" }
    let id: String
    let title: String
    let outcome: Outcome
    let message: String?
    let screenshots: [URL]
    let seconds: Double
}

final class Runner {
    let arguments: RunnerArguments
    init(_ arguments: RunnerArguments) { self.arguments = arguments }

    /// Starts the fixture server, runs every selected scenario in its own app launch, stops the server.
    func runAll() -> [ScenarioResult] {
        // TODO(W6): per scenario: fresh temp data dir, AppUnderTest.launch, run, always quit (record exit status and
        // crash reports; a crash at quit fails a scenario that otherwise passed), collect screenshots.
        fatalError("not implemented")
    }
}

enum Report {
    /// verify/swift/REPORT.md: header with counts, the machine (macOS, display, CEF version from hello), then one
    /// row per scenario (id, title, PASS/FAIL/SKIPPED, seconds, message) and links to its screenshots.
    static func write(_ results: [ScenarioResult], to directory: URL) {
        fatalError("not implemented")
    }
}
