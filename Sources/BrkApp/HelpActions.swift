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
/// - Contact the Team: a new issue on the repository the build came from (`BrkRepositoryURL` in Info.plist), its body
///   Copy {app} Info's text. Brk has no team mailbox.
/// - Check for Updates…: Brk has no update feed; an alert names the build and how a newer one is made.
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
        case .contactTeam:
            guard let issue = HelpLinks.newIssue(BuildInfo.current(engine: engine.engineVersion)) else {
                return alert("This build does not name a repository",
                             "Builds made with scripts/build.sh record their git remote; this one has none to write to.", in: window)
            }
            send(window, .app(.help(.open(issue))))
        case .checkForUpdates:
            let info = BuildInfo.current(engine: engine.engineVersion)
            let notes: String? = HelpLinks.releaseNotes() == nil ? nil : "Release Notes"
            alert("\(Product.name) has no update channel", HelpLinks.updateText(info), in: window, second: notes) { [weak self] in
                self?.run(.releaseNotes, owner: window)
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

    /// `<repository>/issues/new` with the build's info as the body; nil without a repository.
    static func newIssue(_ info: BuildInfo) -> URL? {
        guard let repository = info.repository, var parts = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "title", value: ""),
                            URLQueryItem(name: "body", value: "Describe what happened:\n\n\n---\n" + info.text)]
        return parts.url
    }

    static func updateText(_ info: BuildInfo) -> String {
        "This copy is \(info.versionLine)\(info.commit.map { ", commit \($0)" } ?? ""). \(Product.name) is built from its repository and has no update feed, so nothing is downloaded. To get a newer build, pull the repository and run scripts/build.sh."
    }
}

/// What Copy {app} Info puts on the pasteboard (Arc: "Copied Arc Info!"): the build, the engine, the system and
/// where the data is.
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

    var versionLine: String { "\(name) \(version) (\(build))" }

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
                         dataDirectory: Product.dataDirectory().path)
    }
}
