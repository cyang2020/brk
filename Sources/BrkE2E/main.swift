// brk-e2e: runs the end-to-end scenarios against the built app on this Mac's display.
//
//   swift run brk-e2e --app dist/Brk.app --site Tests/E2ESite --out verify/swift [--only 4,R6] [--engine stub]
//
// For each scenario: a fresh data directory, a launch of the app binary with BRK_CONTROL_SOCKET, BRK_DATA_DIR,
// BRK_TEST_CLOCK=1 and BRK_START_URL=<fixture home> (plus BRK_ENGINE=stub for the stub engine), the scenario's steps
// over the control socket, screenshots into <out>/shots/, then the after-scenario checks (no CEF host window was key,
// a clean quit with exit status 0, no new crash report in ~/Library/Logs/DiagnosticReports). Writes <out>/REPORT.md
// and <out>/logs/<scenario>.log (the app's stdout and stderr). Exit status 1 when any scenario failed.
import BrkControl
import Foundation

do {
    let arguments = try RunnerArguments(CommandLine.arguments)
    let (results, machine, seconds) = try Runner(arguments).runAll()
    let report = E2EReport.markdown(results, machine: machine, totalSeconds: seconds)
    try report.write(to: arguments.outputDirectory.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
    print("[e2e] wrote \(arguments.outputDirectory.appendingPathComponent("REPORT.md").path)")
    exit(results.contains { $0.outcome == .fail } ? 1 : 0)
} catch {
    FileHandle.standardError.write(Data("brk-e2e: \(error)\n".utf8))
    exit(2)
}
