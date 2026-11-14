import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// Chromium UI hosted in Brk: extension actions and page dialogs.
enum CoreScenarios {
    static let all = [
        Scenario("Core-tools", "developer console, source, task manager and trace work through real keys and menus", tools),
        Scenario("Core-editor", "the web editor supports native spelling and text transformations with undo", editor),
        Scenario("Core-pip", "document picture in picture moves the page into a native window and restores it on close", documentPiP),
        Scenario("Core-popup", "an extension's action popup opens from the site controls; typed text and a click in it reach the page's content script", popupReceipt),
        Scenario("Core-dialogs", "a page's alert, confirm and prompt open as a sheet on its window; Return and Escape answer the page", dialogs),
    ]

    @Sendable static func resources(_ app: AppUnderTest) throws {
        let url = app.site.url("page-real.html")
        let item = try app.load(url)
        let first = app.window!
        let original = PageID(window: first, item: item)
        try app.waitForPageInput(original, at: url)
        let browser = try app.native().pages[original]?.browserID
        try app.evaluate(original, "marker='retained';document.title=marker")
        try waitForTitle(app, item, "retained")
        try app.press("cmd+n")
        var second: WindowID?
        try app.waitUntil("the second window") {
            guard case .hello(let hello) = try app.send(.hello) else { return false }
            second = hello.windows.first { $0 != first }
            return second != nil
        }
        app.window = second
        try app.press("escape")
        try app.click(.row(item))
        let moved = PageID(window: second!, item: item)
        try app.waitForPageInput(moved, at: url)
        try expect(try app.native().pages[moved]?.browserID == browser, "handoff created another Chromium tab")
        try app.evaluate(moved, "document.title=marker")
        try waitForTitle(app, item, "retained")
        try expect(try app.native(first).pages[original] == nil, "the old window still owns a second page")
        try app.screenshot("handoff")

        try SitesSettingsRealScenarios.openDetails(app)
        try SitesSettingsRealScenarios.pressInDetails(app, title: "Suspend this site while its tab is hidden", roles: ["AXCheckBox"])
        try app.press("escape")
        let other = try app.load(app.site.url("page2.html"))
        try app.waitForPageInput(PageID(window: second!, item: other), at: app.site.url("page2.html"))
        try app.waitUntil("the background page frozen by Chromium", timeout: 30) {
            try app.native().ownedPages?[moved]?.resourceFrozen == true
        }
        try app.click(.row(item))
        try app.waitForPageInput(moved, at: url)
        try app.waitUntil("the visible page resumed") { try app.native().pages[moved]?.resourceFrozen == false }
        try app.evaluate(moved, "document.title=marker")
        try waitForTitle(app, item, "retained")

        app.window = first
        try WindowServerKeys.ensureFrontmost(app, first)
        try app.click(.row(item))
        try app.waitForPageInput(original, at: url)
        try expect(try app.native().pages[original]?.browserID == browser, "the return handoff recreated the tab")
        try app.evaluate(original, "document.title=marker")
        try waitForTitle(app, item, "retained")
        app.note("same Chromium tab and JavaScript document survived both handoffs and freeze/resume")
    }

    private static func fixture(_ app: AppUnderTest, _ path: String) -> URL {
        app.site.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(path)
    }

    private static func install(_ app: AppUnderTest, directory: URL, name: String) throws -> BrowserExtension {
        try app.dispatch(.site(.installSelectedExtension(directory)))
        try app.click(.settingsField("confirmExtensionInstall"))
        try app.dispatch(.site(.nativeExtensions))
        var found: BrowserExtension?
        try app.waitUntil("\(name) in the installed list", timeout: 20) {
            let controls = try SitePolicyScenarios.controls(app)
            if let error = controls.extensionError { throw Check(description: error) }
            found = controls.extensions.first { $0.name == name }
            return found != nil
        }
        guard let found else { throw Check(description: "\(name) is missing") }
        try expect(found.supportsNativeAction, "\(name) reports no action")
        return found
    }

