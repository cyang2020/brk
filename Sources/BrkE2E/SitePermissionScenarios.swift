import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// Brk's own permission prompt for a request macOS has no authorization for (window management): the three
/// answers, what is remembered, and that Chromium's stored grant follows Brk's choice (Allow this time asks again on
/// the next document; a site setting changed back to Ask clears a block).
enum SitePermissionScenarios {
    static let all = [
        Scenario("SitePermission-prompt", "Brk's prompt: Allow this time, Never allow, remembered denial, back to Ask, Allow while visiting",
                 cefOnly: "CEF permission callbacks", prompt),
    ]

    @Sendable static func prompt(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("site-permissions.html")); try waitForTitle(app, item, "Site permissions fixture")
        guard let owner = app.window else { throw Check(description: "window missing") }
        func press(_ button: String) throws {
            let card = try app.native().computed.cards[0].rect
            try app.click(at: CGPoint(x: card.minX + 130, y: card.minY + 60))
        }
        func texts() -> [String]? {
            if case .menuItems(let texts)? = try? app.send(.sitePrompt(window: owner, path: nil)) { return texts }
            return nil
        }
        /// Clicks one of the prompt's answers once the popover has settled on screen.
        func answer(_ field: String) throws {
            app.sleep(0.4)
            try app.click(.settingsField(field))
        }
        func reload() throws {
            try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
            try app.waitForPageInput(PageID(window: owner, item: item), at: app.site.url("site-permissions.html"))
        }
        func remembered(_ capability: SiteCapability) throws -> SitePermission? {
            try app.dispatch(.site(.controls))
            defer { try? app.dispatch(.site(.closeControls)) }
            return try SitePolicyScenarios.controls(app).rule.permissions[capability]
        }
        let site = "127.0.0.1:\(app.site.port) wants to"

        try press("screens")
        try app.waitUntil("Brk's prompt asks for window management") { texts()?.contains("Manage windows on all your displays") == true }
        try expect(texts()?.contains(site) == true && texts()?.contains("Allow while visiting the site") == true
                   && texts()?.contains("Allow this time") == true && texts()?.contains("Never allow") == true, "prompt texts \(texts() ?? [])")
        _ = try app.send(.sitePrompt(window: owner, path: app.shotsDirectory.appendingPathComponent("SitePermission-prompt-ask.png").path))
        try answer("sitePermissionAllowOnce")
        try waitForTitle(app, item, "screens:granted")
        try expect(try remembered(.windowManagement) == nil, "Allow this time was remembered")

        try reload()
        try press("screens")
        try app.waitUntil("the next document asks again") { texts()?.contains("Manage windows on all your displays") == true }
        try answer("sitePermissionDeny")
        try waitForTitle(app, item, "screens:denied:NotAllowedError")
        try expect(try remembered(.windowManagement) == .deny, "Never allow was not remembered")
        try press("screens")
        try waitForTitle(app, item, "screens:denied:NotAllowedError")
        app.sleep(0.5)
        try expect(texts() == nil, "a remembered denial prompted again")

        try app.dispatch(.site(.controls))
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "site target missing") }
        var rule = try SitePolicyScenarios.controls(app).rule
        rule.permissions[.windowManagement] = .ask
        try app.dispatch(.site(.rule(target, rule)))
        try app.dispatch(.site(.closeControls))
        try press("screens")
        try app.waitUntil("back to Ask: Chromium's block was cleared and Brk asks") { texts()?.contains("Manage windows on all your displays") == true }
        try app.press("escape")
        try waitForTitle(app, item, "screens:denied:NotAllowedError")
        try app.waitUntil("Escape closes the prompt") { texts() == nil }
        try expect(try remembered(.windowManagement) == .ask, "closing the prompt decided something")

        try press("screens")
        try app.waitUntil("Brk asks once more") { texts()?.contains("Manage windows on all your displays") == true }
        try answer("sitePermissionAllow")
        try waitForTitle(app, item, "screens:granted")
        try expect(try remembered(.windowManagement) == .allow, "Allow while visiting the site was not remembered")
        try reload()
        try press("screens")
        try waitForTitle(app, item, "screens:granted")
        app.sleep(0.5)
        try expect(texts() == nil, "a remembered allow prompted again")
        app.note("Window management has no macOS authorization, so Brk's prompt is the only question. Allow this time granted once and asked again after reload; Never allow was remembered and answered without a prompt; setting the site back to Ask cleared Chromium's stored block; Escape closed the prompt without deciding; Allow while visiting the site was remembered across a reload. Camera, microphone, location and notifications additionally need macOS authorization, which only macOS can ask for (not driven here).")
    }
}
