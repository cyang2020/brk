import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// R4-10: the page and site defects the R4-7 review found (A049, A093) and the evidence it was short of.
enum PageSiteFixScenarios {
    static let all = [
        Scenario("OpenerTab", "window.open(url) without features opens a tab that keeps window.opener and reports back; noopener and target=_blank tabs have none", cefOnly: "CEF popup browsing contexts", openerTab),
        Scenario("EaselShareTypedTitle", "Share right after typing an Easel's title suggests the typed title as the file name and keeps it as the Easel's title", easelShareTypedTitle),
        Scenario("SiteFilters-realsite", "a news page's real ad-tech requests (AdSense, Publisher Tag, gtag, analytics pixel, ad iframe) are blocked and their slots hidden; the article works; a site exception lets them through", cefOnly: "CEF request filtering", realSite),
        Scenario("PageDOMClean", "the site policy leaves no attribute or element of Brk's in the page's DOM, also after hide and show with media playing", cefOnly: "CEF site policy", domClean),
        Scenario("HistoryRestore", "the History tab Cmd+Y opened comes back after quitting and relaunching, still the native History page", historyRestore),
        Scenario("Ext-shortcut-mouse", "a window-server mouse click puts the caret in the extension shortcut field; window-server keys enter the shortcut, a click saves it, the chord fires the command", cefOnly: "CEF extension commands", shortcutByMouse),
        Scenario("ATC-routes", "links sent by macOS (open -a) follow Air Traffic Control: the first matching route wins, reordering and the sheet's remove change the result, Most Recent Space follows the last used of two windows", atcRoutes),
        Scenario("SoundCues-recorded", "each sound effect (archive, capture, download) recorded from Brk's own audio output into its own WAV when on; all three silent when off", cefOnly: "signed sound resources", soundCues),
        Scenario("WebSubstitutionsTyping", "while typing in a web editor Smart Quotes, Smart Dashes and Text Replacement follow their Edit menu toggles; Correct Spelling Automatically is greyed as Chromium has none", cefOnly: "web editing", substitutionsWhileTyping),
        Scenario("ProfileSettingsApplied", "each profile's own Favorites, default search engine and archive time are the ones a Space with that profile uses", profileSettingsApplied),
    ]

    private static func row(_ app: AppUnderTest, _ item: ItemID, window: WindowID? = nil) throws -> TabRow? {
        let view = try app.view(window ?? app.window)
        return (allTabs(view) + tabRows(view.scratch?.rows ?? [])).first { $0.id == item }
    }

    // MARK: OpenerTab (A049)

    /// Chrome opens `window.open(url)` with no window features as a tab whose page keeps `window.opener` (a sign-in
    /// or payment page reports back through it), unless the page asked for noopener; an `<a target=_blank>` implies
    /// noopener. Brk opened its own browser for the tab, so `opener` was always null (R4-7 D1).
    @Sendable static func openerTab(_ app: AppUnderTest) throws {
        let page = try PageBrowsingScenarios.load(app, "page-browsing.html")
        let before = Set(allTabs(try app.view()).map(\.id))
        try PageBrowsingScenarios.clicked(app, page, "window.child=window.open('popup-child.html?tab')")
        var report: [String: Any] = [:]
        try app.waitUntil("the child reported to its opener", timeout: 12) {
            guard let t = try PageBrowsingScenarios.title(app, page), t.hasPrefix("popup:") else { return false }
            report = (try? JSONSerialization.jsonObject(with: Data(t.dropFirst(6).utf8))) as? [String: Any] ?? [:]
            return !report.isEmpty
        }
        try PageBrowsingScenarios.record(app, "child-report", report.mapValues { "\($0)" })
        try expect(report["opener"] as? Bool == true, "the tab lost window.opener: \(report)")
        let view = try app.view()
        guard let child = allTabs(view).first(where: { !before.contains($0.id) }) else { throw Check(description: "no new tab") }
        try expect(child.url == app.site.url("popup-child.html?tab"), "the new tab is at \(child.url?.absoluteString ?? "nil")")
        try expect(currentTab(view)?.id == child.id, "the opened tab is not in front")
        try expect(tabRows(view.space.today.rows).contains { $0.id == child.id }, "the opened tab is not in Today")
        let childPage = PageID(window: page.window, item: child.id)
        try app.waitForPageInput(childPage, at: app.site.url("popup-child.html?tab"))
        try expect((try PageBrowsingScenarios.facts(app, page).auxiliaryWindows ?? []).isEmpty, "a native popup window opened as well")
        try expect(try app.native().pages[childPage]?.surfaceFrame.map { $0.width > 100 && $0.height > 100 } == true, "the tab's page is not in the content card")
        try app.screenshot("opener-tab")
        app.passed("window.open(url) without features: a foreground Today tab that keeps window.opener")

        // The two documents share a browsing context group: the opener scripts the tab, the tab posts back.
        try app.evaluate(page, "document.title='reach:'+child.document.title.startsWith('child:')+':'+(child.opener===window)")
        try app.waitUntil("the opener reaches into its tab") { try PageBrowsingScenarios.title(app, page) == "reach:true:true" }
        try app.evaluate(childPage, "window.opener.postMessage({kind:'popup-report',value:{signedIn:'token-42'}},location.origin)")
        try app.waitUntil("a sign-in style message from the tab") { try PageBrowsingScenarios.title(app, page) == "popup:{\"signedIn\":\"token-42\"}" }
        app.passed("opener and tab script each other; the tab reports back like a sign-in page")

        // Typing reaches the tab's own page; its keys and focus are a normal tab's.
        try app.evaluate(childPage, "document.body.innerHTML='<input id=f autofocus>';document.getElementById('f').focus();document.title='child-input'")
        try app.waitUntil("input in the tab") { try row(app, child.id)?.title == "child-input" }
        try app.type("abc")
        try app.evaluate(childPage, "document.title='typed:'+document.getElementById('f').value")
        try app.waitUntil("keys reach the tab's page") { try row(app, child.id)?.title == "typed:abc" }

        // The opener closes the window it opened: the tab goes, as Chrome closes the tab.
        try app.dispatch(.tab(.focus(page.item)))
        try app.waitForPageInput(page, at: app.site.url("page-browsing.html"))
        try app.evaluate(page, "child.close();document.title='closed-child'")
        // A page that closes leaves its row unloaded in Brk (R7a); the browser itself is gone, closed by the page.
        try app.waitUntil("window.close from the opener closes the tab's page") {
            let entries = try app.pageLog().filter { $0.page == childPage }
            return try entries.contains { $0.kind == .closed } && !entries.contains { $0.kind == .closeRequested } && row(app, child.id)?.loaded == false
        }
        app.passed("child.close() from the opener closes the tab's page")

        // noopener and target=_blank (implicit noopener): a tab with no opener, as in Chrome.
        try PageBrowsingScenarios.clicked(app, page, "document.title='noopener-returned:'+(window.open('popup-child.html?noopener','_blank','noopener')===null)")
        try app.waitUntil("noopener's tab", timeout: 12) {
            try allTabs(app.view()).contains { $0.url == app.site.url("popup-child.html?noopener") && ($0.title.hasPrefix("child:")) }
        }
        try expect(try PageBrowsingScenarios.title(app, page) == "noopener-returned:true", "window.open with noopener returned a window")
        guard let noopener = allTabs(try app.view()).first(where: { $0.url == app.site.url("popup-child.html?noopener") }) else { throw Check(description: "noopener tab missing") }
        try expect(noopener.title.contains("\"opener\":false"), "noopener tab has an opener: \(noopener.title)")
        try app.dispatch(.tab(.focus(page.item)))
        try app.waitForPageInput(page, at: app.site.url("page-browsing.html"))
        try PageBrowsingScenarios.clicked(app, page, "const a=document.createElement('a');a.href='popup-child.html?blank';a.target='_blank';document.body.append(a);a.click()")
        try app.waitUntil("target=_blank tab", timeout: 12) {
            try allTabs(app.view()).contains { $0.url == app.site.url("popup-child.html?blank") && $0.title.hasPrefix("child:") }
        }
        let blank = allTabs(try app.view()).first { $0.url == app.site.url("popup-child.html?blank") }!
        try expect(blank.title.contains("\"opener\":false"), "target=_blank tab has an opener: \(blank.title)")
        try expect((try PageBrowsingScenarios.facts(app, page).auxiliaryWindows ?? []).isEmpty, "a native popup window opened")
        app.passed("noopener and target=_blank open tabs without an opener")

        // The opened tab outlives its opener (a tab, not an owned popup) and survives a restart like any tab.
        try app.dispatch(.tab(.close(.item(page.item))))
        try app.waitUntil("opener archived") { try !allTabs(app.view()).contains { $0.id == page.item } }
        try expect(try allTabs(app.view()).contains { $0.id == blank.id }, "closing the opener closed the tab it opened")
        try app.flush(); try app.restart()
        try app.waitUntil("the opened tab restored") { try allTabs(app.view()).contains { $0.url == app.site.url("popup-child.html?blank") } }
        app.note("CEF creates the popup browser (on_before_popup allowed, OnPopupBrowserViewCreated places its view in a frameless host window) and Brk embeds it as the tab's page instead of creating a new browser; Chromium's own opener and noopener rules apply.")
    }

