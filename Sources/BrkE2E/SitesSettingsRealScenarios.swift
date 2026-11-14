import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// The site controls, Brk's permission prompt and the Settings window the way a person uses them: every click and key
/// goes through the window server (hit testing, tracking areas, AppKit's event monitors and key window), aimed at where
/// Accessibility or the site controls' `locate` says the control is. The control socket only sets up (a page, a
/// seeded cookie, the appearance) and reads state. Each visible part runs in light and in dark, with expected labels
/// read from its picture. Sheet and popover labels also have their pixel contrast checked. The facts checked go to
/// `<id>.txt` beside the pictures.
enum SitesSettingsRealScenarios {
    static let all: [Scenario] = [
        Scenario("SiteControls-Real", "real input: the site button, both switches, the security row and its details, the site switches and a permission picker, Clear cookies with its confirmation, four ways to close, the extensions picker, a permission prompt answered with each button, Escape and a click outside; light and dark",
                 siteControls),
        Scenario("Settings-Real", "real input: Cmd+, opens Settings, each toolbar pane and its controls, the Previews sheet, a shortcut removed from its hover menu and Reset All, an Air Traffic Control route added, used and removed, the red close button, Cmd+W; light and dark",
                 settingsWindow),
    ]

    static func field(_ name: String) -> String { ViewID.settingsField(name).identifier }

    // MARK: Site controls

