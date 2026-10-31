import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum ExtensionScenarios {
    static let all = [Scenario("Extension-cancel-uninstall", "pending uninstall confirmation cancels with source close and clean quit", cefOnly: "native extension dialog", cancelUninstall), Scenario("Extension-action-probe", "probe extension action invocation without claiming popup acceptance", cefOnly: "extension actions", actionProbe), Scenario("Extension-webui", "Chrome WebUI lists extensions and cancels its native installer on source close", cefOnly: "Chrome WebUI", webUIProbe), Scenario("Extension-install", "selected harmless local extension installs, runs, pins and removes", cefOnly: "CEF extensions", install)]
    static func selectedFixture(_ app: AppUnderTest) throws -> (ItemID, BrowserExtension) {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        // Explicit fixture selection uses the same production command as the NSOpenPanel completion.
        let directory = app.site.root.deletingLastPathComponent().appendingPathComponent("Fixtures/SiteExtension")
        try app.dispatch(.site(.installSelectedExtension(directory)))
        try app.click(.settingsField("confirmExtensionInstall"))
        try app.dispatch(.site(.nativeExtensions))
        var fixture: BrowserExtension?
        try app.waitUntil("native installed-extension readback", timeout: 12) {
            let controls = try SitePolicyScenarios.controls(app)
            if let error = controls.extensionError { throw Check(description: error) }
            fixture = controls.extensions.first { $0.name == "Brk harmless fixture" }
            return fixture != nil
        }
        guard let fixture else { throw Check(description: "fixture extension missing") }
        return (item, fixture)
    }
    static func changeEnabled(_ app: AppUnderTest, manager: ItemID, id: String, on: Bool) throws {
        let literal = String(decoding: try! JSONSerialization.data(withJSONObject: [id]), as: UTF8.self).dropFirst().dropLast()
        try SitePolicyScenarios.evaluate(app, manager, "chrome.management.setEnabled(\(literal),\(on ? "true" : "false"),()=>{const error=chrome.runtime.lastError;document.title=error?'management-error:'+error.message:'management-enabled:\(on)'})")
        try app.waitUntil("extension enable/disable native callback") {
            let title = tab(manager, in: try app.view())?.title ?? ""
            if title.hasPrefix("management-error:") { throw Check(description: title) }
            return title == "management-enabled:\(on)"
        }
    }
    @Sendable static func install(_ app: AppUnderTest) throws {
        let (item, fixture) = try selectedFixture(app)
        try app.dispatch(.site(.pinExtension(fixture.id, true)))
        try expect(try SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id), "native picker pin missing")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item))); try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitUntil("extension content script") {
            try SitePolicyScenarios.evaluate(app, item, "document.title='extension-installed:'+document.documentElement.getAttribute('data-brk-extension')")
            return tab(item, in: try app.view())?.title == "extension-installed:installed"
        }
        try app.dispatch(.site(.extensions))
        guard let manager = currentTab(try app.view())?.id else { throw Check(description: "extension manager missing") }
        try app.waitForPageInput(PageID(window: app.window!, item: manager), at: URL(string: "chrome://extensions/")!)
        try changeEnabled(app, manager: manager, id: fixture.id, on: false)
        try app.dispatch(.tab(.focus(item))); try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitUntil("disabled extension stops its content script") {
            try SitePolicyScenarios.evaluate(app, item, "document.title='extension-disabled:'+document.documentElement.getAttribute('data-brk-extension')")
            return tab(item, in: try app.view())?.title == "extension-disabled:null"
        }
        try app.dispatch(.tab(.focus(manager)))
        try changeEnabled(app, manager: manager, id: fixture.id, on: true)
        try app.dispatch(.tab(.focus(item))); try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.flush(); try app.restart()
        try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("extension and pin survive restart") {
            let value = try SitePolicyScenarios.controls(app)
            return value.extensions.contains { $0.id == fixture.id } && value.pinnedExtensions.contains(fixture.id)
        }
        try app.dispatch(.site(.closeControls))
        try app.dispatch(.profile(.create(name: "Extension Other", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let other = settings.profiles.first(where: { $0.profile.name == "Extension Other" })?.profile.id else { throw Check(description: "extension profile missing") }
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("other profile extension catalog readback") { try SitePolicyScenarios.controls(app).extensionsLoaded == true }
        try expect(try !SitePolicyScenarios.controls(app).extensions.contains { $0.id == fixture.id }, "extension leaked into another profile")
        try expect(try !SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id), "pin leaked into another profile")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.press("cmd+shift+y")
        try waitForTitle(app, item, "extension-command:fixture-command", timeout: 5)
        try app.dispatch(.site(.nativeExtensions))
        app.note("Installed fixture executed its content script, survived restart, retained its native pin, and dispatched Command+Shift+Y.")
        try app.dispatch(.site(.removeExtension(fixture.id)))
        var dialog: Int?
        try app.waitUntil("Chromium's real uninstall confirmation") {
            dialog = try app.native().appWindows.first { $0.className == "NativeWidgetMacNSWindow" && $0.isVisible }?.number
            return dialog != nil
        }
        try app.perform(.nativeDialogKey(number: dialog!, chord: "return"))
        try app.waitUntil("extension removal readback") {
            let value = try SitePolicyScenarios.controls(app)
            if let error = value.extensionError { throw Check(description: error) }
            return !value.extensions.contains { $0.id == fixture.id }
        }
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitUntil("removed content script stays absent") {
            try SitePolicyScenarios.evaluate(app, item, "document.title='extension-installed:'+document.documentElement.getAttribute('data-brk-extension')")
            return tab(item, in: try app.view())?.title == "extension-installed:null"
        }
        app.note("Selected fixture only. Installation, content script, restart, pin persistence, actual command dispatch and removal were observed. Popup invocation has its own acceptance gate.")
    }
}

