import AppKit
import BrkDomain
import XCTest
@testable import BrkApp

/// Help › Report a Bug… and Send Feedback… (and Arc's Contact the Team) open GitHub's issue forms filled from the build;
/// the launch after a crash offers the newest report of this app.
@MainActor
final class ReportIssueTests: XCTestCase {
    private let info = BuildInfo(name: "Brk", version: "1.0", build: "7", commit: "1a2b3c4d", repository: URL(string: "https://github.com/cyang2020/brk"),
                                 engine: "154.0.7795.0", system: "Version 26.1 (Build 25B78)", architecture: "arm64",
                                 dataDirectory: "/Users/someone/Library/Application Support/Brk", engineKind: "cef")

    private func fields(_ url: URL) throws -> [String: String] {
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary((parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    /// The forms' field ids carry the build, macOS, chip and engine; the data folder (the user's home path) never goes.
    /// Contact the Team opens the feedback form, and both new rows sit right under it in the Help menu.
    func testTheFormsAreFilledFromTheBuildWithoutTheHomeFolder() throws {
        let bug = try XCTUnwrap(HelpLinks.newIssue(.bug, info))
        XCTAssertEqual(bug.path, "/cyang2020/brk/issues/new")
        XCTAssertEqual(try fields(bug), ["template": "bug_report.yml", "version": "Brk 1.0 (7), commit 1a2b3c4d",
                                         "macos": "Version 26.1 (Build 25B78)", "mac": "Apple silicon (arm64)",
                                         "engine": "Chromium 154.0.7795.0 (CEF)"])
        XCTAssertFalse(bug.absoluteString.contains("someone"))
        let feedback = try XCTUnwrap(HelpLinks.newIssue(.feedback, info))
        XCTAssertEqual(try fields(feedback), ["template": "feature_request.yml", "version": "Brk 1.0 (7), commit 1a2b3c4d"])
        var intel = info
        intel.architecture = "x86_64"; intel.translated = true
        XCTAssertEqual(intel.chip, "Apple silicon, Intel build under Rosetta (x86_64)")
        var unnamed = info
        unnamed.repository = nil
        XCTAssertNil(HelpLinks.newIssue(.bug, unnamed))

        XCTAssertEqual(ActionID.contactTheTeam.spec.command, .app(.help(.sendFeedback)))
        let help = try XCTUnwrap(MainMenu.build(target: MenuTarget()).items.first { $0.title == "Help" }?.submenu).items.map(\.title)
        let contact = try XCTUnwrap(help.firstIndex(of: "Contact the Team"))
        XCTAssertEqual(Array(help[contact...].prefix(4)), ["Contact the Team", "Report a Bug…", "Send Feedback…", "Visit Help Center"])
    }

    /// A crash report's "symbol + 12" keeps its plus sign (GitHub reads a bare "+" as a space), and a long report loses
    /// lines from its end until the address fits.
    func testCrashLogsKeepPlusSignsAndFitTheAddressLimit() throws {
        let logs = (0..<400).map { "  \($0)  Brk  someFunction + \($0 * 4)" }.joined(separator: "\n")
        let url = try XCTUnwrap(HelpLinks.newIssue(.bug, info, title: "Crash: EXC_BAD_ACCESS (SIGSEGV)", logs: logs))
        XCTAssertLessThanOrEqual(url.absoluteString.count, HelpLinks.issueURLLimit)
        let sent = try XCTUnwrap(try fields(url)["logs"])
        XCTAssertTrue(sent.hasPrefix("  0  Brk  someFunction + 0\n  1  Brk  someFunction + 4"), sent)
        XCTAssertTrue(logs.hasPrefix(sent) && sent.count < logs.count)
        XCTAssertEqual(try fields(url)["title"], "Crash: EXC_BAD_ACCESS (SIGSEGV)")
    }

    /// The offer reads only this app's reports (not its helpers', not another bundle's) written since the last launch,
    /// newest first, and summarises the .ips header, exception and crashed thread with the home folder as ~.
    func testTheCrashOfferTakesThisAppsNewestReportSinceTheLastLaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("crash-offer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(CrashReportOffer.recordLaunch(dataDirectory: folder), "a first launch offers nothing")
        let earlier = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: earlier], ofItemAtPath: folder.appendingPathComponent(CrashReportOffer.markerName).path)
        let since = try XCTUnwrap(CrashReportOffer.recordLaunch(dataDirectory: folder))
        XCTAssertEqual(since.timeIntervalSince1970, earlier.timeIntervalSince1970, accuracy: 1, "the second launch reads the first one's date")
        let marked = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(CrashReportOffer.markerName).path)[.modificationDate] as? Date)
        XCTAssertGreaterThan(marked, since.addingTimeInterval(3000), "and stamps the marker with this launch")

        func ips(_ name: String, bundle: String, signal: String, age: TimeInterval) throws {
            let header = #"{"app_name":"Brk","timestamp":"2026-11-10 21:04:19.00 +0800","app_version":"1.0","build_version":"7","bundleID":"\#(bundle)","os_version":"macOS 26.1 (25B78)","name":"Brk"}"#
            let body = #"""
            {"cpuType":"ARM-64","exception":{"type":"EXC_BAD_ACCESS","signal":"\#(signal)","subtype":"KERN_INVALID_ADDRESS at 0x0"},
             "termination":{"namespace":"SIGNAL","indicator":"Segmentation fault: 11"},"faultingThread":0,
             "threads":[{"queue":"com.apple.main-thread","frames":[{"imageIndex":0,"symbol":"Sidebar.render()","symbolLocation":12},{"imageIndex":1,"imageOffset":4096}]}],
             "usedImages":[{"name":"Brk","path":"\#(NSHomeDirectory())/Applications/Brk.app/Contents/MacOS/Brk"},{"path":"/usr/lib/system/libdyld.dylib"}]}
            """#
            let file = folder.appendingPathComponent(name)
            try (header + "\n" + body).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: since.addingTimeInterval(age)], ofItemAtPath: file.path)
        }
        try ips("Brk-2026-11-10-100000.ips", bundle: "dev.brk.Brk", signal: "SIGBUS", age: -60)
        try ips("Brk-2026-11-10-210419.ips", bundle: "dev.brk.Brk", signal: "SIGSEGV", age: 30)
        try ips("Brk Helper (Renderer)-2026-11-10-210500.ips", bundle: "dev.brk.Brk.helper.renderer", signal: "SIGILL", age: 60)
        try ips("Brk-2026-11-10-210600.ips", bundle: "dev.other.Brk", signal: "SIGTRAP", age: 90)

        let report = try XCTUnwrap(CrashReportOffer.latest(in: folder, since: since, name: "Brk", bundleID: "dev.brk.Brk"))
        XCTAssertEqual(report.file.lastPathComponent, "Brk-2026-11-10-210419.ips")
        XCTAssertEqual(report.title, "Crash: EXC_BAD_ACCESS (SIGSEGV)")
        XCTAssertEqual(report.summary, """
        Crash report: Brk-2026-11-10-210419.ips
        Time: 2026-11-10 21:04:19.00 +0800
        App: Brk 1.0 (7)
        macOS: macOS 26.1 (25B78)
        CPU: ARM-64
        Exception: EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x0
        Termination: SIGNAL, Segmentation fault: 11
        Crashed thread 0 (com.apple.main-thread):
          0  Brk  Sidebar.render() + 12
          1  libdyld.dylib  offset 4096
        """)
        XCTAssertNil(CrashReportOffer.latest(in: folder, since: since.addingTimeInterval(120), name: "Brk", bundleID: "dev.brk.Brk"))
    }
}