    @Sendable static func siteControls(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed, NativePickerInput.available else { throw Check(description: "this runner may not post events or use Accessibility") }
        guard let owner = app.window else { throw Check(description: "no window") }
        let log = AIThreadsScenarios.Log(app)
        defer { try? app.perform(.setAppAppearance(nil)) }
        let pid = try Real.pid(app)
        let policy = try app.load(app.site.url("site-policy.html")); try waitForTitle(app, policy, "Site policy fixture")
        // The popovers draw with the sidebar's theme. A theme that follows the system appearance (an imported Arc
        // theme does) goes dark with it; the default one stays light.
        var theme = SpaceTheme.default
        var variants = ThemeVariants(legacy: theme)
        variants.selection = .auto
        theme.variants = variants
        try app.dispatch(.space(.update(try app.view().space.id, title: nil, icon: nil, theme: theme)))
        try WindowServerKeys.ensureFrontmost(app, owner)

        for scheme in [Scheme.light, .dark] {
            let pass = scheme == .light ? "light" : "dark"
            try app.perform(.setAppAppearance(scheme))
            try app.dispatch(.tab(.focus(policy)))
            try app.waitForPageInput(PageID(window: owner, item: policy), at: app.site.url("site-policy.html"))
            log.check("\(pass): the site button opens the site controls, and its words can be read") {
                try openControls(app)
                try app.waitUntil("the overview's rows") { try texts(app).contains("Developer Mode") && texts(app).contains("Insecure") }
                let shot = try app.screenshotSiteControls("\(pass)-overview")
                try readable(shot, ["Developer Mode", "Insecure", "Extensions", "Settings"], "\(pass) overview", dark: scheme == .dark)
                return "a real click on the site button opened the popover; Developer Mode, Insecure, Extensions and Settings read back from its picture"
            }
            log.check("\(pass): Developer Mode switches on and off") {
                try openControls(app)
                try pressLocated(app, "siteDeveloperMode")
                try app.waitUntil("Developer Mode on for the site and in the URL pill") { try rule(app)?.developerMode == true && app.view().urlPill.developerMode }
                try pressLocated(app, "siteDeveloperMode")
                try app.waitUntil("Developer Mode off again") { try rule(app)?.developerMode != true && !app.view().urlPill.developerMode }
                return "two real clicks on the row turned the site's Developer Mode on (the URL pill showed it) and off"
            }
            log.check("\(pass): the security row opens the details with its connection note") {
                try openControls(app)
                try pressLocated(app, "siteSecurity")
                let note = "Connection is not secure: this site uses plain HTTP."
                try app.waitUntil("the details page's note") { try texts(app).contains(note) }
                let shot = try app.screenshotSiteControls("\(pass)-details")
                try readable(shot, ["Site Settings", "Connection is not secure"], "\(pass) details", dark: scheme == .dark)
                return "the Insecure button opened the second page: \(note)"
            }
            log.check("\(pass): the site's switches on the details page") {
                try openDetails(app)
                for (title, read) in [("Block known ads and trackers on this site", { (r: SiteRule) in r.blocking }),
                                      ("Hide matching cookie banners", { (r: SiteRule) in r.hideCookieBanners }),
                                      ("Suspend this site while its tab is hidden", { (r: SiteRule) in r.suspendWhenHidden })] {
                    guard let before = try rule(app).map(read) else { throw Check(description: "no site rule") }
                    try pressInDetails(app, title: title, roles: ["AXCheckBox"])
                    try app.waitUntil("\(title) flips") { try rule(app).map(read) == !before }
                    try pressInDetails(app, title: title, roles: ["AXCheckBox"])
                    try app.waitUntil("\(title) back") { try rule(app).map(read) == before }
                }
                return "Block ads, Hide cookie banners and Suspend each flipped and came back with two real clicks"
            }
            log.check("\(pass): Back returns to the overview; Escape closes the popover") {
                try openDetails(app)
                try pressLocated(app, "siteControlsBack")
                try app.waitUntil("the overview again") { overviewShown(app) }
                try Real.key(app, [], .escape)
                try app.waitUntil("Escape closes the site controls") { closed(app, pid) }
                return "Back showed the overview; a real Escape closed the popover"
            }
        }
        try app.perform(.setAppAppearance(.light))

        log.check("the … button and the Settings title open the details") {
            for button in ["siteMore", "siteSettingsDetails", "siteExtensionsDetails"] {
                try openControls(app)
                try pressLocated(app, button)
                try app.waitUntil("\(button) opens the details") { detailsShown(app) }
                try pressLocated(app, "siteControlsBack")
                try app.waitUntil("back on the overview") { overviewShown(app) }
            }
            return "…, Settings and Extensions each opened the details page; Back returned"
        }

        log.check("Clear cookies and refresh, confirmed with a real click, clears the site's cookie") {
            try app.dispatch(.site(.closeControls))
            try SitePolicyScenarios.seed(app, policy, "A")
            try expect((try SitePolicyScenarios.storage(app, policy)["cookie"] as? String)?.contains("sitefixture") == true, "the seeded cookie is missing")
            try openDetails(app)
            try pressInDetails(app, title: "Clear cookies and refresh…", roles: ["AXButton"])
            try Real.click(app, in: .sheet(nil), identifier: field("confirmSiteClear"), "Clear data in the confirmation")
            try app.waitUntil("the clear completes", timeout: 15) {
                guard let result = try SitePolicyScenarios.controls(app).result else { return false }
                if let error = result.error { throw Check(description: error) }
                return result.completed == [.cookies]
            }
            try app.waitUntil("the page reloaded") { try SitePolicyScenarios.controls(app).ready }
            try Real.key(app, [], .escape)
            try app.waitUntil("closed") { closed(app, pid) }
            let cookie = try SitePolicyScenarios.storage(app, policy)["cookie"] as? String ?? ""
            try expect(!cookie.contains("sitefixture"), "the cookie survived: \(cookie)")
            return "the cookie set by the page was gone after Clear data; the result said cookies"
        }

        log.check("the site controls close four ways: the site button again, a click in the sidebar, a click on the page, Cmd+W") {
            try openControls(app)
            let button = try screenPoint(app, .siteInfo)
            let where_ = "front window at the button \(String(describing: PhysicalPointer.frontmost(at: button))), popover \(String(describing: NativeSystemInput.placeFrame(pid: pid, .popover))), button \(button)"
            try Real.click(app, at: button, "the site button again")
            do { try app.waitUntil("the site button closes it") { closed(app, pid) } } catch {
                let state: String
                if case .siteControls(let values)? = try? app.send(.siteControls) { state = values[owner] == nil ? "none" : "open" } else { state = "?" }
                let ax = NativeSystemInput.control(pid: pid, in: .popover, identifier: field("siteDeveloperMode")) != nil
                throw Check(description: "\(error); state \(state), popover window \((try? texts(app)) != nil), on screen \(ax); \(where_)")
            }

            try openControls(app)
            guard let viewport = try app.native().computed.sidebar?.tablistViewport else { throw Check(description: "no sidebar") }
            try Real.click(app, at: try AIThreadsScenarios.screen(app, CGPoint(x: viewport.midX, y: viewport.maxY - 24)), "an empty spot in the sidebar")
            try app.waitUntil("a click in the sidebar closes it") { closed(app, pid) }

            try openControls(app)
            let card = try app.native().computed.cards[0].rect
            try Real.click(app, at: try AIThreadsScenarios.screen(app, CGPoint(x: card.midX, y: card.maxY - 60)), "the page, away from the popover")
            try app.waitUntil("a click on the page closes it") { closed(app, pid) }

            // Cmd+W belongs to the popover once a click in it has made it the key window.
            try openDetails(app)
            try app.waitUntil("the popover is the key window") { try app.native().appWindows.contains { $0.isKey && $0.className.contains("Popover") } }
            let tabs = allTabs(try app.view()).count
            try Real.key(app, .command, .w)
            try app.waitUntil("Cmd+W closes it") { closed(app, pid) }
            app.sleep(0.5)
            try expect(allTabs(try app.view()).count == tabs, "Cmd+W closed a tab as well as the site controls")
            return "each of the four closed the popover; Cmd+W left the tabs alone"
        }

        log.check("a permission picker on the details page decides the next request") {
            let prompts = try app.load(app.site.url("site-permissions.html")); try waitForTitle(app, prompts, "Site permissions fixture")
            try openDetails(app)
            try choose(app, picker: "Window management", typing: "d")
            try app.waitUntil("Window management is Deny") { try rule(app)?.permissions[.windowManagement] == .deny }
            try Real.key(app, [], .escape)
            try app.waitUntil("closed") { closed(app, pid) }
            try request(app)
            try waitForTitle(app, prompts, "screens:denied:NotAllowedError")
            app.sleep(0.5)
            try expect(!promptShown(app, pid), "a denied permission still asked")
            try openDetails(app)
            try choose(app, picker: "Window management", typing: "as")
            try app.waitUntil("Window management back to Ask") { try rule(app)?.permissions[.windowManagement] ?? .ask == .ask }
            try Real.key(app, [], .escape)
            try app.waitUntil("closed") { closed(app, pid) }
            return "the picker set to Deny answered the page's request without a prompt; set back to Ask"
        }

        // Chromium blocks a permission for a week after three closes without an answer (its embargo, as in Chrome), so
        // each pass closes the prompt twice, on a site of its own: the light pass by Escape and a click in the sidebar,
        // the dark pass by Escape and a click on the page.
        for scheme in [Scheme.light, .dark] {
            let pass = scheme == .light ? "light" : "dark"
            try app.perform(.setAppAppearance(scheme))
            log.check("\(pass): the permission prompt's answers, Escape and a click outside") {
                let url = scheme == .light ? app.site.url("site-permissions.html")
                    : URL(string: app.site.url("site-permissions.html").absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost"))!
                let prompts = try app.load(url); try waitForTitle(app, prompts, "Site permissions fixture")
                func reload() throws {
                    try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
                    try app.waitForPageInput(PageID(window: owner, item: prompts), at: url)
                }
                func undecided() throws -> Bool { (try remembered(app, .windowManagement) ?? .ask) == .ask }
                try expect(try undecided(), "a choice is remembered before the prompt")
                func ask() throws {
                    try request(app)
                    try app.waitUntil("Brk's prompt") { promptShown(app, pid) && promptTexts(app, owner)?.contains("Manage windows on all your displays") == true }
                }
                func gone(_ how: String) throws {
                    try waitForTitle(app, prompts, "screens:denied:NotAllowedError")
                    try app.waitUntil("\(how) takes the prompt off screen") { !promptShown(app, pid) && promptTexts(app, owner) == nil }
                    try expect(try undecided(), "\(how) decided something")
                }
                try ask()
                let shot = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-\(pass)-prompt.png")
                _ = try app.send(.sitePrompt(window: owner, path: shot.path))
                try readable(shot, ["wants to", "Allow this time", "Never allow"], "\(pass) prompt", dark: scheme == .dark)
                try Real.click(app, in: .popover, identifier: field("sitePermissionAllowOnce"), "Allow this time")
                try waitForTitle(app, prompts, "screens:granted")
                try app.waitUntil("the prompt goes") { !promptShown(app, pid) }
                try expect(try undecided(), "Allow this time was remembered")
                try reload()

                try ask()
                try Real.key(app, [], .escape)
                try gone("Escape")

                try ask()
                if scheme == .light {
                    guard let viewport = try app.native().computed.sidebar?.tablistViewport else { throw Check(description: "no sidebar") }
                    try Real.click(app, at: try AIThreadsScenarios.screen(app, CGPoint(x: viewport.midX, y: viewport.maxY - 24)), "the sidebar, outside the prompt")
                    try gone("a click in the sidebar")
                } else {
                    let card = try app.native().computed.cards[0].rect
                    try Real.click(app, at: try AIThreadsScenarios.screen(app, CGPoint(x: card.midX, y: card.maxY - 60)), "the page, outside the prompt")
                    try gone("a click on the page")
                }

                // A new prompt after those still answers: its buttons are live.
                try ask()
                try Real.click(app, in: .popover, identifier: field("sitePermissionDeny"), "Never allow")
                try waitForTitle(app, prompts, "screens:denied:NotAllowedError")
                try app.waitUntil("Never allow is remembered") { try remembered(app, .windowManagement) == .deny }
                try request(app)
                try waitForTitle(app, prompts, "screens:denied:NotAllowedError")
                app.sleep(0.5)
                try expect(!promptShown(app, pid), "a remembered denial asked again")

                try setRemembered(app, .windowManagement, .ask)
                try reload()
                try ask()
                try Real.click(app, in: .popover, identifier: field("sitePermissionAllow"), "Allow while visiting the site")
                try waitForTitle(app, prompts, "screens:granted")
                try app.waitUntil("Allow is remembered") { try remembered(app, .windowManagement) == .allow }
                try reload()
                try request(app)
                try waitForTitle(app, prompts, "screens:granted")
                try expect(!promptShown(app, pid), "a remembered allow asked again")
                let outside = scheme == .light ? "a click in the sidebar" : "a click on the page"
                return "Allow this time granted once; Escape and \(outside) took the prompt away unanswered; Never allow and Allow while visiting were remembered"
            }
        }

        // The default theme keeps the sidebar light on a dark Mac; both popovers under the address draw with it.
        log.check("dark Mac, light sidebar: the prompt draws light like the site controls") {
            try app.perform(.setAppAppearance(.dark))
            try app.dispatch(.space(.update(try app.view().space.id, title: nil, icon: nil, theme: SpaceTheme.default)))
            let prompts = try app.load(app.site.url("site-permissions.html")); try waitForTitle(app, prompts, "Site permissions fixture")
            try setRemembered(app, .windowManagement, .ask)
            try openControls(app)
            try readable(try app.screenshotSiteControls("light-sidebar-controls"), ["Developer Mode"], "site controls under a light sidebar", dark: false)
            try Real.key(app, [], .escape)
            try app.waitUntil("closed") { closed(app, pid) }
            try request(app)
            try app.waitUntil("Brk's prompt") { promptShown(app, pid) }
            let shot = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-light-sidebar-prompt.png")
            _ = try app.send(.sitePrompt(window: owner, path: shot.path))
            defer { try? Real.click(app, in: .popover, identifier: field("sitePermissionAllowOnce"), "Allow this time") }
            try readable(shot, ["wants to", "Allow this time"], "prompt under a light sidebar", dark: false)
            return "with the Mac dark and the sidebar light, the site controls and the prompt both drew light"
        }
        try app.perform(.setAppAppearance(.light))

        log.check("a secure page: Secure, its note, and the Automatic Picture-In-Picture switch") {
            let fixture = try HTTPSFixture(app); defer { fixture.stop() }
            let secure = try app.load(fixture.url("127.0.0.1", "/secure.html")); try waitForTitle(app, secure, "Secure fixture")
            try openControls(app)
            try app.waitUntil("Secure and the Picture-In-Picture row") { try texts(app).contains("Secure") && texts(app).contains("Automatic Picture-In-Picture") }
            try pressLocated(app, "sitePictureInPicture")
            try app.waitUntil("Picture-In-Picture blocked for the site") { try rule(app)?.pictureInPictureExempt == true }
            try pressLocated(app, "sitePictureInPicture")
            try app.waitUntil("allowed again") { try rule(app)?.pictureInPictureExempt != true }
            try pressLocated(app, "siteSecurity")
            try app.waitUntil("the secure note") { try texts(app).contains("Connection is secure (HTTPS).") }
            try Real.key(app, [], .escape)
            try app.waitUntil("closed") { closed(app, pid) }
            return "the https page showed Secure; the Picture-In-Picture row blocked and allowed it; the details said the connection is secure"
        }

        log.check("the installed extension's tile and its Pin") {
            try app.dispatch(.tab(.focus(policy)))
            try app.waitForPageInput(PageID(window: owner, item: policy), at: app.site.url("site-policy.html"))
            let directory = app.site.root.deletingLastPathComponent().appendingPathComponent("Fixtures/SiteExtension")
            try app.dispatch(.site(.installSelectedExtension(directory)))
            try Real.click(app, in: .sheet(nil), identifier: field("confirmExtensionInstall"), "Install in the confirmation")
            try app.dispatch(.site(.nativeExtensions))
            var fixture: BrowserExtension?
            try app.waitUntil("the extension in the picker", timeout: 15) {
                let controls = try SitePolicyScenarios.controls(app)
                if let error = controls.extensionError { throw Check(description: error) }
                fixture = controls.extensions.first { $0.name == "Brk harmless fixture" }
                return fixture != nil
            }
            guard let fixture else { throw Check(description: "no fixture extension") }
            try openControls(app)
            try app.waitUntil("its tile in the overview") { NativeSystemInput.control(pid: pid, in: .popover, identifier: field("siteExtension-" + fixture.id)) != nil }
            try pressLocated(app, "siteExtensionsDetails")
            try pressLocated(app, "extension-pin-" + fixture.id)
            try app.waitUntil("pinned") { try SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id) }
            try pressLocated(app, "extension-pin-" + fixture.id)
            try app.waitUntil("unpinned") { try !SitePolicyScenarios.controls(app).pinnedExtensions.contains(fixture.id) }
            try Real.key(app, [], .escape)
            try app.waitUntil("closed") { closed(app, pid) }
            return "the local fixture was selected during setup; Install was clicked in the confirmation; the tile showed and Pin went on and off"
        }
        try log.finish()
    }