    private static func popupPanel(_ app: AppUnderTest) throws -> AppWindowFact? {
        try app.native().appWindows.first { $0.className.contains("ExtensionPopupPanel") && $0.isVisible }
    }

    @Sendable static func popupReceipt(_ app: AppUnderTest) throws {
        let source = app.site.url("extension-popup.html")
        let extensionFixture = fixture(app, "Tests/Fixtures/ExtensionPopup")
        let item = try app.load(source)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: source)
        let action = try install(app, directory: extensionFixture, name: "Brk Action Ownership Probe")
        try app.dispatch(.site(.closeControls))
        try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(page, at: source)
        try app.dispatch(.site(.invokeExtension(action.id)))
        try app.waitUntil("the popup's panel", timeout: 15) { try popupPanel(app) != nil }
        try app.screenshot("popup-open")
        guard let panel = try popupPanel(app) else { throw Check(description: "the popup's panel went away") }
        try expect(panel.isKey, "the popup's panel is not key: \(panel)")
        // The panel is a window of its own; the window screenshot above shows only the browser window.
        app.sleep(0.5)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.number), app.shotsDirectory.appendingPathComponent("Core-popup-panel.png").path]
        try capture.run(); capture.waitUntilExit()
        // The input has autofocus. A real key press, then Tab to the button and Return.
        try app.type("hello")
        try app.press("tab")
        try app.press("return")
        var title = ""
        try app.waitUntil("the receipt in the page's title", timeout: 10) {
            title = tab(item, in: try app.view())?.title ?? ""
            return title.hasPrefix("receipt:")
        }
        let body = Data(title.dropFirst("receipt:".count).utf8)
        let receipt = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        try expect(receipt["text"] as? String == "hello", "typed text in the popup: \(receipt)")
        try expect(receipt["extensionId"] as? String == action.id, "the receipt's extension: \(receipt)")
        try expect((receipt["popupURL"] as? String)?.hasPrefix("chrome-extension://\(action.id)/popup.html") == true, "the popup's URL: \(receipt)")
        let facts = try app.native().pages[page]
        try expect(receipt["tabId"] as? Int == facts?.browserID, "chrome.tabs named another tab: \(receipt), the page is \(String(describing: facts?.browserID))")
        app.note("receipt \(title)")
    }

    @Sendable static func dialogs(_ app: AppUnderTest) throws {
        let url = app.site.url("page2.html")
        let item = try app.load(url)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        func title() throws -> String { tab(item, in: try app.view())?.title ?? "" }
        func sheet() throws -> String? { try app.native().sheetClass }
        try app.evaluate(page, "setTimeout(()=>{alert('Hello from the page');document.title='alert:closed'},0)")
        try app.waitUntil("the alert's sheet on the window") { try sheet() != nil }
        try app.screenshot("alert-sheet")
        try app.press("return")
        try app.waitUntil("the page past its alert") { try title() == "alert:closed" }
        try expect(try sheet() == nil, "the alert's sheet stayed")
        try app.evaluate(page, "setTimeout(()=>{document.title='confirm:'+confirm('Keep going?')},0)")
        try app.waitUntil("the confirm's sheet") { try sheet() != nil }
        try app.press("escape")
        try app.waitUntil("Escape answers Cancel") { try title() == "confirm:false" }
        try app.evaluate(page, "setTimeout(()=>{document.title='prompt:'+prompt('Your name?','Brk')},0)")
        try app.waitUntil("the prompt's sheet") { try sheet() != nil }
        try app.press("return")
        try app.waitUntil("Return answers OK with the default text") { try title() == "prompt:Brk" }
        try app.evaluate(page, "setTimeout(()=>{alert('Gone with the page');document.title='never'},0)")
        try app.waitUntil("a second alert's sheet") { try sheet() != nil }
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitUntil("a navigation takes the open dialog away") { try sheet() == nil }
        try app.waitUntil("the reloaded page") { try title() == "Fixture Page 2" }
    }
}
