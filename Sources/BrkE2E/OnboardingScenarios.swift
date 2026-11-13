import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation
import ImageIO

/// First-run onboarding and import from another browser, through the real window with real clicks and typing
/// (window-server events posted at each control's rectangle, which the app reports over the control socket).
enum OnboardingScenarios {
    static let all = [
        Scenario("Onboarding-Import", "first run: every onboarding screen by real input, a Chrome profile's bookmarks, history, cookie and password come over and the password fills after restart",
                 cefOnly: "cookies, Login Data and autofill are Chromium's", importFlow),
        Scenario("Onboarding-RealArc", "opt-in: this Mac's Arc profile imported through onboarding into a throwaway data folder, every screen captured",
                 cefOnly: "a real Chromium profile", realArc),
        Scenario("Onboarding-Paths", "first run by real keys and clicks, light then dark: Return, Back, Skip, Escape, no import, a click and a dot drag on the theme pad, ad blocker NO, Enable Max then Not now, ⌘Q brings setup back; an Arc folder through the picker, the passwords switch, Favorites picks, the red button finishes; Import from Another Browser… in light with a file through the open panel; Check for Updates…; every screen's text, buttons' included, readable in both appearances",
                 paths),
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
        try clickScreen(app, CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Who owns the frontmost window at a screen point, for a refused click's message.
    static func windowOwner(at point: CGPoint) -> String {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer < 20, let bounds = info[kCGWindowBounds as String] as? [String: Double] else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(point) { return "\(info[kCGWindowOwnerName as String] as? String ?? "?") window \(info[kCGWindowNumber as String] as? Int ?? 0) at \(rect)" }
        }
        return "no window"
    }

    static func pid(_ app: AppUnderTest) throws -> pid_t {
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello") }
        return hello.pid
    }

    /// Real mouse events at a screen point (top-left origin), only while one of this run's windows is the frontmost
    /// window there.
    static func clickScreen(_ app: AppUnderTest, _ point: CGPoint) throws {
        guard let front = PhysicalPointer.frontmost(at: point), front.pid == (try pid(app)) else {
            throw Check(description: "another window is in front of Brk at \(point) (\(windowOwner(at: point))); real click not posted")
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

    // MARK: Onboarding-Paths

    /// `<data>/arc-root`: a made-up Arc folder, small, as ~/brk-evidence/sidebar-lag/make-arc.py makes a big one: Arc's
    /// sidebar file with two Spaces and no Favorites (so the Favorites step offers Brk's own sites), and a Default profile
    /// whose Bookmarks hold a folder of two and one more. Every address is the fixture site's.
    static func makeArcFixture(in data: URL, site: FixtureServer) throws -> URL {
        let root = data.appendingPathComponent("arc-root", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let profile = root.appendingPathComponent("Arc/User Data/Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        // Arc writes its lists as alternating id, value pairs.
        var items: [Any] = []
        func tab(_ id: String, _ title: String, _ page: String) -> String {
            items += [id, ["id": id, "childrenIds": [String](), "data": ["tab": ["savedURL": site.url(page).absoluteString, "savedTitle": title]]] as [String: Any]]
            return id
        }
        func holder(_ id: String, _ title: String?, _ children: [String], list: Bool) -> String {
            let kind = list ? "list" : "itemContainer"
            var item: [String: Any] = ["id": id, "childrenIds": children, "data": [kind: [String: Any]()]]
            if let title { item["title"] = title }
            items += [id, item]
            return id
        }
        func space(_ id: String, _ title: String, pinned: [String], today: [String]) -> [Any] {
            let pinnedID = holder(id + "-pinned", nil, pinned, list: false), todayID = holder(id + "-today", nil, today, list: false)
            return [id, ["id": id, "title": title, "containerIDs": ["pinned", pinnedID, "unpinned", todayID], "profile": ["default": true],
                         "customInfo": ["iconType": ["emoji_v2": title == "Home" ? "🏠" : "💼"]]] as [String: Any]]
        }
        let spaces = space("space-home", "Home", pinned: [holder("home-reading", "Reading", [tab("t1", "Arc Page Two", "page2.html"), tab("t2", "Arc Reading", "index.html?arc-reading")], list: true),
                                                      tab("t3", "Arc Pinned", "index.html?arc-pinned")],
                           today: [tab("t4", "Arc Today", "index.html?arc-today")])
            + space("space-work", "Work", pinned: [tab("t5", "Arc Work", "index.html?arc-work")], today: [])
        let containers: [Any] = [["global": [String: Any]()] as [String: Any], ["spaces": spaces, "items": items] as [String: Any]]
        let sidebar: [String: Any] = ["sidebar": ["containers": containers]]
        try JSONSerialization.data(withJSONObject: sidebar).write(to: root.appendingPathComponent("Arc/StorableSidebar.json"))
        func url(_ name: String, _ page: String) -> [String: Any] { ["type": "url", "name": name, "url": site.url(page).absoluteString] }
        let recipes: [String: Any] = ["type": "folder", "name": "Recipes", "children": [url("Soup", "index.html?soup"), url("Bread", "index.html?bread")]]
        let bar: [String: Any] = ["type": "folder", "name": "Bookmarks bar", "children": [recipes, url("Docs", "index.html?docs")]]
        let other: [String: Any] = ["type": "folder", "name": "Other bookmarks", "children": [Any]()]
        let bookmarks: [String: Any] = ["version": 1, "roots": ["bookmark_bar": bar, "other": other]]
        try JSONSerialization.data(withJSONObject: bookmarks).write(to: profile.appendingPathComponent("Bookmarks"))
        return root
    }

    static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "settings did not answer") }
        return settings
    }

    /// A control's screen rectangle on the current screen.
    static func control(_ app: AppUnderTest, _ id: String) throws -> CGRect {
        var rect: CGRect?
        try app.waitUntil("control \(id) is on screen", timeout: 6) { rect = try facts(app).controls[id]; return rect != nil }
        return rect!
    }

    /// A real key press posted to Brk while its onboarding window is key.
    static func key(_ app: AppUnderTest, _ chord: KeyChord) throws {
        _ = try facts(app, activate: true)
        try app.waitUntil("Brk's onboarding window is key", timeout: 4) { try facts(app).isKey }
        PhysicalKeys.press(chord, pid: try pid(app))
        usleep(300_000)
    }

    /// A real drag between two screen points: press, glide with the button down, release.
    static func dragScreen(_ app: AppUnderTest, from start: CGPoint, to end: CGPoint) throws {
        guard let front = PhysicalPointer.frontmost(at: start), front.pid == (try pid(app)) else {
            throw Check(description: "another window is in front of Brk at \(start); real drag not posted")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ point: CGPoint, wait: UInt32) throws {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(wait)
        }
        try post(.mouseMoved, start, wait: 150_000)
        try post(.leftMouseDown, start, wait: 120_000)
        for step in 1...24 {
            let t = Double(step) / 24, eased = t * t * (3 - 2 * t)
            try post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased), wait: 12_000)
        }
        usleep(150_000)
        try post(.leftMouseUp, end, wait: 300_000)
    }

