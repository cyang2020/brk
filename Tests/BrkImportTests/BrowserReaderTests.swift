import BrkBase
import BrkDomain
@testable import BrkImport
import Foundation
import SQLite3
import XCTest

/// The readers against small profiles made here, in a temporary folder: no real browser data is used or kept.
final class BrowserReaderTests: XCTestCase {
    /// 2026-11-12 00:00 UTC.
    let now = Instant(milliseconds: 1_794_441_600_000)
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("brk-import-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    /// Chrome's Bookmarks JSON keeps its roots and folders and drops script links; History brings only the last 90 days,
    /// without subframe visits, and ranks the most visited sites for the Favorites step.
    func testChromeBookmarksAndHistoryReadFromACopiedProfile() throws {
        let profile = folder.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let bookmarks: [String: Any] = ["roots": [
            "bookmark_bar": ["type": "folder", "name": "Bookmarks bar", "children": [
                ["type": "url", "name": "Docs", "url": "https://docs.example.test/"],
                ["type": "folder", "name": "Work", "children": [["type": "url", "name": "Tracker", "url": "https://tracker.example.test/a"],
                                                                 ["type": "url", "name": "Script", "url": "javascript:alert(1)"]]]]],
            "other": ["type": "folder", "name": "Other bookmarks", "children": [["type": "url", "name": "News", "url": "https://news.example.test/"]]],
            "synced": ["type": "folder", "name": "Mobile bookmarks", "children": []]]]
        try JSONSerialization.data(withJSONObject: bookmarks).write(to: profile.appendingPathComponent("Bookmarks"))
        let day: Int64 = 86_400_000_000
        let recent = Chromium.time(now) - day, old = Chromium.time(now) - 120 * day
        try sqlite(profile.appendingPathComponent("History"), [
            "CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, typed_count INTEGER, hidden INTEGER)",
            "CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER, transition INTEGER)",
            "INSERT INTO urls VALUES (1, 'https://docs.example.test/', 'Docs', 40, 5, 0), (2, 'https://news.example.test/', 'News', 3, 0, 0), (3, 'https://ads.example.test/frame', 'Frame', 9, 0, 0)",
            "INSERT INTO visits VALUES (1, 1, \(recent), 1), (2, 2, \(old), 1), (3, 3, \(recent), 3)",
        ])
        let read = ChromiumReader.read(SourceProfile(id: "Default", name: "Person 1", path: profile), kind: .chrome, .init(now: now))
        XCTAssertEqual(read.failures, [])
        XCTAssertEqual(read.bookmarks, [
            .folder(title: "Bookmarks bar", children: [.tab(title: "Docs", url: URL(string: "https://docs.example.test/")!),
                                                       .folder(title: "Work", children: [.tab(title: "Tracker", url: URL(string: "https://tracker.example.test/a")!)])]),
            .folder(title: "Other bookmarks", children: [.tab(title: "News", url: URL(string: "https://news.example.test/")!)]),
        ])
        XCTAssertEqual(read.visits.map(\.url.host), ["docs.example.test"], "the 120-day-old and the subframe visits stay behind")
        XCTAssertEqual(read.topSites.first?.url.absoluteString, "https://docs.example.test/")
    }

    /// Passwords and cookies open with the source's keychain password; logins land in a Brk Login Data encrypted under
    /// Brk's key, once: importing again adds nothing, and while another connection holds the database the rows wait
    /// (encrypted) in the staged file until the merge that runs before CEF starts.
    func testChromiumSecretsDecryptAndLoginDataWritesOnceOrStages() throws {
        let source = ChromiumKey(password: "source-password"), brk = ChromiumKey(password: "mock_password")
        let profile = folder.appendingPathComponent("Profile 1", isDirectory: true)
        try FileManager.default.createDirectory(at: profile.appendingPathComponent("Network"), withIntermediateDirectories: true)
        let secret = try XCTUnwrap(source.encrypt(Data("hunter2".utf8)))
        try sqlite(profile.appendingPathComponent("Login Data"), [loginsTable,
            "INSERT INTO logins (origin_url, username_value, password_value, signon_realm, date_created, blacklisted_by_user, scheme) VALUES ('https://login.example.test/', 'casey', X'\(hex(secret))', 'https://login.example.test/', 13300000000000000, 0, 0)"])
        let hostHash = Data(repeating: 7, count: 32)
        let cookie = try XCTUnwrap(source.encrypt(hostHash + Data("session-value".utf8)))
        let far = Chromium.time(now) + 86_400_000_000
        try sqlite(profile.appendingPathComponent("Network/Cookies"), [
            "CREATE TABLE meta(key TEXT, value TEXT)", "INSERT INTO meta VALUES ('version', '24')",
            "CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, samesite INTEGER, creation_utc INTEGER, last_access_utc INTEGER, has_expires INTEGER, is_persistent INTEGER, priority INTEGER, top_frame_site_key TEXT)",
            "INSERT INTO cookies VALUES ('.example.test', 'sid', '', X'\(hex(cookie))', '/', \(far), 1, 1, 1, 1, 1, 1, 1, 1, ''), ('old.example.test', 'gone', 'x', X'', '/', 5, 0, 0, -1, 1, 1, 1, 1, 1, '')",
        ])
        let read = ChromiumReader.read(SourceProfile(id: "Profile 1", name: "Work", path: profile), kind: .chrome, .init(now: now, key: source))
        XCTAssertEqual(read.failures, [])
        XCTAssertEqual(read.logins.map(\.password), ["hunter2"])
        XCTAssertEqual(read.cookies.map(\.value), ["session-value"], "host hash dropped, expired cookie left out")

        let target = folder.appendingPathComponent("Brk/Default", isDirectory: true), staging = folder.appendingPathComponent("Brk/pending-logins")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try sqlite(target.appendingPathComponent("Login Data"), [loginsTable])
        XCTAssertEqual(try LoginDataWriter.write(read.logins, key: brk, profileFolder: target, staging: staging), .written(1))
        XCTAssertEqual(try LoginDataWriter.write(read.logins, key: brk, profileFolder: target, staging: staging), .written(0))
        let stored = try passwordValues(target.appendingPathComponent("Login Data"))
        XCTAssertEqual(stored.compactMap { brk.decrypt($0).flatMap { String(data: $0, encoding: .utf8) } }, ["hunter2"])

        // Chromium's exclusive hold, played by a second connection with an exclusive transaction.
        var holder: OpaquePointer?
        XCTAssertEqual(sqlite3_open(target.appendingPathComponent("Login Data").path, &holder), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(holder, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        var other = read.logins[0]; other.usernameValue = "second"
        XCTAssertEqual(try LoginDataWriter.write([other], key: brk, profileFolder: target, staging: staging), .staged(1))
        let staged = try String(contentsOf: LoginDataWriter.stagedFile(for: target, in: staging), encoding: .utf8)
        XCTAssertFalse(staged.contains("hunter2"), "the staged file holds the encrypted value only")
        XCTAssertEqual(LoginDataWriter.mergeStaged(chromiumRoot: target.deletingLastPathComponent(), staging: staging), 0, "still held: kept for later")
        sqlite3_exec(holder, "COMMIT", nil, nil, nil); sqlite3_close(holder)
        XCTAssertEqual(LoginDataWriter.mergeStaged(chromiumRoot: target.deletingLastPathComponent(), staging: staging), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: LoginDataWriter.stagedFile(for: target, in: staging).path))
        XCTAssertEqual(try passwordValues(target.appendingPathComponent("Login Data")).count, 2)
    }

    /// Safari's export ZIP: bookmarks HTML, history JSON (90 days) and passwords CSV, with no permission asked.
    func testSafariExportZipBringsBookmarksHistoryAndPasswords() throws {
        let export = folder.appendingPathComponent("Safari Export", isDirectory: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try Data("""
            <!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p><DT><H3>Favorites</H3><DL><p><DT><A HREF="https://apple.example.test/">Apple</A></DL><p></DL>
            """.utf8).write(to: export.appendingPathComponent("Bookmarks.html"))
        let recent = (now.milliseconds - 86_400_000) * 1000, old = (now.milliseconds - 200 * 86_400_000) * 1000
        try JSONSerialization.data(withJSONObject: ["metadata": ["browser_name": "Safari", "data_type": "history"], "history": [
            ["url": "https://read.example.test/a", "title": "Read", "time_usec": recent, "visit_count": 4],
            ["url": "https://old.example.test/", "title": "Old", "time_usec": old, "visit_count": 1]]])
            .write(to: export.appendingPathComponent("History.json"))
        try Data("Title,URL,Username,Password,Notes,OTPAuth\nShop,https://shop.example.test/login,casey,pa55,,\n".utf8)
            .write(to: export.appendingPathComponent("Passwords.csv"))
        let zip = folder.appendingPathComponent("Safari Export.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", export.path, zip.path]
        try ditto.run(); ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let read = try SafariReader.export(at: zip, now: now)
        XCTAssertEqual(read.bookmarks, [.folder(title: "Favorites", children: [.tab(title: "Apple", url: URL(string: "https://apple.example.test/")!)])])
        XCTAssertEqual(read.visits.map(\.title), ["Read"])
        XCTAssertEqual(read.logins.map { [$0.signonRealm, $0.usernameValue, $0.password] }, [["https://shop.example.test/", "casey", "pa55"]])
        XCTAssertThrowsError(try SafariReader.export(at: export.appendingPathComponent("Bookmarks.html"), now: now)) {
            XCTAssertEqual($0 as? SafariReader.Failure, .notZip)
        }
    }

    /// Firefox's places.sqlite: the toolbar's tree under Firefox's name for it, and recent typed or linked visits.
    func testFirefoxPlacesBookmarksAndHistory() throws {
        let profile = folder.appendingPathComponent("Profiles/abc.default-release", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let recent = (now.milliseconds - 3_600_000) * 1000
        try sqlite(profile.appendingPathComponent("places.sqlite"), [
            "CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, hidden INTEGER, frecency INTEGER)",
            "CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER, title TEXT, guid TEXT)",
            "CREATE TABLE moz_historyvisits(id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER, visit_type INTEGER)",
            "INSERT INTO moz_places VALUES (1, 'https://mdn.example.test/', 'MDN', 12, 0, 900), (2, 'https://embed.example.test/x', 'Embed', 1, 0, 1)",
            "INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 0, '', 'root________'), (2, 2, NULL, 1, 0, 'toolbar', 'toolbar_____'), (3, 2, NULL, 1, 1, 'menu', 'menu________'), (4, 2, NULL, 2, 0, 'Dev', 'aaaaaaaaaaaa'), (5, 1, 1, 4, 0, 'MDN', 'bbbbbbbbbbbb')",
            "INSERT INTO moz_historyvisits VALUES (1, 1, \(recent), 2), (2, 2, \(recent), 4)",
        ])
        try Data("[Profile0]\nName=default-release\nIsRelative=1\nPath=Profiles/abc.default-release\n".utf8).write(to: folder.appendingPathComponent("profiles.ini"))
        let profiles = BrowserCatalog.firefoxProfiles(root: folder)
        XCTAssertEqual(profiles.map(\.name), ["default-release"])
        let read = FirefoxReader.read(try XCTUnwrap(profiles.first), now: now)
        XCTAssertEqual(read.failures, [])
        XCTAssertEqual(read.bookmarks, [.folder(title: "Bookmarks Toolbar", children: [.folder(title: "Dev", children: [.tab(title: "MDN", url: URL(string: "https://mdn.example.test/")!)])])])
        XCTAssertEqual(read.visits.map(\.title), ["MDN"], "embed visits are not history")
    }

    /// Arc's sidebar: Spaces with their profile, icon and theme; Pinned with a folder and a split; Today; Favorites.
    func testArcSidebarMapsSpacesOneToOne() throws {
        func tab(_ id: String, _ parent: String, _ url: String, _ title: String) -> [String: Any] {
            ["id": id, "parentID": parent, "childrenIds": [], "data": ["tab": ["savedURL": url, "savedTitle": title]]]
        }
        let color: [String: Any] = ["red": 0.2, "green": 0.4, "blue": 0.9, "alpha": 1, "colorSpace": "extendedSRGB"]
        let sidebar: [String: Any] = ["sidebar": ["containers": [["global": [:]], [
            "spaces": ["S1", ["id": "S1", "title": "Work", "profile": ["custom": ["_0": ["directoryBasename": "Profile 1"]]],
                              "customInfo": ["iconType": ["emoji_v2": "🚀"], "windowTheme": ["background": ["single": ["_0": ["style": ["color": ["_0": ["blendedSingleColor": ["_0": [
                                  "color": color, "modifiers": ["intensityFactor": 0.6, "overlay": "grain", "noiseFactor": 0.1], "translucencyStyle": "dark"]]]]]]]]]],
                              "containerIDs": ["unpinned", "U1", "pinned", "P1"]]],
            "topAppsContainerIDs": [["default": true], "T0"],
            "items": [
                "P1", ["id": "P1", "childrenIds": ["F1", "SP"], "data": ["itemContainer": ["containerType": ["spaceItems": ["_0": "S1"]]]]],
                "U1", ["id": "U1", "childrenIds": ["t4"], "data": ["itemContainer": ["containerType": ["spaceItems": ["_0": "S1"]]]]],
                "T0", ["id": "T0", "childrenIds": ["t5"], "data": ["itemContainer": ["containerType": ["topApps": ["_0": ["default": true]]]]]],
                "F1", ["id": "F1", "parentID": "P1", "title": "Specs", "childrenIds": ["t1"], "data": ["list": [:]]],
                "SP", ["id": "SP", "parentID": "P1", "childrenIds": ["t2", "t3"], "data": ["splitView": ["layoutOrientation": "horizontal"]]],
                "t1", tab("t1", "F1", "https://spec.example.test/", "Spec"),
                "t2", tab("t2", "SP", "https://left.example.test/", "Left"),
                "t3", tab("t3", "SP", "https://right.example.test/", "Right"),
                "t4", tab("t4", "U1", "https://today.example.test/", "Today"),
                "t5", tab("t5", "T0", "https://mail.example.test/", "Mail"),
            ]]]]]
        let result = try ArcSidebar.read(try JSONSerialization.data(withJSONObject: sidebar), profileNames: ["Profile 1": "Work profile"])
        let space = try XCTUnwrap(result.spaces.first)
        XCTAssertEqual(space.key, "arc:S1")
        XCTAssertEqual(space.title, "Work")
        XCTAssertEqual(space.profileName, "Work profile")
        XCTAssertEqual(space.icon, .custom(.emoji("🚀")))
        XCTAssertEqual(space.theme?.colors, [RGBA(0.2, 0.4, 0.9)])
        XCTAssertEqual(space.theme?.appearance, .dark)
        XCTAssertEqual(space.pinned, [
            .folder(title: "Specs", children: [.tab(title: "Spec", url: URL(string: "https://spec.example.test/")!)]),
            .split(orientation: .horizontal, panes: [.tab(title: "Left", url: URL(string: "https://left.example.test/")!),
                                                     .tab(title: "Right", url: URL(string: "https://right.example.test/")!)]),
        ])
        XCTAssertEqual(space.today, [.tab(title: "Today", url: URL(string: "https://today.example.test/")!)])
        XCTAssertEqual(result.favorites["Default"], [.tab(title: "Mail", url: URL(string: "https://mail.example.test/")!)])
    }

    /// The user's navy Space came in pale lavender: Arc's slider (more color to the right) was read as Brk's wash, and
    /// the "light" Arc saves for its automatic button became Brk's sun, so it never followed dark mode. Also: a light and
    /// dark pair keeps both, and a style with no colors to read takes the theme's palette color, not Brk's beige default.
    func testArcThemeReadsTheSliderTheAppearanceAndPairs() throws {
        func style(_ red: Double, _ green: Double, _ blue: Double, intensity: Double, translucency: String) -> [String: Any] {
            ["style": ["color": ["_0": ["blendedSingleColor": ["_0": [
                "color": ["red": red, "green": green, "blue": blue, "alpha": 1, "colorSpace": "extendedSRGB"],
                "modifiers": ["intensityFactor": intensity, "overlay": "grain", "noiseFactor": 0], "translucencyStyle": translucency]]]]],
             "contentOverBackgroundAppearance": "dark", "isVibrant": true]
        }
        let navy = try XCTUnwrap(ArcSidebar.theme(["background": ["single": ["_0": style(0.15, 0.27, 0.42, intensity: 0.73, translucency: "light")]]]))
        XCTAssertEqual(navy.intensity, 0.27, accuracy: 1e-9)
        XCTAssertEqual(navy.appearance, .auto)
        XCTAssertLessThan(relativeLuminance(resolveTheme(navy, systemScheme: .dark).windowColor), 0.08, "navy stays dark in dark mode")

        let pair = try XCTUnwrap(ArcSidebar.theme(["background": ["appearanceBased": [
            "light": style(0.5, 0.7, 0.9, intensity: 0.5, translucency: "light"), "dark": style(0.3, 0.25, 0.45, intensity: 0.9, translucency: "dark")]]]))
        XCTAssertEqual(pair.variants?.selection, .auto)
        XCTAssertEqual(pair.variants?.light.colors.first?.color, RGBA(0.5, 0.7, 0.9))
        XCTAssertEqual(pair.variants?.dark.colors.first?.color, RGBA(0.3, 0.25, 0.45))
        let shown = try XCTUnwrap(resolveTheme(pair, systemScheme: .dark).gradient.first)
        for (value, expected) in zip([shown.red, shown.green, shown.blue], [0.3, 0.25, 0.45]) {
            XCTAssertEqual(value, expected, accuracy: 1e-9, "dark mode shows the dark style")
        }

        let named = try XCTUnwrap(ArcSidebar.theme(["background": ["single": ["_0": ["style": ["color": ["_0": ["basicColor": ["_0": "darkBlue"]]]]]]],
                                                    "primaryColorPalette": ["shaded": ["red": 0.1, "green": 0.2, "blue": 0.5, "alpha": 1]]]))
        XCTAssertEqual(named.colors, [RGBA(0.1, 0.2, 0.5)])
    }

    /// A sidebar file that lists a folder under itself twice made the import build that folder 2^32 times.
    func testArcSidebarPlacesAnItemListedTwiceOnce() throws {
        let sidebar: [String: Any] = ["sidebar": ["containers": [["global": [:]], [
            "spaces": ["S1", ["id": "S1", "title": "Work", "containerIDs": ["unpinned", "U1", "pinned", "P1"]]],
            "items": [
                "P1", ["id": "P1", "childrenIds": ["F1"], "data": ["itemContainer": ["containerType": ["spaceItems": ["_0": "S1"]]]]],
                "U1", ["id": "U1", "childrenIds": [], "data": ["itemContainer": ["containerType": ["spaceItems": ["_0": "S1"]]]]],
                "F1", ["id": "F1", "parentID": "P1", "title": "Loop", "childrenIds": ["F1", "F1", "t1", "t1"], "data": ["list": [:]]],
                "t1", ["id": "t1", "parentID": "F1", "childrenIds": [], "data": ["tab": ["savedURL": "https://one.example.test/", "savedTitle": "One"]]],
            ]]]]]
        let result = try ArcSidebar.read(try JSONSerialization.data(withJSONObject: sidebar))
        XCTAssertEqual(result.spaces.first?.pinned, [.folder(title: "Loop", children: [.tab(title: "One", url: URL(string: "https://one.example.test/")!)])])
    }

    // MARK: Fixture helpers

    /// Login Data's `logins` table exactly as Brk's Chromium 154 makes it (schema version 43, read from a Brk profile):
    /// its NOT NULL DEFAULT columns are where a careless insert loses rows.
    let loginsTable = """
        CREATE TABLE logins (origin_url VARCHAR NOT NULL, action_url VARCHAR, username_element VARCHAR, username_value VARCHAR, password_element VARCHAR,
        password_value BLOB, submit_element VARCHAR, signon_realm VARCHAR NOT NULL, date_created INTEGER NOT NULL, blacklisted_by_user INTEGER NOT NULL,
        scheme INTEGER NOT NULL, password_type INTEGER, times_used INTEGER, form_data BLOB, display_name VARCHAR, icon_url VARCHAR, federation_url VARCHAR,
        skip_zero_click INTEGER, generation_upload_status INTEGER, possible_username_pairs BLOB, id INTEGER PRIMARY KEY AUTOINCREMENT,
        date_last_used INTEGER NOT NULL DEFAULT 0, moving_blocked_for BLOB, date_password_modified INTEGER NOT NULL DEFAULT 0, sender_email VARCHAR,
        sender_name VARCHAR, date_received INTEGER, sharing_notification_displayed INTEGER NOT NULL DEFAULT 0, keychain_identifier BLOB,
        sender_profile_image_url VARCHAR, date_last_filled INTEGER NOT NULL DEFAULT 0, actor_login_approved INTEGER NOT NULL DEFAULT 0,
        UNIQUE (origin_url, username_element, username_value, password_element, signon_realm))
        """

    func sqlite(_ url: URL, _ statements: [String]) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: error!) + " in " + sql])
            }
        }
    }

    func passwordValues(_ url: URL) throws -> [Data] {
        var db: OpaquePointer?, statement: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_finalize(statement); sqlite3_close(db) }
        sqlite3_prepare_v2(db, "SELECT password_value FROM logins ORDER BY id", -1, &statement, nil)
        var out: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(Data(bytes: sqlite3_column_blob(statement, 0), count: Int(sqlite3_column_bytes(statement, 0))))
        }
        return out
    }

    func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
