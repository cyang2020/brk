import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

struct RunnerArguments {
    var app: URL
    var site: URL
    var outputDirectory: URL
    var only: Set<String>?

    init(_ argv: [String]) {
        // TODO(W6): parse --app, --site, --out, --only.
        fatalError("not implemented")
    }
}

/// Serves Tests/E2ESite/ on 127.0.0.1 (python3 -m http.server, started by the runner) plus `/fail`, which drops the
/// connection (a load failure). Pages: index.html "Fixture Home" (a link to page2 at a fixed position for Cmd+click),
/// page2.html "Fixture Page 2", red.html "Red" (full red background), close.html "Closer" (calls window.close()),
/// keys.html (logs keydowns into document.title, optionally preventDefault).
struct FixtureSite {
    let baseURL: URL
    func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }
}

/// One launched app instance and its control connection. Every helper goes through the control socket; nothing
/// reads the app's files or windows directly except `crashReportsSince`.
final class AppUnderTest {
    let dataDirectory: URL
    let client: ControlClient
    let site: FixtureSite
    private(set) var process: Process?

    init(app: URL, dataDirectory: URL, site: FixtureSite) {
        self.dataDirectory = dataDirectory
        self.site = site
        client = ControlClient(path: dataDirectory.appendingPathComponent("control.sock").path)
        // TODO(W6): keep `app` for launch().
        _ = app
    }

    func launch() throws { fatalError("not implemented") }
    /// Quit over the socket, wait for exit (10 s), return the exit status and new crash reports.
    func quit() throws -> (status: Int32, crashReports: [URL]) { fatalError("not implemented") }
    /// quit() then launch() with the same data directory.
    func restart() throws { fatalError("not implemented") }

    func view() throws -> WindowSnapshot { fatalError("not implemented") }
    func native() throws -> NativeFacts { fatalError("not implemented") }
    @discardableResult func dispatch(_ command: Command) throws -> Int { fatalError("not implemented") }
    func press(_ chord: String) throws { fatalError("not implemented") }
    func type(_ text: String) throws { fatalError("not implemented") }
    func click(_ view: ViewID, modifiers: String? = nil) throws { fatalError("not implemented") }
    func click(at point: CGPoint, modifiers: String? = nil) throws { fatalError("not implemented") }
    func pixel(_ point: CGPoint) throws -> [Int] { fatalError("not implemented") }
    @discardableResult func screenshot(_ name: String) throws -> URL { fatalError("not implemented") }
    func advanceClock(hours: Double) throws { fatalError("not implemented") }
    func pageLog() throws -> [PageLogEntry] { fatalError("not implemented") }

    /// Polls `condition` every 100 ms until true or `timeout`; throws with `message` and the last view on timeout.
    func waitUntil(_ message: String, timeout: TimeInterval = 8, _ condition: () throws -> Bool) throws {
        fatalError("not implemented")
    }
}

/// Assertions record a message and stop the scenario.
struct Check: Error { let message: String }

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Check(message: message()) }
}

/// Max channel distance between two RGBA samples (pixel checks tolerate compositing and color-space rounding).
func distance(_ a: [Int], _ b: [Int]) -> Int {
    zip(a.prefix(3), b.prefix(3)).map { abs($0 - $1) }.max() ?? 0
}
