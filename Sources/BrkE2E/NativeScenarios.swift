import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// N1 to N4: checks for what the native design adds (key priorities through CEF, focus between native views and
/// pages, pixel layout from one function, the ordered quit).
enum NativeScenarios {
    /// The title keys.html sets for a key it saw: "key:<chord in KeyChord order>:seen" (":swallowed" with ?swallow=1).
    static func keyTitle(_ chord: String, swallowed: Bool = false) -> String {
        "key:\(KeyChord(parsing: chord)!.description):\(swallowed ? "swallowed" : "seen")"
    }

    /// N1 (CEF): app-priority Cmd+T never reaches keys.html; page-priority Cmd+Shift+K reaches it first and then
    /// clears page2 from Today; with ?swallow=1 the first Cmd+S goes to the page and the second within 1 s hides the
    /// sidebar; two quick unconsumed Cmd+R presses reload twice.
    @Sendable static func keyPriorities(_ app: AppUnderTest) throws {
        let page2 = try openTab(app, app.site.url("page2.html"))
        let keys = try openTab(app, app.site.url("keys.html"))
        try waitForTitle(app, keys.id, "keys:loads=1")
        try app.press("cmd+t")
        try app.waitUntil("Cmd+T to open the command bar") { isCommandBar(try app.view().overlay) }
        app.sleep(0.3)
        let afterCmdT = tab(keys.id, in: try app.view())?.title ?? ""
        try expect(!afterCmdT.contains("cmd+t"), "keys.html saw Cmd+T (title \"\(afterCmdT)\")")
        try app.press("escape")
        try app.waitUntil("Esc to close the bar and return focus to keys.html") {
            let v = try app.view(), n = try app.native()
            return v.overlay == nil && n.focusedPage == PageID(keys.id)
        }
        try app.press("cmd+shift+k")
        try waitForTitle(app, keys.id, keyTitle("cmd+shift+k"))
        try app.waitUntil("Cmd+Shift+K to clear page2 from Today") { try !todayIDs(app.view()).contains(page2.id) }

        let swallow = try openTab(app, app.site.url("keys.html?swallow=1"))
        try waitForTitle(app, swallow.id, "keys:loads=1")
        try app.press("cmd+s")
        try waitForTitle(app, swallow.id, keyTitle("cmd+s", swallowed: true))
        try expect(try app.view().sidebar.visible, "the first Cmd+S (swallowed by the page) hid the sidebar")
        try app.press("cmd+s")
        try app.waitUntil("the second Cmd+S within 1 s to hide the sidebar", timeout: 3) { try !app.view().sidebar.visible }

        try app.dispatch(.tab(.focus(keys.id)))
        try app.waitUntil("keys.html current again") { try currentTab(app.view())?.id == keys.id }
        try app.settle()
        try app.press("cmd+r")
        try app.press("cmd+r")
        try waitForTitle(app, keys.id, "keys:loads=3")
    }

