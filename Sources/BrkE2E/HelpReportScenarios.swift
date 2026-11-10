import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// Bug reports from inside Brk: Help › Report a Bug… chosen in the real menu bar (through Accessibility, as an
/// accessibility client chooses a menu item) opens GitHub's bug form in a tab with the build filled in; after a crash
/// the next launch asks once, and Report… opens the form with the crash report's lines. The runner gives this
/// scenario its own crash folder (`BRK_CRASH_REPORTS_DIR`), so nothing is written to ~/Library/Logs.
enum HelpReportScenarios {
    static let all: [Scenario] = [
        Scenario("HelpReport", "Help › Report a Bug… opens the prefilled bug form; the launch after a crash offers once to report it", cefOnly: "a page tab for the form", helpReport),
    ]

    /// The crash folder the runner names for this scenario.
    static func crashFolder(_ app: AppUnderTest) -> URL { app.dataDirectory.appendingPathComponent("crash-reports", isDirectory: true) }

    /// The form's fields from a tab's address: the new-issue page itself, or GitHub's sign-in page holding it in
    /// `return_to` (GitHub asks a signed-out visitor to sign in first).
    private static func formFields(_ url: URL?) -> [String: String]? {
        guard var url, url.host == "github.com" else { return nil }
        if url.path == "/login", let back = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "return_to" })?.value,
           let inner = URL(string: back, relativeTo: URL(string: "https://github.com")!)?.absoluteURL { url = inner }
        guard url.path.hasSuffix("/issues/new"), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    private static func waitForForm(_ app: AppUnderTest, _ what: String, except seen: Set<ItemID>) throws -> (ItemID, [String: String]) {
        var found: (ItemID, [String: String])?
        try app.waitUntil(what, timeout: 15) {
            found = allTabs(try app.view()).lazy.filter { !seen.contains($0.id) }.compactMap { tab in formFields(tab.url).map { (tab.id, $0) } }.first
            return found != nil
        }
        return found!
    }

    private static func alertShown(_ app: AppUnderTest) throws -> Bool {
        try app.native().appWindows.contains { $0.isVisible && $0.className.contains("Alert") }
    }

    /// A macOS-style .ips report of this app (header line, then the body), written after the previous launch.
    private static func writeCrashReport(_ app: AppUnderTest) throws {
        let plist = app.executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let info = (NSDictionary(contentsOf: plist) as? [String: Any]) ?? [:]
        let name = info["CFBundleName"] as? String ?? app.productPrefix
        let header = ["app_name": name, "timestamp": "2026-11-10 21:04:19.00 +0800", "app_version": "1.0", "build_version": "1",
                      "bundleID": info["CFBundleIdentifier"] as? String ?? "", "os_version": "macOS 26.1 (25B78)", "name": name]
        let body: [String: Any] = [
            "cpuType": "ARM-64", "faultingThread": 0,
            "exception": ["type": "EXC_BAD_ACCESS", "signal": "SIGSEGV", "subtype": "KERN_INVALID_ADDRESS at 0x0"],
            "termination": ["namespace": "SIGNAL", "indicator": "Segmentation fault: 11"],
            "threads": [["queue": "com.apple.main-thread", "frames": [["imageIndex": 0, "symbol": "HelpReport.fixture()", "symbolLocation": 12]]]],
            "usedImages": [["name": name]],
        ]
        let folder = crashFolder(app)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: header), as: UTF8.self) + "\n"
            + String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        try text.write(to: folder.appendingPathComponent("\(name)-2026-11-10-210419.ips"), atomically: true, encoding: .utf8)
    }

    @Sendable static func helpReport(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Check(description: "the runner may not use Accessibility") }
        guard let pid = app.hello?.pid else { throw Check(description: "app identity missing") }
        // Help: Arc's Contact the Team, then Brk's two rows.
        let titles = try NativeSystemInput.mainMenuTitles(pid: pid, menu: "Help")
        guard let contact = titles.firstIndex(of: "Contact the Team") else { throw Check(description: "no Contact the Team in Help: \(titles)") }
        try expect(Array(titles[contact...].prefix(3)) == ["Contact the Team", "Report a Bug…", "Send Feedback…"], "Help menu order: \(titles)")
        let before = Set(allTabs(try app.view()).map(\.id))
        try NativeSystemInput.chooseMainMenu(pid: pid, menu: "Help", item: "Report a Bug…")
        let (bugTab, bug) = try waitForForm(app, "Report a Bug… opens the bug form in a tab", except: before)
        try expect(bug["template"] == "bug_report.yml", "template: \(bug)")
        try expect(bug["version"]?.hasPrefix("\(app.productPrefix) ") == true && bug["macos"]?.isEmpty == false
                   && bug["mac"]?.isEmpty == false && bug["engine"]?.contains("CEF") == true, "bug form fields: \(bug)")
        try expect(!bug.values.contains { $0.contains(NSHomeDirectory()) }, "the form names the home folder: \(bug)")
        _ = try app.screenshot("report-a-bug")

        // A crash report written after this launch; the next launch asks once.
        try writeCrashReport(app)
        try app.restart()
        try app.waitUntil("the crash offer after a crash", timeout: 10) { try alertShown(app) }
        _ = try app.screenshot("crash-offer")
        guard let relaunched = app.hello?.pid else { throw Check(description: "app identity missing after the restart") }
        try NativeSystemInput.pressButton(pid: relaunched, title: "Report…")
        let (_, crash) = try waitForForm(app, "Report… opens the bug form with the crash report", except: [bugTab])
        try expect(crash["title"] == "Crash: EXC_BAD_ACCESS (SIGSEGV)", "crash title: \(crash["title"] ?? "none")")
        try expect(crash["logs"]?.contains("Crashed thread 0 (com.apple.main-thread):") == true
                   && crash["logs"]?.contains("HelpReport.fixture() + 12") == true, "crash logs: \(crash["logs"] ?? "none")")

        // Offered once: the launch after that asks nothing.
        try app.restart()
        Thread.sleep(forTimeInterval: 3)
        try expect(!(try alertShown(app)), "the crash offer came back on the next launch")
        app.note("Help › Report a Bug… chosen in the menu bar through Accessibility opened GitHub's bug form with version, macOS, Mac and engine; a seeded .ips report after the first launch made the second launch offer it, Report… opened the form with the report's title and frames; the third launch asked nothing.")
    }
}
