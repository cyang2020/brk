import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class SitePolicyTests: XCTestCase {
    func readyDriver() -> Driver {
        let d = Driver()
        let page = d.snapshot.pages[0].id
        let browser = d.state.session.live[page]!.browser!
        d.page(page.item, .documentChanged(.loading(DocumentToken(browser: browser, sequence: 1))))
        d.page(page.item, .documentChanged(.ready(DocumentToken(browser: browser, sequence: 1))))
        return d
    }

    func testRuleUpdatesValidateAtTheBoundaryAndPersistWithoutApplyingAnInvalidFile() throws {
        let d = readyDriver()
        let data = Data(#"{"version":2,"blockedHosts":["TRACKER.EXAMPLE"],"blockedPathPrefixes":["/track/"],"cosmeticSelectors":[".sponsor"]}"#.utf8)
        let update = StateCodec.decodeWebsiteRules(data)
        guard case .loaded(let rules) = update else { return XCTFail("valid rules refused") }
        XCTAssertEqual(rules.blockedHosts, ["tracker.example"])
        XCTAssertEqual(d.user(.site(.loadBlockingRules)).effects, [.chooseWebsiteRules(d.window, .profile(.default))])
        XCTAssertEqual(d.user(.site(.selectedBlockingRules(URL(fileURLWithPath: "/tmp/rules.json"), .profile(.default)))).effects, [.loadWebsiteRules(URL(fileURLWithPath: "/tmp/rules.json"), .profile(.default))])
        d.system(.websiteRulesLoaded(.profile(.default), update))
        XCTAssertEqual(Driver(file: d.savedFile).state.doc.sitePreferences[.default]?.blockingRules, rules)
        let bad = StateCodec.decodeWebsiteRules(Data("{}".utf8))
        d.system(.websiteRulesLoaded(.profile(.default), bad))
        XCTAssertEqual(d.state.doc.sitePreferences[.default]?.blockingRules, rules)
        XCTAssertNotNil(d.state.session.sites.rulesErrors[.profile(.default)])
        d.user(.site(.resetBlockingRules))
        XCTAssertNil(d.state.doc.sitePreferences[.default]?.blockingRules)
    }

    func testOriginCanonicalizationIsExactAndRejectsNonWebSchemes() throws {
        XCTAssertEqual(SiteOrigin(url("HTTPS://Example.COM:443/path?q=1#x"))?.value, "https://example.com")
        XCTAssertNotEqual(SiteOrigin(url("https://sub.example.com")), SiteOrigin(url("https://example.com")))
        XCTAssertNotEqual(SiteOrigin(url("https://example.com:444")), SiteOrigin(url("https://example.com")))
        XCTAssertNil(SiteOrigin(url("file:///tmp/example")))
        XCTAssertThrowsError(try JSONDecoder().decode(SiteOrigin.self, from: Data("\"https://example.com/path\"".utf8)))
    }

    func testProfilePolicyPersistsAndOldV3DefaultsWithoutChangingTheFormat() throws {
        let d = readyDriver()
        d.user(.site(.appearance(.dark)))
        d.user(.site(.controls))
        let target = try XCTUnwrap(d.state.siteTarget(in: d.window))
        var rule = SiteRule(); rule.blocking = false; rule.keepAlive = true; rule.permissions[.notifications] = .deny
        d.user(.site(.rule(target, rule)))
        let saved = StateCodec.encode(d.state)
        let restored = Driver(file: saved)
        XCTAssertEqual(restored.snapshot.pages.first?.websitePolicy.appearance, .dark)
        XCTAssertEqual(restored.state.doc.sitePreferences[.default]?.rule(for: target.origin), rule)
        var file = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var doc = try XCTUnwrap(file["doc"] as? [String: Any]); doc.removeValue(forKey: "sitePreferences"); file["doc"] = doc
        let old = Driver(file: try JSONSerialization.data(withJSONObject: file))
        XCTAssertEqual(old.state.doc.sitePreferences, [:])
        XCTAssertEqual(StateCodec.currentVersion, 3)
    }

    func testClearRequiresConfirmationAndReloadsOnlyTheOriginalDocument() throws {
        let d = readyDriver()
        let first = d.user(.site(.clear(kinds: [.cookies, .history], scope: .site, reload: true)))
        guard case .confirmSiteData(let request)? = first.effects.first else { return XCTFail("missing preflight") }
        XCTAssertFalse(first.effects.contains(.clearSiteData(request)))
        let confirmed = d.user(.site(.confirmClear(request.id, true)))
        XCTAssertTrue(confirmed.effects.contains(.clearSiteData(request)))
        XCTAssertEqual(d.user(.site(.cancelClearing)).effects, [.cancelSiteData(request.id)])
        XCTAssertNotNil(d.state.session.sites.running[request.id], "Cancellation must wait for a real terminal result")
        let done = d.system(.siteDataCleared(ClearSiteDataResult(request: request, completed: request.kinds, error: nil)))
        XCTAssertTrue(done.effects.contains(.page(request.target.page, .reload(ignoringCache: false))))
        XCTAssertTrue(d.system(.siteDataCleared(ClearSiteDataResult(request: request, completed: request.kinds, error: nil))).effects.isEmpty)
        XCTAssertNotNil(d.state.doc.profiles[.default])
    }

    func testNavigationAndProfileReplacementFenceClearRepliesAndSettings() throws {
        let d = readyDriver()
        let first = d.user(.site(.clear(kinds: [.cache], scope: .profile, reload: true)))
        guard case .confirmSiteData(let request)? = first.effects.first else { return XCTFail("missing preflight") }
        d.user(.site(.confirmClear(request.id, true)))
        d.page(request.target.page.item, .documentChanged(.loading(DocumentToken(browser: request.target.document.browser, sequence: 999))))
        var rule = SiteRule(); rule.blocking = false
        d.user(.site(.rule(request.target, rule)))
        XCTAssertTrue(d.state.doc.sitePreferences.isEmpty)
        let done = d.system(.siteDataCleared(ClearSiteDataResult(request: request, completed: [.cache], error: nil)))
        XCTAssertFalse(done.effects.contains(.page(request.target.page, .reload(ignoringCache: true))))
    }

    func testPrivateThemeNeverExposesThePublicSpaceColorOrContrast() throws {
        let d = readyDriver()
        d.user(.space(.update(d.view.space.id, title: nil, icon: nil, theme: SpaceTheme(colors: [RGBA(1, 0, 0)], texture: .grain, intensity: 0.2, appearance: .light))))
        d.user(.settings(.advanced(.themeToCSS(true))))
        d.user(.window(.newIncognito))
        let w = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://private.example")), in: w)
        let privatePage = try XCTUnwrap(d.snapshot.pages.first { $0.id.window == w })
        XCTAssertEqual(privatePage.websitePolicy.themeCSS["--brk-space-color"], "rgb(51, 51, 51)")
        XCTAssertEqual(privatePage.websitePolicy.themeCSS["--brk-space-text"], "white")
    }

    func testPrivatePolicyAndOperationMetadataNeverEnterSavedDoc() throws {
        let d = readyDriver()
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.site(.appearance(.light)), in: privateWindow)
        XCTAssertFalse(d.state.session.sites.privatePreferences.isEmpty)
        let text = String(decoding: StateCodec.encode(d.state), as: UTF8.self)
        XCTAssertFalse(text.contains("privatePreferences"))
        XCTAssertFalse(text.contains("confirmations"))
        XCTAssertTrue(d.state.doc.sitePreferences.isEmpty)
    }

    func testSelectedExtensionNeedsNativeConfirmationAndKeepsItsOriginalProfile() throws {
        let d = readyDriver()
        let directory = URL(fileURLWithPath: "/tmp/fixture")
        XCTAssertEqual(d.user(.site(.installSelectedExtension(directory))).effects, [.confirmLocalExtension(d.window, .profile(.default), directory)])
        let transition = d.user(.site(.executeExtensionInstall(directory, .profile(.default))))
        XCTAssertTrue(transition.effects.contains(.installLocalExtension(PageID(window: d.window, item: try XCTUnwrap(d.current?.id)), .profile(.default), directory)))
        XCTAssertEqual(d.current?.url?.absoluteString, "chrome://extensions/")
    }

    func testExtensionAndPanelCommandsRespectPrivateScopeAndCloseState() throws {
        let d = readyDriver()
        d.user(.site(.controls)); XCTAssertNotNil(d.snapshot.sites[d.window])
        d.user(.site(.closeControls)); XCTAssertNil(d.snapshot.sites[d.window])
        d.user(.site(.controls))
        let add = d.user(.site(.addExtension))
        XCTAssertEqual(d.current?.url?.absoluteString, "https://chromewebstore.google.com/category/extensions")
        XCTAssertFalse(add.effects.contains(.addLocalExtension(d.window, .profile(.default))))
        XCTAssertNil(d.snapshot.sites[d.window])
        d.user(.site(.extensions)); XCTAssertEqual(d.current?.url?.scheme, "chrome")
        d.user(.site(.extensionShortcuts)); XCTAssertTrue(d.current?.url?.absoluteString.contains("shortcuts") == true)
        d.user(.window(.newIncognito))
        let w = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        XCTAssertEqual(d.user(.site(.addExtension), in: w).effects, [.app(.beep)])
        d.user(.window(.close), in: w)
        XCTAssertTrue(d.state.session.sites.privatePreferences.isEmpty)
    }

    func testExtensionOptionsRequireATrustedEventAndAnEnabledOwningCatalog() throws {
        let d = readyDriver()
        let source = try XCTUnwrap(d.current?.id)
        let id = String(repeating: "a", count: 32)
        let options = url("chrome-extension://\(id)/options.html")
        let extension_ = BrowserExtension(id: id, name: "Options probe", version: "1", enabled: true)
        d.system(.extensionsRead(ExtensionCatalog(context: .profile(.default), extensions: [extension_], error: nil)))
        d.page(source, .openRequested(options, .foregroundTab))
        XCTAssertEqual(d.current?.id, source, "A webpage cannot gain the trusted options route")
        d.page(source, .extensionOptionsRequested(id: id, url: url("chrome-extension://other/options.html")))
        XCTAssertEqual(d.current?.id, source)
        d.page(source, .extensionOptionsRequested(id: id, url: options))
        XCTAssertEqual(d.current?.url, options)
        let settings = try XCTUnwrap(d.current?.id)
        d.page(settings, .committed(options))
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.current?.id, settings, "Restart must preserve the settings tab and selection")
        XCTAssertEqual(restored.current?.url, options)
        d.user(.tab(.focus(source)))
        let manager = url("chrome://extensions/?options=\(id)")
        d.page(source, .extensionOptionsRequested(id: id, url: manager))
        XCTAssertEqual(d.current?.url, manager, "Embedded options use Chromium's extensions manager")
        d.user(.tab(.focus(source)))
        d.system(.extensionsRead(ExtensionCatalog(context: .profile(.default), extensions: [], error: nil)))
        d.page(source, .extensionOptionsRequested(id: id, url: options))
        XCTAssertEqual(d.current?.id, source, "An uninstalled extension cannot open a privileged page")
    }

    func testExtensionOptionsUsePendingAndCurrentWindowAddresses() throws {
        let d = readyDriver()
        let source = try XCTUnwrap(d.current?.id)
        let id = String(repeating: "a", count: 32)
        let options = url("chrome-extension://\(id)/options.html")
        d.system(.extensionsRead(ExtensionCatalog(context: .profile(.default), extensions: [
            BrowserExtension(id: id, name: "Options probe", version: "1", enabled: true)
        ], error: nil)))
        d.page(source, .extensionOptionsRequested(id: id, url: options))
        let first = try XCTUnwrap(d.current?.id)
        d.page(source, .extensionOptionsRequested(id: id, url: options))
        XCTAssertEqual(d.current?.id, first, "A request before the first commit must select the pending tab")
        d.page(first, .committed(options))
        d.user(.page(.navigate(.focused, url("https://away.example/"))))
        d.page(source, .extensionOptionsRequested(id: id, url: options))
        XCTAssertNotEqual(d.current?.id, first, "A tab navigating away is no longer the options tab")
        XCTAssertEqual(d.current?.url, options)
    }

    func testRememberedPermissionsAreOriginScopedAndCancelledTargetsCannotSaveGrants() throws {
        let d = readyDriver()
        let target = try XCTUnwrap(d.state.siteTarget(in: d.window))
        let request = SiteOrigin(url("https://permission.example"))!
        d.user(.site(.permission(target, request, [.notifications], .deny)))
        XCTAssertEqual(d.state.doc.sitePreferences[.default]?.permissions(for: request, embeddedIn: target.origin)[.notifications], .deny)
        XCTAssertNil(d.state.doc.sitePreferences[.default]?.rule(for: target.origin).permissions[.notifications])
    }

    func testPendingNavigationCannotSaveAPermissionUntilItsOriginCommits() throws {
        let d = readyDriver()
        let previous = try XCTUnwrap(d.state.siteTarget(in: d.window))
        let next = url("https://permission-next.example/path")
        d.page(previous.page.item, .navigationRequested(next))
        let document = DocumentToken(browser: previous.document.browser, sequence: 2)
        d.page(previous.page.item, .documentChanged(.loading(document)))
        let target = SiteTarget(document: document, context: previous.context, origin: SiteOrigin(next)!)
        let before = d.state
        assertUnchanged(before, d.user(.site(.permission(target, target.origin, [.notifications], .allow))))
        d.page(previous.page.item, .committed(next))
        d.user(.site(.permission(target, target.origin, [.notifications], .allow)))
        XCTAssertEqual(Driver(file: d.savedFile).state.doc.sitePreferences[.default]?.permissions(for: target.origin, embeddedIn: target.origin)[.notifications], .allow)
    }
}