    // MARK: Site controls helpers

    /// The popover is on screen and in the state.
    static func open(_ app: AppUnderTest) -> Bool {
        guard let window = app.window, case .siteControls(let values)? = try? app.send(.siteControls), values[window] != nil else { return false }
        return (try? texts(app)) != nil
    }
    /// Nothing of the popover is left: not in the state, not as a window, not to Accessibility.
    static func closed(_ app: AppUnderTest, _ pid: Int32) -> Bool {
        guard let window = app.window, case .siteControls(let values)? = try? app.send(.siteControls), values[window] == nil, (try? texts(app)) == nil else { return false }
        return NativeSystemInput.control(pid: pid, in: .popover, identifier: field("siteDeveloperMode")) == nil
            && NativeSystemInput.control(pid: pid, in: .popover, identifier: field("siteControlsBack")) == nil
    }
    static func overviewShown(_ app: AppUnderTest) -> Bool { (try? locate(app, "siteDeveloperMode")) != nil }
    static func detailsShown(_ app: AppUnderTest) -> Bool { (try? locate(app, "siteControlsBack")) != nil }
    static func texts(_ app: AppUnderTest) throws -> [String] {
        guard let window = app.window else { throw Check(description: "no window") }
        return try SiteSecurityScenarios.texts(app, window)
    }
    static func rule(_ app: AppUnderTest) throws -> SiteRule? { try SitePolicyScenarios.controls(app).target == nil ? nil : SitePolicyScenarios.controls(app).rule }

