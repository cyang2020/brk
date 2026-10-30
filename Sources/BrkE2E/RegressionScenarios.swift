import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// R2 to R10: electron-v1:e2e/regression.spec.ts (the interrogate findings) on the control socket.
enum RegressionScenarios {
    /// R2: sidebar hidden, archive open, the pointer at the reveal strip: the sidebar peeks, the archive stays, and the
    /// floating sidebar draws above the archive.
    @Sendable static func peekKeepsArchive(_ app: AppUnderTest) throws {
        try app.press("cmd+s")
        try app.waitUntil("Cmd+S to hide the sidebar") { try !app.view().sidebar.visible }
        try app.dispatch(.archive(.open))
        try app.waitUntil("the archive page to open") { isArchive(try app.view().overlay) }
        let v = try app.view(), n = try app.native()
        // Points where the floating sidebar (Metrics.sidebar.floatingInset from the window, the sidebar's width) will
        // overlap the archive page; sampled now, with only the archive there.
        let floatingX = Metrics.sidebar.floatingInset.value + v.sidebar.width / 2
        let probes = [60.0, n.contentSize.height / 2, n.contentSize.height - 30].map { CGPoint(x: floatingX, y: $0) }
        let archiveOnly = try probes.map { try app.pixel($0) }
        guard let strip = n.computed.revealStrip else { throw Check(description: "computed.revealStrip is nil with the sidebar hidden") }
        try app.hover(CGPoint(x: max(strip.minX, 0) + 2, y: n.contentSize.height / 2))
        try app.waitUntil("the hover to peek the sidebar") { try app.view().sidebar.peek }
        try expect(isArchive(try app.view().overlay), "peeking closed the archive")
        try app.waitUntil("floating-sidebar on screen above the archive") {
            let n = try app.native()
            _ = try visible(n, .floatingSidebar)
            _ = try visible(n, .archive)
            let now = try probes.map { try app.pixel($0) }
            let changed = zip(archiveOnly, now).contains { distance($0, $1) > 24 }
            try expect(changed, "pixels at \(probes) are still the archive's (\(now)): the floating sidebar is not above it")
            return true
        }
        try app.screenshot("peek")
    }

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

    /// R5a: B shown from the start, 11 h later Ctrl+Tab leaves it; an hour and a minute later B is still in Today.
    @Sendable static func ctrlTabStamps(_ app: AppUnderTest) throws {
        let b = try openTab(app, app.site.url("page2.html"))
        try app.onCEF("B's title") { try waitForTitle(app, b.id, "Fixture Page 2") }
        try app.advanceClock(seconds: 11 * hour)
        try app.hold("ctrl", "tab", times: 1)
        try app.waitUntil("Ctrl+Tab to leave B") { try currentTab(app.view())?.id != b.id }
        try app.advanceClock(seconds: hour + 60)
        app.sleep(0.2)
        try expect(todayIDs(try app.view()).contains(b.id), "B was archived an hour after Ctrl+Tab left it")
    }

    /// R5b: a tab on screen for 13 h, then dropped on another space's dock icon, survives the next sweep there.
    @Sendable static func moveStamps(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        let work = try createSpace(app, title: "Work")
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("the first space again") { try app.view().space.id == first }
        guard let x = try app.view().space.today.rows.first?.id else { throw Check(description: "no Today row in the first space") }
        try app.advanceClock(seconds: 13 * hour)
        try app.dispatch(.item(.move(x, to: .space(work))))
        try app.waitUntil("x to leave the first space") { try !todayIDs(app.view()).contains(x) }
        try app.advanceClock(seconds: 60)
        try app.dispatch(.space(.focus(work)))
        try app.waitUntil("Work shown") { try app.view().space.id == work }
        try expect(todayIDs(try app.view()).contains(x), "x was archived by the sweep after the move")
    }

    /// R6: B, pin and unpin it, then C; one Ctrl+Tab hold goes to B, the next returns to C.
    @Sendable static func ctrlTabTwice(_ app: AppUnderTest) throws {
        let b = try openTab(app, app.site.url("page2.html"))
        try app.press("cmd+d")
        try app.waitUntil("B pinned") { try app.view().space.pinned.rows.count == 1 }
        try app.press("cmd+d")
        try app.waitUntil("B unpinned") { try app.view().space.pinned.rows.isEmpty }
        let c = try openTab(app, app.site.url("index.html?c"))   // not the launch tab's URL: Return would switch to it
        try app.hold("ctrl", "tab", times: 1)
        try app.waitUntil("the first hold to show B") { try currentTab(app.view())?.id == b.id }
        try app.hold("ctrl", "tab", times: 1)
        try app.waitUntil("the second hold to return to C") { try currentTab(app.view())?.id == c.id }
    }

    /// R7a (CEF): close.html closes itself: closed without closeRequested (page-initiated), the row goes, and every
    /// card has a surface or is the placeholder `view()` predicts.
    @Sendable static func pageCloses(_ app: AppUnderTest) throws {
        let t = try openTab(app, app.site.url("close.html"))
        let page = PageID(t.id)
        try app.waitUntil("close.html to close itself", timeout: 8) {
            let entries = try app.pageLog().filter { $0.page == page }
            try expect(entries.contains { $0.kind == .closed }, "no closed entry yet: \(entries.map(\.kind))")
            try expect(!entries.contains { $0.kind == .closeRequested }, "the engine requested the close: \(entries.map(\.kind))")
            return true
        }
        try app.waitUntil("the row to leave Today", timeout: 8) { try !todayIDs(app.view()).contains(t.id) }
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
        let page = PageID(home.id)
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
        try app.onCEF("the title \"Red\"") { try waitForTitle(app, red.id, "Red") }
        try app.click(.dockSpace(first))
        try app.waitUntil("the first space shown") { try app.view().space.id == first }
        app.sleep(0.6)
        let v = try app.view(), n = try app.native()
        let shown = Set(v.content.panes.compactMap { pane -> PageID? in if case .page(let p) = pane.content { p } else { nil } })
        try expect(Set(n.pages.keys) == shown,
                   "attached surfaces \(n.pages.keys.map(\.description).sorted()) differ from the panes view() shows \(shown.map(\.description).sorted())")
        try expect(n.pages[PageID(red.id)] == nil, "red.html's surface is still in the window")
        let mid = try app.pixel(cardProbe(try visible(n, .card(0)).frame))
        try expect(distance(mid, white) <= 3, "card pixel \(mid), expected white (red would mean a detached page is drawn)")
        if app.engine == .stub { app.note("every stub page is white, so the white-not-red pixel cannot fail on the stub") }
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
        try app.crash(PageID(home.id), .gpu)
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
