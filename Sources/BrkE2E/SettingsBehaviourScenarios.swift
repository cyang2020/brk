import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// R3-2: the settings that only saved a value now change what the app does. Each scenario turns a switch on and off
/// through the real window or key path and checks the behaviour, not the saved field.
enum SettingsBehaviourScenarios {
    static let all: [Scenario] = [
        Scenario("SettingsQuit", "Warn before quitting: Cmd+Q asks, Cancel keeps the app, don't ask again quits and saves; off quits at once", quitWarning),
        Scenario("SettingsRoutes", "Air Traffic Control sheet: New Route, typed Contains text routes a link from another app; Default decides the rest", airTrafficControl),
        Scenario("SettingsPageDrag", "Allow window dragging from the top of webpages: on, the page-top band moves the window; off, no band and no move", cefOnly: "page surfaces", pageDragging),
        Scenario("SettingsQuotes", "Shared Quotes: on, Copy URL links to the highlighted text; off, the plain address", cefOnly: "renderer selection", sharedQuotes),
        Scenario("SettingsIcon", "Icon pane: a chosen icon is the Dock icon, survives a restart, and Original restores it", appIcon),
    ]

    private static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let s) = try app.send(.settings) else { throw Check(description: "settings did not answer") }
        return s
    }

    private static func alertShown(_ app: AppUnderTest) throws -> Bool {
        try app.native().appWindows.contains { $0.isVisible && $0.className.contains("Alert") }
    }

    /// Waits for the app to exit by itself (no quit request from the runner), then records the outcome.
    private static func waitForOwnExit(_ app: AppUnderTest, _ what: String) throws {
        guard let process = app.process else { throw Check(description: "no process") }
        try expect(process.waitForExit(timeout: 20), "\(what): the app did not exit")
        let outcome = try app.quit()
        try expect(outcome.clean, "\(what): \(outcome.exit)")
    }

    @Sendable static func quitWarning(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.general(.warnBeforeQuitting(true))))
        try app.press("cmd+q")
        try app.waitUntil("the Warn before quitting dialog", timeout: 10) { try alertShown(app) }
        try app.click(.settingsField("quitWarning-cancel"))
        try app.waitUntil("Cancel closes the dialog") { try !alertShown(app) }
        app.sleep(1)
        try expect(app.isRunning, "Cancel quit the app")
        try expect(try settings(app).general.warnBeforeQuitting, "Cancel changed the setting")
        app.passed("on: Cmd+Q asks and Cancel keeps the app running")

        try app.press("cmd+q")
        try app.waitUntil("the dialog again", timeout: 10) { try alertShown(app) }
        try app.click(.settingsField("quitWarning-dontAsk"))
        try app.click(.settingsField("quitWarning-quit"))
        try waitForOwnExit(app, "Quit, and don't ask again")
        try app.launch()
        try expect(try settings(app).general.warnBeforeQuitting == false, "don't ask again was not saved")
        app.passed("Quit, and don't ask again quits through the ordered quit and turns the setting off")

        let shown = uptime()
        try app.press("cmd+q")
        try waitForOwnExit(app, "off")
        try expect(uptime() - shown < 15, "off: the quit waited on something")
        try app.launch()
        app.passed("off: Cmd+Q quits with no dialog")
    }

    @Sendable static func airTrafficControl(_ app: AppUnderTest) throws {
        guard case .dispatched = try app.send(.openSettings(pane: .links)) else { throw Check(description: "openSettings did not dispatch") }
        try app.settle()
        try app.click(.settingsField("airTrafficControl"))
        try app.waitUntil("the sheet's New Route button", timeout: 8) { (try? app.click(.settingsField("route-new"))) != nil }
        try app.waitUntil("New Route adds an empty Contains row") { try settings(app).routes.count == 1 }
        let route = try XCTUnwrap(settings(app).routes.first?.route, "no route")
        try expect(route.pattern.isEmpty && route.match == .contains && route.destination == .mostRecentSpace, "New Route's row: \(route)")
        try app.click(.settingsField("route-\(route.id.rawValue)-pattern"))
        try app.type("page2.html")
        try app.waitUntil("the typed text is the route's") { try settings(app).routes.first?.route.pattern == "page2.html" }
        try app.click(.settingsField("routes-close"))
        try app.waitUntil("× closes the sheet and keeps the filled row") {
            let closed = (try? app.click(.settingsField("route-new"))) == nil
            return try closed && settings(app).routes.count == 1
        }
        app.passed("the sheet adds, fills and keeps a Contains route through its own controls")

        let windowsBefore = try standardAndLittle(app)
        guard case .dispatched = try app.send(.externalURL(url: app.site.url("page2.html?from=other-app"))) else { throw Check(description: "externalURL") }
        try app.waitUntil("the Contains route opens the link as a tab in the most recent space") {
            tabRows(try app.view().space.today.rows).contains { $0.url == app.site.url("page2.html?from=other-app") }
        }
        try expect(try standardAndLittle(app) == windowsBefore, "the routed link opened another window")
        guard case .dispatched = try app.send(.externalURL(url: app.site.url("index.html?from=other-app"))) else { throw Check(description: "externalURL") }
        try app.waitUntil("Default (Little Arc) takes a link no route matches") { try standardAndLittle(app).little == windowsBefore.little + 1 }
        try app.dispatch(.settings(.links(.defaultRoute(.mostRecentSpace))))
        try expect(try settings(app).links.externalLinksInLittleArc == false, "Default: Most Recent Space did not turn the Little Arc switch off")
        app.passed("a link from another app follows the Contains route, else the Default")
    }

    private static func standardAndLittle(_ app: AppUnderTest) throws -> (standard: Int, little: Int) {
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello") }
        var standard = 0, little = 0
        for id in hello.windows {
            guard let kind = try? app.view(id).kind else { continue }
            if kind == .little { little += 1 } else { standard += 1 }
        }
        return (standard, little)
    }

    @Sendable static func pageDragging(_ app: AppUnderTest) throws {
        try app.setWindowFrame(CGRect(x: 200, y: 160, width: 1100, height: 720))
        try app.settle()
        try app.dispatch(.settings(.advanced(.windowDraggingFromPages(true))))
        try app.settle()
        let band = try XCTUnwrap(app.native().actual[ViewID.pageDragStrip(0).identifier]?.frame, "on: no drag band over the page")
        let card = try XCTUnwrap(app.native().computed.cards.first?.rect, "no card")
        try expect(abs(band.minY - card.minY) < 1 && abs(band.height - Metrics.content.pageDragHeight.value) < 1, "band \(band) over card \(card)")
        let before = try app.native().windowFrame
        let from = CGPoint(x: band.midX, y: band.midY)
        try app.perform(.pointerDrag(from: from, to: CGPoint(x: from.x + 60, y: from.y + 30), cancel: false))
        try app.waitUntil("the band dragged the window") { abs(try app.native().windowFrame.minX - before.minX - 60) < 2 }
        let after = try app.native().windowFrame
        try expect(abs(after.minY - (before.minY - 30)) < 2, "the window moved \(after.minY - before.minY) vertically, not -30")
        app.passed("on: dragging the page-top band moves the window with the pointer")

        try app.dispatch(.settings(.advanced(.windowDraggingFromPages(false))))
        try app.settle()
        try expect(try app.native().actual[ViewID.pageDragStrip(0).identifier] == nil, "off: the band is still there")
        try app.perform(.pointerDrag(from: from, to: CGPoint(x: from.x + 60, y: from.y + 30), cancel: false))
        app.sleep(0.5)
        try expect(near(try app.native().windowFrame, after, tolerance: 1), "off: the same drag moved the window")
        app.passed("off: no band; the same drag leaves the window where it is")
    }

    @Sendable static func sharedQuotes(_ app: AppUnderTest) throws {
        let url = app.site.url("index.html")
        let tab = try app.load(url)
        let page = PageID(window: try XCTUnwrap(app.window, "no window"), item: tab)
        try app.waitForPageInput(page, at: url)
        try app.evaluate(page, "const q=document.createElement('p');q.id='quote';q.textContent='quoted words here';document.body.prepend(q);getSelection().selectAllChildren(q)")
        app.sleep(0.3)
        try app.dispatch(.page(.copyURL(.plain)))
        let link = url.absoluteString + "#:~:text=quoted%20words%20here"
        try app.waitUntil("on: Copy URL links to the highlight") { try app.send(.readPasteboard) == .text(link) }
        try app.dispatch(.page(.copyURL(.quote)))
        try app.waitUntil("on: Copy URL as Quote quotes the highlight") { try app.send(.readPasteboard) == .text("> quoted words here\n" + link) }
        app.passed("on: the copies link to the highlighted text")

        try app.dispatch(.settings(.advanced(.sharedQuotes(false))))
        try app.dispatch(.page(.copyURL(.plain)))
        app.sleep(0.8)
        try expect(try app.send(.readPasteboard) == .text(url.absoluteString), "off: Copy URL did not copy the plain address")
        app.passed("off: the same selection copies the plain address")
    }

    @Sendable static func appIcon(_ app: AppUnderTest) throws {
        try expect(try app.native().dockIcon == AppIconChoice.original.rawValue, "the Dock does not show the original icon at launch")
        guard case .dispatched = try app.send(.openSettings(pane: .icon)) else { throw Check(description: "openSettings did not dispatch") }
        try app.settle()
        try app.click(.settingsField("appIcon-neon"))
        try app.waitUntil("Neon is the Dock icon") { try app.native().dockIcon == AppIconChoice.neon.rawValue }
        try expect(try settings(app).general.appIcon == .neon, "the choice was not saved")
        try app.flush()
        try app.restart()
        try app.waitUntil("Neon is the Dock icon after a restart") { try app.native().dockIcon == AppIconChoice.neon.rawValue }
        app.passed("the chosen icon is the Dock icon and survives a restart")
        guard case .dispatched = try app.send(.openSettings(pane: .icon)) else { throw Check(description: "openSettings did not dispatch") }
        try app.settle()
        try app.click(.settingsField("appIcon-original"))
        try app.waitUntil("Original is the Dock icon again") { try app.native().dockIcon == AppIconChoice.original.rawValue }
        app.passed("The Original restores the original icon")
    }
}

private func XCTUnwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw Check(description: message) }
    return value
}
