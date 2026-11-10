import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// R4-10: the page and site defects the R4-7 review found (A049, A093) and the evidence it was short of.
enum PageSiteFixScenarios {
    static let all = [
        Scenario("OpenerTab", "window.open(url) without features opens a tab that keeps window.opener and reports back; noopener and target=_blank tabs have none", cefOnly: "CEF popup browsing contexts", openerTab),
        Scenario("HistoryRestore", "the History tab Cmd+Y opened comes back after quitting and relaunching, still the native History page", historyRestore),
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

        // The opener closes the window it opened: the row goes (Arc, Q12), the opener stays in front.
        try app.dispatch(.tab(.focus(page.item)))
        try app.waitForPageInput(page, at: app.site.url("page-browsing.html"))
        try app.evaluate(page, "child.close();document.title='closed-child'")
        try app.waitUntil("child.close() from the opener closes the tab's page and its row") {
            let entries = try app.pageLog().filter { $0.page == childPage }
            return try entries.contains { $0.kind == .closed } && !entries.contains { $0.kind == .closeRequested } && row(app, child.id) == nil
        }
        try expect(try currentTab(app.view())?.id == page.item, "the opener is not in front after child.close()")
        try expect(try archived(app).contains { $0 == child.url }, "child.close() did not archive the row")
        app.passed("child.close() from the opener removes the row and leaves it in the archive")

        // A sign-in style tab reports to its opener and closes itself (Q12): Today is back to what it was, the opener in front.
        let rows = try app.view().space.today.rows.count
        try PageBrowsingScenarios.clicked(app, page, "window.selfCloser=window.open('popup-child.html?selfclose');document.title='opened-self-closer'")
        var signIn: TabRow?
        try app.waitUntil("the self-closing tab in front", timeout: 12) {
            signIn = currentTab(try app.view())
            return signIn?.url == app.site.url("popup-child.html?selfclose") && signIn?.title.hasPrefix("child:") == true
        }
        guard let signIn else { throw Check(description: "no self-closing tab") }
        // A more recently used tab must not take over from the opener.
        guard let other = tabRows(try app.view().space.today.rows).first(where: { $0.id != page.item && $0.id != signIn.id }) else { throw Check(description: "no other tab") }
        try app.dispatch(.tab(.focus(other.id)))
        try app.dispatch(.tab(.focus(signIn.id)))
        let signInPage = PageID(window: page.window, item: signIn.id)
        try app.waitForPageInput(signInPage, at: app.site.url("popup-child.html?selfclose"))
        try app.screenshot("self-closing-tab")
        try expect(try app.view().space.today.rows.count == rows + 1, "the tab did not add a row")
        try app.evaluate(signInPage, "window.opener.postMessage({kind:'popup-report',value:{signedIn:'token-43'}},location.origin);window.close()")
        try app.waitUntil("the tab's own window.close() removes its row") { try row(app, signIn.id) == nil }
        try app.waitUntil("the opener in front") { try currentTab(app.view())?.id == page.item }
        try expect(try app.view().space.today.rows.count == rows, "Today did not return to \(rows) rows")
        try app.waitForPageInput(page, at: app.site.url("page-browsing.html"))
        try app.waitUntil("the message reached the opener") { try PageBrowsingScenarios.title(app, page) == "popup:{\"signedIn\":\"token-43\"}" }
        try app.screenshot("self-closed")
        app.passed("the tab's window.close(): Today back to \(rows) rows, focus on the opener, not on the more recent \(other.title)")

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
        // With its opener gone a tab that closes itself follows the close rule (the most recent other tab).
        try app.dispatch(.tab(.focus(blank.id)))
        try app.dispatch(.tab(.focus(noopener.id)))
        let noopenerPage = PageID(window: page.window, item: noopener.id)
        try app.waitForPageInput(noopenerPage, at: app.site.url("popup-child.html?noopener"))
        try app.evaluate(noopenerPage, "window.close()")
        try app.waitUntil("the orphan's window.close() removes its row") { try row(app, noopener.id) == nil }
        try app.waitUntil("the most recent other tab in front") { try currentTab(app.view())?.id == blank.id }
        try app.flush(); try app.restart()
        try app.waitUntil("the opened tab restored") { try allTabs(app.view()).contains { $0.url == app.site.url("popup-child.html?blank") } }
        app.note("CEF creates the popup browser (on_before_popup allowed, OnPopupBrowserViewCreated places its view in a frameless host window) and Brk embeds it as the tab's page instead of creating a new browser; Chromium's own opener and noopener rules apply.")
    }

    /// The addresses in the Library's archive.
    static func archived(_ app: AppUnderTest) throws -> [URL?] {
        try app.dispatch(.library(.open(.archive)))
        defer { try? app.dispatch(.library(.close)) }
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no Library") }
        return library.archive?.groups.flatMap(\.entries).map(\.url) ?? []
    }

    // MARK: EaselShareTypedTitle (A101)


    // MARK: SiteFilters-realsite (A109)


    // MARK: PageDOMClean (out-of-group finding)


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

    static func focused(_ app: AppUnderTest, _ owner: WindowID, _ field: String) throws -> Bool {
        if case .failed = try app.send(.siteControlInput(window: owner, field: field, action: .locate)) {
            try app.perform(.siteControlInput(window: owner, field: "siteSettingsDetails", action: .press))
        }
        guard case .menuItems(let values) = try app.send(.siteControlInput(window: owner, field: field, action: .locate)), values.count == 7 else { return false }
        return values[4] == "focused:true"
    }
    static func fieldValue(_ app: AppUnderTest, _ owner: WindowID, _ field: String) throws -> String? {
        guard case .menuItems(let values) = try app.send(.siteControlInput(window: owner, field: field, action: .locate)), values.count == 7 else { return nil }
        return String(values[6].dropFirst("value:".count))
    }

    /// Whether the extension command's key cap is recording (it then says Type Shortcut…).
    static func isRecording(_ app: AppUnderTest, owner: WindowID, _ field: String) throws -> Bool {
        try fieldValue(app, owner, field) == "Type Shortcut…"
    }



    // MARK: ATC-routes (A111)




    // MARK: SoundCues-recorded (A106)


    // MARK: WebSubstitutionsTyping (A046)


    // MARK: ProfileSettingsApplied (A093)

}
