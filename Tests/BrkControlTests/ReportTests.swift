import XCTest
@testable import BrkControl

/// verify/swift/REPORT.md's format: header with machine and counts, one line per scenario with PASS / FAIL / SKIPPED,
/// failure and skip reasons, notes, shots, and the grouped "Needs" section.
final class ReportTests: XCTestCase {
    let machine = E2EMachine(date: "2026-10-30T12:00:00Z", macOS: "macOS 26.6 (25G83)", model: "Macmini9,1", engine: "stub",
                             cefVersion: "n/a", display: "locked, backing scale 2", app: ".build/release/Brk")

    func testFormatsPassFailAndSkipped() {
        let results = [
            E2EResult(id: "0", title: "launch smoke", outcome: .pass, seconds: 1.24, screenshots: ["shots/0-launch-smoke.png"], log: "logs/0.log"),
            E2EResult(id: "2", title: "Cmd+T opens the bar", outcome: .fail, seconds: 3.3,
                      message: "the app exited during press(\"cmd+t\"): signal 5 (SIGTRAP)\nsecond line", log: "logs/2.log",
                      needs: ["W1: BrkDomain/CommandBar.swift:15"]),
            E2EResult(id: "R3", title: "Cmd+click", outcome: .skipped, seconds: 0, message: "needs CEF engine (a click on a link in a page)"),
            E2EResult(id: "4", title: "dock switch", outcome: .pass, seconds: 2, notes: ["page titles not checked on the stub engine"]),
            E2EResult(id: "7", title: "archive", outcome: .fail, seconds: 1, message: "x", needs: ["W1: BrkDomain/CommandBar.swift:15"]),
        ]
        let text = E2EReport.markdown(results, machine: machine, totalSeconds: 7.54)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines[0], "# Brk e2e report")
        XCTAssertEqual(lines[2], "2026-10-30T12:00:00Z · macOS 26.6 (25G83) · Macmini9,1 · engine stub (CEF n/a) · display locked, backing scale 2 · "
                       + "5 scenarios in 7.5 s · 2 PASS, 2 FAIL, 1 SKIPPED")
        XCTAssertTrue(lines.contains("- PASS 0 launch smoke · 1.2 s · [0-launch-smoke.png](shots/0-launch-smoke.png) · [log](logs/0.log)"))
        XCTAssertTrue(lines.contains("- FAIL 2 Cmd+T opens the bar · 3.3 s — the app exited during press(\"cmd+t\"): signal 5 (SIGTRAP) second line · [log](logs/2.log)"))
        XCTAssertTrue(lines.contains("- SKIPPED R3 Cmd+click · 0.0 s — needs CEF engine (a click on a link in a page)"))
        XCTAssertTrue(lines.contains("- PASS 4 dock switch · 2.0 s · note: page titles not checked on the stub engine"))
        XCTAssertTrue(lines.contains("## Needs"))
        XCTAssertTrue(lines.contains("- W1: BrkDomain/CommandBar.swift:15 (scenarios 2, 7)"))
    }

    func testNoNeedsSectionWithoutFailures() {
        let text = E2EReport.markdown([E2EResult(id: "0", title: "smoke", outcome: .pass, seconds: 1)], machine: machine, totalSeconds: 1)
        XCTAssertFalse(text.contains("## Needs"))
        XCTAssertTrue(text.contains("1 PASS, 0 FAIL, 0 SKIPPED"))
    }

    func testOwnersFollowTheModuleMap() {
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkDomain/CommandBar.swift"), "W1")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkLayout/SidebarLayout.swift"), "W1")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkCEF/CEFEngine.swift"), "W2")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkApp/AppStore.swift"), "W2")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkApp/ControlExecutor.swift"), "W6")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkSidebar/TablistView.swift"), "W3")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkOverlays/Suggest.swift"), "W4")
        XCTAssertEqual(E2EReport.owner(ofFileID: "BrkTheme/ThemeRenderer.swift"), "W5")
    }
}