    static func screenPoint(_ app: AppUnderTest, _ id: ViewID) throws -> CGPoint {
        let frame = try AIThreadsScenarios.still(app, id)
        return try AIThreadsScenarios.screen(app, CGPoint(x: frame.midX, y: frame.midY))
    }

    /// A real click on the site button, unless the popover is open.
    static func openControls(_ app: AppUnderTest) throws {
        if open(app) { return }
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try Real.click(app, at: try screenPoint(app, .siteInfo), "the site button")
        try app.waitUntil("the site controls open") { open(app) }
    }
    static func openDetails(_ app: AppUnderTest) throws {
        try openControls(app)
        if detailsShown(app) { return }
        try pressLocated(app, "siteSettingsDetails")
        try app.waitUntil("the details page") { detailsShown(app) }
    }

    /// A control of the popover with an identifier, where the popover lays it out now.
    static func locate(_ app: AppUnderTest, _ name: String) throws -> CGRect {
        guard let window = app.window else { throw Check(description: "no window") }
        guard case .menuItems(let values) = try app.send(.siteControlInput(window: window, field: name, action: .locate)), values.count >= 4,
              let x = Double(values[0]), let y = Double(values[1]), let width = Double(values[2]), let height = Double(values[3]) else {
            throw Check(description: "\(name) is not in the site controls")
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
    static func pressLocated(_ app: AppUnderTest, _ name: String) throws {
        var frame = CGRect.zero
        try app.waitUntil("\(name) in the site controls") { frame = try locate(app, name); return true }
        try Real.click(app, at: CGPoint(x: frame.midX, y: frame.midY), name)
    }

    /// A control of the details form by its title, brought into view with the wheel first, as a person scrolls to it.
    static func pressInDetails(_ app: AppUnderTest, title: String, roles: [String]) throws {
        let frame = try scrolledTo(app, title: title, roles: roles)
        try Real.click(app, at: CGPoint(x: frame.minX + min(10, frame.width / 2), y: frame.midY), title)
    }
    static func scrolledTo(_ app: AppUnderTest, title: String, roles: [String]) throws -> CGRect {
        let pid = try Real.pid(app)
        var panel: CGRect?
        try app.waitUntil("the popover through Accessibility") { panel = NativeSystemInput.placeFrame(pid: pid, .popover); return panel != nil }
        // The form scrolls under a 44 pt header; a control not listed yet may be further down.
        for _ in 0..<14 {
            guard let panel = NativeSystemInput.placeFrame(pid: pid, .popover) else { throw Check(description: "the popover went away") }
            let view = CGRect(x: panel.minX, y: panel.minY + 50, width: panel.width, height: panel.height - 56)
            guard let frame = NativeSystemInput.control(pid: pid, in: .popover, title: title, roles: roles) else {
                Real.scroll(at: CGPoint(x: panel.midX, y: panel.midY), lines: -3)
                continue
            }
            if view.contains(CGPoint(x: frame.midX, y: frame.minY)) && view.contains(CGPoint(x: frame.midX, y: frame.maxY)) { return frame }
            Real.scroll(at: CGPoint(x: panel.midX, y: panel.midY), lines: frame.midY > view.midY ? -3 : 3)
        }
        throw Check(description: "\(title) could not be scrolled into the popover; Accessibility lists: \(NativeSystemInput.outline(pid: pid, in: .popover))")
    }
    /// A pop-up of the details form: a real click opens its menu, the first letters pick the item, Return chooses.
    static func choose(_ app: AppUnderTest, picker title: String, typing letters: String) throws {
        // The picker's title is a text of its own; the pop-up beside it carries the choice.
        let pid = try Real.pid(app)
        _ = try scrolledTo(app, title: title, roles: ["AXStaticText"])
        guard let frame = NativeSystemInput.control(pid: pid, in: .popover, beside: title, roles: ["AXPopUpButton"]) else {
            throw Check(description: "no pop-up beside \(title)")
        }
        try Real.click(app, at: CGPoint(x: frame.maxX - 20, y: frame.midY), "the \(title) picker")
        app.sleep(0.5)
        try Real.type(app, letters)
        app.sleep(0.3)
        try Real.key(app, [], .returnKey)
        app.sleep(0.5)
    }

    static func promptTexts(_ app: AppUnderTest, _ owner: WindowID) -> [String]? {
        if case .menuItems(let texts)? = try? app.send(.sitePrompt(window: owner, path: nil)) { return texts }
        return nil
    }
    /// The prompt as Accessibility sees the screen, not as the app's own list of prompts has it.
    static func promptShown(_ app: AppUnderTest, _ pid: Int32) -> Bool {
        NativeSystemInput.control(pid: pid, in: .popover, identifier: field("sitePermissionAllowOnce")) != nil
    }
    /// A real click on site-permissions.html's Window management button.
    static func request(_ app: AppUnderTest) throws {
        let card = try app.native().computed.cards[0].rect
        try Real.click(app, at: try AIThreadsScenarios.screen(app, CGPoint(x: card.minX + 130, y: card.minY + 60)), "the page's Window management button")
    }
    /// What the site has remembered, read with the popover opened and closed through the socket (setup, not the step).
    static func remembered(_ app: AppUnderTest, _ capability: SiteCapability) throws -> SitePermission? {
        try app.dispatch(.site(.controls))
        defer { try? app.dispatch(.site(.closeControls)) }
        return try SitePolicyScenarios.controls(app).rule.permissions[capability]
    }
    static func setRemembered(_ app: AppUnderTest, _ capability: SiteCapability, _ answer: SitePermission) throws {
        try app.dispatch(.site(.controls))
        defer { try? app.dispatch(.site(.closeControls)) }
        guard let target = try SitePolicyScenarios.controls(app).target else { throw Check(description: "no site target") }
        var rule = try SitePolicyScenarios.controls(app).rule
        rule.permissions[capability] = answer
        try app.dispatch(.site(.rule(target, rule)))
    }

    // MARK: Settings window

    @Sendable static func settingsWindow(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed, NativePickerInput.available else { throw Check(description: "this runner may not post events or use Accessibility") }
        guard let owner = app.window else { throw Check(description: "no window") }
        let log = AIThreadsScenarios.Log(app)
        defer { try? app.perform(.setAppAppearance(nil)) }
        let pid = try Real.pid(app)
        let page = try app.load(app.site.url("index.html"))
        try app.waitForPageInput(PageID(window: owner, item: page), at: app.site.url("index.html"))
        try WindowServerKeys.ensureFrontmost(app, owner)
        try app.perform(.setAppAppearance(.light))

        log.check("Cmd+, opens Settings on General") {
            try openSettings(app)
            return "a real Cmd+, showed the Settings window, titled General"
        }
        log.check("General: Warn before quitting, the Previews sheet, Profile Settings…") {
            try toggle(app, .general, "warnBeforeQuitting") { $0.general.warnBeforeQuitting }
            try pressInPane(app, in: .window("General"), identifier: field("previewsSettings"), "Previews Settings…")
            let before = try settings(app).tabPreferences.hoverPreviews
            try Real.click(app, in: .sheet("General"), identifier: field("tabHoverPreviews"), "the folder and tab previews box")
            try app.waitUntil("previews flip") { try settings(app).tabPreferences.hoverPreviews == !before }
            try Real.click(app, in: .sheet("General"), identifier: field("tabHoverPreviews"), "the folder and tab previews box")
            try app.waitUntil("previews back") { try settings(app).tabPreferences.hoverPreviews == before }
            try Real.key(app, [], .returnKey)
            try app.waitUntil("Return is Done") { NativeSystemInput.control(pid: pid, in: .sheet("General"), identifier: field("tabHoverPreviews")) == nil }
            try pressInPane(app, in: .window("General"), identifier: field("profileSettings"), "Profile Settings…")
            try app.waitUntil("the Profiles pane") { try settings(app).pane == .profiles }
            return "the switch went on and off; the sheet's box flipped twice and Return closed it; Profile Settings… showed Profiles"
        }
        log.check("Profiles: search suggestions and Archive tabs after") {
            try show(app, .profiles)
            let id = ProfileID.default
            try toggle(app, .profiles, "searchSuggestions-\(id)") { $0.profiles.first { $0.profile.id == id }?.settings.searchSuggestions == true }
            try pick(app, .profiles, "autoArchive-\(id)", typing: "7")
            try app.waitUntil("archive after 7 days") { try settings(app).profiles.first { $0.profile.id == id }?.settings.autoArchive == .sevenDays }
            try pick(app, .profiles, "autoArchive-\(id)", typing: "12")
            try app.waitUntil("archive after 12 hours") { try settings(app).profiles.first { $0.profile.id == id }?.settings.autoArchive == .twelveHours }
            return "the suggestions switch went off and on; the archive pop-up chose 7 days, then 12 hours, with real keys in its menu"
        }
        log.check("Max: Automatically enable future features") {
            try show(app, .max)
            try toggle(app, .max, "autoEnableFutureFeatures") { $0.max.settings.autoEnableFutureFeatures == true }
            return "the switch went on and off"
        }
        log.check("Links: both Peek switches") {
            try show(app, .links)
            try toggle(app, .links, "shiftClickPeek") { $0.links.shiftClickPeek }
            try toggle(app, .links, "peekFromPinnedAndFavorites") { $0.links.peekFromPinnedAndFavorites }
            return "Shift+click Peek and Peek from Pinned and Favorites each went off and on"
        }
        log.check("Links: an Air Traffic Control route typed in, chosen and used; its info; removed") {
            try show(app, .links)
            try pressInPane(app, in: .window("Links"), identifier: field("airTrafficControlInfo"), "the routes' info button")
            do { try app.waitUntil("the info popover") { NativeSystemInput.shows(pid: pid, in: .anywhere, text: "Routes let you choose") } }
            catch { throw Check(description: "\(error); Accessibility lists: \(NativeSystemInput.outline(pid: pid, in: .popover)) / \(NativeSystemInput.outline(pid: pid, in: .window("Links"), limit: 120))") }
            try Real.key(app, [], .escape)
            try app.waitUntil("Escape closes the info") { !NativeSystemInput.shows(pid: pid, in: .anywhere, text: "Routes let you choose") }
            try expect(try settings(app).pane == .links, "Escape on the info popover closed Settings")

            guard let space = try settings(app).spaces.first else { throw Check(description: "no space to route to") }
            try pressInPane(app, in: .window("Links"), identifier: field("airTrafficControl"), "Air Traffic Control…")
            try Real.click(app, in: .sheet("Links"), identifier: field("route-new"), "New Route")
            var route: LinkRoute?
            try app.waitUntil("a new route") { route = try settings(app).routes.first?.route; return route != nil }
            guard let id = route?.id.rawValue else { throw Check(description: "no route") }
            try Real.click(app, in: .sheet("Links"), identifier: field("route-\(id)-pattern"), "the route's text field")
            try Real.type(app, "routed")
            try Real.key(app, [], .returnKey)
            try app.waitUntil("the pattern saved") { try settings(app).routes.first?.route.pattern == "routed" }
            let letters = String(space.title.lowercased().filter { $0.isLetter }.prefix(4))
            try Real.click(app, in: .sheet("Links"), identifier: field("route-\(id)-destination"), "the route's Open in pop-up")
            app.sleep(0.5)
            try Real.type(app, letters)
            try Real.key(app, [], .returnKey)
            try app.waitUntil("the route opens in \(space.title)") { try settings(app).routes.first?.route.destination == .space(space.id) }
            try Real.click(app, in: .sheet("Links"), identifier: field("routes-close"), "the sheet's ×")
            try app.waitUntil("the sheet closed") { NativeSystemInput.control(pid: pid, in: .sheet("Links"), identifier: field("route-new")) == nil }
            let kept = try settings(app).routes.map(\.route.pattern)
            try expect(kept == ["routed"], "the route was not kept: \(kept)")

            let routed = URL(string: app.site.url("index.html").absoluteString + "?routed=1")!
            let windows = try hello(app).windows.count
            try externalURL(app, routed)
            try app.waitUntil("the routed link opens as a tab in \(space.title)", timeout: 12) {
                allTabs(try app.view(owner)).contains { $0.url == routed }
            }
            try expect(try hello(app).windows.count == windows, "the routed link opened another window")

            try frontSettings(app)
            try pressInPane(app, in: .window("Links"), identifier: field("airTrafficControl"), "Air Traffic Control…")
            try Real.click(app, in: .sheet("Links"), identifier: field("route-\(id)-remove"), "the route's ⊖")
            try app.waitUntil("the route removed") { try settings(app).routes.isEmpty }
            try Real.key(app, [], .escape)
            try app.waitUntil("Escape closes the sheet") { NativeSystemInput.control(pid: pid, in: .sheet("Links"), identifier: field("route-new")) == nil }
            try expect(try settings(app).pane == .links, "Escape on the sheet closed Settings too")
            return "the info popover opened and Escape closed only it; New Route, typed 'routed', Open in \(space.title); a link from another app with 'routed' opened as a tab there; ⊖ removed it and Escape closed the sheet"
        }
        log.check("Shortcuts: the filter, the hover menu's Remove Shortcut, Reset All Shortcuts") {
            try show(app, .shortcuts)
            try pressInPane(app, in: .window("Shortcuts"), identifier: field("shortcut-filter"), "the filter field")
            try Real.type(app, "refresh the")
            let action = ActionID.reloadPage.rawValue
            let title = try Real.control(app, in: .window("Shortcuts"), title: "Refresh the Page", roles: ["AXStaticText"], "the Refresh the Page row")
            guard let row = try settings(app).shortcuts.first(where: { $0.action.rawValue == action }), row.state != .unset else {
                throw Check(description: "no Reload shortcut to remove")
            }
            // The row's … shows only under the pointer: glide over the row first.
            try Real.move(app, to: CGPoint(x: title.midX, y: title.midY))
            try pressInPane(app, in: .window("Shortcuts"), identifier: field("shortcut-menu-\(action)"), "the row's … menu")
            app.sleep(0.5)
            if let rect = NativeSystemInput.placeFrame(pid: pid, .window("Shortcuts")) {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",
                                     app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-shortcut-menu.png").path]
                try capture.run(); capture.waitUntilExit()
            }
            try Real.type(app, "remove")
            try Real.key(app, [], .returnKey)
            do { try app.waitUntil("Reload has no shortcut") { try settings(app).shortcuts.first { $0.action.rawValue == action }?.state == .unset } }
            catch { throw Check(description: "\(error); current Reload shortcut: \(String(describing: try settings(app).shortcuts.first { $0.action.rawValue == action }))") }
            try pressInPane(app, in: .window("Shortcuts"), identifier: field("shortcut-reset-all"), "Reset All Shortcuts")
            try app.waitUntil("Reload's shortcut back") { try settings(app).shortcuts.first { $0.action.rawValue == action }?.state == row.state }
            return "typing in the filter showed the Reload row; its hover … menu removed the shortcut; Reset All Shortcuts restored it"
        }
        log.check("Icon: Neon, then the original") {
            try show(app, .icon)
            try pressInPane(app, in: .window("Icon"), identifier: field("appIcon-neon"), "the Neon row")
            try app.waitUntil("Neon in the Dock") { try app.native().dockIcon == AppIconChoice.neon.rawValue }
            try pressInPane(app, in: .window("Icon"), identifier: field("appIcon-original"), "the original row")
            // The original is saved as no choice.
            try app.waitUntil("the original in the Dock") { try app.native().dockIcon == AppIconChoice.original.rawValue && settings(app).general.appIcon == nil }
            return "the Dock showed Neon, then the original"
        }
        log.check("Advanced: Show full URL in the toolbar; More Settings… and Back") {
            try app.dispatch(.sidebar(.toggleToolbar))
            defer { try? app.dispatch(.sidebar(.toggleToolbar)) }
            try show(app, .advanced)
            guard let address = currentTab(try app.view(owner))?.url?.absoluteString else { throw Check(description: "no current tab") }
            try toggle(app, .advanced, "showFullURLInToolbar", back: false) { $0.advanced.showFullURLInToolbar }
            try app.waitUntil("the toolbar shows the whole address") { try app.view(owner).urlPill.toolbarText == address }
            try pressInPane(app, in: .window("Advanced"), identifier: field("showFullURLInToolbar"), "Show full URL")
            try app.waitUntil("the toolbar shows the host") { try app.view(owner).urlPill.toolbarText == "127.0.0.1" }
            try pressInPane(app, in: .window("Advanced"), identifier: field("moreSettings"), "More Settings…")
            try pressInPane(app, in: .window("Advanced"), identifier: field("subpageBack"), "Back")
            try app.waitUntil("the Advanced cards again") { NativeSystemInput.control(pid: pid, in: .window("Advanced"), identifier: field("moreSettings")) != nil }
            return "the toolbar showed the whole address with the switch on and the host with it off; More Settings… and Back"
        }
        log.check("the red close button closes Settings; Cmd+W too") {
            try frontSettings(app)
            let windowTitle = try title(app)
            guard let button = NativeSystemInput.closeButton(pid: pid, window: windowTitle) else { throw Check(description: "no close button") }
            try Real.click(app, at: CGPoint(x: button.midX, y: button.midY), "the red close button")
            try app.waitUntil("Settings closed") { try settings(app).pane == nil && NativeSystemInput.placeFrame(pid: pid, .window(windowTitle)) == nil }
            try openSettings(app)
            try Real.key(app, .command, .w)
            try app.waitUntil("Cmd+W closes Settings") { try settings(app).pane == nil && NativeSystemInput.placeFrame(pid: pid, .window("General")) == nil }
            return "the close button and Cmd+W each closed the window"
        }

        // Every pane's words must read in either appearance.
        let words: [(SettingsPane, [String])] = [
            (.general, ["Warn before quitting", "Previews"]), (.profiles, ["Archive tabs after"]), (.max, ["Enable Max"]),
            (.links, ["smaller, simpler"]), (.shortcuts, ["Custom Shortcuts"]), (.icon, ["Neon"]), (.advanced, ["sound effects", "More Settings"]),
        ]
        for scheme in [Scheme.light, .dark] {
            let pass = scheme == .light ? "light" : "dark"
            try app.perform(.setAppAppearance(scheme))
            log.check("\(pass): each pane from the toolbar, and its words read") {
                try openSettings(app)
                for (pane, expected) in words {
                    try show(app, pane)
                    app.sleep(0.6)
                    try readable(try settingsShot(app, "\(pass)-\(pane.rawValue)"), expected, "\(pass) \(pane.rawValue)", dark: scheme == .dark)
                }
                try show(app, .general)
                try pressInPane(app, in: .window("General"), identifier: field("previewsSettings"), "Previews Settings…")
                try app.waitUntil("the Previews sheet") { NativeSystemInput.control(pid: pid, in: .sheet("General"), identifier: field("tabHoverPreviews")) != nil }
                app.sleep(0.4)
                try readable(try settingsShot(app, "\(pass)-previews"), ["Previews", "Done"], "\(pass) Previews sheet")
                try textContrast(app, in: .sheet("General"), name: "\(pass)-previews-labels", required: "Save a click!")
                try Real.key(app, [], .returnKey)
                try app.waitUntil("the Previews sheet closed") { NativeSystemInput.control(pid: pid, in: .sheet("General"), identifier: field("tabHoverPreviews")) == nil }
                try show(app, .links)
                try pressInPane(app, in: .window("Links"), identifier: field("airTrafficControl"), "Air Traffic Control…")
                try app.waitUntil("the routes sheet") { NativeSystemInput.control(pid: pid, in: .sheet("Links"), identifier: field("route-new")) != nil }
                app.sleep(0.4)
                try readable(try settingsShot(app, "\(pass)-routes"), ["Air Traffic Control", "New Route", "Default"], "\(pass) routes sheet")
                try Real.click(app, in: .sheet("Links"), identifier: field("routes-close"), "the sheet's ×")
                try app.waitUntil("the routes sheet closed") { NativeSystemInput.control(pid: pid, in: .sheet("Links"), identifier: field("route-new")) == nil }
                try pressInPane(app, in: .window("Links"), identifier: field("airTrafficControlInfo"), "the routes' info button")
                try app.waitUntil("the info popover") { NativeSystemInput.shows(pid: pid, in: .anywhere, text: "Routes let you choose") }
                try textContrast(app, in: .anywhere, name: "\(pass)-routes-info-labels", required: "Routes let you choose")
                try Real.key(app, [], .escape)
                try app.waitUntil("Escape closes only the info popover") {
                    try settings(app).pane == .links && !NativeSystemInput.shows(pid: pid, in: .anywhere, text: "Routes let you choose")
                }
                try Real.key(app, .command, .w)
                try app.waitUntil("closed") { try settings(app).pane == nil }
                return "seven toolbar clicks showed seven panes whose words read back; the Previews and routes sheets too"
            }
        }
        try log.finish()
    }

    // MARK: Settings helpers

    static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "settings did not answer") }
        return settings
    }
    static func hello(_ app: AppUnderTest) throws -> Hello {
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello did not answer") }
        return hello
    }
    static func title(_ app: AppUnderTest) throws -> String {
        guard let pane = try settings(app).pane else { throw Check(description: "Settings is closed") }
        return title(pane)
    }
    static func title(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General"
        case .max: "Max"
        case .profiles: "Profiles"
        case .shortcuts: "Shortcuts"
        case .links: "Links"
        case .icon: "Icon"
        case .advanced: "Advanced"
        }
    }
    static func settingsNumber(_ app: AppUnderTest) throws -> Int? {
        try app.native().appWindows.first { $0.className == "NSWindow" && $0.isVisible }?.number
    }
    /// Brk active with the Settings window in front, so a click lands there and keys go to it.
    static func frontSettings(_ app: AppUnderTest) throws {
        guard let number = try settingsNumber(app) else { throw Check(description: "the Settings window is not open") }
        if !Real.active(app) { try WindowServerKeys.ensureFrontmost(app, app.window!) }
        try app.perform(.focusAppWindow(number: number))
        try app.waitUntil("Settings is the key window") { try app.native().appWindows.first { $0.number == number }?.isKey == true }
    }
    static func openSettings(_ app: AppUnderTest) throws {
        let pid = try Real.pid(app)
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try Real.key(app, .command, .comma)
        try app.waitUntil("Settings on General") { try settings(app).pane == .general && NativeSystemInput.placeFrame(pid: pid, .window("General")) != nil }
    }
    /// A real click on a control of the Settings window or its sheet, first brought into the scrolling part's view with
    /// the wheel, as a person scrolls down a long pane to it.
    static func pressInPane(_ app: AppUnderTest, in place: AXPlace, identifier: String, _ what: String) throws {
        let pid = try Real.pid(app)
        _ = try Real.control(app, in: place, identifier: identifier, what)
        for _ in 0..<14 {
            guard let frame = NativeSystemInput.control(pid: pid, in: place, identifier: identifier) else { throw Check(description: "\(what) went away") }
            // A sheet does not scroll; a pane scrolls in the window's first scroll area.
            guard case .window = place, let area = NativeSystemInput.control(pid: pid, in: place, roles: ["AXScrollArea"]) else {
                try Real.click(app, at: CGPoint(x: frame.midX, y: frame.midY), what); return
            }
            if area.insetBy(dx: 0, dy: 4).contains(CGPoint(x: frame.midX, y: frame.midY)) {
                try Real.click(app, at: CGPoint(x: frame.midX, y: frame.midY), what); return
            }
            Real.scroll(at: CGPoint(x: area.midX, y: area.midY), lines: frame.midY > area.midY ? -3 : 3)
        }
        throw Check(description: "\(what) could not be scrolled into view")
    }
    /// A real click on the pane's toolbar item.
    static func show(_ app: AppUnderTest, _ pane: SettingsPane) throws {
        if try settings(app).pane == pane { return }
        try frontSettings(app)
        let current = try title(app)
        try Real.click(app, in: .window(current), title: title(pane), roles: ["AXButton", "AXRadioButton", "AXCheckBox", "AXToolbarButton"], "the \(title(pane)) toolbar item")
        let pid = try Real.pid(app)
        try app.waitUntil("the \(title(pane)) pane") { try settings(app).pane == pane && NativeSystemInput.placeFrame(pid: pid, .window(title(pane))) != nil }
    }
    /// Two real clicks on a switch: the setting flips, then comes back (unless `back` is false).
    static func toggle(_ app: AppUnderTest, _ pane: SettingsPane, _ name: String, back: Bool = true, _ read: @escaping (SettingsSnapshot) -> Bool) throws {
        try frontSettings(app)
        let before = read(try settings(app))
        try pressInPane(app, in: .window(title(pane)), identifier: field(name), name)
        try app.waitUntil("\(name) flips") { read(try settings(app)) == !before }
        guard back else { return }
        try pressInPane(app, in: .window(title(pane)), identifier: field(name), name)
        try app.waitUntil("\(name) back") { read(try settings(app)) == before }
    }
    /// A pop-up: a real click opens its menu, the first letters pick the item, Return chooses.
    static func pick(_ app: AppUnderTest, _ pane: SettingsPane, _ name: String, typing letters: String) throws {
        try frontSettings(app)
        try pressInPane(app, in: .window(title(pane)), identifier: field(name), name)
        app.sleep(0.5)
        try Real.type(app, letters)
        app.sleep(0.3)
        try Real.key(app, [], .returnKey)
        app.sleep(0.4)
    }
    /// The Settings window's picture, sheets included.
    static func settingsShot(_ app: AppUnderTest, _ name: String) throws -> URL {
        guard let number = try settingsNumber(app) else { throw Check(description: "no Settings window to capture") }
        // The window server's picture of the window and what is attached to it (a sheet is a window of its own).
        let url = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(number), url.path]
        try capture.run(); capture.waitUntilExit()
        if let sheet = try app.native().appWindows.first(where: { $0.isVisible && $0.className.contains("Sheet") })?.number {
            let sheetURL = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-\(name)-sheet.png")
            let sheetCapture = Process()
            sheetCapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            sheetCapture.arguments = ["-x", "-o", "-l", String(sheet), sheetURL.path]
            try sheetCapture.run(); sheetCapture.waitUntilExit()
            return sheetURL
        }
        return url
    }

    // MARK: Reading a picture

    /// Accessibility supplies the labels, including text too faint for OCR. Measure their ink against the actual
    /// sheet or popover pixels; the Previews sheet stays light even while the Settings window behind it is dark.
    static func textContrast(_ app: AppUnderTest, in place: AXPlace, name: String, required: String) throws {
        let pid = try Real.pid(app)
        let all = NativeSystemInput.textFrames(pid: pid, in: place)
        let panel: CGRect, labels: [(text: String, frame: CGRect)]
        if place == .anywhere {
            // SwiftUI publishes its info popover as an AXWindow on some macOS versions, rather than AXPopover.
            // Its one explanation paragraph supplies the exact screen rectangle without guessing the window role.
            guard let explanation = all.first(where: { $0.text.contains(required) }) else { throw Check(description: "no \(required) explanation") }
            panel = explanation.frame.insetBy(dx: -4, dy: -4)
            labels = [explanation]
        } else {
            guard let frame = NativeSystemInput.placeFrame(pid: pid, place) else {
                throw Check(description: "no \(place): \(NativeSystemInput.outline(pid: pid, in: place))")
            }
            panel = frame
            labels = all.filter { panel.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        }
        try expect(labels.contains { $0.text.contains(required) }, "\(required) is absent from \(place)")
        let url = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-R", "\(Int(panel.minX)),\(Int(panel.minY)),\(Int(panel.width)),\(Int(panel.height))", url.path]
        try capture.run(); capture.waitUntilExit()
        guard capture.terminationStatus == 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Check(description: "cannot capture \(place)") }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let linear = (0...255).map { value -> Double in
            let channel = Double(value) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        var measurements: [String] = [], failures: [String] = [], requiredMeasured = false
        let scale = Double(width) / panel.width
        for (text, rect) in labels {
            let box = CGRect(x: (rect.minX - panel.minX) * scale, y: (rect.minY - panel.minY) * scale,
                             width: rect.width * scale, height: rect.height * scale).integral
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard box.width >= 4, box.height >= 4 else { continue }
            var luminances: [Double] = []
            for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) {
                let i = (y * width + x) * 4
                luminances.append(0.2126 * linear[Int(bytes[i])] + 0.7152 * linear[Int(bytes[i + 1])] + 0.0722 * linear[Int(bytes[i + 2])])
            } }
            luminances.sort()
            let background = luminances[luminances.count / 2]
            let low = luminances[luminances.count / 100], high = luminances[luminances.count * 99 / 100]
            let ink = background - low > high - background ? low : high
            let contrast = (max(background, ink) + 0.05) / (min(background, ink) + 0.05)
            let line = "\(name): \(String(format: "%.1f", contrast)):1 \(text.prefix(100))"
            measurements.append(line)
            if text.contains(required) { requiredMeasured = true }
            if contrast < 3 { failures.append(line) }
        }
        let log = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(app.scenarioID)-contrast.txt")
        let prior = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try (prior + measurements.joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
        try expect(requiredMeasured && failures.isEmpty, "\(place): required label measured=\(requiredMeasured); unreadable labels: \(failures.joined(separator: "; "))")
    }

    /// Checks the expected words are drawn. OCR alone does not measure contrast; `textContrast` does that for labels
    /// in the sheets and popovers. With `dark`, a part that stays in the wrong appearance also fails here.
    static func readable(_ url: URL, _ words: [String], _ what: String, dark: Bool? = nil) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Check(description: "cannot read \(url.lastPathComponent)")
        }
        if let dark {
            // The mean grey of the opaque pixels, on an 8 x 8 reduction.
            var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
            let context = CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            var sum = 0.0, weight = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
                sum += (Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])) / 3 / 255
                weight += 1
            }
            let mean = weight > 0 ? sum / weight : 0.5
            try expect(dark ? mean < 0.45 : mean > 0.55, "\(what): \(url.lastPathComponent) is \(dark ? "light" : "dark") (mean grey \(String(format: "%.2f", mean)))")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        let missing = words.filter { !text.localizedCaseInsensitiveContains($0) }
        try expect(missing.isEmpty, "\(what): \(missing) do not read in \(url.lastPathComponent) (read: \(text.prefix(300)))")
    }
}

