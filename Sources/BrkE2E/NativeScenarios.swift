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
    /// `KeyChord` knows only the shortcut keys; a plain typed character ("y") is its own name.
    static func keyTitle(_ chord: String, swallowed: Bool = false) -> String {
        "key:\(KeyChord(parsing: chord)?.description ?? chord.lowercased()):\(swallowed ? "swallowed" : "seen")"
    }

    /// N1 (CEF): app-priority Cmd+T never reaches keys.html; page-priority Cmd+Shift+K reaches it first and then
    /// clears page2 from Today; with ?swallow=1 the first Cmd+S goes to the page and the second within 1 s hides the
    /// sidebar; two unconsumed Cmd+R presses each complete a reload.
    @Sendable static func keyPriorities(_ app: AppUnderTest) throws {
        let page2 = try openTab(app, app.site.url("page2.html"))
        let keys = try openTab(app, app.site.url("keys.html"))
        try waitForTitle(app, keys.id, "keys:loads=1")
        try app.waitForPageInput(PageID(window: app.window!, item: keys.id), at: app.site.url("keys.html"))
        try app.press("cmd+t")
        try app.waitUntil("Cmd+T to open the command bar") { isCommandBar(try app.view().overlay) }
        app.sleep(0.3)
        let afterCmdT = tab(keys.id, in: try app.view())?.title ?? ""
        try expect(!afterCmdT.contains("cmd+t"), "keys.html saw Cmd+T (title \"\(afterCmdT)\")")
        try app.press("escape")
        try app.waitUntil("Esc to close the bar and return focus to keys.html") {
            let v = try app.view(), n = try app.native()
            return v.overlay == nil && n.focusedPage == PageID(window: app.window!, item: keys.id)
        }
        try app.press("cmd+shift+k")
        try waitForTitle(app, keys.id, keyTitle("cmd+shift+k"))
        try app.waitUntil("Cmd+Shift+K to clear page2 from Today") { try !todayIDs(app.view()).contains(page2.id) }

        let swallow = try openTab(app, app.site.url("keys.html?swallow=1"))
        try waitForTitle(app, swallow.id, "keys:loads=1")
        try app.waitForPageInput(PageID(window: app.window!, item: swallow.id), at: app.site.url("keys.html?swallow=1"))
        try app.press("cmd+s")
        try waitForTitle(app, swallow.id, keyTitle("cmd+s", swallowed: true))
        try expect(try app.view().sidebar.visible, "the first Cmd+S (swallowed by the page) hid the sidebar")
        try app.recordWindows("swallow-delivered")
        try app.press("cmd+s")
        try app.waitUntil("the second Cmd+S within 1 s to hide the sidebar", timeout: 3) { try !app.view().sidebar.visible }

        try app.dispatch(.tab(.focus(keys.id)))
        try app.waitUntil("keys.html current again") { try currentTab(app.view())?.id == keys.id }
        try app.settle()
        try app.press("cmd+r")
        // A second reload before the first commits can replace it. The fixture counts completed documents.
        try waitForTitle(app, keys.id, "keys:loads=2")
        try app.press("cmd+r")
        try waitForTitle(app, keys.id, "keys:loads=3")
        try app.verifyStablePageFocus("after-reloads")
        try app.recordWindows("after-reloads")
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
            try expect(n.focusedPage == PageID(window: app.window!, item: keys.id), "focused page is \(n.focusedPage?.description ?? "none"), first responder \(n.firstResponder)")
            return true
        }
        try app.type("y")
        try app.onCEF("that the page got \"y\"") { try waitForTitle(app, keys.id, keyTitle("y")) }
        _ = try app.native()
        try expect(app.hostKeyViolations.isEmpty, "a CEF host window was key: \(app.hostKeyViolations)")
    }

    /// N3R: the window buttons stay at Arc's spots under the pointer and through resizes. AppKit lays the titlebar out
    /// again the moment the pointer goes over the buttons and puts them back at the system's spots (x 9, centre y 16),
    /// so the colored buttons came up beside the grey circles and the circles' own spots took no click (the user's
    /// report, 26b91660a8:verify/visual-pairs/run-20261103/Q16). The pointer here is the real one, moved through the window server.
    @Sendable static func lightsStayUnderThePointer(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed, let owner = app.window else { throw Check(description: "window-server input unavailable") }
        let w = Metrics.window, lights = ["window-close-button", "window-minimize-button", "window-zoom-button"]
        let pitch = w.trafficLightSize.value + w.trafficLightSpacing.value
        func spots() throws -> [String] {
            let n = try app.native()
            return lights.map { key in n.actual[key].map { $0.hidden ? "hidden" : "x \($0.frame.minX) centre y \($0.frame.midY)" } ?? "missing" }
        }
        let expected = lights.indices.map { "x \(w.trafficLightLeft.value + Double($0) * pitch) centre y \(w.trafficLightCenterY.value)" }
        func check(_ label: String) throws {
            app.sleep(0.5)
            let now = try spots()
            try expect(now == expected, "\(label): the window buttons are at \(now), Arc's spots are \(expected)")
        }
        /// The real pointer, moved in from outside so AppKit sees it enter the buttons.
        func pointer(toWindowPoint point: CGPoint) throws {
            try WindowServerKeys.ensureFrontmost(app, owner)
            let frame = try app.native().windowFrame
            let origin = CGPoint(x: frame.minX, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY)
            let target = CGPoint(x: origin.x + point.x, y: origin.y + point.y)
            guard case .hello(let hello) = try app.send(.hello), PhysicalPointer.frontmost(at: target)?.pid == hello.pid else {
                throw Check(description: "another window is in front of Brk at \(target); the pointer was not moved")
            }
            let source = CGEventSource(stateID: .hidSystemState)
            for step in [CGPoint(x: target.x + 90, y: target.y + 60), CGPoint(x: target.x + 30, y: target.y + 20), CGPoint(x: target.x + 3, y: target.y + 2), target] {
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: step, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(120_000)
            }
        }
        try check("at launch")
        let centreY = w.trafficLightCenterY.value, half = w.trafficLightSize.value / 2
        for (i, name) in ["close", "minimize", "zoom"].enumerated() {
            try pointer(toWindowPoint: CGPoint(x: w.trafficLightLeft.value + Double(i) * pitch + half, y: centreY))
            try check("the pointer over \(name)")
        }
        try app.screenshot("lights-under-the-pointer")
        try pointer(toWindowPoint: CGPoint(x: 400, y: 300))
        try check("the pointer away again")
        let start = try app.native().windowFrame
        try app.setWindowFrame(CGRect(origin: start.origin, size: CGSize(width: 900, height: 600)))
        try check("after a resize to 900x600")
        try pointer(toWindowPoint: CGPoint(x: w.trafficLightLeft.value + half, y: centreY))
        try check("the pointer over close after the resize")
        try pointer(toWindowPoint: CGPoint(x: 400, y: 300))
        try app.setWindowFrame(start)
        try check("back at the first size")
        app.passed("the window buttons stay at Arc's spots under the pointer and through two resizes")
    }



    /// N4: three tabs and a split, then quit: exit status 0 within 10 s, no crash report, and the final page log has
    /// a closed entry for every created page (the CEF shutdown order; on the stub only the mechanism runs).
    @Sendable static func cleanQuit(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html"))
        let redURL = app.site.url("red.html")
        let red = try app.load(redURL)
        try app.waitForPageInput(PageID(window: app.window!, item: red), at: redURL)
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