extension ExtensionScenarios {
    @Sendable static func webUIProbe(_ app: AppUnderTest) throws {
        try app.dispatch(.site(.extensions))
        guard let item = currentTab(try app.view())?.id else { throw Check(description: "manager missing") }
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: URL(string: "chrome://extensions/")!)
        try SitePolicyScenarios.evaluate(app, item, "chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true}).then(xs=>document.title='webui-info:'+xs.length).catch(e=>document.title='webui-error:'+e.message)")
        try app.waitUntil("Chrome's native extension API readback") { try currentTab(app.view())?.title.hasPrefix("webui-info:") == true }
        app.note("getExtensionsInfo readback: " + (currentTab(try app.view())?.title ?? ""))
        try SitePolicyScenarios.evaluate(app, item, "(async()=>{await chrome.developerPrivate.updateProfileConfiguration({inDeveloperMode:true});await chrome.developerPrivate.loadUnpacked({failQuietly:false});document.title='webui-installed'})().catch(e=>document.title='webui-error:'+e.message)")
        try app.waitUntil("Chromium's native folder picker") { try app.native().appWindows.contains { $0.className == "NSOpenPanel" && $0.isVisible } }
        app.note("Chrome's local installer reached a real OS folder picker; selection is a separate manual gate.")
        try app.dispatch(.tab(.close(.focused)))
        return

    }
}

extension ExtensionScenarios {
    @Sendable static func actionProbe(_ app: AppUnderTest) throws {
        let (item, fixture) = try selectedFixture(app)
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.dispatch(.site(.nativeExtensions))
        try app.dispatch(.site(.invokeExtension(fixture.id)))
        app.sleep(0.4)
        let value = try SitePolicyScenarios.controls(app)
        if let error = value.extensionError { throw Skipped(description: "Pinned CEF extension action invocation rejected: " + error) }
        try app.recordWindows("extension-action-invoked")
        throw Skipped(description: "Invocation was submitted; actual popup input, permission UI and lifecycle have not been established")
    }
}

extension ExtensionScenarios {
    @Sendable static func cancelUninstall(_ app: AppUnderTest) throws {
        let (item, fixture) = try selectedFixture(app)
        try app.dispatch(.site(.removeExtension(fixture.id)))
        try app.waitUntil("pending uninstall confirmation") { try app.native().appWindows.contains { $0.className == "NativeWidgetMacNSWindow" && $0.isVisible } }
        try app.dispatch(.tab(.close(.focused)))
        try app.waitUntil("source closure cancels the real uninstall dialog") { try !app.native().appWindows.contains { $0.className == "NativeWidgetMacNSWindow" && $0.isVisible } }
        try app.dispatch(.tab(.focus(item))); try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("cancellation preserves the installed extension") {
            let value = try SitePolicyScenarios.controls(app)
            return value.extensionsLoaded == true && value.extensions.contains { $0.id == fixture.id }
        }
        try app.dispatch(.site(.removeExtension(fixture.id)))
        try app.waitUntil("a second pending uninstall confirmation") { try app.native().appWindows.contains { $0.className == "NativeWidgetMacNSWindow" && $0.isVisible } }
        let outcome = try app.quit()
        try expect(outcome.clean, "pending uninstall prevented clean quit: \(outcome.exit)")
        app.note("The original native confirmation was cancelled by manager closure. A new confirmation was then cancelled by actual ordered app shutdown, without an accepted-operation lease blocking browser closure.")
    }
}
