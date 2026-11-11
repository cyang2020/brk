import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// First-run onboarding and import from another browser, through the real window with real clicks and typing
/// (window-server events posted at each control's rectangle, which the app reports over the control socket).
enum OnboardingScenarios {
    static let all = [
        Scenario("Onboarding-Import", "first run: every onboarding screen by real input, a Chrome profile's bookmarks, history, cookie and password come over and the password fills after restart",
                 cefOnly: "cookies, Login Data and autofill are Chromium's", importFlow),
        Scenario("Onboarding-RealArc", "opt-in: this Mac's Arc profile imported through onboarding into a throwaway data folder, every screen captured",
                 cefOnly: "a real Chromium profile", realArc),
    ]

    /// The fixture Chrome's "Chrome Safe Storage" password; the encrypted values below were made with it (PBKDF2 and
    /// AES-128-CBC as Chromium does, see BrkImport/ChromiumCrypto.swift).
    static let fixtureKey = "brk-fixture-key"
    /// "v10" + AES-128-CBC("fixture-pass-123") and ("imported-session") under `fixtureKey`.
    static let encryptedPassword = "76313059ab57d5d11a6a6eb507766d670b7a655d6b886bdd43cb0fc60922d1a785fb21"
    static let encryptedCookie = "763130ae3f483b8e20e2b62a438154d0ef86a8c623317fce0552c33982e1a2e033b99e"

