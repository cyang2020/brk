// brk-e2e: runs the end-to-end scenarios against the built app on this Mac's display.
//
//   swift run brk-e2e --app dist/Brk.app --site Tests/E2ESite --out verify/swift [--only 4,R6]
//
// For each scenario: a fresh data directory, a launch of the app binary with BRK_CONTROL_SOCKET, BRK_DATA_DIR,
// BRK_TEST_CLOCK=1 and BRK_START_URL=<fixture home>, the scenario's steps over the control socket, screenshots into
// <out>/shots/, then a clean quit (exit status 0 and no new crash report in ~/Library/Logs/DiagnosticReports is part
// of every scenario's pass condition). Writes <out>/REPORT.md.
import Foundation

let arguments = RunnerArguments(CommandLine.arguments)
let results = Runner(arguments).runAll()
Report.write(results, to: arguments.outputDirectory)
exit(results.allSatisfy { $0.outcome != .failed } ? 0 : 1)
