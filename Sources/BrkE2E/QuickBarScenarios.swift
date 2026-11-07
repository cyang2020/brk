import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The command bar's own quick jobs beyond Arc (calculator family, files, apps, Tab to ask, emoji), through real key
/// events posted at the window server, as a keyboard types them. The rows are read through Accessibility, by what they
/// show. Files and apps come from a fixture folder (`BRK_LOCAL_SEARCH_FIXTURE`), never the real home folder; the fixture
/// app only appends a line to a marker file; the rates come from a fixture file with no network.
enum QuickBarScenarios {
    static let all = [
        Scenario("QuickBar-Answers", "percent, root, units, CSS, dates and times answer inline, Return copies; bare words sit under the typed row; searches stay searches", cefOnly: "native command bar", answers),
        Scenario("QuickBar-Currency", "a currency question answers from the rates file with its date, Return copies", cefOnly: "native command bar", currency),
        Scenario("QuickBar-NoRates", "with no rates there is no currency row and the search stays", cefOnly: "native command bar", noRates),
        Scenario("QuickBar-Files", "file rows from the fixture folder: last places, hidden and Library left out, Return opens, Cmd+Return reveals, Option+Return copies, the file mode, no stale rows", cefOnly: "native command bar", files),
        Scenario("QuickBar-Spotlight", "the file rows through the real Spotlight index, in a fixture folder outside the home folder", cefOnly: "native command bar", spotlight),
        Scenario("QuickBar-Apps", "an app by name with Return launching it", cefOnly: "native command bar", apps),
        Scenario("QuickBar-AskTab", "Tab sends the text to the local AI; site search first; no text, Max off and an address stay as they were", cefOnly: "native command bar", askTab),
        Scenario("QuickBar-Emoji", "emoji <name> lists matches, Return copies", cefOnly: "native command bar", emoji),
        Scenario("QuickBar-Beside", "none of it in the bar over the address, an empty pane, site search or AI mode", cefOnly: "native command bar", beside),
    ]

    // MARK: Fixtures

