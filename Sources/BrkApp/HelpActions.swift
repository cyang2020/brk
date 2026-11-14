import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import Foundation

/// Check for Updates… and the Help menu (`AppEffect.help`). Pages open as new tabs through `.app(.help(.open))`;
/// alerts attach to the window the row came from.
///
/// - Release Notes: `Help/release-notes.html` in the bundle, written by `scripts/declare-scripting.sh` from the
///   build's git history.
/// - Visit Help Center: Arc's help center, as the command bar's Help Center row.
/// - Report a Bug… and Send Feedback… (Contact the Team is the second): GitHub's issue forms on the repository the
///   build came from (`BrkRepositoryURL` in Info.plist), opened in a tab with the build, macOS, the Mac's chip and the
///   engine filled in (`HelpLinks.newIssue`). Nothing is sent; the user reads, edits and submits the form. Brk has no
///   team mailbox.
/// - After a crash, the next launch offers once to report it (`offerCrashReport`), the report's first lines filled in.
/// - Check for Updates…: Brk does not update itself; an alert names the build and where the newest one is (the
///   repository's Latest build release, its DMGs rebuilt after every change), with a button that opens it.
/// - Restore Data, Record and Cancel Trace, Open Task Manager: their windows and recorder below.
@MainActor
final class HelpActions {
    private let engine: any WebEngine
    private let send: @MainActor (WindowID, Command) -> Void
    private let owner: @MainActor (WindowID) -> NSWindow?
    let trace: TraceRecorder
    private var taskManager: TaskManagerWindow?
    private var restore: RestoreDataWindow?
    /// Called with the chosen backup when the user confirms Restore Data (Lifecycle quits, installs it, relaunches).
    var restoreConfirmed: (@MainActor (URL) -> Void)?
    /// Where Copy {app} Info writes (tests give a private pasteboard).
    var pasteboard = NSPasteboard.general

    private let now: () -> Instant

    init(engine: any WebEngine, now: @escaping () -> Instant, send: @escaping @MainActor (WindowID, Command) -> Void,
         owner: @escaping @MainActor (WindowID) -> NSWindow?) {
        self.engine = engine
        self.now = now
        self.send = send
        self.owner = owner
        trace = TraceRecorder(engine: engine, directory: Product.dataDirectory().appendingPathComponent("Traces", isDirectory: true), now: now)
    }

    func run(_ action: HelpAction, owner window: WindowID) {
        switch action {
        case .open: break
        case .copyInfo:
            pasteboard.clearContents()
            pasteboard.setString(BuildInfo.current(engine: engine.engineVersion).text, forType: .string)
        case .helpCenter: send(window, .app(.help(.open(HelpLinks.helpCenter))))
        case .releaseNotes:
            guard let notes = HelpLinks.releaseNotes() else {
                return alert("Release notes are not bundled with this build",
                             "Only builds made with scripts/build.sh carry Help/release-notes.html.", in: window)
            }
            send(window, .app(.help(.open(notes))))
        case .reportBug: openIssue(.bug, in: window)
        case .sendFeedback: openIssue(.feedback, in: window)
        case .checkForUpdates, .installUpdate:
            let info = BuildInfo.current(engine: engine.engineVersion)
            if let latest = HelpLinks.latestBuild(info) {
                alert("\(Product.name) has no update channel", HelpLinks.updateText(info), in: window, second: "Open Latest Build") { [weak self] in
                    self?.send(window, .app(.help(.open(latest))))
                }
            } else {
                let notes: String? = HelpLinks.releaseNotes() == nil ? nil : "Release Notes"
                alert("\(Product.name) has no update channel", HelpLinks.updateText(info), in: window, second: notes) { [weak self] in
                    self?.run(.releaseNotes, owner: window)
                }
            }
        case .trace:
            trace.toggle { [weak self] message in self?.alert("Trace", message, in: window) }
        case .cancelTrace: trace.cancel()
        case .taskManager:
            let manager = taskManager ?? TaskManagerWindow(engine: engine)
            taskManager = manager
            manager.show()
        case .restoreData:
            let panel = restore ?? RestoreDataWindow(backups: StateBackups(directory: Product.dataDirectory()), now: now)
            restore = panel
            panel.confirmed = { [weak self] url in self?.restoreConfirmed?(url) }
            panel.show()
        }
    }