    // MARK: EaselShareTypedTitle (A101)

    /// R4-7 saw Share, clicked while the new title was still being typed, suggest "Untitled Easel.png": the click on
    /// the pill does not end the title's editing, so the share went out with the saved title.
    @Sendable static func easelShareTypedTitle(_ app: AppUnderTest) throws {
        let (id, item) = try EaselScenarios.make(app)
        try expect(try EaselScenarios.board(app).editingTitle, "the new Easel's title is not selected for typing")
        try app.type("Review easel")
        try app.click(.urlPill)
        var controls: [String] = []
        try app.waitUntil("the Share Easel save panel") {
            guard case .menuItems(let items) = try app.send(.sidebarPanel(window: app.window, action: .inspect)) else { return false }
            controls = items
            return items.first == "Share Easel"
        }
        try PageBrowsingScenarios.record(app, "share-panel", controls)
        _ = try app.screenshotSheet("share-panel")
        try expect(controls.last == "name:Review easel.png", "the panel suggests \(controls.last ?? "nothing")")
        try app.waitUntil("the typed title is the Easel's") {
            try EaselScenarios.board(app).title == "Review easel" && row(app, item)?.title == "Review easel"
        }
        try app.perform(.sidebarPanel(window: app.window, action: .button("Cancel")))
        try app.waitUntil("panel cancelled") { if case .failed = try app.send(.sidebarPanel(window: app.window, action: .inspect)) { true } else { false } }
        try expect(try app.view().urlPill.share == id, "the pill is no longer the Easel's Share")
        app.passed("Share after typing a title: the panel suggests Review easel.png and the Easel is renamed")
    }

    // MARK: SiteFilters-realsite (A109)

    /// The local stand-in for a real ad-funded news page (`news-site.html`): the third-party requests such pages make
    /// (AdSense, Google Publisher Tag, gtag.js, an analytics hit pixel, an ad iframe) go to the fixture server under
    /// `localhost`, a different site from the page's 127.0.0.1, so the server's counts say what got through. The list
    /// is chosen through the real open panel; its lines have the shape EasyList and EasyPrivacy use for these requests.
    @Sendable static func realSite(_ app: AppUnderTest) throws {
        let start = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, start, "Site policy fixture")
        let file = app.dataDirectory.appendingPathComponent("real-site-excerpt.txt")
        try Data("""
        [Adblock Plus 2.0]
        ! Title: Real-site excerpt (Brk fixture)
        ! The shape of EasyList and EasyPrivacy's rules for AdSense, Publisher Tag, gtag, analytics hits and ad frames.
        /pagead/js/adsbygoogle.js$script,third-party
        /tag/js/gpt.js$script,third-party
        /gtag/js?id=$script,third-party
        /collect?v=$image,third-party
        /ads/frame.html$subdocument,third-party
        ##.adsbygoogle
        ##div[id^="div-gpt-ad-"]
        ##.sponsored-strip

        """.utf8).write(to: file)
        try app.dispatch(.site(.controls))
        try ExtScenarios.control(app, "siteImportRules", .press)
        try app.waitUntil("the real open panel is attached") { try app.native().sheetClass == "NSOpenPanel" }
        try ImportSyncScenarios.panel(app, .open(path: file.path))
        try app.waitUntil("the excerpt is the profile's imported list") {
            try SiteFilterScenarios.lists(app).contains { $0.id == FilterListRecord.importedID && $0.summary?.networkFilters == 5 && $0.summary?.hidingRules == 3 }
        }
        try app.dispatch(.site(.closeControls))

