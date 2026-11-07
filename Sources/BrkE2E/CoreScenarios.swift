import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// What only BrkCore does: an extension's action popup opens from the site controls, and the popup is Chromium's own (ledger row A097,
/// verify/visual-pairs/run-20261103/r3-8/EXTENSION-POPUP.md). They skip on CEF, which cannot do it.
enum CoreScenarios {
    static let all = [
        Scenario("Core-popup", "an extension's action popup opens from the site controls; typed text and a click in it reach the page's content script", popupReceipt),
        Scenario("Core-activeTab", "opening the popup grants activeTab on the page it opened on and no other, in a normal window", activeTab),
    ]

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
        guard app.engine == .core else { throw Skipped(description: "needs BrkCore; CEF cannot open an action popup") }
        let source = app.site.url("extension-popup.html")
        let extensionFixture = fixture(app, "verify/completion/batch2-extensions-sites/toolbar/Fixtures/Extension")
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
        let panel = try popupPanel(app)
        try expect(panel?.isKey == true, "the popup's panel is not key: \(String(describing: panel))")
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

    @Sendable static func activeTab(_ app: AppUnderTest) throws {
        guard app.engine == .core else { throw Skipped(description: "needs BrkCore; CEF cannot open an action popup") }
        let other = app.site.url("page2.html")
        let otherItem = try app.load(other)
        try app.waitForPageInput(PageID(window: app.window!, item: otherItem), at: other)
        let target = app.site.url("extension-popup.html")
        let item = try app.load(target)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: target)
        let probe = try install(app, directory: fixture(app, "Tests/Fixtures/ExtensionActiveTab"), name: "Brk activeTab probe")
        try app.dispatch(.site(.closeControls))
        try app.dispatch(.tab(.focus(item)))
        try app.waitForPageInput(page, at: target)
        try app.dispatch(.site(.invokeExtension(probe.id)))
        var title = ""
        try app.waitUntil("the probe's report through its own grant", timeout: 15) {
            title = tab(item, in: try app.view())?.title ?? ""
            return title.hasPrefix("activeTab:")
        }
        let report = try JSONSerialization.jsonObject(with: Data(title.dropFirst("activeTab:".count).utf8)) as? [String: Any] ?? [:]
        try expect(report["activeURL"] as? String == target.absoluteString, "the granted tab's URL: \(report)")
        try expect(report["windowType"] as? String == "normal", "extensions see the window as: \(report)")
        try expect((report["others"] as? [String])?.allSatisfy { $0 == "denied" } == true, "scripting another tab: \(report)")
        try expect((report["otherURLs"] as? [Any])?.allSatisfy { $0 is NSNull } == true, "another tab's URL was readable: \(report)")
        let facts = try app.native().pages[page]
        try expect(report["tabId"] as? Int == facts?.browserID, "the granted tab is another page: \(report)")
        app.note("report \(title)")
    }
}