    private func openIssue(_ form: IssueForm, title: String = "", logs: String? = nil, in window: WindowID) {
        guard let issue = HelpLinks.newIssue(form, BuildInfo.current(engine: engine.engineVersion), title: title, logs: logs) else {
            return alert("This build does not name a repository",
                         "Builds made with scripts/build.sh record their git remote; this one has none to write to.", in: window)
        }
        send(window, .app(.help(.open(issue))))
    }

    /// The launch after a crash: one alert on `window` naming the report. Report… opens the bug form with the report's
    /// first lines in its Logs field; "Don't offer again" turns the offer off (`CrashReportOffer.enabledKey`).
    func offerCrashReport(_ report: CrashReport, in window: WindowID) {
        let alert = NSAlert()
        alert.messageText = "\(Product.name) quit unexpectedly last time"
        alert.informativeText = "Report it on GitHub? A new tab opens the bug report form with the crash report's first lines filled in. Nothing is sent until you submit the form, and you can edit or remove anything first."
        alert.addButton(withTitle: "Report…")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't offer again"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self, weak alert] response in
            MainActor.assumeIsolated {
                if alert?.suppressionButton?.state == .on { UserDefaults.standard.set(false, forKey: CrashReportOffer.enabledKey) }
                guard response == .alertFirstButtonReturn else { return }
                self?.openIssue(.bug, title: report.title, logs: report.summary, in: window)
            }
        }
        if let host = owner(window), host.isVisible, host.attachedSheet == nil { alert.beginSheetModal(for: host, completionHandler: finish) }
        else { finish(alert.runModal()) }
    }

    private func alert(_ title: String, _ text: String, in window: WindowID, second: String? = nil, then: (@MainActor () -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        if let second { alert.addButton(withTitle: second) }
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertSecondButtonReturn, let then else { return }
            MainActor.assumeIsolated { then() }
        }
        if let host = owner(window), host.isVisible, host.attachedSheet == nil { alert.beginSheetModal(for: host, completionHandler: finish) }
        else { finish(alert.runModal()) }
    }
}

/// The addresses the Help rows open. Pure, so the tests read the same values the menu uses.
enum HelpLinks {
    static let helpCenter = URL(string: "https://resources.arc.net/hc/en-us")!