        let adPaths = ["/pagead/js/adsbygoogle.js", "/tag/js/gpt.js", "/gtag/js", "/collect", "/ads/frame.html"]
        func counts() -> [String: Int] { Dictionary(uniqueKeysWithValues: (adPaths + ["/news-assets/app.js", "/news-assets/hero.svg"]).map { ($0, app.site.requestCount($0)) }) }
        func report(_ item: ItemID) throws -> [String: Any] {
            var value: [String: Any] = [:]
            try app.waitUntil("the news page's report") {
                try SitePolicyScenarios.evaluate(app, item, "document.title='news:'+reportNow()")
                guard let title = try row(app, item)?.title, title.hasPrefix("news:"),
                      let parsed = try? JSONSerialization.jsonObject(with: Data(title.dropFirst(5).utf8)) as? [String: Any],
                      let loaded = parsed["loaded"] as? [String: Bool], loaded.count == 6 else { return false }
                value = parsed
                return true
            }
            return value
        }
        let before = counts()
        let news = try app.load(app.site.url("news-site.html"))
        try app.waitForPageInput(PageID(window: app.window!, item: news), at: app.site.url("news-site.html"))
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "news target missing") }
        try app.dispatch(.site(.closeControls))
        var rule = SiteRule(); rule.blocking = true; rule.hideCookieBanners = true
        try app.dispatch(.site(.rule(target, rule)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: true)))
        app.sleep(0.5)
        var dom = try report(news)
        try PageBrowsingScenarios.record(app, "blocked", dom.mapValues { "\($0)" })
        let blocked = counts()
        try expect(adPaths.allSatisfy { blocked[$0] == before[$0] }, "an ad request reached the server: \(blocked) from \(before)")
        try expect(blocked["/news-assets/app.js"]! > before["/news-assets/app.js"]!, "the page's own script did not load")
        let loaded = dom["loaded"] as? [String: Bool] ?? [:], shown = dom["shown"] as? [String: Bool] ?? [:]
        try expect(loaded["app"] == true && loaded["hero"] == true && dom["appReady"] as? Bool == true, "first-party content broke: \(dom)")
        try expect(["adsbygoogle", "gpt", "gtag", "collect"].allSatisfy { loaded[$0] == false }, "an ad resource loaded: \(loaded)")
        try expect(shown["adsense"] == false && shown["gpt"] == false && shown["sponsored"] == false && shown["banner"] == false, "an ad slot or the cookie banner shows: \(shown)")
        try expect(shown["headline"] == true && shown["hero"] == true, "the article is hidden: \(shown)")
        try app.screenshot("news-blocked")
        app.passed("ads, trackers and the ad frame blocked before the network; slots and banner hidden; the article and its own script work")

        // A rule names the document it was read from; read the target again after the reload.
        func currentTarget() throws -> SiteTarget {
            try app.dispatch(.tab(.focus(news)))
            try app.dispatch(.site(.controls))
            defer { _ = try? app.dispatch(.site(.closeControls)) }
            guard let value = try SitePolicyScenarios.controls(app).target else { throw Check(description: "news target missing") }
            return value
        }
        rule.blocking = false; rule.hideCookieBanners = false
        try app.dispatch(.site(.rule(try currentTarget(), rule)))
        let excepted = try app.load(app.site.url("news-site.html?excepted"))
        try app.waitForPageInput(PageID(window: app.window!, item: excepted), at: app.site.url("news-site.html?excepted"))
        try app.waitUntil("the excepted site's ad requests reach the server", timeout: 10) { adPaths.allSatisfy { app.site.requestCount($0) > blocked[$0]! } }
        dom = try report(excepted)
        try PageBrowsingScenarios.record(app, "excepted", dom.mapValues { "\($0)" })
        let allowedLoaded = dom["loaded"] as? [String: Bool] ?? [:], allowedShown = dom["shown"] as? [String: Bool] ?? [:]
        try expect(["adsbygoogle", "gpt", "gtag", "collect"].allSatisfy { allowedLoaded[$0] == true }, "the excepted site's ad resources did not load: \(allowedLoaded)")
        try expect(allowedShown["adsense"] == true && allowedShown["gpt"] == true && allowedShown["banner"] == true, "the excepted site's slots are hidden: \(allowedShown)")
        try app.screenshot("news-excepted")
        app.passed("a site exception lets the same requests through and shows the slots")

        rule.blocking = true; rule.hideCookieBanners = true
        try app.dispatch(.site(.rule(try currentTarget(), rule)))
        let afterException = counts()
        let again = try app.load(app.site.url("news-site.html?again"))
        try app.waitForPageInput(PageID(window: app.window!, item: again), at: app.site.url("news-site.html?again"))
        _ = try report(again)
        app.sleep(0.5)
        try expect(adPaths.allSatisfy { app.site.requestCount($0) == afterException[$0] }, "blocking on again let a request through: \(counts()) from \(afterException)")
        try app.dispatch(.site(.controls))
        let status = try app.send(.siteControlTexts(window: app.window!))
        try PageBrowsingScenarios.record(app, "site-texts", "\(status)")
        _ = try app.screenshotSiteControls("rules-status")
        app.note("Requests went to localhost on the fixture port (a third party to the 127.0.0.1 page); nothing left the machine. The list was imported through the real NSOpenPanel.")
    }

    // MARK: PageDOMClean (out-of-group finding)

    /// R4-7 saw `data-brk-media-<id>-observed` on every page's <html> (and the site policy also marked playing media
    /// elements). Arc adds nothing to a page's DOM; the policy's state now lives in its isolated world.
    @Sendable static func domClean(_ app: AppUnderTest) throws {
        let url = app.site.url("capture-media.html")
        let item = try app.load(url), page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        let probe = "(()=>{const own=n=>n.getAttributeNames().filter(a=>a.startsWith('data-brk')||a.includes('brk-media'));const html=own(document.documentElement);const media=[...document.querySelectorAll('audio,video')].flatMap(own);document.title='dom:'+JSON.stringify({html:document.documentElement.getAttributeNames(),brk:html.concat(media),media:document.querySelectorAll('audio,video').length,playing:[...document.querySelectorAll('audio,video')].some(m=>!m.paused)})})()"
        func read(_ what: String) throws -> [String: Any] {
            var value: [String: Any] = [:]
            try app.waitUntil(what) {
                try app.evaluate(page, probe)
                guard let title = try row(app, item)?.title, title.hasPrefix("dom:"),
                      let parsed = try? JSONSerialization.jsonObject(with: Data(title.dropFirst(4).utf8)) as? [String: Any] else { return false }
                value = parsed; return true
            }
            return value
        }
        var dom: [String: Any] = [:]
        try app.waitUntil("the page's video plays", timeout: 12) { dom = try read("DOM read"); return dom["playing"] as? Bool == true }
        try PageBrowsingScenarios.record(app, "visible", dom.mapValues { "\($0)" })
        try expect((dom["brk"] as? [String])?.isEmpty == true, "Brk's attributes in the page: \(dom)")
        // Hidden with media playing (the policy keeps the page running and remembers it), then shown again.
        let other = try app.load(app.site.url("page2.html"))
        app.sleep(1.5)
        try app.dispatch(.tab(.focus(item)))
        try app.waitForPageInput(page, at: url)
        try app.dispatch(.tab(.focus(other)))
        app.sleep(1.0)
        try app.dispatch(.tab(.focus(item)))
        try app.waitForPageInput(page, at: url)
        dom = try read("DOM read after hide and show")
        try PageBrowsingScenarios.record(app, "after-hide", dom.mapValues { "\($0)" })
        try expect((dom["brk"] as? [String])?.isEmpty == true, "Brk's attributes after hide and show: \(dom)")
        app.note("The page's own getAttributeNames() on <html> and on every audio/video element, read while the video played, and again after the tab was hidden and shown (the site policy refreshed both times).")
    }

    // MARK: HistoryRestore (out-of-group finding)

    @Sendable static func historyRestore(_ app: AppUnderTest) throws {
        try app.press("cmd+y")
        var history: ItemID?
        try app.waitUntil("Cmd+Y opens the History tab") {
            history = tabRows(try app.view().space.today.rows).first { $0.url == HistoryPage.url }?.id
            return try history != nil && app.view().history != nil
        }
        try app.screenshot("history-before")
        try app.flush(); try app.restart()
        try app.waitUntil("the History tab is back after the relaunch") { try tabRows(app.view().space.today.rows).contains { $0.id == history && $0.url == HistoryPage.url && $0.title == "History" } }
        try app.dispatch(.tab(.focus(history!)))
        try app.waitUntil("its card is the native History page") { try app.view().history != nil && app.view().content.panes.first?.tab == history }
        try expect(try !app.native().pages.keys.contains { $0.item == history }, "a browser was made for the History tab")
        try app.screenshot("history-after")
    }

    // MARK: Ext-shortcut-mouse (A098)

    /// A window-server mouse click on a control of the site controls panel, posted only when the frontmost window at
    /// the point is this Brk's (the panel is its own window, so `PhysicalPointer`'s key-window check does not apply).
    static func panelClick(_ app: AppUnderTest, _ owner: WindowID, _ field: String) throws -> Bool {
        // The field may be on the panel's second page (site settings details), as `ExtScenarios.control` handles.
        if case .failed = try app.send(.siteControlInput(window: owner, field: field, action: .locate)) {
            try app.perform(.siteControlInput(window: owner, field: "siteSettingsDetails", action: .press))
            try app.waitUntil("site settings page shows \(field)") {
                if case .menuItems = try app.send(.siteControlInput(window: owner, field: field, action: .locate)) { true } else { false }
            }
        }
        guard case .menuItems(let values) = try app.send(.siteControlInput(window: owner, field: field, action: .locate)), values.count == 6,
              let x = Double(values[0]), let y = Double(values[1]), let w = Double(values[2]), let h = Double(values[3]) else {
            throw Check(description: "\(field) has no screen rectangle")
        }
        let point = CGPoint(x: x + min(20, w / 2), y: y + min(11, h / 2))
        try PageBrowsingScenarios.record(app, "click-" + String(field.prefix(24)), ["point": "\(point)", "control": values.joined(separator: " ")])
        guard case .hello(let hello) = try app.send(.hello), let front = PhysicalPointer.frontmost(at: point), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk's panel at \(point); no click posted")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 60_000)
        }
        app.note("click on \(field) at \(point): \(values[5])")
        return values[4] == "focused:true"
    }
    static func focused(_ app: AppUnderTest, _ owner: WindowID, _ field: String) throws -> Bool {
        if case .failed = try app.send(.siteControlInput(window: owner, field: field, action: .locate)) {
            try app.perform(.siteControlInput(window: owner, field: "siteSettingsDetails", action: .press))
        }
        guard case .menuItems(let values) = try app.send(.siteControlInput(window: owner, field: field, action: .locate)), values.count == 6 else { return false }
        return values[4] == "focused:true"
    }
    static func locateState(_ app: AppUnderTest, _ owner: WindowID, _ field: String) throws -> String {
        guard case .menuItems(let values) = try app.send(.siteControlInput(window: owner, field: field, action: .locate)) else { return "unavailable" }
        return values.joined(separator: " ")
    }

    /// The Ext-shortcut-physical scenario focused the field through AppKit (R4-7: "the focus is set by the program");
    /// here every step is input the window server delivers: the click into the field, ⌘A and the typed shortcut, the
    /// click on Save shortcut, and the chord that runs the extension command.
    @Sendable static func shortcutByMouse(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting window-server events is not allowed for this runner") }
        let (item, fixture) = try ExtensionScenarios.selectedFixture(app)
        guard let pid = app.hello?.pid, let owner = app.window else { throw Check(description: "app identity missing") }
        let command = "fixture-command", field = "extension-shortcut-" + fixture.id + "-" + command
        try app.dispatch(.site(.nativeExtensions))
        try app.waitUntil("installed shortcut editor") { try ExtScenarios.catalogValue(app, fixture.id) != nil }
        try expect(try !focused(app, owner, field), "the shortcut field had focus before the click")
        try expect(try ExtScenarios.catalogValue(app, fixture.id)?.commands?.contains { $0.name == command && ExtensionShortcuts.chord($0.keybinding) == KeyChord([.command, .shift], .u) } != true, "the command already has ⇧⌘U")
        _ = try app.screenshotSiteControls("before-click")
        _ = try panelClick(app, owner, field)
        do { try app.waitUntil("the mouse click put the caret in the shortcut field") { try focused(app, owner, field) } }
        catch { _ = try? app.screenshotSiteControls("field-not-focused"); throw Check(description: "after the click: " + (try locateState(app, owner, field))) }
        _ = try app.screenshotSiteControls("field-clicked")
        app.passed("a window-server click focused the shortcut field")
        PhysicalKeys.press(KeyChord([.command], .a), pid: pid)
        PhysicalKeys.type("cmd+shift+u", pid: pid)
        app.sleep(0.3)
        _ = try panelClick(app, owner, "extension-shortcut-save-" + fixture.id + "-" + command)
        try app.waitUntil("Chromium reads back the shortcut entered by keyboard and saved by mouse") {
            if let error = try SitePolicyScenarios.controls(app).extensionError { throw Check(description: error) }
            return try ExtScenarios.catalogValue(app, fixture.id)?.commands?.contains { $0.name == command && ExtensionShortcuts.chord($0.keybinding) == KeyChord([.command, .shift], .u) } == true
        }
        _ = try app.screenshotSiteControls("shortcut-saved")
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(item)))
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: owner, item: item), at: app.site.url("site-policy.html"))
        try app.waitUntil("extension listener ready") {
            try SitePolicyScenarios.evaluate(app, item, "document.title='shortcut-ready:'+document.documentElement.getAttribute('data-brk-extension')")
            return try tab(item, in: app.view())?.title == "shortcut-ready:installed"
        }
        try WindowServerKeys.press(app, KeyChord([.command, .shift], .u), window: owner)
        try waitForTitle(app, item, "extension-command:fixture-command")
        app.note("Click, ⌘A, the typed text cmd+shift+u, the click on Save shortcut and ⇧⌘U were all window-server events; the field is Brk's text entry for a shortcut (Chrome's own page records the chord instead).")
    }

    // MARK: ATC-routes (A111)

    /// A link handed to this run's Brk by macOS: `open -g -a <bundle> <url>` asks LaunchServices, which sends the
    /// GetURL Apple Event to the running instance of that bundle (the bundle path is this run's, so no other Brk on
    /// the machine gets it). Refuses to go on if LaunchServices started a second Brk instead.
    static func openFromSystem(_ app: AppUnderTest, _ url: URL) throws {
        guard case .hello(let hello) = try app.send(.hello), let executable = NativePickerInput.executable(hello.pid) else { throw Check(description: "no executable") }
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func instances() -> [String] {
            let pgrep = Process(), out = Pipe()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); pgrep.arguments = ["-f", executable.path]; pgrep.standardOutput = out
            try? pgrep.run(); pgrep.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
        }
        let before = instances()
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", bundle.path, url.absoluteString]
        try open.run(); open.waitUntilExit()
        try expect(open.terminationStatus == 0, "open -a exited \(open.terminationStatus)")
        app.sleep(0.3)
        let extra = Set(instances()).subtracting(before)
        for pid in extra { kill(pid_t(pid) ?? 0, SIGKILL) }
        try expect(extra.isEmpty, "LaunchServices started another Brk (\(extra)); killed it")
    }

    /// Where a link landed: the window and space whose Today holds it.
    static func landed(_ app: AppUnderTest, _ url: URL) throws -> (window: WindowID, space: SpaceID, kind: WindowKind)? {
        guard case .hello(let hello) = try app.send(.hello) else { return nil }
        for window in hello.windows {
            guard let view = try? app.view(window) else { continue }
            if tabRows(view.space.today.rows + (view.scratch?.rows ?? [])).contains(where: { $0.url == url }) { return (window, view.space.id, view.kind) }
        }
        return nil
    }

    @Sendable static func atcRoutes(_ app: AppUnderTest) throws {
        let first = app.window!, personal = try app.view().space.id
        func space(_ title: String) throws -> SpaceID {
            let before = Set(try app.view().dock.map(\.id))
            try app.dispatch(.space(.create(title: title, icon: .none, theme: SpaceTheme(colors: [ThemePresets.pastel[1]], texture: .grain, intensity: 0.4, appearance: .light))))
            guard let id = try app.view().dock.map(\.id).first(where: { !before.contains($0) }) else { throw Check(description: "\(title) missing") }
            return id
        }
        let work = try space("Work"), research = try space("Research")
        try app.dispatch(.space(.focus(personal)))
        try app.dispatch(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("host"), pattern: "127.0.0.1", destination: .space(work), match: .contains)))))
        try app.dispatch(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("red"), pattern: "red.html", destination: .space(research), match: .contains)))))
        func routes() throws -> [String] {
            guard case .settings(let settings) = try app.send(.settings) else { return [] }
            return settings.routes.map(\.route.id.rawValue)
        }
        func send(_ query: String, expect destination: SpaceID?, window: WindowID? = nil, _ what: String) throws -> WindowID {
            let url = app.site.url("red.html?" + query)
            try openFromSystem(app, url)
            var found: (window: WindowID, space: SpaceID, kind: WindowKind)?
            try app.waitUntil(what, timeout: 10) { found = try landed(app, url); return found != nil }
            if let destination { try expect(found!.space == destination && found!.kind == .standard, "\(what): landed in space \(found!.space) of a \(found!.kind) window") }
            else { try expect(found!.kind == .little, "\(what): landed in a \(found!.kind) window, not a Little Arc") }
            if let window { try expect(found!.window == window, "\(what): landed in window \(found!.window), not \(window)") }
            return found!.window
        }
        let initial = try routes()
        try expect(initial == ["host", "red"], "routes \(initial)")
        _ = try send("one", expect: work, "the first matching route (127.0.0.1 → Work) wins over the later red.html route")
        app.passed("macOS-delivered link: the first matching route decides")

        try app.dispatch(.settings(.links(.moveRoute(LinkRouteID("red"), index: 0))))
        let moved = try routes()
        try expect(moved == ["red", "host"], "moved routes \(moved)")
        _ = try send("two", expect: research, "after moving red.html first it decides (→ Research)")
        app.passed("reordering the routes changes which one wins")

        // The sheet's own remove control (⊖ on the red.html row).
        guard case .dispatched = try app.send(.openSettings(pane: .links)) else { throw Check(description: "openSettings") }
        try app.settle()
        try app.click(.settingsField("airTrafficControl"))
        try app.waitUntil("Air Traffic Control sheet") { try app.native().sheetClass != nil || routes().count == 2 }
        app.sleep(0.5)
        try app.click(.settingsField("route-red-remove"))
        try app.waitUntil("⊖ removes the red.html route") { try routes() == ["host"] }
        try app.click(.settingsField("routes-close"))
        try app.dispatch(.settings(.closeWindow))
        _ = try send("three", expect: work, "with red.html removed the 127.0.0.1 route takes it again (→ Work)")
        app.passed("removing a route through the sheet")

        try app.dispatch(.settings(.links(.removeRoute(LinkRouteID("host")))))
        let little = try send("four", expect: nil, "with no route the Default (Little Arc) takes the link")
        _ = try app.send(.dispatch(window: little, command: .window(.close)))
        app.passed("no route left: the Default, a Little Arc")

        // Two standard windows, Default Most Recent Space: the last window used gets the link, in its current space.
        try app.dispatch(.settings(.links(.defaultRoute(.mostRecentSpace))))
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let second = hello.windows.first(where: { $0 != first && (try? app.view($0).kind) == .standard }) else { throw Check(description: "second window") }
        _ = try app.send(.dispatch(window: second, command: .space(.focus(research))))
        try app.waitUntil("the second window shows Research") { try app.view(second).space.id == research }
        _ = try app.send(.activate(window: first))
        try app.waitUntil("first window key") { try app.native(first).isKey }
        try app.dispatch(.space(.focus(personal)))
        _ = try send("five", expect: personal, window: first, "Most Recent Space: the first window was used last")
        _ = try app.send(.activate(window: second))
        try app.waitUntil("second window key") { try app.native(second).isKey }
        _ = try send("six", expect: research, window: second, "Most Recent Space: now the second window was used last")
        try app.screenshot("two-windows", window: second)
        app.passed("Most Recent Space follows the last used of two standard windows")
        app.note("Every link came from /usr/bin/open -g -a <this run's Brk.app> <url>: LaunchServices delivered the GetURL Apple Event; no control-socket externalURL was used. Reordering used the moveRoute setting (the sheet has no drag handle).")
    }

    // MARK: SoundCues-recorded (A106)

    /// PB6S recorded only the archive cue. Here every cue Brk has gets its own recording of Brk's output through
    /// ScreenCaptureKit (the PB6S recorder, which captures this one process only), saved as `<scenario>-<cue>.wav`,
    /// and one more recording with sound effects off while all three events happen again.
    @Sendable static func soundCues(_ app: AppUnderTest) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("verify/completion/browser-basic-parent/round3-page-browsing/tools/record-app-audio.swift")
        let tool = app.dataDirectory.appendingPathComponent("record-app-audio")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-O", "-o", tool.path, source.path]
        try compile.run(); compile.waitUntilExit()
        try expect(compile.terminationStatus == 0, "recorder did not compile")
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello") }
        let downloads = app.dataDirectory.appendingPathComponent("cue-downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(downloads.path))))
        try app.dispatch(.settings(.profile(.default, .promptForDownloadLocation(false))))
        let captureURL = app.site.url("capture-media.html")

        func archive() throws { _ = try app.load(app.site.url("page2.html?cue")); app.sleep(0.5); try app.dispatch(.tab(.close(.focused))) }
        func capture() throws {
            let item = try app.load(captureURL)
            try app.waitForPageInput(PageID(window: app.window!, item: item), at: captureURL)
            try app.dispatch(.capture(.begin(.fullPage)))
        }
        func download() throws { _ = try app.load(app.site.url("download")) }
        func closeLibrary() { _ = try? app.dispatch(.library(.close)) }

        /// Records `seconds` of Brk's output around `body` (started a second in); returns the RMS trace.
        func record(_ name: String, seconds: Int, _ body: () throws -> Void) throws -> (trace: [[String: Double]], at: Double) {
            let base = app.shotsDirectory.deletingLastPathComponent()
            let wav = base.appendingPathComponent("\(app.scenarioID)-\(name).wav"), json = base.appendingPathComponent("\(app.scenarioID)-\(name).json")
            let recorder = Process(), out = Pipe()
            recorder.executableURL = tool
            recorder.arguments = [String(hello.pid), String(seconds), wav.path, json.path]
            recorder.standardOutput = out
            try recorder.run()
            var buffer = Data(), ready = false
            let deadline = uptime() + 15
            while uptime() < deadline, !ready {
                let chunk = out.fileHandleForReading.availableData
                if chunk.isEmpty { if !recorder.isRunning { break }; app.sleep(0.05); continue }
                buffer += chunk
                ready = String(decoding: buffer, as: UTF8.self).contains("ready")
            }
            try expect(ready, "recorder did not start: \(String(decoding: buffer, as: UTF8.self))")
            app.sleep(1)
            let at = uptime()
            try body()
            recorder.waitUntilExit()
            try expect(recorder.terminationStatus == 0, "recorder failed for \(name)")
            let summary = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any] ?? [:]
            return ((summary["trace"] as? [[String: Double]]) ?? [], at)
        }
        func loudest(_ trace: [[String: Double]], _ from: Double, _ to: Double) -> Double {
            trace.filter { ($0["t"] ?? 0) >= from && ($0["t"] ?? 0) < to }.map { $0["rms"] ?? 0 }.max() ?? 0
        }

        try app.dispatch(.settings(.advanced(.soundEffects(true))))
        var levels: [String: [String: Double]] = [:]
        for (name, seconds, trigger) in [("tabsArchived", 5, archive), ("captureCompleted", 9, capture), ("downloadCompleted", 8, download)] as [(String, Int, () throws -> Void)] {
            let (trace, at) = try record(name, seconds: seconds, trigger)
            closeLibrary()
            let quiet = loudest(trace, at - 1, at), cue = loudest(trace, at, at + Double(seconds) - 1)
            levels[name] = ["quietBefore": quiet, "cue": cue]
            try expect(!trace.isEmpty, "\(name): no audio buffers were recorded")
            try expect(cue > 0.003 && cue > quiet * 10, "\(name) was not heard on Brk's output (rms \(cue), before \(quiet))")
        }
        app.passed("archive, capture and download cues each recorded from Brk's output")

        try app.dispatch(.settings(.advanced(.soundEffects(false))))
        let (trace, at) = try record("off", seconds: 12) { try archive(); app.sleep(1); try capture(); app.sleep(3); closeLibrary(); try download() }
        let off = loudest(trace, at, at + 11)
        levels["off"] = ["all": off]
        try PageBrowsingScenarios.record(app, "levels", levels)
        try expect(off < 0.0005, "sound effects off still produced output (rms \(off))")
        app.note("Levels (RMS of 20 ms windows) per cue are in SoundCues-recorded-levels.json; each WAV holds that cue as Brk's process output, captured by ScreenCaptureKit, not the speaker.")
    }

    // MARK: WebSubstitutionsTyping (A046)

    /// R3-7 made the Substitutions panel's Replace buttons work in web editors; typing itself never substituted.
    /// Chromium's input view does substitute while typing when its switches are on; Brk now hands it the menu's toggles.
    @Sendable static func substitutionsWhileTyping(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed, let pid = app.hello?.pid, let owner = app.window else { throw Check(description: "window-server input unavailable") }
        let page = try PageBrowsingScenarios.load(app, "page-browsing.html")
        try app.evaluate(page, "document.body.innerHTML='<textarea id=t style=\"position:fixed;left:20px;top:20px;width:600px;height:200px;font:20px sans-serif\"></textarea>';document.title='editor ready'")
        try app.waitUntil("editor ready") { try PageBrowsingScenarios.title(app, page) == "editor ready" }
        guard let frame = try PageBrowsingScenarios.facts(app, page).surfaceFrame else { throw Check(description: "surface") }
        _ = try app.send(.activate(window: owner))
        try app.click(at: CGPoint(x: frame.minX + 100, y: frame.minY + 60))
        try app.evaluate(page, "document.title='focus:'+(document.activeElement.id)")
        try app.waitUntil("textarea focused") { try PageBrowsingScenarios.title(app, page) == "focus:t" }
        func services() throws -> [String] { try PageBrowsingScenarios.facts(app, page).textServices ?? [] }
        /// Sets a toggle through its Edit menu row, reading the state the surface reports.
        func set(_ title: String, _ key: String, _ on: Bool) throws {
            for _ in 0..<2 {
                let before = try services().count
                try app.perform(.menuAction(title))
                try app.waitUntil("\(title) toggled") { try services().count > before }
                if try services().last == "\(key):\(on)" { return }
            }
            throw Check(description: "\(title) did not reach \(on): \(try services().suffix(3))")
        }
        func typed(_ text: String) throws -> String {
            try app.evaluate(page, "document.getElementById('t').value='';document.getElementById('t').focus();document.title='cleared'")
            try app.waitUntil("cleared") { try PageBrowsingScenarios.title(app, page) == "cleared" }
            try WindowServerKeys.ensureFrontmost(app, owner)
            PhysicalKeys.type(text, pid: pid)
            app.sleep(1.0)
            var value = ""
            try app.waitUntil("typed text read back") {
                // Percent-encoded: a document title collapses and trims whitespace.
                try app.evaluate(page, "document.title='value:'+encodeURIComponent(document.getElementById('t').value)")
                guard let t = try PageBrowsingScenarios.title(app, page), t.hasPrefix("value:"), let decoded = String(t.dropFirst(6)).removingPercentEncoding else { return false }
                value = decoded; return true
            }
            return value
        }
        try set("Smart Quotes", "quotes", true); try set("Smart Dashes", "dashes", true)
        let smart = try typed("She said \"hi\" -- twice. ")
        try PageBrowsingScenarios.record(app, "typed-on", ["value": smart])
        try expect(smart == "She said \u{201C}hi\u{201D} \u{2014} twice. ", "typing with Smart Quotes and Smart Dashes on gave \(smart.debugDescription)")
        try app.screenshot("typed-smart")
        app.passed("typing substitutes curly quotes and an em dash with both toggles on")
        try set("Smart Quotes", "quotes", false)
        let plain = try typed("She said \"hi\" -- twice. ")
        try PageBrowsingScenarios.record(app, "typed-quotes-off", ["value": plain])
        try expect(plain == "She said \"hi\" \u{2014} twice. ", "Smart Quotes off still curled the quotes: \(plain.debugDescription)")
        try set("Smart Dashes", "dashes", false)
        let none = try typed("She said \"hi\" -- twice. ")
        try expect(none == "She said \"hi\" -- twice. ", "both off still substituted: \(none.debugDescription)")
        app.passed("each toggle switches its substitution off while typing")
        guard case .failed = try app.send(.menuAction("Correct Spelling Automatically")) else { throw Check(description: "Correct Spelling Automatically is enabled in a web editor") }
        try set("Smart Quotes", "quotes", true); try set("Smart Dashes", "dashes", true)
        app.note("Typed with window-server key events posted to Brk (the field editor of Chromium's input view, not a script). Chromium has no automatic spelling correction in web content, so that row is greyed there, as in Chrome.")
    }

    // MARK: ProfileSettingsApplied (A093)

    /// The Profiles pane keeps Favorites, the default search engine and "Archive tabs after" per profile. W2-1-edit
    /// proves the values are saved; this proves a Space uses its own profile's: what typing a query in the command
    /// bar searches with, which Favorites the Space shows (and in which context they browse), and when its idle
    /// Today tabs are archived.
    @Sendable static func profileSettingsApplied(_ app: AppUnderTest) throws {
        let personal = try app.view().space.id
        let work = try DataScenarios.profile(app, "Work Settings")
        try app.dispatch(.space(.create(title: "Work", icon: .none, theme: SpaceTheme(colors: [ThemePresets.pastel[2]], texture: .grain, intensity: 0.4, appearance: .light), profile: work)))
        guard let workSpace = try app.view().dock.map(\.id).first(where: { $0 != personal }) else { throw Check(description: "Work space missing") }
        try app.waitUntil("Work space shown with its profile") { try app.view().space.id == workSpace && app.view().urlPill.profile?.name == "Work Settings" }

        // Search engines: one site search per profile, each the profile's default.
        func engine(_ profile: ProfileID, _ name: String, _ path: String) throws -> SearchEngineID {
            try app.dispatch(.settings(.profile(profile, .addSiteSearch(name: name, keyword: name.lowercased(), template: app.site.url(path).absoluteString + "?q={q}"))))
            guard case .settings(let settings) = try app.send(.settings),
                  let id = settings.profiles.first(where: { $0.profile.id == profile })?.settings.siteSearchEngines?.first(where: { $0.name == name })?.id else {
                throw Check(description: "\(name) engine missing")
            }
            try app.dispatch(.settings(.profile(profile, .searchEngine(id))))
            return id
        }
        _ = try engine(.default, "PersonalFind", "page2.html")
        _ = try engine(work, "WorkFind", "red.html")
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "settings") }
        try PageBrowsingScenarios.record(app, "profile-settings", settings.profiles.map { "\($0.profile.name): engine \($0.settings.searchEngine.rawValue), archive \($0.settings.autoArchive.rawValue)" })

        func search(_ query: String, expect path: String) throws -> TabRow {
            _ = try app.send(.activate(window: app.window!))
            try app.press("cmd+t")
            try app.waitUntil("command bar open") { if case .commandBar? = try app.view().overlay { true } else { false } }
            try app.type(query); try app.press("return")
            let expected = app.site.url(path).absoluteString + "?q=" + query.replacingOccurrences(of: " ", with: "%20")
            var found: TabRow?
            try app.waitUntil("\(query) searched with \(path)", timeout: 12) {
                found = currentTab(try app.view())
                return found?.url?.absoluteString == expected
            }
            return found!
        }
        let workSearch = try search("work query", expect: "red.html")
        try app.dispatch(.space(.focus(personal)))
        try app.waitUntil("Personal space shown") { try app.view().space.id == personal }
        let personalSearch = try search("personal query", expect: "page2.html")
        try PageBrowsingScenarios.record(app, "searches", ["work": workSearch.url?.absoluteString ?? "", "personal": personalSearch.url?.absoluteString ?? ""])
        app.passed("the command bar searches with the Space's profile engine (Work: WorkFind, Personal: PersonalFind)")

        // Favorites: a favorite added in Work is Work's only, and browses in Work's cookie jar.
        try app.dispatch(.space(.focus(workSpace)))
        try app.waitUntil("Work again") { try app.view().space.id == workSpace }
        let cookieURL = app.site.url("cookie.html?work-favorite#set")
        let favorite = try app.load(cookieURL)
        try app.waitForPageInput(PageID(window: app.window!, item: favorite), at: cookieURL)
        try app.waitUntil("cookie set in Work") { try row(app, favorite)?.title == "cookie:brk=1" }
        try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().favorites.root, index: Int.max))))
        try app.waitUntil("Work favorite") { try app.view().favorites.tiles.contains { $0.id == favorite } }
        try app.screenshot("work-favorites")
        try app.dispatch(.space(.focus(personal)))
        try app.waitUntil("Personal again") { try app.view().space.id == personal }
        try expect(try !app.view().favorites.tiles.contains { $0.id == favorite }, "Work's favorite shows in the Personal space")
        try app.screenshot("personal-favorites")
        let probe = app.site.url("cookie.html?personal-probe")
        let personalProbe = try app.load(probe)
        try app.waitForPageInput(PageID(window: app.window!, item: personalProbe), at: probe)
        try app.waitUntil("Personal cookie jar read") { try row(app, personalProbe)?.title.hasPrefix("cookie:") == true }
        let personalCookies = try row(app, personalProbe)?.title ?? ""
        try expect(personalCookies == "cookie:", "Personal reads Work's favorite cookie: \(personalCookies)")
        app.passed("Favorites are per profile: Work's favorite is shown in Work only and its cookie stays in Work's jar")

        // Archive time: Work archives idle tabs after 1 hour, Personal after 24 hours.
        try app.dispatch(.settings(.profile(work, .autoArchive(.oneHour))))
        try app.dispatch(.settings(.profile(.default, .autoArchive(.twentyFourHours))))
        try app.dispatch(.space(.focus(workSpace)))
        try app.waitUntil("Work for the archive check") { try app.view().space.id == workSpace }
        let workIdle = try app.load(app.site.url("page2.html?work-idle"))
        _ = try app.load(app.site.url("index.html?work-front"))
        try app.dispatch(.space(.focus(personal)))
        try app.waitUntil("Personal for the archive check") { try app.view().space.id == personal }
        let personalIdle = try app.load(app.site.url("page2.html?personal-idle"))
        _ = try app.load(app.site.url("index.html?personal-front"))
        _ = try app.advanceClock(seconds: 2 * 3600)
        try app.dispatch(.space(.focus(workSpace)))
        try app.waitUntil("Work's idle tab archived after 2 h (Work: 1 hour)") {
            let ids = Set(tabRows(try app.view().space.today.rows).map(\.id))
            return !ids.contains(workIdle)
        }
        try app.dispatch(.space(.focus(personal)))
        try app.waitUntil("Personal shown after 2 h") { try app.view().space.id == personal }
        try expect(tabRows(try app.view().space.today.rows).contains { $0.id == personalIdle }, "Personal's idle tab was archived after 2 h (Personal: 24 hours)")
        _ = try app.advanceClock(seconds: 23 * 3600)
        try app.dispatch(.space(.focus(workSpace)))
        try app.dispatch(.space(.focus(personal)))
        try app.waitUntil("Personal's idle tab archived after 25 h") { try !tabRows(app.view().space.today.rows).contains { $0.id == personalIdle } }
        app.passed("each Space archives idle Today tabs after its own profile's time (Work 1 hour, Personal 24 hours)")

        // Restart: the Space comes back with its own profile's settings still in force.
        try app.flush(); try app.restart()
        try app.dispatch(.space(.focus(workSpace)))
        try app.waitUntil("Work after restart") { try app.view().space.id == workSpace && app.view().urlPill.profile?.name == "Work Settings" }
        try expect(try app.view().favorites.tiles.contains { $0.id == favorite }, "Work's favorite is gone after restart")
        _ = try search("after restart", expect: "red.html")
        app.note("Engines are site searches on the fixture site (Personal → page2.html, Work → red.html) so the check never leaves the machine; archive time runs on the app's test clock.")
    }
}
