import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// R2 to R10: electron-v1:e2e/regression.spec.ts (the interrogate findings) on the control socket.
enum RegressionScenarios {

    /// R3 (CEF): Cmd+click on fixture home's link opens a background Today tab that loads page 2; focus stays home.
    @Sendable static func cmdClickLink(_ app: AppUnderTest) throws {
        guard let home = tabRows(try app.view().space.today.rows).first else { throw Check(description: "no Today tab at launch") }
        try app.settle()
        try waitForTitle(app, home.id, "Fixture Home")
        let card = try visible(try app.native(), .card(0)).frame
        // index.html places its link at (40, 40) in the page; aim inside the text.
        try app.click(at: CGPoint(x: card.minX + 52, y: card.minY + 48), modifiers: "cmd")
        var opened: TabRow?
        try app.waitUntil("a second Today row") {
            let v = try app.view()
            opened = tabRows(v.space.today.rows).first { $0.id != home.id }
            return v.space.today.rows.count == 2 && opened != nil
        }
        try expect(try currentTab(app.view())?.id == home.id, "focus left the opener")
        try app.waitUntil("the background tab to load") { try tab(opened!.id, in: app.view())?.loaded == true }
        try waitForTitle(app, opened!.id, "Fixture Page 2")
    }




    /// R7a (CEF): close.html closes itself: closed without closeRequested (page-initiated), the row leaves Today for the
    /// archive as Cmd+W does (Arc, Q12-c), and every card has a surface or is the placeholder `view()` predicts.
    @Sendable static func pageCloses(_ app: AppUnderTest) throws {
        let t = try openTab(app, app.site.url("close.html"))
        let page = PageID(window: app.window!, item: t.id)
        try app.waitUntil("close.html to close itself", timeout: 8) {
            let entries = try app.pageLog().filter { $0.page == page }
            try expect(entries.contains { $0.kind == .closed }, "no closed entry yet: \(entries.map(\.kind))")
            try expect(!entries.contains { $0.kind == .closeRequested }, "the engine requested the close: \(entries.map(\.kind))")
            return true
        }
        try app.waitUntil("the row to leave Today with another selection", timeout: 8) {
            let view = try app.view()
            return tab(t.id, in: view) == nil && currentTab(view)?.id != t.id
        }
        try expect(try app.pageLog().filter { $0.page == page && $0.kind == .created }.count == 1, "local close immediately recreated the page")
        try app.waitUntil("every card to show what view() predicts", timeout: 8) {
            let v = try app.view(), n = try app.native()
            for (i, pane) in v.content.panes.enumerated() {
                _ = try visible(n, .card(i))
                if case .page(let p) = pane.content {
                    try expect(n.pages[p]?.surfaceFrame != nil, "card \(i) should host \(p) but has no surface")
                }
            }
            return true
        }
    }

    /// R7b (CEF): chrome://crash in the shown page; with no further input the page's Chromium views come back and the
    /// card is the page's white again.
    @Sendable static func rendererCrash(_ app: AppUnderTest) throws {
        try app.settle()
        guard let home = currentTab(try app.view()) else { throw Check(description: "no current tab") }
        try waitForTitle(app, home.id, "Fixture Home")
        let page = PageID(window: app.window!, item: home.id)
        let card = try visible(try app.native(), .card(0)).frame
        try app.crash(page, .renderer)
        try app.waitUntil("the renderer crash to show", timeout: 5) {
            let v = try app.view(), n = try app.native()
            let crashed = v.content.panes.contains { $0.content == .crashed(page) }
            return crashed || (n.pages[page]?.embeddedViews.isEmpty ?? true)
        }
        try app.waitUntil("the page to recover by itself", timeout: 8) {
            let n = try app.native()
            try expect(!(n.pages[page]?.embeddedViews.isEmpty ?? true), "the surface has no Chromium views")
            let mid = try app.pixel(cardProbe(card))
            try expect(distance(mid, white) <= 3, "card pixel \(mid), expected the page's white")
            return true
        }
    }

    /// R8: the window moved to (5000, 4000), saved, restarted: the restored frame overlaps a display by 100 x 100.
    @Sendable static func offscreenWindow(_ app: AppUnderTest) throws {
        let offscreen = CGRect(x: 5000, y: 4000, width: 1000, height: 700)
        try app.setWindowFrame(offscreen)
        try app.waitUntil("the saved bounds to be off screen") {
            let bounds = try app.view().bounds
            try expect(bounds.map { near($0, offscreen) } == true, "saved bounds \(bounds.map { "\($0)" } ?? "nil")")
            return true
        }
        try app.flush()
        app.passed("off-screen bounds saved")
        try app.restart()
        let frame = try app.native().windowFrame
        let screens = Displays.appKitFrames()
        try expect(!screens.isEmpty, "no active display")
        try expect(screens.contains { let o = $0.intersection(frame); return o.width >= 100 && o.height >= 100 },
                   "the restored window \(frame) does not overlap any display \(screens) by 100 x 100")
        try app.screenshot("back-on-screen")
    }

    /// R9: after a space with red.html and a switch back, the window holds exactly the shown panes' surfaces and the
    /// card shows white, not red.
    @Sendable static func onlyCurrentSurface(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        try app.settle()
        try createSpace(app, title: "Work")
        let red = try openTab(app, app.site.url("red.html"))
        try app.checkPage("the title \"Red\"") { try waitForTitle(app, red.id, "Red") }
        try app.click(.dockSpace(first))
        try app.waitUntil("the first space shown") { try app.view().space.id == first }
        app.sleep(0.6)
        let v = try app.view(), n = try app.native()
        let shown = Set(v.content.panes.compactMap { pane -> PageID? in if case .page(let p) = pane.content { p } else { nil } })
        try expect(Set(n.pages.keys) == shown,
                   "attached surfaces \(n.pages.keys.map(\.description).sorted()) differ from the panes view() shows \(shown.map(\.description).sorted())")
        try expect(n.pages[PageID(window: app.window!, item: red.id)] == nil, "red.html's surface is still in the window")
        let mid = try app.pixel(cardProbe(try visible(n, .card(0)).frame))
        try expect(distance(mid, white) <= 3, "card pixel \(mid), expected white (red would mean a detached page is drawn)")
        try app.screenshot("current-space-only")
    }

    /// R10 (CEF): chrome://gpucrash; within 8 s the card is the page's white again and a dock click still switches.
    @Sendable static func gpuCrash(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        let work = try createSpace(app, title: "Work")
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("the first space shown") { try app.view().space.id == first }
        try app.settle()
        guard let home = currentTab(try app.view()) else { throw Check(description: "no current tab") }
        try waitForTitle(app, home.id, "Fixture Home")
        let card = try visible(try app.native(), .card(0)).frame
        try app.crash(PageID(window: app.window!, item: home.id), .gpu)
        app.sleep(1)
        try app.waitUntil("the page to repaint white", timeout: 8) {
            let mid = try app.pixel(cardProbe(card))
            try expect(distance(mid, white) <= 3, "card pixel \(mid)")
            return true
        }
        try app.click(.dockSpace(work))
        try app.waitUntil("a dock click to switch space") { try app.view().space.id == work }
    }
}

/// Active displays in AppKit screen coordinates (bottom-left origin at the main display), from CoreGraphics.
enum Displays {
    static func appKitFrames() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return ids.prefix(Int(count)).map { id in
            let b = CGDisplayBounds(id)
            return CGRect(x: b.minX, y: mainHeight - b.maxY, width: b.width, height: b.height)
        }
    }
}