    /// The red button of the app's window titled `title`.
    static func closeButton(_ app: AppUnderTest, window title: String) throws -> CGPoint {
        guard let rect = NativeSystemInput.closeButtonFrame(pid: try pid(app), window: title) else { throw Check(description: "no close button on the window \(title)") }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// The name field's text, as Accessibility reads it.
    static func nameField(_ app: AppUnderTest) throws -> String? {
        let field = try control(app, "name-field")
        return NativeSystemInput.elements(pid: try pid(app), role: "AXTextField").first { $0.frame.intersects(field) }?.value
    }

    static func windowTexts(_ app: AppUnderTest) throws -> [String] { try windowTextFrames(app).map(\.text) }

    /// The texts Accessibility lists in the onboarding window itself (the browser window under it has its own), with
    /// their screen rectangles.
    static func windowTextFrames(_ app: AppUnderTest) throws -> [(text: String, frame: CGRect)] {
        NativeSystemInput.staticTexts(pid: try pid(app), window: try facts(app).frame)
    }

    /// A window picture's pixels (RGBA, the first row at the top) and the window's screen frame, for measuring.
    struct Picture {
        let width: Int, height: Int, bytes: [UInt8], frame: CGRect

        init(_ url: URL, frame: CGRect) throws {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw Check(description: "cannot read \(url.lastPathComponent)")
            }
            width = image.width; height = image.height; self.frame = frame
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { raw in
                guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            self.bytes = bytes
        }

        private static let linear = (0...255).map { value -> Double in let c = Double(value) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

        /// WCAG's relative luminance.
        func luminance(_ x: Int, _ y: Int) -> Double {
            let i = (y * width + x) * 4
            return 0.2126 * Self.linear[Int(bytes[i])] + 0.7152 * Self.linear[Int(bytes[i + 1])] + 0.0722 * Self.linear[Int(bytes[i + 2])]
        }

        /// A screen rectangle in this picture's pixels, clipped to it.
        func pixels(_ rect: CGRect) -> CGRect {
            let scale = Double(width) / frame.width
            return CGRect(x: (rect.minX - frame.minX) * scale, y: (rect.minY - frame.minY) * scale, width: rect.width * scale, height: rect.height * scale)
                .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        }

        /// The share of the pixels in a screen rectangle that are more than 40 levels apart in a channel in `other`, a
        /// picture of the same window.
        func changed(from other: Picture, in rect: CGRect) -> Double {
            let box = pixels(rect)
            var count = 0, total = 0
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    let i = (y * width + x) * 4
                    total += 1
                    if (0..<3).contains(where: { abs(Int(bytes[i + $0]) - Int(other.bytes[i + $0])) > 40 }) { count += 1 }
                }
            }
            return total == 0 ? 0 : Double(count) / Double(total)
        }

        /// The contrast of the text in a pixel box. Glyphs cover a small part of their box: the middle value is the
        /// background, the far end the ink.
        func contrast(_ box: CGRect) -> Double {
            var values: [Double] = []
            for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) { values.append(luminance(x, y)) } }
            values.sort()
            let background = values[values.count / 2], low = values[values.count / 100], high = values[values.count * 99 / 100]
            let ink = background - low > high - background ? low : high
            return (max(background, ink) + 0.05) / (min(background, ink) + 0.05)
        }

        /// The pieces of text in a pixel region, each as the box to measure. A button's label is one Accessibility title,
        /// with no frame per text, so the pieces are found on the picture: what most of the region has is the background,
        /// a pixel more than 10 levels off it in a channel is ink (light-mode ink on the dark card is about 20 off), rows
        /// with ink make lines, and ink farther apart in a line than 0.45 of the line's height makes separate pieces: the
        /// ad blocker's "YES, block them." and its "Recommended" tag, a bookmark's title and its address, each against
        /// its own background. Each box is grown by 3 px so its middle value is what is behind the text.
        func pieces(_ region: CGRect) -> [CGRect] {
            let x0 = Int(region.minX), x1 = Int(region.maxX), y0 = Int(region.minY), y1 = Int(region.maxY)
            guard x1 - x0 >= 4, y1 - y0 >= 4 else { return [] }
            var channels: [[Int]] = [[], [], []]
            for y in y0..<y1 { for x in x0..<x1 { for c in 0..<3 { channels[c].append(Int(bytes[(y * width + x) * 4 + c])) } } }
            let base = channels.map { $0.sorted()[$0.count / 2] }
            func ink(_ x: Int, _ y: Int) -> Bool {
                let i = (y * width + x) * 4
                return (0..<3).contains { abs(Int(bytes[i + $0]) - base[$0]) > 10 }
            }
            var lines: [ClosedRange<Int>] = [], top: Int?, last = y0
            for y in y0..<y1 {
                if (x0..<x1).contains(where: { ink($0, y) }) { if top == nil { top = y }; last = y }
                else if let start = top, y - last >= 2 { lines.append(start...last); top = nil }
            }
            if let start = top { lines.append(start...last) }
            var out: [CGRect] = []
            for line in lines where line.count >= 6 {
                let join = max(10, Int(Double(line.count) * 0.45))
                var left: Int?, right = x0
                func close() {
                    guard let start = left, right - start >= 3 else { return }
                    out.append(CGRect(x: start - 3, y: line.lowerBound - 3, width: right - start + 7, height: line.count + 6).intersection(region))
                }
                for x in x0..<x1 where line.contains(where: { ink(x, $0) }) {
                    if left != nil, x - right > join { close(); left = nil }
                    if left == nil { left = x }
                    right = x
                }
                close()
            }
            return out
        }
    }

    /// Where the text sits in each onboarding control that holds some, as (left, top, right, bottom) insets in points
    /// from its rectangle, read off OnboardingViews: icons, the keychain switch, borders and rounded corners stay out.
    /// Left out: the Welcome arrow and a folder's chevron (no text), the theme editor and the finish card (their texts
    /// are static texts, measured as such), and the Safari and Full Disk Access buttons (steps this scenario does not reach).
    static func textInsets(_ id: String) -> (left: Double, top: Double, right: Double, bottom: Double)? {
        switch id {
        case "next": return (8, 8, 8, 8)                        // inside the filled shape's rounded corners
        case "back", "skip", "start-fresh": return (0, 0, 0, 0)
        case "name-field": return (10, 8, 10, 8)                // inside the focus ring
        case "secrets-toggle": return (12, 4, 72, 4)            // left of the switch
        case "bookmarks-all": return (20, 0, 0, 0)              // right of the check box
        default:
            if id.hasPrefix("adblock-") || id.hasPrefix("default-") { return (40, 6, 8, 6) }   // right of the radio circle, inside the border
            if id.hasPrefix("browser-") { return (4, 50, 4, 3) }                              // under the 40 pt icon: the name and the detail
            if id.hasPrefix("site-") { return (4, 51, 4, 4) }                                 // under the 34 pt letter tile: the site's name
            if id.hasPrefix("profile-") { return (58, 4, 4, 4) }                              // right of the check box and the person
            if id.hasPrefix("bookmark-"), !id.hasPrefix("bookmark-expand-") { return (40, 3, 20, 3) }   // right of the check box and globe, left of a star
            return nil
        }
    }

    /// The screen as it is now, captured, and the contrast against what is behind it of every static text the window
    /// lists to Accessibility and of every piece of text inside its buttons, the name field and the keychain row,
    /// measured on the picture: a label left in its light-mode ink on the dark background (or the reverse) measures about
    /// 1:1. Apple's text recognition is no judge of this: it reads near-black text on Brk's dark column. A disabled
    /// button is left out, as WCAG does. `dark`: whether the step's left column must be dark or light; nil on Welcome,
    /// which has no column. Returns what failed.
    static func readable(_ app: AppUnderTest, _ name: String, dark: Bool?) throws -> [String] {
        let current = try facts(app)
        let picture = try Picture(try app.windowScreenshot(name, number: current.windowNumber), frame: current.frame)
        var problems: [String] = []
        // The left column's background, 2% in and 60% down: below the text, beside nothing.
        let column = picture.luminance(Int(Double(picture.width) * 0.02), Int(Double(picture.height) * 0.6))
        if let dark, dark ? (column > 0.1) : (column < 0.5) {
            problems.append("\(name): the left column's luminance is \(String(format: "%.2f", column)) in \(dark ? "dark" : "light") mode")
        }
        var lowest = Double.infinity, measured: [String] = []
        func judge(_ box: CGRect, _ what: String) {
            let contrast = picture.contrast(box)
            lowest = min(lowest, contrast)
            measured.append("\(String(format: "%.1f", contrast)):1 at pixels \(Int(box.minX)),\(Int(box.minY)) \(Int(box.width))x\(Int(box.height)): \(what)")
            // WCAG's floor for large text; a wrong-appearance ink measures about 1.1.
            if contrast < 3 { problems.append("\(name): \(what) has contrast \(String(format: "%.1f", contrast)):1 against its background") }
        }
        let texts = try windowTextFrames(app)
        if texts.isEmpty { problems.append("\(name): Accessibility lists no text in the window") }
        // A blank line a screen keeps its place with (the picker's " ") has no ink to measure.
        for (text, rect) in texts where text.contains(where: { $0.isLetter || $0.isNumber }) {
            let box = picture.pixels(rect)
            if box.width >= 4, box.height >= 4 { judge(box, "\"\(text.prefix(40))\"") }
        }
        let disabled = NativeSystemInput.disabledIdentifiers(pid: try pid(app), window: current.frame)
        var controls = 0
        for (id, rect) in current.controls.sorted(by: { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }) {
            guard let inset = textInsets(id), !disabled.contains("onboarding-\(id)") else { continue }
            let region = picture.pixels(CGRect(x: rect.minX + inset.left, y: rect.minY + inset.top,
                                               width: rect.width - inset.left - inset.right, height: rect.height - inset.top - inset.bottom))
            let pieces = picture.pieces(region)
            controls += 1
            if pieces.isEmpty { problems.append("\(name): no text to see in control \(id)") }
            for (index, piece) in pieces.enumerated() { judge(piece, "control \(id), piece \(index + 1) of \(pieces.count)") }
        }
        // Kept beside the run's logs too: the scenario reports them at its end, which a later failure never reaches.
        let log = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(app.scenarioID)-readable.txt")
        let line = "\(name): \(texts.count) static texts and \(controls) controls, \(measured.count) measured, lowest contrast \(String(format: "%.1f", lowest)):1, \(problems.count) problems"
            + (problems + measured).map { "\n  " + $0 }.joined() + "\n"
        if let handle = try? FileHandle(forWritingTo: log) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? line.write(to: log, atomically: true, encoding: .utf8) }
        return problems
    }

    /// The onboarding window captured now.
    static func picture(_ app: AppUnderTest, _ name: String) throws -> Picture {
        let current = try facts(app)
        return try Picture(try app.windowScreenshot(name, number: current.windowNumber), frame: current.frame)
    }

    /// An sRGB color's hue in degrees, 0..<360 (0 for a grey).
    static func hue(_ color: RGBA) -> Double {
        let high = max(color.red, color.green, color.blue), spread = high - min(color.red, color.green, color.blue)
        guard spread > 0.0001 else { return 0 }
        let sector = high == color.red ? (color.green - color.blue) / spread : high == color.green ? (color.blue - color.red) / spread + 2 : (color.red - color.green) / spread + 4
        return (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Folders' tabs, all levels.
    static func leafTitles(_ rows: [Row]) -> [String] {
        rows.flatMap { row -> [String] in
            switch row {
            case .tab(let tab): [tab.title]
            case .folder(let folder): leafTitles(folder.children)
            case .split: []
            }
        }
    }

    static func importedFolder(_ view: WindowSnapshot, _ title: String) -> FolderRow? {
        for row in view.space.pinned.rows { if case .folder(let folder) = row, folder.title == title { return folder } }
        return nil
    }

    @Sendable static func paths(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Check(description: "the runner may not use Accessibility") }
        try app.waitUntil("the onboarding window opens on Welcome", timeout: 15) { try facts(app).step == "welcome" }
        var unreadable: [String] = []
        defer { try? app.perform(.setAppAppearance(nil)) }

        // Light: Return on Welcome and in the name field, Back, Skip for now, Escape. Welcome draws in light in either
        // appearance; its colors drift, so its contrast is the one of the moment it is captured.
        try app.perform(.setAppAppearance(.light))
        unreadable += try readable(app, "L-welcome", dark: nil)
        try key(app, KeyChord([], .returnKey))
        try waitStep(app, "name")
        try click(app, "back"); try waitStep(app, "welcome")
        try key(app, KeyChord([], .returnKey))
        try waitStep(app, "name")
        try click(app, "name-field")
        PhysicalKeys.type("Robin", pid: try pid(app))
        try key(app, KeyChord([], .returnKey))
        try waitStep(app, "pickBrowser")
        try click(app, "back"); try waitStep(app, "name")
        try app.waitUntil("Back shows the typed name in the field again") { try nameField(app) == "Robin" }
        unreadable += try readable(app, "L-name", dark: false)
        try click(app, "skip"); try waitStep(app, "pickBrowser")
        app.passed("Return on Welcome and Return in the name field each went one step; Back from the name returned to Welcome; Back from the picker showed the name again; Skip for now went on")
        try key(app, KeyChord([], .escape))
        usleep(500_000)
        let afterEscape = try facts(app).step
        try expect(afterEscape == "pickBrowser", "Escape changed the onboarding window: it shows \(afterEscape ?? "nothing")")
        unreadable += try readable(app, "L-pick-browser", dark: false)

        // No import: "No thanks", Back, then the footer's Skip for now.
        try click(app, "start-fresh"); try waitStep(app, "favorites")
        try click(app, "back"); try waitStep(app, "pickBrowser")
        try click(app, "skip"); try waitStep(app, "favorites")
        // A pick shows its letter tile in the card on the right as well (not kept: this pass never finishes).
        try click(app, "site-https://github.com/")
        unreadable += try readable(app, "L-favorites", dark: false)
        app.passed("Escape left the window as it was; No thanks and Skip for now both skip the import; Back from Favorites returns to the picker")

        // The theme editor's pad (340 pt square, 8 pt into the editor): a real click puts the selected color's dot where
        // it lands, then a real drag carries that dot on. The angle around the pad's centre is the hue (ThemePad), so
        // the Space's primary hue says where the dot is: a drag whose moves never arrived leaves the click's hue, since
        // the dot only follows the moves (a press and a release on it change nothing).
        try click(app, "next"); try waitStep(app, "theme")
        let editor = try control(app, "theme-editor")
        let pad = CGRect(x: editor.minX + 8, y: editor.minY + 8, width: 340, height: 340)
        func padPoint(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: pad.minX + pad.width * x, y: pad.minY + pad.height * y) }
        func padHue(_ x: Double, _ y: Double) -> Double { (atan2(y - 0.5, x - 0.5) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
        func hueOff(_ expected: Double) throws -> Double {
            guard let primary = try app.view().theme.gradient.first else { return 180 }
            let off = abs(hue(primary) - expected).truncatingRemainder(dividingBy: 360)
            return min(off, 360 - off)
        }
        try clickScreen(app, padPoint(0.3, 0.5))
        try app.waitUntil("a real click on the theme pad moves the color there (hue \(Int(padHue(0.3, 0.5))))") { try hueOff(padHue(0.3, 0.5)) < 12 }
        usleep(300_000)
        try dragScreen(app, from: padPoint(0.3, 0.5), to: padPoint(0.75, 0.3))
        try app.waitUntil("a real drag carries the color's dot to where the drag ends (hue \(Int(padHue(0.75, 0.3))))") { try hueOff(padHue(0.75, 0.3)) < 12 }
        let dragged = try app.view().theme
        unreadable += try readable(app, "L-theme", dark: false)
        try click(app, "back"); try waitStep(app, "favorites")
        try click(app, "next"); try waitStep(app, "theme")
        usleep(500_000)
        try expect(try app.view().theme == dragged, "Back and Next on the theme step changed the Space's colors")
        app.passed("a real click on the theme pad and a real drag of its dot each put the Space's hue where the pointer ended; Back and Next kept it")

        // Ad blocker NO survives Back; Enable Max, then Back and Not now turns it off again.
        try click(app, "next"); try waitStep(app, "adBlocker")
        try click(app, "adblock-no")
        unreadable += try readable(app, "L-ad-blocker", dark: false)
        try click(app, "back"); try waitStep(app, "theme")
        try click(app, "next"); try waitStep(app, "adBlocker")
        try click(app, "next"); try waitStep(app, "max")
        try app.waitUntil("NO turns the ad blocker off") { try settings(app).general.blockAds == false }
        try click(app, "back"); try waitStep(app, "adBlocker")
        try click(app, "next"); try waitStep(app, "max")
        unreadable += try readable(app, "L-max", dark: false)
        try click(app, "next")
        try app.waitUntil("Enable Max moves on", timeout: 6) { try ["defaultBrowser", "finish"].contains(facts(app).step) }
        try app.waitUntil("Enable Max turns Max on") { try settings(app).max.settings.provider != .off }
        if try facts(app).step == "defaultBrowser" {
            usleep(500_000)
            try click(app, "back"); try waitStep(app, "max")
            try click(app, "skip"); try waitStep(app, "defaultBrowser")
            try app.waitUntil("Not now after Back turns Max off again") { try settings(app).max.settings.provider == .off }
            unreadable += try readable(app, "L-default-browser", dark: false)
            try click(app, "default-no"); try click(app, "next")
        } else {
            app.note("this Brk is the Mac's default browser: no default browser step, and Not now after Back was not tried")
        }
        try waitStep(app, "finish")
        let greeting = try windowTexts(app)
        try expect(greeting.contains("Welcome to Brk."), "the finish screen still greets a name after Skip: \(greeting)")
        unreadable += try readable(app, "L-finish", dark: false)
        app.passed("ad blocker NO kept through Back and saved; Back from Max returned to the ad blocker; Enable Max turned Max on and Not now after Back turned it off; the skipped name is not greeted")

        // ⌘Q on the last screen: setup is not done, so the next launch shows it again.
        let quitting = try pid(app)
        try key(app, KeyChord([.command], .q))
        let start = ProcessInfo.processInfo.systemUptime
        while kill(quitting, 0) == 0, ProcessInfo.processInfo.systemUptime - start < 20 { usleep(200_000) }
        try expect(kill(quitting, 0) != 0, "Brk did not quit on ⌘Q during onboarding")
        let outcome = try app.quit()
        try expect(outcome.clean, "the ⌘Q quit: \(outcome.exit)")
        try app.launch()
        try app.waitUntil("setup shows again after ⌘Q", timeout: 15) { try facts(app).step == "welcome" }
        try expect(try ImportSyncScenarios.data(app).needsOnboarding, "⌘Q during onboarding saved setup as done")
        app.passed("⌘Q during onboarding quit cleanly and the next launch showed setup again")

        // Dark: an Arc folder through the picker, Back on the keychain step, passwords off, bookmarks and Favorites picked.
        try app.perform(.setAppAppearance(.dark))
        unreadable += try readable(app, "D-welcome", dark: nil)
        try click(app, "welcome-next"); try waitStep(app, "name")
        try click(app, "name-field")
        PhysicalKeys.type("Robin", pid: try pid(app))
        unreadable += try readable(app, "D-name", dark: true)
        try click(app, "next"); try waitStep(app, "pickBrowser")
        try click(app, "browser-arc")
        unreadable += try readable(app, "D-pick-browser", dark: true)
        try click(app, "next"); try waitStep(app, "keychain")
        try click(app, "back"); try waitStep(app, "pickBrowser")
        try click(app, "next"); try waitStep(app, "keychain")
        // The fixture has no Login Data and a test launch never reads the keychain, so the import cannot show whether
        // passwords were off: the row's switch must visibly turn (its knob slides and its color changes).
        let row = try control(app, "secrets-toggle")
        let switchArea = CGRect(x: row.maxX - 68, y: row.minY + 6, width: 56, height: row.height - 12)
        let passwordsOn = try picture(app, "D-keychain-passwords-on")
        try click(app, "secrets-toggle")
        usleep(500_000)
        let passwordsOff = try picture(app, "D-keychain-passwords-off")
        let turned = passwordsOff.changed(from: passwordsOn, in: switchArea)
        try expect(turned > 0.1, "a real click on the passwords row left its switch as it was (\(Int(turned * 100))% of it changed)")
        unreadable += try readable(app, "D-keychain", dark: true)
        try click(app, "next"); try waitStep(app, "progress")
        try app.waitUntil("the Arc import finishes", timeout: 30) { try facts(app).progressDone }
        let read = try facts(app)
        try expect(read.failures.isEmpty, "Arc import failures: \(read.failures)")
        unreadable += try readable(app, "D-progress", dark: true)
        try click(app, "next"); try waitStep(app, "bookmarks")
        // Recipes (0.0) opens; Bread (0.0.1) is left out.
        try click(app, "bookmark-expand-0.0")
        try click(app, "bookmark-0.0.1")
        unreadable += try readable(app, "D-bookmarks", dark: true)
        // Back shows the finished progress screen again; Next returns with the picks as they were (checked in Pinned below).
        try click(app, "back"); try waitStep(app, "progress")
        try click(app, "next"); try waitStep(app, "bookmarks")
        try click(app, "next"); try waitStep(app, "favorites")
        try click(app, "site-https://github.com/")
        try click(app, "site-https://www.wikipedia.org/")
        try click(app, "site-https://www.wikipedia.org/")
        unreadable += try readable(app, "D-favorites", dark: true)
        try click(app, "next"); try waitStep(app, "theme")
        unreadable += try readable(app, "D-theme", dark: true)
        try click(app, "next"); try waitStep(app, "adBlocker")
        try click(app, "adblock-yes")
        unreadable += try readable(app, "D-ad-blocker", dark: true)
        try click(app, "next"); try waitStep(app, "max")
        unreadable += try readable(app, "D-max", dark: true)
        try click(app, "skip")
        try app.waitUntil("Not now moves on", timeout: 6) { try ["defaultBrowser", "finish"].contains(facts(app).step) }
        if try facts(app).step == "defaultBrowser" {
            usleep(500_000)
            try click(app, "default-no")
            unreadable += try readable(app, "D-default-browser", dark: true)
            try click(app, "next")
        }
        try waitStep(app, "finish")
        let finish = try facts(app)
        app.note("Finish summary: " + finish.summary.joined(separator: "; "))
        try expect(finish.summary.contains("2 Spaces from Arc") && finish.summary.contains("2 bookmarks in Pinned"), "finish summary: \(finish.summary)")
        unreadable += try readable(app, "D-finish", dark: true)

        // The red button finishes setup with what was picked.
        try clickScreen(app, try closeButton(app, window: "Welcome to Brk"))
        try app.waitUntil("the red button closes the onboarding window") { try facts(app).step == nil }
        try app.waitUntil("Brk 101 opens in the browser window", timeout: 15) { try currentTab(app.view())?.title == "Brk 101" }
        let data = try ImportSyncScenarios.data(app)
        try expect(!data.needsOnboarding && data.userName == "Robin", "after the red button: setup done \(!data.needsOnboarding), name \(data.userName ?? "none")")
        var view = try app.view()
        try expect(view.space.title == "Home" && view.dock.map(\.title) == ["Home", "Work"], "Spaces after the Arc import: \(view.dock.map(\.title)), showing \(view.space.title)")
        let fromArc = try XCTUnwrapValue(importedFolder(view, "Imported from Arc"))
        try expect(leafTitles(fromArc.children).sorted() == ["Docs", "Soup"], "the Arc bookmarks in Pinned: \(leafTitles(fromArc.children))")
        try expect(view.favorites.tiles.map { $0.url?.absoluteString } == ["https://github.com/"], "Favorites after the picks: \(view.favorites.tiles.map(\.title))")
        try expect(try settings(app).general.blockAds != false, "ad blocker YES did not turn it back on")
        _ = try app.screenshot("D-sidebar")
        app.passed("Arc's two Spaces and the two ticked bookmarks came over (through Back and Next on the bookmarks step), the Favorites pick and the typed name were kept, the passwords switch turned off, and the red button finished setup")

        // Light again, for the import screens the first light pass skipped (keychain, progress, bookmarks).
        // Brk › Import from Another Browser… (the menu item pressed through Accessibility, as the other scenarios do; no
        // pointer on the menu bar); Arc's keychain step and Back; then a bookmarks file chosen in the open panel with the
        // keyboard. The file sits in a folder whose path has only keys AIThreadsScenarios.type knows (lower case, digits,
        // - and /).
        try app.perform(.setAppAppearance(.light))
        let owner = try pid(app)
        let folder = URL(fileURLWithPath: "/tmp/brk-onboarding-paths-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("bookmarks.html")
        try """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
            <TITLE>Bookmarks</TITLE>
            <H1>Bookmarks</H1>
            <DL><p>
                <DT><A HREF="\(app.site.url("index.html?file-one").absoluteString)">File One</A>
                <DT><A HREF="\(app.site.url("index.html?file-two").absoluteString)">File Two</A>
            </DL><p>
            """.write(to: file, atomically: true, encoding: .utf8)
        try NativeSystemInput.chooseMainMenu(pid: owner, menu: "Brk", item: "Import from Another Browser…")
        try waitStep(app, "pickBrowser")
        try click(app, "browser-arc")
        try click(app, "next"); try waitStep(app, "keychain")
        unreadable += try readable(app, "L-keychain", dark: false)
        try click(app, "back"); try waitStep(app, "pickBrowser")
        try click(app, "browser-file")
        unreadable += try readable(app, "L-import-pick", dark: false)
        try click(app, "next")
        // The panel is another process's view inside Brk's sheet: keys reach it from the window server, as a keyboard's do
        // (Accessibility reports its rows' places off the panel, so no click). ⇧⌘G, the file's path, Return to go there
        // and select it, Return for Import; each only while Brk is the active app.
        try app.waitUntil("the open panel opens", timeout: 8) { try app.native().appWindows.contains { $0.className == "NSOpenPanel" && $0.isVisible && $0.isKey } }
        usleep(1_000_000)
        func active() throws { try expect(try app.native().appActive == true, "Brk is not the active app; no key posted") }
        try active(); try AIThreadsScenarios.key([.command, .shift], .g)
        usleep(800_000)
        try active(); try AIThreadsScenarios.type(file.path)
        usleep(500_000)
        try active(); try AIThreadsScenarios.key([], .returnKey)
        usleep(1_000_000)
        try active(); try AIThreadsScenarios.key([], .returnKey)
        try waitStep(app, "progress")
        try app.waitUntil("the file import finishes", timeout: 15) { try facts(app).progressDone }
        unreadable += try readable(app, "L-progress", dark: false)
        try click(app, "next"); try waitStep(app, "bookmarks")
        unreadable += try readable(app, "L-bookmarks", dark: false)
        try click(app, "next"); try waitStep(app, "finish")
        let imported = try facts(app)
        try expect(imported.summary == ["2 bookmarks in Pinned"], "the file import's finish screen: \(imported.summary)")
        unreadable += try readable(app, "L-import-finish", dark: false)
        try click(app, "next")
        try app.waitUntil("Done closes the import window") { try facts(app).step == nil }
        view = try app.view()
        let fromFile = try XCTUnwrapValue(importedFolder(view, "Imported from bookmarks.html"))
        try expect(leafTitles(fromFile.children) == ["File One", "File Two"], "the file's bookmarks in Pinned: \(leafTitles(fromFile.children))")
        app.passed("Import from Another Browser…: Back from Arc's keychain step returned to the picker, and a bookmarks file chosen in the real open panel went into Pinned")

        // Brk › Check for Updates… (pressed through Accessibility): the alert names this build; a real click on Open Latest
        // Build opens the Latest build release. Only the new tab's address is checked; its page is not waited for, and the
        // tab is closed right away.
        try NativeSystemInput.chooseMainMenu(pid: owner, menu: "Brk", item: "Check for Updates…")
        var open: CGRect?
        try app.waitUntil("the update alert opens", timeout: 8) {
            open = NativeSystemInput.frame(pid: owner, title: "Open Latest Build", roles: ["AXButton"])
            return open != nil
        }
        let alert = NativeSystemInput.staticTexts(pid: owner).map(\.text)
        try expect(alert.contains("Brk has no update channel") && alert.contains { $0.hasPrefix("This copy is Brk ") && $0.contains("does not update itself") },
                   "the update alert says: \(alert)")
        _ = try app.screenshotSheet("updates")
        let tabsBefore = Set(allTabs(try app.view()).map(\.id))
        try clickScreen(app, CGPoint(x: open!.midX, y: open!.midY))
        var release: ItemID?
        try app.waitUntil("Open Latest Build opens the Latest build release in a tab", timeout: 10) {
            release = allTabs(try app.view()).first { !tabsBefore.contains($0.id) && $0.url?.host == "github.com" && $0.url?.path.hasSuffix("/releases/tag/latest") == true }?.id
            return release != nil
        }
        if let release { try app.dispatch(.tab(.close(.item(release)))) }
        app.passed("Check for Updates… named this build and Open Latest Build opened the release page in a tab")

        try expect(unreadable.isEmpty, "onboarding screens with hard-to-read text:\n" + unreadable.joined(separator: "\n"))
        app.passed("on every onboarding screen, in light and in dark, every static text and every piece of text in the buttons, the name field and the passwords row stands out from its background (3:1 or more)")
    }
}
