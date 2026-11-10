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
    ]

    private static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let s) = try app.send(.settings) else { throw Check(description: "settings did not answer") }
        return s
    }

    /// SwiftUI's sheet window over the settings window.
    private static func sheetShown(_ app: AppUnderTest) throws -> Bool {
        try app.native().appWindows.contains { $0.isVisible && $0.className.contains("SheetPresentation") }
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
        for icon in AppIconChoice.allCases where icon != .original {
            try app.click(.settingsField("appIcon-\(icon.rawValue)"))
            try app.waitUntil("\(icon.rawValue) is the Dock icon") { try app.native().dockIcon == icon.rawValue }
            try expect(try settings(app).general.appIcon == icon, "\(icon.rawValue) was not saved")
        }
        app.passed("all six icon styles render and can be selected")
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
