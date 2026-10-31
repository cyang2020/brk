import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

enum SitePolicyBehaviorScenarios {
    static let all = [
        Scenario("SitePolicy-permission", "native permission denial reports the real origin and resolves the page request", cefOnly: "CEF permission callbacks", permission),
        Scenario("SitePolicy-scheduling", "hidden-site suspension stops network ticks and keep-alive resumes scheduling", cefOnly: "Chromium page lifecycle", scheduling),
        Scenario("SitePolicy-cache", "HTTP cache deletion waits for completion and leaves cookies intact", cefOnly: "HTTP cache", cache),
    ]
    @Sendable static func permission(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try SitePolicyScenarios.evaluate(app, item, "document.querySelector('button').style.cssText='position:fixed;left:20px;top:220px;width:200px;height:40px'")
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + 80, y: card.minY + 240))
        try app.click(.settingsField("sitePermissionDeny"))
        try waitForTitle(app, item, "permission:denied")
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "permission target missing") }
        var rule = SiteRule(); rule.permissions[.notifications] = .deny
        try app.dispatch(.site(.rule(target, rule)))
        try expect(try SitePolicyScenarios.controls(app).rule.permissions[.notifications] == .deny, "permission readback missing")
        try app.dispatch(.site(.closeControls))
        app.note("A real page click requested notifications; Brk's native Deny button resolved the page promise as denied. Camera/microphone/location OS allow paths remain unproven on this host.")
    }
    @Sendable static func scheduling(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "site target missing") }
        var rule = SiteRule(); rule.suspendWhenHidden = true
        try app.dispatch(.site(.rule(target, rule))); try app.dispatch(.site(.closeControls))
        try SitePolicyScenarios.evaluate(app, item, "window.fixtureTick=0;window.fixtureTickTimer=setInterval(()=>fetch('/site-policy-tick?n='+(fixtureTick++),{cache:'no-store'}),100)")
        try app.waitUntil("foreground network ticks") { app.site.requestCount("/site-policy-tick") >= 2 }
        _ = try app.load(app.site.url("page2.html"))
        // native().pages intentionally lists presented surfaces only. Server ticks prove the hidden page's scheduling.
        app.sleep(0.5)
        app.sleep(0.2)
        let before = app.site.requestCount("/site-policy-tick")
        app.sleep(1.6)
        try expect(app.site.requestCount("/site-policy-tick") == before, "network ticks continued while frozen")
        try app.dispatch(.tab(.focus(item)))
        try app.waitUntil("visible page resumes network activity") { app.site.requestCount("/site-policy-tick") > before }
        try app.dispatch(.site(.controls))
        guard let current = try SitePolicyScenarios.controls(app).target else { throw Check(description: "resumed target missing") }
        rule.keepAlive = true
        try app.dispatch(.site(.rule(current, rule))); try app.dispatch(.site(.closeControls))
        _ = try app.load(app.site.url("page2.html"))
        let live = app.site.requestCount("/site-policy-tick")
        try app.waitUntil("hidden keep-alive page sends actual requests", timeout: 4) { app.site.requestCount("/site-policy-tick") > live }
        app.note("Frozen is backed by zero server ticks over 1.2 seconds. Visibility and keep-alive both restore actual network scheduling. PiP/WebAudio cases remain separate.")
    }
    @Sendable static func cache(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        func fetch(_ tag: String) throws {
            try SitePolicyScenarios.evaluate(app, item, "fetch('/site-policy-cache.js').then(x=>x.text()).then(()=>document.title='cache:\(tag)')")
            try waitForTitle(app, item, "cache:" + tag)
        }
        try SitePolicyScenarios.evaluate(app, item, "document.cookie='cachecookie=keep;path=/'")
        let baseline = app.site.requestCount("/site-policy-cache.js")
        try fetch("first"); try fetch("second")
        try expect(app.site.requestCount("/site-policy-cache.js") == baseline + 1, "fixture response did not actually cache")
        try app.dispatch(.profile(.create(name: "Cache Work", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let other = settings.profiles.first(where: { $0.profile.name == "Cache Work" })?.profile.id else { throw Check(description: "cache profile missing") }
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try fetch("other-first")
        try expect(app.site.requestCount("/site-policy-cache.js") == baseline + 2, "profiles shared their HTTP cache")
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try app.dispatch(.site(.clear(kinds: [.cache], scope: .profile, reload: true)))
        try app.click(.settingsField("confirmSiteClear"))
        try app.waitUntil("cache deletion completes") {
            guard let result = try SitePolicyScenarios.controls(app).result else { return false }
            try expect(result.error == nil, result.error ?? ""); return result.completed == [.cache]
        }
        try app.waitUntil("cache clear reload") { try SitePolicyScenarios.controls(app).target != nil }
        try fetch("after")
        try expect(app.site.requestCount("/site-policy-cache.js") == baseline + 3, "cleared cache still served the old response")
        try SitePolicyScenarios.evaluate(app, item, "document.title='cookie-kept:'+document.cookie.includes('cachecookie=keep')")
        try waitForTitle(app, item, "cookie-kept:true")
        try app.dispatch(.site(.closeControls))
        try app.dispatch(.profile(.assign(.current, to: other)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("site-policy.html"))
        try fetch("other-after")
        try expect(app.site.requestCount("/site-policy-cache.js") == baseline + 3, "clearing Default also cleared the other profile's cache")
        app.note("Cache warm-up produced one request in each profile. Clearing Default caused one new Default request and preserved both its cookie and the other profile's cached response.")
    }
}
