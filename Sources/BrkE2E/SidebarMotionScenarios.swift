import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Arc's folder open and close under a real mouse (docs/checks/2026-11-13-sidebar-animations.md). The rows move as an
/// offset on top of their final frames, so frames read through the control socket are final at once; what this guards is
/// the real path (the window server's clicks on the folder row) and that nothing of a motion is left behind: rows on
/// their way out gone, rows that came back fully drawn (no clip, no fade), the glyph in the right state, also when the
/// folder is clicked again before a motion ends.
enum SidebarMotionScenarios {
    static let all = [
        Scenario("R57-FolderMotion", "real clicks close and open a pinned folder, also three times within 0.2 s; the rows end in place with their titles drawn, the glyph follows, nothing of the motion stays", cefOnly: "real mouse", folderMotion),
    ]

    private typealias E = SidebarEvidenceScenarios

    private static func frame(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect? {
        guard let view = try app.native().actual[id.identifier], !view.hidden else { return nil }
        return view.frame
    }

    private static func glyph(_ app: AppUnderTest, _ folder: ItemID) throws -> String? {
        let actual = try app.native().actual
        if actual[ViewID.tabTool("folder-glyph-open-" + folder.rawValue).identifier]?.hidden == false { return "open" }
        if actual[ViewID.tabTool("folder-glyph-closed-" + folder.rawValue).identifier]?.hidden == false { return "closed" }
        return nil
    }

    private static func collapsed(_ app: AppUnderTest, _ folder: ItemID) throws -> Bool? {
        E.folder(folder, in: try app.view().space.pinned.rows)?.collapsed
    }

    /// Single clicks at `point` (window content coordinates) `gap` seconds apart, each its own click (click state 1), as
    /// quick hands do: no app reads them as a double-click.
    private static func clicks(_ app: AppUnderTest, at point: CGPoint, count: Int, gap: Double) throws {
        try PhysicalPointer.move(app, to: point, window: app.window!)
        let frame = try app.native(app.window!).windowFrame
        let at = CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
        let source = CGEventSource(stateID: .hidSystemState)
        for n in 0..<count {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left) else { throw Check(description: "mouse event") }
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.post(tap: .cghidEventTap)
                usleep(30_000)
            }
            if n < count - 1 { usleep(UInt32(max(0, gap - 0.06) * 1_000_000)) }
        }
    }

    /// Dark pixels (text) in the title part of a row: the row is drawn, not clipped away or faded out.
    private static func titleInk(_ app: AppUnderTest, _ row: CGRect, _ name: String) throws -> Int {
        let band = CGRect(x: row.minX + 45, y: row.midY - 6, width: min(90, row.width - 60), height: 12)
        let bytes = try SidebarReviewScenarios.pixels(app, name, band)
        var dark = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3 < 120 { dark += 1 }
        return dark
    }

    @Sendable static func folderMotion(_ app: AppUnderTest) throws {
        let a = try E.loadReady(app, "page2.html?folder=a"), b = try E.loadReady(app, "page2.html?folder=b")
        let today = try E.loadReady(app, "page2.html?today=c")
        let folder = try E.newFolder(app, "Box")
        try app.dispatch(.item(.move(a, to: .into(parent: folder, index: 0))))
        try app.dispatch(.item(.move(b, to: .into(parent: folder, index: 1))))
        try app.dispatch(.tab(.focus(today)))
        try app.waitUntil("the folder holds a and b, open") { try collapsed(app, folder) == false && frame(app, .row(b)) != nil }
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real mouse events") }
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let folderRow = try frame(app, .row(folder)).unwrap("the folder row")
        let openToday = try frame(app, .row(today)).unwrap("the Today row")
        let point = CGPoint(x: folderRow.midX, y: folderRow.midY)
        let openGlyph = try glyph(app, folder)
        try expect(openGlyph == "open", "an open folder's glyph is \(String(describing: openGlyph))")

        // One click closes it. The rows on their way out are no rows any more at once; the Today row's frame is final.
        try clicks(app, at: point, count: 1, gap: 0)
        try app.waitUntil("closed", timeout: 2) { try collapsed(app, folder) == true }
        try expect(try frame(app, .row(a)) == nil && frame(app, .row(b)) == nil, "a row on its way out is still reported as a row")
        try expect(try glyph(app, folder) == "closed", "the glyph did not close")
        let closedToday = try frame(app, .row(today)).unwrap("the Today row after closing")
        try expect(abs((openToday.minY - closedToday.minY) - 82) < 0.5, "the Today row's frame moved \(openToday.minY - closedToday.minY), not two rows")
        app.sleep(0.5)
        _ = try app.screenshot("closed")

        // Open, close, open again, each click 0.1 s after the last: every motion is still running when the next starts.
        try clicks(app, at: point, count: 3, gap: 0.1)
        try app.waitUntil("open after three clicks", timeout: 2) { try collapsed(app, folder) == false }
        app.sleep(0.6)
        let endGlyph = try glyph(app, folder)
        try expect(endGlyph == "open", "after three quick clicks the glyph is \(String(describing: endGlyph))")
        let rowA = try frame(app, .row(a)).unwrap("a after reopening"), rowB = try frame(app, .row(b)).unwrap("b after reopening")
        try expect(abs(rowA.minY - (folderRow.maxY + 1)) < 0.5 && abs(rowB.minY - (rowA.maxY + 1)) < 0.5, "the reopened rows sit at \(rowA.minY) and \(rowB.minY)")
        let endToday = try frame(app, .row(today))
        try expect(endToday == openToday, "the Today row ended at \(String(describing: endToday)), not \(openToday)")
        let inkA = try titleInk(app, rowA, "reopened-a"), inkB = try titleInk(app, rowB, "reopened-b")
        try expect(inkA > 20 && inkB > 20, "a reopened row's title is not drawn (dark pixels \(inkA), \(inkB)): a clip or fade stayed")
        app.passed("real clicks close and open the folder; after three quick clicks its rows are back in place and drawn")
    }
}

private extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw Check(description: "no \(what)") }
        return self
    }
}