    static func releaseNotes(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "release-notes", withExtension: "html", subdirectory: "Help")
    }

    /// About's "other open source software": the licences of what Brk ships besides Chromium,
    /// written into the bundle by scripts/declare-scripting.sh.
    static func credits(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "credits", withExtension: "html", subdirectory: "Help")
    }

    /// GitHub keeps prefilled addresses working up to about 8,000 characters; the Logs field is cut to stay under this.
    static let issueURLLimit = 6_000

    /// `<repository>/issues/new?template=<form>` with the form's fields filled from the build (GitHub fills an issue
    /// form's fields from query parameters named by the fields' ids). The data folder is left out: its path names the
    /// user's home folder. `logs` (the bug form's Logs field) loses lines from its end until the address fits
    /// `issueURLLimit`. Nil without a repository.
    static func newIssue(_ form: IssueForm, _ info: BuildInfo, title: String = "", logs: String? = nil) -> URL? {
        guard let repository = info.repository,
              var parts = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false) else { return nil }
        var fields = [("template", form.rawValue)]
        if !title.isEmpty { fields.append(("title", title)) }
        fields.append(("version", info.versionLine + (info.commit.map { ", commit \($0)" } ?? "")))
        if form == .bug {
            fields += [("macos", info.system), ("mac", info.chip), ("engine", info.engineLine)]
        }
        func url(logs: String?) -> URL? {
            parts.queryItems = (fields + (logs.map { [("logs", $0)] } ?? [])).map { URLQueryItem(name: $0.0, value: $0.1) }
            // URLComponents leaves "+" as it is, and GitHub reads a "+" in a query as a space ("symbol + 12" in a crash).
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return parts.url
        }
        guard form == .bug, var lines = logs?.components(separatedBy: "\n") else { return url(logs: nil) }
        while let full = url(logs: lines.joined(separator: "\n")), full.absoluteString.count > issueURLLimit, !lines.isEmpty {
            lines.removeLast()
        }
        return url(logs: lines.isEmpty ? nil : lines.joined(separator: "\n"))
    }

    /// The repository's Latest build release (README, docs/release.md): signed DMGs rebuilt from main after every change.
    /// Nil for a build that names no repository.
    static func latestBuild(_ info: BuildInfo) -> URL? {
        info.repository?.appendingPathComponent("releases/tag/latest")
    }

    static func updateText(_ info: BuildInfo) -> String {
        let copy = "This copy is \(info.versionLine)\(info.commit.map { ", commit \($0)" } ?? ""). \(Product.name) does not update itself, so nothing is downloaded."
        guard latestBuild(info) != nil else {
            return copy + " This build names no repository; to get a newer one, pull the repository and run scripts/build.sh."
        }
        return copy + " The newest build is on the repository's Latest build release, rebuilt after every change: download the DMG for your Mac and replace this copy in Applications."
    }
}

/// The issue forms in the repository's `.github/ISSUE_TEMPLATE/`. The query parameters `HelpLinks.newIssue` writes are
/// those forms' field ids (`version`, `macos`, `mac`, `engine`, `logs`); renaming a field there breaks the prefill.
enum IssueForm: String {
    case bug = "bug_report.yml"
    case feedback = "feature_request.yml"
}

/// What Copy {app} Info puts on the pasteboard (Arc: "Copied Arc Info!"): the build, the engine, the system and
/// where the data is. The issue forms take the same facts except the data folder.
struct BuildInfo: Equatable {
    var name: String
    var version: String
    var build: String
    var commit: String?
    var repository: URL?
    var engine: String?
    var system: String
    var architecture: String
    var dataDirectory: String
    /// An Intel build running under Rosetta on an Apple silicon Mac.
    var translated = false

    var versionLine: String { "\(name) \(version) (\(build))" }

    /// The Mac as the bug form asks for it: Apple silicon or Intel, and the build's architecture.
    var chip: String {
        if architecture == "arm64" { return "Apple silicon (arm64)" }
        return translated ? "Apple silicon, Intel build under Rosetta (x86_64)" : "Intel (x86_64)"
    }

    /// The engine as the bug form asks for it: Chromium's version in BrkCore, Brk's own build of it.
    var engineLine: String {
        engine.map { "Chromium \($0) (BrkCore)" } ?? "BrkCore"
    }

    var text: String {
        var lines = [versionLine]
        if let commit { lines.append("Commit: \(commit)") }
        if let engine { lines.append("Chromium Engine: \(engine)") }
        lines.append("macOS: \(system)")
        lines.append("Architecture: \(architecture)")
        lines.append("Data: \(dataDirectory)")
        return lines.joined(separator: "\n")
    }

    static func current(engine: String?, bundle: Bundle = .main) -> BuildInfo {
        let info = bundle.infoDictionary ?? [:]
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return BuildInfo(name: Product.name, version: info["CFBundleShortVersionString"] as? String ?? "1.0",
                         build: info["CFBundleVersion"] as? String ?? "1", commit: info["BrkGitCommit"] as? String,
                         repository: (info["BrkRepositoryURL"] as? String).flatMap(URL.init(string:)), engine: engine,
                         system: ProcessInfo.processInfo.operatingSystemVersionString, architecture: architecture,
                         dataDirectory: Product.dataDirectory().path, translated: runsUnderRosetta)
    }

    private static var runsUnderRosetta: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }
}