    /// `<data>/import-root/Google/Chrome/Default` with Bookmarks, History, Login Data and Cookies; SQLite through the
    /// system's sqlite3 tool (BrkE2E links no SQLite).
    static func makeChromeFixture(in data: URL, site: FixtureServer) throws -> URL {
        let root = data.appendingPathComponent("import-root", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let profile = root.appendingPathComponent("Google/Chrome/Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profile.appendingPathComponent("Network"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": ["Default": ["name": "Fixture Person"], "Profile 1": ["name": "Work Fixture"]],
                                                                "profiles_order": ["Default", "Profile 1"]]])
            .write(to: root.appendingPathComponent("Google/Chrome/Local State"))
        // A second profile with one bookmark: the profile step appears and each profile's bookmarks keep their own folder.
        let work = root.appendingPathComponent("Google/Chrome/Profile 1", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["roots": ["bookmark_bar": ["type": "folder", "name": "Bookmarks bar", "children": [
            ["type": "url", "name": "Work Notes", "url": site.url("index.html?work").absoluteString]]]]])
            .write(to: work.appendingPathComponent("Bookmarks"))
        let bookmarks: [String: Any] = ["roots": [
            "bookmark_bar": ["type": "folder", "name": "Bookmarks bar", "children": [
                ["type": "url", "name": "Fixture Page 2", "url": site.url("page2.html").absoluteString],
                ["type": "folder", "name": "Fixture Work", "children": [["type": "url", "name": "Fixture Cookie", "url": site.url("cookie.html").absoluteString]]]]],
            "other": ["type": "folder", "name": "Other bookmarks", "children": [["type": "url", "name": "Fixture Home", "url": site.url("index.html").absoluteString]]]]]
        try JSONSerialization.data(withJSONObject: bookmarks).write(to: profile.appendingPathComponent("Bookmarks"))
        let now = Int64((Date().timeIntervalSince1970 + 11_644_473_600) * 1_000_000), hour: Int64 = 3_600_000_000
        try sqlite(profile.appendingPathComponent("History"), """
            CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, typed_count INTEGER, hidden INTEGER);
            CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER, transition INTEGER);
            INSERT INTO urls VALUES (1, '\(site.url("page2.html").absoluteString)', 'Fixture Page 2', 12, 3, 0), (2, '\(site.url("imported-history-only.html").absoluteString)', 'Imported history only', 2, 0, 0);
            INSERT INTO visits VALUES (1, 1, \(now - hour), 1), (2, 2, \(now - 2 * hour), 1);
            """)
        let realm = site.baseURL.absoluteString.hasSuffix("/") ? site.baseURL.absoluteString : site.baseURL.absoluteString + "/"
        try sqlite(profile.appendingPathComponent("Login Data"), """
            CREATE TABLE logins (origin_url VARCHAR NOT NULL, action_url VARCHAR, username_element VARCHAR, username_value VARCHAR, password_element VARCHAR,
              password_value BLOB, submit_element VARCHAR, signon_realm VARCHAR NOT NULL, date_created INTEGER NOT NULL, blacklisted_by_user INTEGER NOT NULL,
              scheme INTEGER NOT NULL, times_used INTEGER, date_last_used INTEGER, date_password_modified INTEGER, id INTEGER PRIMARY KEY AUTOINCREMENT,
              UNIQUE (origin_url, username_element, username_value, password_element, signon_realm));
            INSERT INTO logins (origin_url, action_url, username_element, username_value, password_element, password_value, submit_element, signon_realm, date_created, blacklisted_by_user, scheme, times_used)
              VALUES ('\(site.url("import-login.html").absoluteString)', '\(site.url("import-login.html").absoluteString)', 'username', 'fixture-user', 'password', X'\(encryptedPassword)', '', '\(realm)', \(now - hour), 0, 0, 3);
            """)
        try sqlite(profile.appendingPathComponent("Network/Cookies"), """
            CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR);
            INSERT INTO meta VALUES ('version', '18');
            CREATE TABLE cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL,
              encrypted_value BLOB NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL,
              last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL, samesite INTEGER NOT NULL);
            INSERT INTO cookies VALUES (\(now - hour), '127.0.0.1', '', 'brk_import', '', X'\(encryptedCookie)', '/', \(now + 240 * hour), 0, 0, \(now - hour), 1, 1, 1, -1);
            """)
        return root
    }

    private static func sqlite(_ file: URL, _ script: String) throws {
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        tool.arguments = [file.path]
        let input = Pipe()
        tool.standardInput = input
        try tool.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        tool.waitUntilExit()
        guard tool.terminationStatus == 0 else { throw Check(description: "sqlite3 fixture failed for \(file.lastPathComponent)") }
    }

    // MARK: Driving the window

    static func facts(_ app: AppUnderTest, activate: Bool = false) throws -> OnboardingFacts {
        guard case .onboarding(let facts) = try app.send(.onboarding(activate: activate)) else { throw Check(description: "no onboarding facts") }
        return facts
    }

    static func waitStep(_ app: AppUnderTest, _ step: String, timeout: Double = 10) throws {
        try app.waitUntil("onboarding shows \(step)", timeout: timeout) { try facts(app).step == step }
        usleep(500_000)   // the cross-fade
    }

    /// A real click at the control's centre, only while Brk's onboarding window is the frontmost window there.
    static func click(_ app: AppUnderTest, _ control: String) throws {
        var current = try facts(app, activate: true)
        try app.waitUntil("Brk's onboarding window is key", timeout: 4) { current = try facts(app); return current.isKey }
        try app.waitUntil("control \(control) is on screen", timeout: 6) { current = try facts(app); return current.controls[control] != nil }
        guard let rect = current.controls[control] else { throw Check(description: "no control \(control) on \(current.step ?? "?")") }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        guard case .hello(let hello) = try app.send(.hello), let front = PhysicalPointer.frontmost(at: point), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk's onboarding window at \(point); real click not posted")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 70_000)
        }
        usleep(250_000)
    }

    static func shot(_ app: AppUnderTest, _ name: String) throws {
        let number = try facts(app).windowNumber
        _ = try app.windowScreenshot(name, number: number)
    }

    // MARK: Onboarding-Import

    @Sendable static func importFlow(_ app: AppUnderTest) throws {
        try app.waitUntil("the onboarding window opens on Welcome", timeout: 15) { try facts(app).step == "welcome" }
        try expect(try ImportSyncScenarios.data(app).needsOnboarding, "first-run marker missing")
        try shot(app, "01-welcome")
        try click(app, "welcome-next"); try waitStep(app, "name")
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello") }
        try click(app, "name-field")
        PhysicalKeys.type("Casey", pid: hello.pid)
        usleep(300_000)
        try shot(app, "02-name")
        try click(app, "next"); try waitStep(app, "pickBrowser")
        try click(app, "browser-chrome")
        try shot(app, "03-pick-browser")
        try click(app, "next"); try waitStep(app, "profiles")
        try shot(app, "03b-profiles")
        try click(app, "next"); try waitStep(app, "keychain")
        try shot(app, "04-keychain")
        try click(app, "next"); try waitStep(app, "progress")
        try app.waitUntil("the import finishes", timeout: 30) { try facts(app).progressDone }
        let progress = try facts(app)
        try expect(progress.failures.isEmpty, "import failures: \(progress.failures)")
        try shot(app, "05-progress")
        try click(app, "next"); try waitStep(app, "bookmarks")
        try shot(app, "06-bookmarks")
        // Arc's step starts with its recommendation (the most visited bookmark); Select All takes the other three.
        try click(app, "bookmarks-all")
        try click(app, "next"); try waitStep(app, "favorites")
        try shot(app, "07-favorites")
        try click(app, "next"); try waitStep(app, "theme")
        try shot(app, "08-theme")
        try click(app, "next"); try waitStep(app, "adBlocker")
        try click(app, "adblock-yes")
        try shot(app, "09-ad-blocker")
        try click(app, "next"); try waitStep(app, "max")
        try shot(app, "10-max")
        try click(app, "skip")
        if try facts(app).step == "max" { usleep(500_000) }
        if try facts(app).step != "finish" {
            try waitStep(app, "defaultBrowser")
            try click(app, "default-no")
            try shot(app, "11-default-browser")
            try click(app, "next")
        }
        try waitStep(app, "finish")
        let finish = try facts(app)
        try shot(app, "12-finish")
        app.note("Finish summary: " + finish.summary.joined(separator: "; "))
        try expect(finish.summary.contains("4 bookmarks in Pinned"), "finish summary lacks the four bookmarks: \(finish.summary)")
        try expect(finish.summary.contains { $0.contains("history visit") }, "finish summary lacks history: \(finish.summary)")
        try expect(finish.summary.contains { $0.contains("password") }, "finish summary lacks the password: \(finish.summary)")
        try expect(finish.summary.contains { $0.contains("site login") }, "finish summary lacks the cookie: \(finish.summary)")
        try click(app, "next")
        try app.waitUntil("onboarding closed") { try facts(app).step == nil }
        try app.waitUntil("Brk 101 opens in the browser window", timeout: 15) { try currentTab(app.view())?.title == "Brk 101" }
        let data = try ImportSyncScenarios.data(app)
        try expect(!data.needsOnboarding, "setup marker not saved")
        try expect(data.userName == "Casey", "the typed name was not kept: \(String(describing: data.userName))")
        let view = try app.view()
        try expect(view.space.title == "Personal", "the starting Space is \(view.space.title), not Personal")
        try expect(view.space.pinned.rows.contains { if case .folder(let folder) = $0 { folder.title == "Imported from Chrome" } else { false } },
                   "no Imported from Chrome folder in Pinned")
        _ = try app.screenshot("13-sidebar")
        let history = try historyRows(app, returning: false)
        try expect(history.contains { $0.title == "Imported history only" }, "imported history not on the History page")
        try app.dispatch(.library(.close))
        app.passed("every screen by real clicks and typing; Pinned has Imported from Chrome, History has the imported visit, the name is kept")

        // The cookie came through CEF's cookie store: the fixture page reads it back.
        _ = try app.load(app.site.url("cookie.html"))
        try app.waitUntil("the imported cookie reaches the page", timeout: 10) { try currentTab(app.view())?.title.contains("brk_import=imported-session") == true }
        app.passed("the imported cookie is sent to its site")

        // The password waited in the staged file while CEF held Login Data; the next launch merges it before CEF starts.
        try app.flush(); try app.restart(); try app.settle()
        let staged = app.dataDirectory.appendingPathComponent("pending-logins/Default.json")
        try expect(!FileManager.default.fileExists(atPath: staged.path), "staged logins were not merged at launch")
        _ = try app.load(app.site.url("import-login.html"))
        try app.waitUntil("the login page loads", timeout: 10) { try currentTab(app.view())?.title.hasPrefix("login") == true }
        guard let window = app.window else { throw Check(description: "no window") }
        let frame = try app.native(window).windowFrame
        try PhysicalPointer.press(app, at: CGPoint(x: frame.width * 0.65, y: frame.height * 0.6), window: window) {}
        try app.waitUntil("Chromium fills the imported password", timeout: 10) { try currentTab(app.view())?.title == "login:fixture-user:filled" }
        _ = try app.screenshot("14-autofill")
        app.passed("after restart CEF's password manager fills the imported login on its page")
    }

    // MARK: Onboarding-RealArc (opt-in)

    @Sendable static func realArc(_ app: AppUnderTest) throws {
        try app.waitUntil("the onboarding window opens on Welcome", timeout: 15) { try facts(app).step == "welcome" }
        try shot(app, "01-welcome")
        try click(app, "welcome-next"); try waitStep(app, "name")
        try shot(app, "02-name")
        try click(app, "skip"); try waitStep(app, "pickBrowser")
        try click(app, "browser-arc")
        try shot(app, "03-pick-browser")
        try click(app, "next")
        if try facts(app).step == "profiles" { try shot(app, "03b-profiles"); try click(app, "next") }
        try waitStep(app, "keychain")
        // The keychain step asks macOS for "Arc Safe Storage", which needs the Mac's login password typed by a person.
        // Unattended, the run turns passwords and cookies off and imports the rest.
        try click(app, "secrets-toggle")
        try shot(app, "04-keychain")
        try click(app, "next"); try waitStep(app, "progress")
        try app.waitUntil("the import finishes", timeout: 60) { try facts(app).progressDone }
        let progress = try facts(app)
        app.note("Read: " + progress.summary.joined(separator: "; "))
        if !progress.failures.isEmpty { app.note("Failures: " + progress.failures.joined(separator: "; ")) }
        try shot(app, "05-progress")
        try click(app, "next")
        usleep(800_000)
        if try facts(app).step == "bookmarks" { try shot(app, "06-bookmarks"); try click(app, "next"); usleep(800_000) }
        if try facts(app).step == "favorites" { try shot(app, "07-favorites"); try click(app, "next") }
        try waitStep(app, "theme"); try shot(app, "08-theme"); try click(app, "next")
        try waitStep(app, "adBlocker"); try shot(app, "09-ad-blocker"); try click(app, "next")
        try waitStep(app, "max"); try shot(app, "10-max"); try click(app, "skip")
        usleep(800_000)
        if try facts(app).step == "defaultBrowser" { try shot(app, "11-default-browser"); try click(app, "default-no"); try click(app, "next") }
        try waitStep(app, "finish")
        let finish = try facts(app)
        app.note("Imported: " + finish.summary.joined(separator: "; "))
        try shot(app, "12-finish")
        try click(app, "next")
        try app.waitUntil("onboarding closed") { try facts(app).step == nil }
        try app.waitUntil("Brk 101 opens", timeout: 15) { try currentTab(app.view())?.title == "Brk 101" }
        let view = try app.view()
        app.note("Spaces after import: " + view.dock.map(\.title).joined(separator: " | "))
        _ = try app.screenshot("13-sidebar")
        // Every imported Space's sidebar.
        for (index, item) in view.dock.enumerated() {
            try app.dispatch(.space(.focus(item.id)))
            usleep(700_000)
            let shown = try app.view()
            func names(_ rows: [Row]) -> [String] {
                rows.map { row in
                    switch row {
                    case .tab(let tab): tab.title
                    case .folder(let folder): "[\(folder.title)]"
                    case .split: "[split]"
                    }
                }
            }
            app.note("Space \(shown.space.title): pinned \(names(shown.space.pinned.rows)), today \(names(shown.space.today.rows)), favorites \(shown.favorites.tiles.count)")
            _ = try app.screenshot("14-space-\(index)")
        }

        // Importing the same profile again (Brk > Import from Another Browser…) adds nothing.
        let before = try app.view().dock.count
        try app.dispatch(.sidebarData(.importBrowser))
        try waitStep(app, "pickBrowser")
        try click(app, "browser-arc")
        try shot(app, "15-again-pick")
        try click(app, "next")
        if try facts(app).step == "profiles" { try click(app, "next") }
        try waitStep(app, "keychain")
        try click(app, "secrets-toggle")
        try click(app, "next"); try waitStep(app, "progress")
        try app.waitUntil("the second import finishes", timeout: 60) { try facts(app).progressDone }
        try click(app, "next")
        usleep(800_000)
        if try facts(app).step == "bookmarks" { try click(app, "next") }
        try waitStep(app, "finish")
        let again = try facts(app)
        app.note("Second import: " + again.summary.joined(separator: "; "))
        try shot(app, "16-again-finish")
        try expect(again.summary == ["Nothing new: everything was already here"], "the second import added rows: \(again.summary)")
        try click(app, "next")
        try app.waitUntil("import window closed") { try facts(app).step == nil }
        try expect(try app.view().dock.count == before, "the second import made Spaces")

        // The Safari screens (the export ZIP, and the Full Disk Access route for Safari 17 and earlier), captured only.
        try app.dispatch(.sidebarData(.importBrowser))
        try waitStep(app, "pickBrowser")
        try click(app, "browser-safari")
        try click(app, "next"); try waitStep(app, "safari")
        try shot(app, "17-safari-zip")
        try click(app, "safari-legacy"); try waitStep(app, "safariLegacy")
        try shot(app, "18-safari-full-disk-access")
        try click(app, "skip")
        try app.waitUntil("import window closed") { try facts(app).step == nil }
    }
}