    private static let fixedRates = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    <gesmes:subject>Reference rates</gesmes:subject>
    <Cube><Cube time='2026-11-06'><Cube currency='USD' rate='1.10'/><Cube currency='CNY' rate='7.70'/></Cube></Cube>
    </gesmes:Envelope>
    """

    /// Launch Services refuses apps under /tmp, so the fixture lives in the checkout's build folder; the Spotlight one in
    /// /Users/Shared, which is indexed and not the home folder.
    static func fixtureFolder(_ app: AppUnderTest) -> URL {
        if app.scenarioID == "QuickBar-Spotlight" {
            return URL(fileURLWithPath: "/Users/Shared/brk-quickbar-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return app.site.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/quick-bar/\(app.scenarioID)", isDirectory: true)
    }

    static func ratesFile(_ app: AppUnderTest) -> URL { app.dataDirectory.appendingPathComponent("rates.xml") }

    private static func make(_ app: AppUnderTest, files: [String]) throws -> URL {
        let root = fixtureFolder(app), manager = FileManager.default
        try? manager.removeItem(at: root)
        for file in files {
            let url = root.appendingPathComponent(file)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture\n".utf8).write(to: url)
        }
        return root
    }

    /// A background app with no window whose whole work is one line in `marker`; it also claims `.brkquickdoc`, so a file
    /// of that type opening with its default app can be seen without any real app starting.
    private static func makeApp(_ root: URL, name: String, marker: URL) throws -> URL {
        let bundle = root.appendingPathComponent("Applications/\(name).app"), macos = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.brk.quickbar-fixture</string><key>CFBundleName</key><string>\(name)</string>
        <key>CFBundleExecutable</key><string>run</string><key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleVersion</key><string>1</string><key>LSBackgroundOnly</key><true/>
        <key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeExtensions</key><array><string>brkquickdoc</string></array>
        <key>CFBundleTypeName</key><string>Quick bar fixture</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Owner</string></dict></array>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let source = root.appendingPathComponent("run.c")
        try Data("""
        #include <stdio.h>
        int main(void) { FILE *f = fopen("\(marker.path)", "a"); if (f) { fputs("launched\\n", f); fclose(f); } return 0; }
        """.utf8).write(to: source)
        try tool("/usr/bin/clang", ["-o", macos.appendingPathComponent("run").path, source.path])
        try tool("/usr/bin/codesign", ["-s", "-", "--force", bundle.path])
        try FileManager.default.removeItem(at: source)
        try tool(lsregister, ["-f", bundle.path])
        return bundle
    }

    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    private static func tool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "\(path) failed with \(process.terminationStatus)")
    }

    private static func removeFixture(_ root: URL, app bundle: URL? = nil) {
        if let bundle { try? tool(lsregister, ["-u", bundle.path]) }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Real keys

    private static let codes: [Character: (code: CGKeyCode, shift: Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ".": (47, false), ",": (43, false), "/": (44, false), "-": (27, false), "=": (24, false), "'": (39, false),
                                                   "%": (23, true), "?": (44, true), ":": (41, true), "(": (25, true), ")": (29, true), "+": (24, true), "*": (28, true)]
        for key in Key.allCases {
            let name = key.description
            if name.count == 1, let character = name.first, character.isASCII, character.isLetter || character.isNumber { map[character] = (CGKeyCode(key.code), false) }
        }
        return map
    }()

    /// Text as a US keyboard types it, posted at the window server while this Brk is the active app.
    private static func type(_ app: AppUnderTest, _ text: String) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        for character in text {
            guard let key = codes[character] else { throw Check(description: "no key for \(character)") }
            if key.shift { post(56, true, .maskShift) }
            post(key.code, true, key.shift ? .maskShift : [])
            post(key.code, false, key.shift ? .maskShift : [])
            if key.shift { post(56, false, []) }
        }
        PhysicalKeys.clearSystemModifiers(KeyChord([.shift], .a))
    }

    private static func press(_ app: AppUnderTest, _ modifiers: Modifiers = [], _ key: Key) throws {
        try WindowServerKeys.press(app, KeyChord(modifiers, key), window: app.window!)
    }

    private static func isOpen(_ app: AppUnderTest) throws -> Bool { isCommandBar(try app.view().overlay) }

    /// Cmd+T for real, then the focused input.
    private static func open(_ app: AppUnderTest) throws {
        try press(app, [.command], .t)
        try app.waitUntil("the bar from a real Cmd+T") { try isOpen(app) }
        try app.waitUntil("the bar's input focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
    }

    private static func dismiss(_ app: AppUnderTest) throws {
        for _ in 0..<3 where try isOpen(app) {
            try press(app, [], .escape)
            app.sleep(0.2)
        }
        try app.waitUntil("the bar closed") { try !isOpen(app) }
    }

    private static func rows(_ app: AppUnderTest) throws -> [[String]] { try CommandBarEvidenceScenarios.rowTexts(app) }

    /// Waits for rows that satisfy `condition`; the last rows read are returned, and named in a failure.
    @discardableResult
    private static func waitForRows(_ app: AppUnderTest, _ what: String, timeout: Double = 6, _ condition: ([[String]]) -> Bool) throws -> [[String]] {
        var last: [[String]] = []
        do {
            try app.waitUntil(what, timeout: timeout) {
                last = try rows(app)
                return condition(last)
            }
        } catch {
            throw Check(description: "\(what): the rows are \(last)")
        }
        return last
    }

    private static func pasteboard(_ app: AppUnderTest) throws -> String {
        if case .text(let text) = try app.send(.readPasteboard) { return text }
        return ""
    }

    /// The user's clipboard is put back whatever the body does.
    private static func keepingPasteboard(_ app: AppUnderTest, _ body: () throws -> Void) throws {
        let saved = try pasteboard(app)
        defer { _ = try? app.send(.pasteboard(saved)) }
        try body()
    }

    private static func preflight(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Skipped(description: "reading the rows needs Accessibility for the runner") }
        guard WindowServerKeys.allowed else { throw Skipped(description: "posting keys needs the runner's event access") }
    }

    private static func has(_ row: [String], _ text: String) -> Bool { row.contains { $0.contains(text) } }
    private static let fileCaption = "⌘↩ Reveal"

    // MARK: A

    /// Types `text`, waits for the answer on the first row, Return copies it and no tab opens.
    private static func copies(_ app: AppUnderTest, _ text: String, _ answer: String, shot: String? = nil) throws {
        let tabs = todayIDs(try app.view())
        try open(app)
        try type(app, text)
        let shown = try waitForRows(app, "\(text) answers \(answer)") { $0.first.map { has($0, answer) && has($0, "Copy Result") } ?? false }
        try expect(has(shown[0], text), "the row should also show the expression: \(shown[0])")
        if let shot { _ = try app.screenshot(shot) }
        try press(app, [], .returnKey)
        try app.waitUntil("\(text): Return copied \(answer)") { try !isOpen(app) && pasteboard(app) == answer }
        try expect(todayIDs(try app.view()) == tabs, "\(text) opened a tab")
    }

    @Sendable static func answers(_ app: AppUnderTest) throws {
        try preflight(app)
        try keepingPasteboard(app) {
            try copies(app, "52% of 900", "468", shot: "percent")
            try copies(app, "square root of 625", "25")
            try copies(app, "10ft in m", "3.048 m", shot: "units")
            try copies(app, "2rem in px", "32 px", shot: "css")
            try copies(app, "145 mins to timespan", "2 hours 25 minutes")

            // Worked out here on its own, not through the parser.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let today = calendar.startOfDay(for: Date())
            var target = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 3, day: 31))!
            if target < today { target = calendar.date(byAdding: .year, value: 1, to: target)! }
            let count = calendar.dateComponents([.day], from: today, to: target).day!
            try copies(app, "days until 31 mar", count == 1 ? "1 day" : "\(count) days", shot: "days")

            func clock(_ date: Date, _ template: String, _ zone: String) -> String {
                let formatter = DateFormatter()
                formatter.locale = .current
                formatter.timeZone = TimeZone(identifier: zone)
                formatter.setLocalizedDateFormatFromTemplate(template)
                return formatter.string(from: date)
            }
            // The minute can turn while typing: the row is compared with both.
            let tokyo = [Date(), Date().addingTimeInterval(60), Date().addingTimeInterval(-60)].map { clock($0, "EEE d MMM jmm", "Asia/Tokyo") }
            try open(app)
            try type(app, "time in tokyo")
            let timeRows = try waitForRows(app, "time in tokyo leads") { $0.first.map { has($0, "Copy Result") } ?? false }
            try expect(tokyo.contains { has(timeRows[0], $0) }, "time in tokyo shows \(timeRows[0]), expected one of \(tokyo)")
            _ = try app.screenshot("time-in-tokyo")
            try dismiss(app)

            var london = Calendar(identifier: .gregorian)
            london.timeZone = TimeZone(identifier: "Europe/London")!
            var parts = london.dateComponents([.year, .month, .day], from: Date())
            parts.hour = 17
            let five = london.date(from: parts)!
            try open(app)
            try type(app, "5pm ldn in sf")
            let expected = clock(five, "EEE jmm", "America/Los_Angeles")
            try waitForRows(app, "5pm ldn in sf is \(expected)") { $0.first.map { has($0, expected) } ?? false }
            try dismiss(app)

            // A bare word: the typed row first (Return searches), the answer below it. "tomorrow" completes to no site.
            // The search goes to a fixture engine, so nothing leaves the machine.
            let profile = ProfileID.default
            try app.dispatch(.settings(.profile(profile, .addSiteSearch(name: "Fixture Search", keyword: "fixture", template: app.site.baseURL.absoluteString + "browser-basic-search.html?q={q}"))))
            try open(app)
            guard case .commandBar(let snapshot)? = try app.view().overlay, let engine = snapshot.siteSearch.first(where: { $0.name == "Fixture Search" }) else { throw Check(description: "no fixture engine") }
            try dismiss(app)
            try app.dispatch(.settings(.profile(profile, .searchEngine(engine.id))))
            try open(app)
            try type(app, "tomorrow")
            let tomorrow = clock(calendar.date(byAdding: .day, value: 1, to: today)!, "EEEE d MMMM y", TimeZone.current.identifier)
            let bare = try waitForRows(app, "the answer under the typed row") { rows in
                guard let typed = rows.firstIndex(where: { $0.contains("tomorrow") }), typed + 1 < rows.count else { return false }
                return has(rows[typed + 1], tomorrow) && has(rows[typed + 1], "Copy Result")
            }
            try expect(!has(bare[0], "Copy Result"), "the answer must not be first: \(bare)")
            _ = try app.screenshot("bare-word")
            try press(app, [], .returnKey)
            try app.waitUntil("Return searched") { currentTab(try app.view())?.title == "query:tomorrow" }
            try expect(app.site.requestCount("/browser-basic-search.html") == 1, "the search did not reach the fixture engine once")

            // Ordinary searches and addresses have no answer row.
            for text in ["10 things", "best 10 ft in m", "example.com", "time.com"] {
                try open(app)
                try type(app, text)
                app.sleep(0.4)
                let shown = try rows(app)
                try expect(!shown.isEmpty && !shown.contains { has($0, "Copy Result") }, "\(text) has an answer: \(shown)")
                try dismiss(app)
            }

            // Plain arithmetic is one row, as before.
            try open(app)
            try type(app, "2+3*4")
            let plain = try waitForRows(app, "arithmetic") { $0.first.map { has($0, "14") } ?? false }
            try expect(plain.count == 1, "arithmetic has other rows: \(plain)")
            try press(app, [], .returnKey)
            try app.waitUntil("the arithmetic copied") { try pasteboard(app) == "14" }
            app.passed("Percent, root, units, CSS, days, timespan, time zones and bare words answered through real keys; searches and addresses did not")
        }
    }

    @Sendable static func currency(_ app: AppUnderTest) throws {
        try preflight(app)
        try Data(fixedRates.utf8).write(to: ratesFile(app))
        try keepingPasteboard(app) {
            try copies(app, "100 usd in cny", "700.00 CNY", shot: "currency")
            try open(app)
            try type(app, "100 usd in cny")
            let shown = try waitForRows(app, "the rate's date") { $0.first.map { has($0, "ECB 2026-11-06") } ?? false }
            try expect(has(shown[0], "700.00 CNY"), "\(shown[0])")
            try dismiss(app)
            try open(app)
            try type(app, "100 usd in xyz")
            app.sleep(0.4)
            let unknown = try rows(app)
            try expect(!unknown.contains { has($0, "Copy Result") }, "an unknown code has an answer: \(unknown)")
            try dismiss(app)
            app.passed("100 usd in cny from the fixture file, with its date; an unknown code has no row")
        }
    }

    @Sendable static func noRates(_ app: AppUnderTest) throws {
        try preflight(app)
        try open(app)
        try type(app, "100 usd in cny")
        let shown = try waitForRows(app, "the typed row") { $0.first.map { $0.contains("100 usd in cny") } ?? false }
        app.sleep(1.2)
        let later = try rows(app)
        try expect(!later.contains { has($0, "Copy Result") || has($0, "CNY") }, "a currency row with no rates: \(later)")
        try expect(has(shown[0], "100 usd in cny"), "the search should stay: \(shown)")
        try dismiss(app)
        app.passed("No cache and no network: no currency row, the search stays first")
    }

    // MARK: B

    private static let fixtureFiles = ["Documents/quickbar-report.brkquickdoc", "Documents/quickbar-notes.txt", "Documents/quickbar-table.csv", "Downloads/quickbar-four.txt",
                                       "Downloads/quickbar-five.txt", "Downloads/quickbar-six.txt", ".hiddenfolder/quickbar-secret.txt", "Documents/.quickbar-dot.txt",
                                       "Library/Application Support/Fixture/quickbar-profile.txt"]

    private static func assertNothingExcluded(_ rows: [[String]]) throws {
        for text in ["quickbar-secret", "quickbar-dot", "quickbar-profile"] {
            try expect(!rows.contains { has($0, text) }, "\(text) should stay hidden: \(rows)")
        }
    }

    @Sendable static func files(_ app: AppUnderTest) throws {
        try preflight(app)
        let marker = app.dataDirectory.appendingPathComponent("opened.txt")
        let root = try make(app, files: fixtureFiles)
        let bundle = try makeApp(root, name: "Quickbarviewer", marker: marker)
        defer { removeFixture(root, app: bundle) }
        try keepingPasteboard(app) {
            // Inline: last places, at most two, never the first row.
            try open(app)
            try type(app, "quickbar")
            let inline = try waitForRows(app, "file rows under the typed row") { $0.contains { has($0, fileCaption) } }
            try expect(!has(inline[0], fileCaption), "a file row came first: \(inline)")
            try expect(inline[0].contains("quickbar"), "the typed row should lead: \(inline)")
            let fileRows = inline.indices.filter { has(inline[$0], fileCaption) }
            try expect(fileRows.count <= 2, "more than two inline: \(inline)")
            try expect(fileRows.last == inline.count - 1, "file rows should be last: \(inline)")
            try assertNothingExcluded(inline)
            _ = try app.screenshot("inline-files")

            // Option+Return copies the path. The rows are told by name: the row's text says which file.
            let index = fileRows[0], name = inline[index].first { $0.hasPrefix("quickbar-") } ?? ""
            for _ in 0..<index { try press(app, [], .downArrow) }
            app.sleep(0.2)
            try press(app, [.option], .returnKey)
            try app.waitUntil("Option+Return copied the path") { try !isOpen(app) && pasteboard(app).hasSuffix("/" + name) }
            let copied = try pasteboard(app)
            try expect(copied.hasPrefix(root.path), "copied \(copied)")

            // Command+Return shows it in the Finder.
            try open(app)
            try type(app, "quickbar")
            try waitForRows(app, "the file rows again") { $0.contains { has($0, fileCaption) } }
            let again = try rows(app)
            for _ in 0..<(again.firstIndex { has($0, fileCaption) } ?? 0) { try press(app, [], .downArrow) }
            app.sleep(0.2)
            let folder = URL(fileURLWithPath: copied).deletingLastPathComponent().lastPathComponent
            try press(app, [.command], .returnKey)
            try app.waitUntil("Command+Return closed the bar") { try !isOpen(app) }
            var revealed = false
            for _ in 0..<40 where !revealed {
                revealed = NativeSystemInput.closeFinderWindow(titled: folder)
                if !revealed { app.sleep(0.25) }
            }
            try expect(revealed, "no Finder window for \(folder)")
            try WindowServerKeys.ensureFrontmost(app, app.window!)

            // The file mode lists only files, more than the inline two.
            try open(app)
            try type(app, "file quickbar")
            let listed = try waitForRows(app, "the file mode") { $0.count >= 5 && $0.allSatisfy { has($0, fileCaption) } }
            try assertNothingExcluded(listed)
            _ = try app.screenshot("file-mode")

            // A result must not appear once the text has changed.
            try type(app, "zz")
            try app.waitUntil("the old rows gone at the next key") { try !rows(app).contains { has($0, fileCaption) } }
            for _ in 0..<8 {
                app.sleep(0.1)
                let moved = try rows(app)
                try expect(!moved.contains { has($0, fileCaption) }, "a stale file row: \(moved)")
            }
            try dismiss(app)

            // Return opens with the default app: the fixture app owns this type and writes its marker.
            try open(app)
            try type(app, "file quickbar-report")
            let report = try waitForRows(app, "the one report") { $0.count == 1 && has($0[0], "quickbar-report.brkquickdoc") }
            try expect(has(report[0], fileCaption), "\(report)")
            try press(app, [], .returnKey)
            try app.waitUntil("the default app opened the file", timeout: 10) { (try? String(contentsOf: marker, encoding: .utf8))?.contains("launched") == true }
            try expect(try !isOpen(app), "the bar stayed open")
            try WindowServerKeys.ensureFrontmost(app, app.window!)

            // Two characters are too few inline; a short query shows no file row.
            try open(app)
            try type(app, "qu")
            app.sleep(0.6)
            let short = try rows(app)
            try expect(!short.contains { has($0, fileCaption) }, "a file row for two characters: \(short)")
            try dismiss(app)

            // Nothing went to history.
            let history = try app.view().history ?? []
            try expect(!history.contains { $0.url.absoluteString.contains("quickbar") }, "history has \(history)")
            app.passed("Inline rows last, at most two; hidden and Library left out; Return, Cmd+Return, Option+Return; the file mode; no stale rows")
        }
    }

    @Sendable static func spotlight(_ app: AppUnderTest) throws {
        try preflight(app)
        let root = try make(app, files: ["Documents/zqxquickbar-spot.txt", "zqxquickbar-top.txt", "Library/zqxquickbar-lib.txt", ".hid/zqxquickbar-hid.txt", "Documents/.zqxquickbar-dot.txt"])
        defer { removeFixture(root) }
        // Wait for the index itself before asking through the bar.
        var indexed = false
        for _ in 0..<60 where !indexed {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-onlyin", root.path, "-name", "zqxquickbar-spot"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let found = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            indexed = found.contains("zqxquickbar-spot.txt")
            if !indexed { app.sleep(0.5) }
        }
        guard indexed else { throw Skipped(description: "Spotlight did not index the fixture folder within 30 s") }
        try keepingPasteboard(app) {
            try open(app)
            try type(app, "file zqxquickbar")
            let found = try waitForRows(app, "Spotlight's answer", timeout: 8) { $0.contains { has($0, "zqxquickbar-spot.txt") } }
            try expect(found.allSatisfy { has($0, fileCaption) }, "only files: \(found)")
            try expect(found.contains { has($0, "zqxquickbar-top.txt") }, "the file lying directly in the folder: \(found)")
            for text in ["zqxquickbar-lib", "zqxquickbar-hid", "zqxquickbar-dot"] {
                try expect(!found.contains { has($0, text) }, "\(text) should stay out: \(found)")
            }
            _ = try app.screenshot("spotlight")
            let index = found.firstIndex { has($0, "zqxquickbar-spot.txt") }!
            for _ in 0..<index { try press(app, [], .downArrow) }
            app.sleep(0.2)
            try press(app, [.option], .returnKey)
            let expected = root.appendingPathComponent("Documents/zqxquickbar-spot.txt").path
            try app.waitUntil("the path from Spotlight") { try pasteboard(app).hasSuffix(expected) }
            app.passed("The real index answered by file name; Library, hidden files and dot files stayed out; the path copied")
        }
    }

    // MARK: C

    @Sendable static func apps(_ app: AppUnderTest) throws {
        try preflight(app)
        let marker = app.dataDirectory.appendingPathComponent("launched.txt")
        let root = try make(app, files: [])
        let bundle = try makeApp(root, name: "Quickbarlauncher", marker: marker)
        defer { removeFixture(root, app: bundle) }
        try open(app)
        try type(app, "quickbarla")
        let shown = try waitForRows(app, "the app's row") { $0.contains { has($0, "Quickbarlauncher") && has($0, "Open App") } }
        let index = shown.firstIndex { has($0, "Quickbarlauncher") }!
        try expect(index > 0, "the app came first: \(shown)")
        _ = try app.screenshot("app-row")
        for _ in 0..<index { try press(app, [], .downArrow) }
        app.sleep(0.2)
        try press(app, [], .returnKey)
        try app.waitUntil("Return launched the app", timeout: 10) { (try? String(contentsOf: marker, encoding: .utf8))?.contains("launched") == true }
        try expect(try !isOpen(app), "the bar stayed open")
        app.passed("Quickbarlauncher found by name with Return launching it; the fixture app wrote its marker")
    }

    // MARK: D

    private static func aiCalls(_ app: AppUnderTest) -> [[String: Any]] {
        let data = (try? String(contentsOf: app.dataDirectory.appendingPathComponent("ai-fixture.jsonl"), encoding: .utf8)) ?? ""
        return data.split(whereSeparator: \.isNewline).compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    @Sendable static func askTab(_ app: AppUnderTest) throws {
        try preflight(app)
        try app.dispatch(.settings(.max(.feature(.commandBar, true))))
        try open(app)
        guard case .commandBar(let bar)? = try app.view().overlay, bar.askAgentFound else {
            try dismiss(app)
            throw Skipped(description: "no local agent on this Mac's PATH, so Tab keeps its old behaviour by design")
        }
        // A question and Tab.
        try type(app, "why is the sky blue?")
        try press(app, [], .tab)
        try app.waitUntil("the answer panel's answer", timeout: 15) { try app.view().ai?.busy == false && app.view().ai?.text.contains("Fixture answer") == true }
        try expect(try !isOpen(app), "the bar stayed open")
        try expect(aiCalls(app).last?["prompt"] as? String == "why is the sky blue?", "asked \(String(describing: aiCalls(app).last?["prompt"]))")
        _ = try app.screenshot("answer")
        try app.dispatch(.assist(.dismiss))

        // No text: nothing happens.
        let asked = aiCalls(app).count
        try open(app)
        try press(app, [], .tab)
        app.sleep(0.4)
        try expect(try isOpen(app) && aiCalls(app).count == asked, "Tab with no text did something")

        // An address: nothing is asked.
        try type(app, "example.com")
        app.sleep(0.2)
        try press(app, [], .tab)
        app.sleep(0.4)
        try expect(try isOpen(app) && aiCalls(app).count == asked, "Tab on an address asked")
        try dismiss(app)

        // Site search keeps Tab: wikipedia is offered, Tab enters it and asks nothing; Escape gives the word back.
        try open(app)
        try type(app, "wiki")
        app.sleep(0.3)
        try press(app, [], .tab)
        try waitForRows(app, "the empty site search has no rows") { $0.isEmpty }
        try expect(aiCalls(app).count == asked, "Tab asked instead of entering site search")
        try dismiss(app)

        // Max's Ask off: Tab does nothing.
        try app.dispatch(.settings(.max(.feature(.commandBar, false))))
        try open(app)
        try type(app, "why is the sky blue?")
        app.sleep(0.2)
        try press(app, [], .tab)
        app.sleep(0.4)
        try expect(try isOpen(app) && aiCalls(app).count == asked, "Tab asked with Max's Ask off")
        try dismiss(app)
        app.passed("Tab asked with the typed text; no text, an address, site search and Max off stayed as they were")
    }

    // MARK: E

    @Sendable static func emoji(_ app: AppUnderTest) throws {
        try preflight(app)
        try keepingPasteboard(app) {
            try open(app)
            try type(app, "emoji smile")
            let listed = try waitForRows(app, "emoji rows") { $0.count == 5 && $0.allSatisfy { has($0, "Copy Emoji") } }
            try expect(listed.contains { $0.contains { $0.contains("smil") } }, "no smiling name: \(listed)")
            _ = try app.screenshot("emoji")
            try dismiss(app)
            try open(app)
            try type(app, "emoji rocket")
            try waitForRows(app, "the rocket") { $0.first.map { $0.contains("rocket") } ?? false }
            try press(app, [], .returnKey)
            try app.waitUntil("the rocket copied") { try !isOpen(app) && pasteboard(app) == "🚀" }
            // No match: the ordinary rows.
            try open(app)
            try type(app, "emoji zzzqqq")
            let none = try waitForRows(app, "the typed row") { $0.first.map { $0.contains("emoji zzzqqq") } ?? false }
            try expect(!none.contains { has($0, "Copy Emoji") }, "\(none)")
            try dismiss(app)
            app.passed("emoji smile lists five, Return copied 🚀, no match leaves the ordinary rows")
        }
    }

    // MARK: Beside Arc

    @Sendable static func beside(_ app: AppUnderTest) throws {
        try preflight(app)
        let root = try make(app, files: fixtureFiles)
        defer { removeFixture(root) }
        func assertNoLocalRows(_ what: String) throws {
            app.sleep(0.6)
            let shown = try rows(app)
            try expect(!shown.contains { has($0, fileCaption) || has($0, "Open App") }, "\(what): \(shown)")
        }
        // The control: this new-tab bar does show the file rows.
        try open(app)
        try type(app, "quickbar")
        try waitForRows(app, "the control") { $0.contains { has($0, fileCaption) } }
        try dismiss(app)

        // The bar over the page's address.
        try press(app, [.command], .l)
        try app.waitUntil("the bar over the address") { try isOpen(app) }
        try app.waitUntil("its input focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
        try type(app, "quickbar")
        try assertNoLocalRows("the bar over the address")
        try dismiss(app)

        // Site search.
        try open(app)
        try type(app, "wiki")
        app.sleep(0.3)
        try press(app, [], .tab)
        try type(app, "quickbar")
        try assertNoLocalRows("site search")
        try dismiss(app)

        // AI mode.
        try app.dispatch(.settings(.max(.feature(.commandBar, true))))
        try app.dispatch(.assist(.open(.question)))
        try app.waitUntil("AI mode") { if case .commandBar(let bar)? = try app.view().overlay { return bar.aiMode == .question }; return false }
        try app.waitUntil("its input focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
        try type(app, "quickbar")
        try assertNoLocalRows("AI mode")
        try dismiss(app)

        // An empty split pane.
        try app.dispatch(.split(.addPane))
        try app.waitUntil("the empty pane's bar") { if case .commandBar(let bar)? = try app.view().overlay { return bar.fillsPane }; return false }
        try app.waitUntil("its input focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
        try type(app, "quickbar")
        try assertNoLocalRows("the empty pane")
        try press(app, [.command], .a)
        try type(app, "10ft in m")
        app.sleep(0.4)
        let pane = try rows(app)
        try expect(!pane.contains { has($0, "Copy Result") }, "an answer in the empty pane: \(pane)")
        try dismiss(app)
        app.passed("No file, app or answer rows over the address, in site search, in AI mode or in an empty pane")
    }
}
