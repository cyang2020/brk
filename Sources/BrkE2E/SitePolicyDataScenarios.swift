import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum SitePolicyDataScenarios {
    static let all = [
        Scenario("SitePolicy-rule-update", "selected rule files update actual requests and cosmetics; invalid updates preserve the last valid rules", cefOnly: "CEF request filtering", ruleUpdate),
        Scenario("SitePolicy-domain-cookies", "clearing host cookies includes shared domain cookies and preserves a sibling's host cookies", cefOnly: "domain cookies", domainCookies),
    ]
    @Sendable static func ruleUpdate(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        let files = app.site.root.deletingLastPathComponent().appendingPathComponent("Fixtures")
        try app.dispatch(.site(.selectedBlockingRules(files.appendingPathComponent("site-rules-v2.json"), .profile(.default))))
        try app.waitUntil("the selected rules file is applied") { try SitePolicyScenarios.controls(app).rulesVersion == 2 }
        let before = app.site.requestCount("/site-policy-update-test/asset")
        try SitePolicyScenarios.evaluate(app, item, "fetch('/site-policy-update-test/asset').then(()=>document.title='update:allowed').catch(()=>document.title='update:blocked')")
        try waitForTitle(app, item, "update:blocked")
        try expect(app.site.requestCount("/site-policy-update-test/asset") == before, "updated network rule did not block the actual request")
        try SitePolicyScenarios.evaluate(app, item, "document.title='cosmetic-update:'+getComputedStyle(document.getElementById('sponsor')).display")
        try waitForTitle(app, item, "cosmetic-update:none")
        try app.dispatch(.site(.selectedBlockingRules(files.appendingPathComponent("site-rules-invalid.json"), .profile(.default))))
        try app.waitUntil("invalid update reports an error") { try SitePolicyScenarios.controls(app).rulesError != nil }
        try expect(try SitePolicyScenarios.controls(app).rulesVersion == 2, "invalid update replaced the working list")
        try app.dispatch(.site(.closeControls)); try app.flush(); try app.restart()
        try app.dispatch(.site(.controls))
        try expect(try SitePolicyScenarios.controls(app).rulesVersion == 2, "rules did not survive restart")
        try app.dispatch(.site(.resetBlockingRules))
        try SitePolicyScenarios.evaluate(app, item, "fetch('/site-policy-update-test/asset').then(()=>document.title='update:restored')")
        try waitForTitle(app, item, "update:restored")
        try expect(app.site.requestCount("/site-policy-update-test/asset") == before + 1, "restoring built-in rules did not restore the request")
        try app.dispatch(.site(.closeControls))
        app.note("The explicitly selected JSON file changed real network and DOM behavior. Invalid JSON kept v2, v2 survived restart, and restoring built-ins restored the request. The OS file-selection gesture is separate from this selected-fixture path.")
    }
    @Sendable static func domainCookies(_ app: AppUnderTest) throws {
        func address(_ host: String) -> URL { URL(string: app.site.url("site-policy.html").absoluteString.replacingOccurrences(of: "127.0.0.1", with: host))! }
        let b = try app.load(address("b.brk.test"))
        try waitForTitle(app, b, "Site policy fixture")
        try SitePolicyScenarios.evaluate(app, b, "fetch('/site-policy-cookie-seed?value=B').then(()=>document.title='domain:B')")
        try waitForTitle(app, b, "domain:B")
        let a = try app.load(address("a.brk.test"))
        try waitForTitle(app, a, "Site policy fixture")
        try SitePolicyScenarios.evaluate(app, a, "fetch('/site-policy-cookie-seed?value=shared').then(()=>document.title='domain:'+document.cookie)")
        try app.waitUntil("a real shared domain cookie") { try currentTab(app.view())?.title.contains("domainfixture=shared") == true }
        try app.dispatch(.site(.clear(kinds: [.cookies], scope: .site, reload: true)))
        try app.click(.settingsField("confirmSiteClear"))
        try app.waitUntil("domain-cookie removal completion") {
            guard let result = try SitePolicyScenarios.controls(app).result else { return false }
            try expect(result.error == nil, result.error ?? ""); return result.completed == [.cookies]
        }
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(b)))
        try SitePolicyScenarios.evaluate(app, b, "fetch('/site-policy-cookie-read').then(x=>x.json()).then(x=>document.title='sibling:'+x.cookie)")
        try app.waitUntil("the sibling's real cookie header") {
            let title = currentTab(try app.view())?.title ?? ""
            return title.hasPrefix("sibling:") && title.contains("httponlyfixture=B") && !title.contains("domainfixture")
        }
        app.note("Loopback *.brk.test fixture names are mapped only in control-test mode. The shared Domain=brk.test cookie was removed, while b.brk.test's HttpOnly host cookie survived.")
    }
}