/// Clicks, wheel turns and keys at the window server, only while Brk is the app that receives them.
enum Real {
    static func pid(_ app: AppUnderTest) throws -> Int32 {
        guard let pid = app.hello?.pid else { throw Check(description: "no app pid") }
        return pid
    }
    static func active(_ app: AppUnderTest) -> Bool { (try? app.native())?.appActive == true }

    /// A left click at `point` (screen, top-left origin), refused unless Brk's window is the front one there.
    static func click(_ app: AppUnderTest, at point: CGPoint, _ what: String) throws {
        let pid = try pid(app)
        guard let front = PhysicalPointer.frontmost(at: point), front.pid == pid else {
            throw Check(description: "another window is in front of Brk at \(point) for \(what) (\(String(describing: PhysicalPointer.frontmost(at: point)))); nothing posted")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 60_000)
        }
        usleep(350_000)
    }
    /// The pointer glides to `point` (screen, top-left origin), as a hand moves it: tracking areas answer.
    static func move(_ app: AppUnderTest, to point: CGPoint) throws {
        let pid = try pid(app)
        guard PhysicalPointer.frontmost(at: point)?.pid == pid else { throw Check(description: "another window is in front of Brk at \(point); the pointer was not moved") }
        let from = CGEvent(source: nil)?.location ?? point
        for step in 1...12 {
            let t = Double(step) / 12
            CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                    mouseCursorPosition: CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t), mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        usleep(300_000)
    }
    /// Wheel lines at `point`; negative moves the content up.
    static func scroll(at point: CGPoint, lines: Int32) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(100_000)
        for _ in 0..<4 {
            let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
            event?.location = point
            event?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
        usleep(400_000)
    }
    static func key(_ app: AppUnderTest, _ modifiers: Modifiers, _ key: Key) throws {
        guard active(app) else { throw Check(description: "Brk is not the active app; no key posted") }
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(350_000)
    }
    static func type(_ app: AppUnderTest, _ text: String) throws {
        guard active(app) else { throw Check(description: "Brk is not the active app; nothing typed") }
        try AIThreadsScenarios.type(text)
    }
    static func paste(_ app: AppUnderTest, _ text: String) throws {
        guard active(app) else { throw Check(description: "Brk is not the active app; nothing pasted") }
        try AIThreadsScenarios.paste(text)
    }
    /// Waits for a control through Accessibility; the failure lists what Accessibility saw there.
    static func control(_ app: AppUnderTest, in place: AXPlace, identifier: String? = nil, title: String? = nil, roles: [String] = [], _ what: String, timeout: Double = 8) throws -> CGRect {
        let pid = try pid(app)
        var found: CGRect?
        do {
            try app.waitUntil("\(what) in \(place)", timeout: timeout) {
                found = NativeSystemInput.control(pid: pid, in: place, identifier: identifier, title: title, roles: roles)
                return found != nil
            }
        } catch {
            throw Check(description: "\(error); Accessibility lists: \(NativeSystemInput.outline(pid: pid, in: place))")
        }
        guard let found else { throw Check(description: "\(what) vanished") }
        return found
    }
    @discardableResult
    static func click(_ app: AppUnderTest, in place: AXPlace, identifier: String? = nil, title: String? = nil, roles: [String] = [], _ what: String) throws -> CGRect {
        let frame = try control(app, in: place, identifier: identifier, title: title, roles: roles, what)
        try click(app, at: CGPoint(x: frame.midX, y: frame.midY), what)
        return frame
    }
}
