import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum SitePolicyScenarios {
    static let all = [
        Scenario("SitePolicy-appearance", "website appearance uses native dark CSS, keeps light-only pages readable, and survives restart", appearance),
        Scenario("SitePolicy-clear", "origin cookies and storage clear while another origin and profile survive restart", clearData),
        Scenario("SitePolicy-blocking", "network/cosmetic blocking and per-site exceptions", blocking),
    ]

    static func controls(_ app: AppUnderTest) throws -> SiteControlSnapshot {
        guard case .siteControls(let values) = try app.send(.siteControls), let value = values[app.window!] else { throw Check(description: "site controls missing") }
        return value
    }
    static func evaluate(_ app: AppUnderTest, _ item: ItemID, _ script: String) throws {
        try app.perform(.evaluate(page: PageID(window: app.window!, item: item), script: script))
    }
    static func report(_ app: AppUnderTest, _ item: ItemID) throws -> [String: Any] {
        try evaluate(app, item, "reportPolicy()")
        var value: [String: Any] = [:]
        try app.waitUntil("policy DOM report") {
            guard let title = tab(item, in: try app.view())?.title, title.hasPrefix("policy:"),
                  let data = String(title.dropFirst(7)).data(using: .utf8), let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            value = result; return true
        }
        return value
    }
    @Sendable static func appearance(_ app: AppUnderTest) throws {
        let lightOnly = try app.load(app.site.url("appearance.html"))
        try waitForTitle(app, lightOnly, "Appearance:light")
        try app.dispatch(.site(.appearance(.dark)))
        try waitForTitle(app, lightOnly, "Appearance:dark")
        try app.dispatch(.site(.controls))
        try app.waitUntil("dark website policy applied") { try controls(app).applied?.appearance == .dark }
        try app.dispatch(.site(.closeControls))
        let area = try app.native().computed.contentArea
        let sample = CGPoint(x: area.minX + 40, y: area.minY + 40)
        try app.waitUntil("light-only page keeps its white canvas in Dark appearance") {
            try app.pixel(sample).prefix(3).allSatisfy { $0 > 240 }
        }
        try app.screenshot("light-only-in-dark")
        let nativeDark = try app.load(app.site.url("appearance.html?native"))
        try waitForTitle(app, nativeDark, "Appearance:dark")
        try app.dispatch(.site(.controls))
        try app.waitUntil("native dark website policy applied") { try controls(app).applied?.appearance == .dark }
        try app.dispatch(.site(.closeControls))
        try app.waitUntil("native dark page paints its own dark canvas") {
            try app.pixel(sample).prefix(3).allSatisfy { $0 < 60 }
        }
        try app.screenshot("native-dark")
        try app.dispatch(.site(.appearance(.light)))
        let item = try app.load(app.site.url("site-policy.html"))
        try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        try app.waitUntil("origin-bound site controls") { try controls(app).target != nil }
        _ = try app.screenshotSiteControls("controls")
        try app.dispatch(.site(.appearance(.dark)))
        try app.waitUntil("dark website CSS") { try report(app, item)["dark"] as? Bool == true }
        try app.dispatch(.site(.appearance(.light)))
        try app.waitUntil("light website CSS") { try report(app, item)["dark"] as? Bool == false }
        try app.dispatch(.settings(.advanced(.themeToCSS(true))))
        try app.waitUntil("theme CSS is injected") { try (report(app, item)["css"] as? String)?.hasPrefix("rgb(") == true }
        try app.dispatch(.settings(.advanced(.themeToCSS(false))))
        try app.waitUntil("theme CSS opt-out removes Brk variables") { try report(app, item)["css"] as? String == "" }
        try expect(try report(app, item)["pageStyle"] as? String == "keep", "Brk overwrote the page's pre-existing style element")
        try app.dispatch(.site(.closeControls))
        try app.flush(); try app.restart()
        try app.waitUntil("restored light website CSS") { try report(app, item)["dark"] as? Bool == false }
        try app.dispatch(.site(.appearance(.automatic)))
        try app.perform(.setAppAppearance(.dark))
        try app.waitUntil("automatic appearance follows native dark appearance") { try report(app, item)["dark"] as? Bool == true }
        try app.perform(.setAppAppearance(.light))
        try app.waitUntil("automatic appearance follows native light appearance") { try report(app, item)["dark"] as? Bool == false }
        try app.perform(.setAppAppearance(nil))
        app.note("Actual matchMedia changes dark→light, CSS variable appears and is removed, and profile appearance survives restart. No system-wide appearance change was made.")
    }

    static func seed(_ app: AppUnderTest, _ item: ItemID, _ value: String) throws {
        try evaluate(app, item, "seedSite('\(value)').catch(e=>document.title='seed-error:'+e.message)")
        try waitForTitle(app, item, "seed:" + value)
    }
    static func storage(_ app: AppUnderTest, _ item: ItemID) throws -> [String: Any] {
        try evaluate(app, item, "readSite()")
        var value: [String: Any] = [:]
        try app.waitUntil("storage readback") {
            guard let title = tab(item, in: try app.view())?.title, title.hasPrefix("storage:"), let data = String(title.dropFirst(8)).data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            value = result; return true
        }
        return value
    }
    @Sendable static func clearData(_ app: AppUnderTest) throws {
        let a = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, a, "Site policy fixture")
        try seed(app, a, "A")
        let otherURL = URL(string: app.site.url("site-policy.html").absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost"))!
        let b = try app.load(otherURL); try waitForTitle(app, b, "Site policy fixture"); try seed(app, b, "B")
        try app.dispatch(.profile(.create(name: "Site Work", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let profile = settings.profiles.first(where: { $0.profile.name == "Site Work" })?.profile.id else { throw Check(description: "profile missing") }
        try app.dispatch(.profile(.assign(.current, to: profile)))
        try app.dispatch(.tab(.focus(a))); try waitForTitle(app, a, "Site policy fixture"); try seed(app, a, "C")
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try waitForTitle(app, a, "Site policy fixture")
        try expect(try storage(app, a)["local"] as? String == "A", "default profile lost its original storage")
        try app.dispatch(.site(.clear(kinds: [.cookies, .storage, .history], scope: .site, reload: true)))
        try app.click(.settingsField("confirmSiteClear"))
        try app.waitUntil("clear-data native completion", timeout: 15) {
            guard let result = try controls(app).result else { return false }
            try expect(result.error == nil, result.error ?? "")
            return result.completed == [.cookies, .storage, .history]
        }
        try app.waitUntil("cleared page reload") { try controls(app).target != nil }
        let cleared = try storage(app, a)
        try expect(cleared["local"] is NSNull && cleared["idb"] as? Bool == false && cleared["cache"] as? Bool == false && cleared["worker"] as? Bool == false, "origin storage remains: \(cleared)")
        try expect((cleared["cookie"] as? String)?.contains("sitefixture") == false, "site cookie remains")
        try expect((cleared["serverCookie"] as? String)?.contains("httponlyfixture") == false, "HttpOnly cookie remains")
        try evaluate(app, a, "(()=>{const f=document.createElement('iframe');f.src='/nested/probe.html';f.onload=()=>{document.title='nested:'+f.contentDocument.cookie;f.remove()};document.body.append(f)})()")
        try app.waitUntil("all-path cookie removal") {
            let title = tab(a, in: try app.view())?.title ?? ""
            return title.hasPrefix("nested:") && !title.contains("pathfixture")
        }
        try app.dispatch(.site(.closeControls)); try app.dispatch(.tab(.focus(b)))
        let otherOrigin = try storage(app, b)
        try expect(otherOrigin["local"] as? String == "B" && otherOrigin["idb"] as? Bool == true && otherOrigin["cache"] as? Bool == true && otherOrigin["worker"] as? Bool == true, "unrelated origin storage was cleared")
        try expect((otherOrigin["serverCookie"] as? String)?.contains("httponlyfixture=B") == true, "unrelated origin HttpOnly cookie was cleared")
        try app.dispatch(.profile(.assign(.current, to: profile))); try app.dispatch(.tab(.focus(a)))
        try waitForTitle(app, a, "Site policy fixture")
        let otherProfile = try storage(app, a)
        try expect(otherProfile["local"] as? String == "C" && otherProfile["idb"] as? Bool == true && otherProfile["cache"] as? Bool == true && otherProfile["worker"] as? Bool == true, "unrelated profile storage was cleared")
        try expect((otherProfile["serverCookie"] as? String)?.contains("httponlyfixture=C") == true, "unrelated profile HttpOnly cookie was cleared")
        try app.dispatch(.profile(.assign(.current, to: .default))); try app.flush(); try app.restart()
        try app.waitUntil("cleared default origin restored") { try currentTab(app.view())?.title == "Site policy fixture" }
        try expect(try storage(app, a)["local"] is NSNull, "cleared localStorage returned after restart")
        app.note("Actual cookies/localStorage/IndexedDB/Cache Storage were seeded and read. Other origin B and profile C survive. Default origin stays cleared after restart.")
    }

    @Sendable static func blocking(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, item, "Site policy fixture")
        try app.dispatch(.site(.controls))
        guard let target = try controls(app).target else { throw Check(description: "target missing") }
        try app.waitUntil("asynchronous cosmetic rule application") { try report(app, item)["ad"] as? String == "none" }
        let before = app.site.requestCount("/brk-blocked-tracker/tracker.js")
        try evaluate(app, item, "fetch('/brk-blocked-tracker/tracker.js').then(()=>document.title='network:allowed').catch(()=>document.title='network:blocked')")
        try waitForTitle(app, item, "network:blocked")
        try expect(app.site.requestCount("/brk-blocked-tracker/tracker.js") == before, "blocked request reached fixture server")
        var rule = SiteRule(); rule.blocking = false; rule.hideCookieBanners = true
        try app.dispatch(.site(.rule(target, rule)))
        try app.waitUntil("cosmetic opt-out and independent banner rule") {
            let dom = try report(app, item)
            return dom["ad"] as? String != "none" && dom["banner"] as? String == "none" && dom["normal"] as? String != "none"
        }
        try evaluate(app, item, "fetch('/brk-blocked-tracker/tracker.js').then(()=>document.title='network:allowed')")
        try waitForTitle(app, item, "network:allowed")
        try expect(app.site.requestCount("/brk-blocked-tracker/tracker.js") == before + 1, "site exception did not reach the network")
        try app.dispatch(.site(.closeControls))
        _ = try app.screenshot("SitePolicy-blocking")
        app.note("Blocked request produces a rejected fetch and zero server hits. The per-origin exception sends one real request. Cosmetic and banner rules have separate DOM readback.")
    }

}