    /// N2: Cmd+L focuses the command bar input and "x" goes there, not to the page; Esc returns focus to the page and
    /// "y" reaches it (titles: CEF only); no host window was ever key.
    @Sendable static func focusRoundTrip(_ app: AppUnderTest) throws {
        let keys = try openTab(app, app.site.url("keys.html"))
        try app.settle()
        try app.onCEF("keys.html's load title") { try waitForTitle(app, keys.id, "keys:loads=1") }
        try app.press("cmd+l")
        try app.waitUntil("Cmd+L to focus the command bar input") {
            let v = try app.view(), n = try app.native()
            try expect(isCommandBar(v.overlay), "the command bar is not open")
            try expect(n.firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier), "first responder is \(n.firstResponder)")
            return true
        }
        try app.type("x")
        app.sleep(0.3)
        try app.onCEF("that the page did not get \"x\"") {
            let title = tab(keys.id, in: try app.view())?.title ?? ""
            try expect(!title.contains("key:x"), "keys.html saw the x typed into the bar (title \"\(title)\")")
        }
        try app.press("escape")
        try app.waitUntil("Esc to give the page focus back") {
            let v = try app.view(), n = try app.native()
            try expect(v.overlay == nil, "the command bar is still open")
            try expect(n.focusedPage == PageID(keys.id), "focused page is \(n.focusedPage?.description ?? "none"), first responder \(n.firstResponder)")
            return true
        }
        try app.type("y")
        try app.onCEF("that the page got \"y\"") { try waitForTitle(app, keys.id, keyTitle("y")) }
        _ = try app.native()
        try expect(app.hostKeyViolations.isEmpty, "a CEF host window was key: \(app.hostKeyViolations)")
    }

    /// N3: every layout-owned frame on screen equals `WindowLayout.compute`'s, and the constants hold: traffic lights
    /// at x 13, 14 pt, centred 24 from the top; URL pill 36 tall, 8 from each side, radius 12; dock 50 tall; rows 40
    /// tall on a 41 pitch; favorite tiles at least 47 with gap 8.
    @Sendable static func pixelLayout(_ app: AppUnderTest) throws {
        var n = try app.native()
        let v = try app.view()
        let w = Metrics.window, width = v.sidebar.width
        let lights = ["window-close-button", "window-minimize-button", "window-zoom-button"]
        for (i, key) in lights.enumerated() {
            guard let light = n.actual[key], !light.hidden else { throw Check(description: "\(key) is not on screen") }
            let x = w.trafficLightLeft.value + Double(i) * (w.trafficLightSize.value + w.trafficLightSpacing.value)
            try expect(light.frame.minX == x, "\(key) x \(light.frame.minX), expected \(x)")
            try expect(light.frame.width == w.trafficLightSize.value, "\(key) width \(light.frame.width), expected \(w.trafficLightSize.value)")
            try expect(light.frame.midY == w.trafficLightCenterY.value, "\(key) centre y \(light.frame.midY), expected \(w.trafficLightCenterY.value)")
        }
        let pill = try visible(n, .urlPill)
        let p = Metrics.urlPill
        try expect(pill.frame.height == p.height.value, "url-pill height \(pill.frame.height), expected \(p.height.value)")
        try expect(pill.frame.minX == p.sideInset.value && pill.frame.maxX == width - p.sideInset.value,
                   "url-pill spans \(pill.frame.minX)...\(pill.frame.maxX), expected \(p.sideInset.value)...\(width - p.sideInset.value)")
        try expect(pill.cornerRadius == p.cornerRadius.value, "url-pill radius \(pill.cornerRadius), expected \(p.cornerRadius.value)")
        let dock = try visible(n, .dock)
        try expect(dock.frame.height == Metrics.dock.height.value, "dock height \(dock.frame.height), expected \(Metrics.dock.height.value)")
        try computedEqualsActual(n)
        app.passed("traffic lights, URL pill, dock and every computed frame at launch")

        // Rows and favorites need more than a fresh profile has: two more Today tabs, then two of them as favorites.
        let more = [try app.load(app.site.url("page2.html")), try app.load(app.site.url("red.html"))]
        try app.waitUntil("three Today rows") { try app.view().space.today.rows.count == 3 }
        n = try app.native()
        let t = Metrics.tablist
        let rows = try app.view().space.today.rows.map { try visible(n, .row($0.id)).frame }.sorted { $0.minY < $1.minY }
        for row in rows { try expect(row.height == t.rowHeight.value, "a row is \(row.height) tall, expected \(t.rowHeight.value)") }
        for (a, b) in zip(rows, rows.dropFirst()) {
            try expect(b.minY - a.minY == t.rowHeight.value + t.rowSpacing.value,
                       "row pitch \(b.minY - a.minY), expected \(t.rowHeight.value + t.rowSpacing.value)")
        }
        try computedEqualsActual(n)
        app.passed("rows 40 on a 41 pitch")

        let favorites = try app.view().favorites.root
        for (i, id) in more.enumerated() { try app.dispatch(.item(.move(id, to: .into(parent: favorites, index: i)))) }
        try app.waitUntil("two favorites") { try app.view().favorites.tiles.count == 2 }
        n = try app.native()
        let f = Metrics.favorites
        let tiles = try more.map { try visible(n, .favorite($0)).frame }.sorted { $0.minX < $1.minX }
        for tile in tiles {
            try expect(tile.width >= f.minTile.value && tile.height >= f.minTile.value, "a favorite tile is \(tile.size), expected at least \(f.minTile.value)")
        }
        try expect(tiles[1].minX - tiles[0].maxX == f.gap.value, "favorites gap \(tiles[1].minX - tiles[0].maxX), expected \(f.gap.value)")
        try computedEqualsActual(n)
        try app.screenshot("layout")
    }

    /// Every view whose frame layout owns (`WindowFrames.frame(of:)`) is on screen at exactly that frame.
    static func computedEqualsActual(_ n: NativeFacts) throws {
        let f = n.computed
        var ids: [ViewID] = [.sidebar, .floatingSidebar, .titleRow, .urlPill, .favoritesTray, .todayNewTab, .dock, .dockLibrary, .dockPlus,
                             .resizeHandle, .revealStrip, .commandBar, .archive]
        if let s = f.sidebar {
            ids += s.favoriteTiles.keys.sorted().map { ViewID.favorite($0) }
            ids += s.rows.compactMap { if case .item(let id) = $0.kind { ViewID.row(id) } else { nil } }
            ids += s.dockSpaces.keys.sorted().map { ViewID.dockSpace($0) }
        }
        ids += f.cards.indices.map { ViewID.card($0) } + f.dividers.indices.map { ViewID.divider($0) }
        var problems: [String] = []
        for id in ids {
            guard let computed = f.frame(of: id) else { continue }
            guard let actual = n.actual[id.identifier] else { problems.append("\(id.identifier) missing (computed \(computed))"); continue }
            if actual.hidden { problems.append("\(id.identifier) hidden (computed \(computed))") }
            if !near(actual.frame, computed) { problems.append("\(id.identifier) at \(actual.frame), computed \(computed)") }
        }
        try expect(problems.isEmpty, "computed and actual frames differ: \(problems.joined(separator: "; "))")
    }

    /// N4: three tabs and a split, then quit: exit status 0 within 10 s, no crash report, and the final page log has
    /// a closed entry for every created page (the CEF shutdown order; on the stub only the mechanism runs).
    @Sendable static func cleanQuit(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html"))
        _ = try app.load(app.site.url("red.html"))
        try app.press("ctrl+shift+=")
        try app.waitUntil("the split's command bar") { isCommandBar(try app.view().overlay) }
        try app.type(app.site.url("index.html?pane").absoluteString)   // not an open tab's URL
        try app.press("return")
        try app.waitUntil("two cards") { isShown(try app.native(), .card(1)) }
        try app.settle()
        let created = Set(try app.pageLog().filter { $0.kind == .created }.map { "\($0.page)#\($0.generation)" })
        try expect(created.count >= 4, "pageLog has \(created.count) created pages, expected at least 4")
        app.passed("three tabs and a split")
        let started = uptime()
        let outcome = try app.quit()
        try expect(outcome.clean, "quit: \(outcome.exit)")
        try expect(uptime() - started <= 10, "the quit took \(uptime() - started) s")
        try expect(outcome.crashReports.isEmpty, "crash reports: \(outcome.crashReports)")
        guard let final = outcome.finalPageLog else { throw Check(description: "no final page log in the data directory after quit") }
        let closed = Set(final.filter { $0.kind == .closed }.map { "\($0.page)#\($0.generation)" })
        let unclosed = created.subtracting(closed)
        try expect(unclosed.isEmpty, "pages never closed (no OnBeforeClose): \(unclosed.sorted())")
        try app.requireCEF("the ordered CEF shutdown")
    }
}
