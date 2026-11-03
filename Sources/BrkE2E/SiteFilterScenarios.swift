import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// EasyList-syntax filter lists on the real engine: a list chosen through the real open panel, the two subscriptions
/// downloaded from the fixture site (the harness points `BRK_TEST_FILTER_BASE` at `Tests/E2ESite/filter-lists`), the
/// off switch, and a download with no server behind it.
enum SiteFilterScenarios {
    static let all = [
        Scenario("SiteFilters-panel", "a list chosen in the real open panel blocks, excepts, ignores third-party and hides",
                 cefOnly: "CEF request filtering", panel),
        Scenario("SiteFilters-subscriptions", "EasyList and EasyPrivacy download on the clock, apply, stop when updates are off, resume on Update now",
                 cefOnly: "CEF request filtering", subscriptions),
        Scenario("SiteFilters-offline", "a download with no server is offline, not an error, and the built-in rules keep working",
                 cefOnly: "CEF request filtering", offline),
    ]

    static func lists(_ app: AppUnderTest) throws -> [FilterListRecord] { try SitePolicyScenarios.controls(app).filterLists }

    /// Adds `<script>` and `<img>` requests and two marker elements to the page.
    static func inject(_ app: AppUnderTest, _ item: ItemID, scripts: [String], images: [String] = [], elements: [String] = []) throws {
        let script = "for(const src of \(json(scripts))){const s=document.createElement('script');s.src=src;document.head.append(s)}"
            + "for(const src of \(json(images))){const i=document.createElement('img');i.src=src;document.body.append(i)}"
            + "for(const name of \(json(elements))){const e=document.createElement('div');e.className=name;e.textContent=name;document.body.append(e)}"
        try SitePolicyScenarios.evaluate(app, item, script)
    }
    static func display(_ app: AppUnderTest, _ item: ItemID, _ selector: String) throws -> String {
        try SitePolicyScenarios.evaluate(app, item, "document.title='display:'+getComputedStyle(document.querySelector(\(ExtScenarios.js(selector)))).display")
        app.sleep(0.2)
        return String((try tab(item, in: app.view())?.title ?? "").dropFirst("display:".count))
    }
    static func json(_ values: [String]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: values), as: UTF8.self) }

    @Sendable static func panel(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        let file = app.dataDirectory.appendingPathComponent("panel-filters.txt")
        try Data("""
        [Adblock Plus 2.0]
        ! Title: Panel fixture list
        /brk-filter/panel-block.js$script
        @@/brk-filter/panel-block.js?allowed$script
        ||filter.brk.test^$third-party
        ##.brk-panel-ad
        example.com##+js(set, x, 1)

        """.utf8).write(to: file)
        try app.dispatch(.site(.controls))
        try ExtScenarios.control(app, "siteImportRules", .press)
        try app.waitUntil("the real open panel is attached") { try app.native().sheetClass == "NSOpenPanel" }
        try ImportSyncScenarios.panel(app, .open(path: file.path))
        try app.waitUntil("the chosen file is the profile's imported list") {
            try lists(app).contains { list in
                guard list.id == FilterListRecord.importedID, let summary = list.summary else { return false }
                return list.title == "Panel fixture list" && summary.networkFilters == 2 && summary.exceptionFilters == 1 && summary.hidingRules == 1 && summary.skipped == 1
            }
        }
        _ = try app.screenshotSiteControls("imported")
        try app.dispatch(.site(.closeControls))
        try inject(app, item, scripts: [], elements: ["brk-panel-ad"])
        try app.waitUntil("element hiding from the chosen list") { try display(app, item, ".brk-panel-ad") == "none" }
        let third = "http://filter.brk.test:\(app.site.port)/brk-filter/panel-third.gif"
        try inject(app, item, scripts: ["/brk-filter/panel-block.js", "/brk-filter/panel-block.js?allowed", "/brk-filter/panel-control.js"], images: [third])
        try app.waitUntil("the positive control reached the server") { app.site.requestCount("/brk-filter/panel-control.js") == 1 }
        app.sleep(0.5)
        try expect(app.site.requestCount("/brk-filter/panel-block.js") == 1, "expected only the @@-excepted copy of panel-block.js to load, got \(app.site.requestCount("/brk-filter/panel-block.js"))")
        try expect(app.site.requestCount("/brk-filter/panel-third.gif") == 0, "the third-party request reached the server")
        app.note("REAL PANEL: Import blocking rules… opened NSOpenPanel and the file was chosen by AX selection and Open. The list's $script filter blocked, its @@ exception let the ?allowed copy through, $third-party blocked filter.brk.test from a 127.0.0.1 page, ## hid the marker, and the scriptlet line was counted as skipped.")
    }

    @Sendable static func subscriptions(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        try expect(try lists(app).map(\.id) == ["easylist", "easyprivacy"] && lists(app).allSatisfy { $0.key == nil }, "the subscriptions start not downloaded")
        _ = try app.send(.advanceClock(seconds: 1))
        try app.waitUntil("both subscriptions downloaded on the clock", timeout: 15) { try lists(app).allSatisfy { $0.key != nil && $0.problem == nil } }
        try expect(app.site.requestCount("/filter-lists/easylist.txt") == 1 && app.site.requestCount("/filter-lists/easyprivacy.txt") == 1, "one download each")
        let easyList = try XCTUnwrapped(try lists(app).first { $0.id == "easylist" }?.summary, "EasyList summary")
        try expect(easyList.title == "EasyList (Brk fixture)" && easyList.networkFilters == 1 && easyList.exceptionFilters == 2 && easyList.hidingRules == 2 && easyList.skipped == 1 && easyList.expiresHours == 96,
                   "EasyList summary \(easyList)")
        try app.dispatch(.site(.closeControls))

        try inject(app, item, scripts: [], elements: ["brk-easylist-ad", "brk-easylist-kept"])
        try app.waitUntil("element hiding from the downloaded list") { try display(app, item, ".brk-easylist-ad") == "none" }
        try expect(try display(app, item, ".brk-easylist-kept") != "none", "the 127.0.0.1#@# exception did not keep its element")
        let tracker = "http://tracker.brk.test:\(app.site.port)/brk-filter/tracker.gif"
        try inject(app, item, scripts: ["/brk-filter/easylist-ad.js", "/brk-filter/easylist-ad.js?allowed", "/brk-filter/easylist-control.js"], images: [tracker])
        try app.waitUntil("the positive control reached the server") { app.site.requestCount("/brk-filter/easylist-control.js") == 1 }
        app.sleep(0.5)
        try expect(app.site.requestCount("/brk-filter/easylist-ad.js") == 1, "expected only the excepted easylist-ad.js to load")
        try expect(app.site.requestCount("/brk-filter/tracker.gif") == 0, "EasyPrivacy's third-party tracker reached the server")

        // Updates off through the site settings checkbox: five days later nothing is fetched.
        try app.dispatch(.site(.controls))
        try ExtScenarios.control(app, "filterUpdates", .press)
        try app.waitUntil("updates are off") { try SitePolicyScenarios.controls(app).filterUpdates == false }
        _ = try app.send(.advanceClock(seconds: 5 * 24 * 3600))
        app.sleep(1.5)
        try expect(app.site.requestCount("/filter-lists/easylist.txt") == 1, "a download happened with updates off")
        _ = try app.screenshotSiteControls("updates-off")
        // On again: both lists are past their four days and download at once; then Update now fetches again.
        try ExtScenarios.control(app, "filterUpdates", .press)
        try app.waitUntil("turning updates on fetches the expired lists", timeout: 15) {
            app.site.requestCount("/filter-lists/easylist.txt") == 2 && app.site.requestCount("/filter-lists/easyprivacy.txt") == 2
        }
        try ExtScenarios.control(app, "filterUpdateNow", .press)
        try app.waitUntil("Update now fetches again", timeout: 15) { app.site.requestCount("/filter-lists/easylist.txt") == 3 }
        try app.waitUntil("unchanged text keeps the same copy") { try lists(app).allSatisfy { $0.key != nil && $0.problem == nil && $0.offline == nil } }
        _ = try app.screenshotSiteControls("subscriptions")
        app.note("Downloads came from the fixture site's filter-lists/ (BRK_TEST_FILTER_BASE), never from easylist.to. The Download list updates checkbox stopped scheduled downloads; turning it on and Update now fetched again.")
    }

    @Sendable static func offline(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        _ = try app.send(.advanceClock(seconds: 1))
        try app.waitUntil("the downloads find no server", timeout: 20) { try lists(app).allSatisfy { $0.offline == true && $0.problem == nil && $0.key == nil } }
        try expect(try SitePolicyScenarios.controls(app).rulesError == nil, "offline was reported as a rules error")
        let first = try lists(app).compactMap(\.checked)
        try ExtScenarios.control(app, "siteSettingsDetails", .press)
        var seen: [String] = []
        do {
            try app.waitUntil("the second page says there is no network") {
                guard case .menuItems(let texts) = try app.send(.siteControlTexts(window: app.window!)) else { return false }
                seen = texts
                return texts.filter { $0 == "Not downloaded yet; no network connection" }.count >= 2
            }
        } catch { throw Check(description: "\(error); the panel showed \(seen)") }
        _ = try app.screenshotSiteControls("offline")
        _ = try app.send(.advanceClock(seconds: 3601))
        try app.waitUntil("an hour later Brk tries again", timeout: 20) {
            let checked = try lists(app).compactMap(\.checked)
            return try checked.count == 2 && zip(checked, first).allSatisfy { $0 > $1 } && lists(app).allSatisfy { $0.offline == true }
        }
        try app.dispatch(.site(.closeControls))
        let blocked = "/brk-blocked-tracker/offline.js"
        try inject(app, item, scripts: [blocked, "/brk-filter/offline-control.js"])
        try app.waitUntil("the positive control reached the server") { app.site.requestCount("/brk-filter/offline-control.js") == 1 }
        app.sleep(0.5)
        try expect(app.site.requestCount(blocked) == 0, "the built-in rules stopped blocking while offline")
        app.note("BRK_TEST_FILTER_BASE pointed at 127.0.0.1:9, which refuses connections: both lists read offline with no problem text and no rules error, retried an hour later, and the built-in path rule kept blocking.")
    }
}

func XCTUnwrapped<T>(_ value: T?, _ what: String) throws -> T {
    guard let value else { throw Check(description: what + " missing") }
    return value
}
