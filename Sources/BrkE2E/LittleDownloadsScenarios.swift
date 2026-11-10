import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Owner: W3. Little Arc's download pills (Arc's `LittleBrowserDownloadsTrayViewController`;
/// docs/arc-anatomy/little-arc-downloads.md) with real downloads started by real clicks in a real Little Arc window:
/// the pill's place and size, the file's real name (never the staging name), progress then the kind, a second pill
/// beside the first, no Chromium download card, the × under the real pointer.
enum LittleDownloadsScenarios {
    static let all = [
        Scenario("LittleDownloads-Pill", "real clicks on download links in a Little Arc window show Arc's pills at its bottom left with the real file names, progress then the kind; no Chromium card; the real × removes a pill", cefOnly: "real downloads and window-server pointer", pill),
    ]

    private static func pill(_ index: Int) -> ViewID { .tabTool("little-download-\(index)") }
    private static func close(_ index: Int) -> ViewID { .tabTool("little-download-close-\(index)") }

    private static func littleWindow(_ app: AppUnderTest) throws -> WindowID? {
        guard case .hello(let hello) = try app.send(.hello) else { return nil }
        return hello.windows.first { (try? app.view($0))?.kind == .little }
    }

    /// `point` in the window's content coordinates (top-left origin) on the screen.
    private static func screen(_ app: AppUnderTest, _ window: WindowID, _ point: CGPoint) throws -> CGPoint {
        let frame = try app.native(window).windowFrame
        return CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
    }

    /// The real pointer moved to `point` (window coordinates), only while Brk's window is in front there.
    private static func move(_ app: AppUnderTest, _ window: WindowID, to point: CGPoint) throws {
        let at = try screen(app, window, point)
        try WindowServerKeys.ensureFrontmost(app, window)
        guard case .hello(let hello) = try app.send(.hello), let front = PhysicalPointer.frontmost(at: at), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(at); real pointer not moved")
        }
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// The texts accessibility reads inside a pill, top to bottom (its title and subtitle).
    private static func texts(_ app: AppUnderTest, _ window: WindowID, in frame: CGRect) throws -> [String] {
        let origin = try screen(app, window, frame.origin)
        let area = CGRect(origin: origin, size: frame.size)
        return NativeSystemInput.staticTexts(pid: app.hello!.pid)
            .filter { area.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .sorted { $0.frame.minY < $1.frame.minY }.map(\.text)
    }

    private static func rows(_ app: AppUnderTest, _ window: WindowID) throws -> [DownloadRow] { try app.view(window).littleDownloads }

    @Sendable static func pill(_ app: AppUnderTest) throws {
        let folder = app.dataDirectory.appendingPathComponent("little-downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(folder.path))))
        try app.dispatch(.window(.newLittle(app.site.url("little-downloads.html"))))
        try app.waitUntil("a Little Arc window", timeout: 8) { try littleWindow(app) != nil }
        let little = try littleWindow(app)!
        try app.waitUntil("its page", timeout: 10) { try app.native(little).pages.values.contains { ($0.surfaceFrame?.height ?? 0) > 100 } }
        try app.settle()
        app.sleep(1.0)
        let n = try app.native(little)
        guard let surface = n.pages.values.compactMap(\.surfaceFrame).first(where: { $0.height > 100 }) else { throw Check(description: "no page in the Little Arc window") }
        let height = n.contentSize.height
        let slowLink = CGPoint(x: surface.minX + 140, y: surface.minY + 80), fastLink = CGPoint(x: surface.minX + 380, y: surface.minY + 80)
        let away = CGPoint(x: surface.minX + 700, y: surface.minY + 300)

        // A real click on a slow download: its pill at the bottom left, the real name, a ring and received/total.
        try PhysicalPointer.click(app, at: try screen(app, little, slowLink), window: little)
        try app.waitUntil("the slow download receiving in a pill", timeout: 10) {
            try rows(app, little).first.map { $0.state == .inProgress && $0.received > 0 } ?? false
        }
        try move(app, little, to: away)
        app.sleep(0.6)
        let first = try visible(app.native(little), pill(0)).frame
        try expect(near(first, CGRect(x: 20, y: height - 76, width: 250, height: 56)), "the pill at \(first), Arc's place (20, \(height - 76), 250 x 56)")
        let running = try texts(app, little, in: first)
        try expect(running.first == "little-slow.bin", "the running pill reads \(running), not the file's name")
        try expect(running.count == 2 && running[1].contains("/") && running[1].contains("MB"), "the running pill's subtitle is not received/total: \(running)")
        try app.screenshot("LD-running", window: little)
        app.passed("a real click on a download link in Little Arc shows a 250 x 56 pill 20 from the bottom left with the file's real name and \(running.last ?? "")")

        try app.waitUntil("the slow download finished", timeout: 15) { try rows(app, little).first?.state == .finished }
        let before = Set(try app.native(little).appWindows.filter(\.isVisible).map(\.number))
        try PhysicalPointer.click(app, at: try screen(app, little, fastLink), window: little)
        try app.waitUntil("a second pill, finished", timeout: 10) { try rows(app, little).count == 2 && rows(app, little)[1].state == .finished }
        try move(app, little, to: away)
        // Chromium's own download card used to show 1.75 s after a download ("payload · 900 B · Done"); Arc shows none.
        app.sleep(2.5)
        let facts = try app.native(little)
        let extra = facts.appWindows.filter { $0.isVisible && !before.contains($0.number) && $0.isPageHost != true }
        try expect(extra.isEmpty, "new windows after the download finished: \(extra.map { "\($0.number) \($0.className)" })")
        let second = try visible(facts, pill(1)).frame
        try expect(abs(second.minX - 280) < 0.5 && abs(second.minY - first.minY) < 0.5, "the second pill at \(second), Arc's 260 to the right of the first")
        let slowTexts = try texts(app, little, in: first), fastTexts = try texts(app, little, in: second)
        try expect(slowTexts == ["little-slow.bin", "Archive"] && fastTexts == ["notes.txt", "Download"],
                   "finished pills read \(slowTexts) and \(fastTexts) (Arc: the name over its kind)")
        try app.screenshot("LD-two", window: little)
        app.passed("a finished pill shows the file's kind (Archive, Download); a second download's pill stands 10 to the right; no Chromium card appears")

        // The real pointer on the first pill shows its ×; a real click on it removes the pill and keeps the file.
        try move(app, little, to: CGPoint(x: first.midX, y: first.midY))
        try app.waitUntil("the × on the hovered pill", timeout: 3) { isShown(try app.native(little), close(0)) }
        try expect(!isShown(try app.native(little), close(1)), "the other pill shows its × too")
        try app.screenshot("LD-hover", window: little)
        let x = try visible(app.native(little), close(0)).frame
        try PhysicalPointer.click(app, at: try screen(app, little, CGPoint(x: x.midX, y: x.midY)), window: little)
        try app.waitUntil("the first pill gone", timeout: 4) { try rows(app, little).map(\.filename) == ["notes.txt"] }
        try move(app, little, to: away)
        app.sleep(0.4)
        try expect(abs(try visible(app.native(little), pill(0)).frame.minX - 20) < 0.5, "the remaining pill did not move to the first place")
        try expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("little-slow.bin").path), "the × removed the downloaded file")
        app.passed("the real pointer shows the pill's ×; its real click removes that pill, the file stays and the next pill takes its place")
        _ = try? dispatch(app, window: little, .window(.close))
    }
}
