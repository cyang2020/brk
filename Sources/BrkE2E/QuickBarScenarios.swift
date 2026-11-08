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
        Scenario("QuickBar-Prefix", "a whole word and Tab enters through site search's pill; a real Space never does, so the words can begin a search; Backspace and Esc give it back; an engine of the same name wins; part of a word is offered", cefOnly: "native command bar", prefixKeys),
        Scenario("QuickBar-AIPrefix", "claude, gpt, ask and ai ask; page and summarize read the page; Max off and a missing agent leave the word plain", cefOnly: "native command bar", aiPrefix),
        Scenario("QuickBar-Split", "split opens an address in a new pane on the named side, Return with no text adds a pane, a tab's title, and the split commands", cefOnly: "native command bar", split),
        Scenario("QuickBar-Window", "window places Brk's own window on the visible frame, with full screen, minimize and stay on top; an exact phrase shows low down", cefOnly: "native command bar", windowPlaces),
        Scenario("QuickBar-Translate", "translate shows a pending row, then the answer, Return copies; a change asks again; translate page runs the page translation", cefOnly: "native command bar", translate),
        Scenario("QuickBar-Define", "define shows the offline dictionary's first lines; Return opens Dictionary.app", cefOnly: "native command bar", define),
        Scenario("QuickBar-Color", "colours with no prefix and after color, each form copied; bare #abc still searches", cefOnly: "native command bar", color),
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
            guard name.count == 1, let character = name.first, character.isASCII, character.isLetter || character.isNumber else { continue }
            map[character] = (CGKeyCode(key.code), false)
            if character.isLetter { map[Character(name.uppercased())] = (CGKeyCode(key.code), true) }
        }
        map["#"] = (20, true)
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

    /// The Backspace key (no `Key` of its own: nothing in the shortcut table uses it).
    private static func backspace(_ app: AppUnderTest) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: down) else { continue }
            event.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    private static func isOpen(_ app: AppUnderTest) throws -> Bool { isCommandBar(try app.view().overlay) }

    /// The pill before the input is showing: a prefix or a site search is on.
    private static func pillShown(_ app: AppUnderTest) throws -> Bool {
        try app.native().actual[ViewID.commandBarPill.identifier].map { !$0.hidden } ?? false
    }

    private static func inputText(_ app: AppUnderTest) throws -> String { try app.native().editorText ?? "" }

    /// An AI prefix's word that cannot work here: the reason beside the input, then Tab opens `pane` and no mode is entered.
    private static func blockedWord(_ app: AppUnderTest, _ word: String, _ reason: String, _ pane: SettingsPane) throws {
        try open(app)
        try type(app, word)
        let card = try visible(app.native(), .commandBar).frame
        try app.waitUntil("\(word): \(reason)") { try SidebarReviewScenarios.texts(app, in: card).contains(reason) }
        _ = try app.screenshot("blocked-" + word)
        try press(app, [], .tab)
        try app.waitUntil("\(word): Settings at \(pane)") { if case .settings(let settings) = try app.send(.settings) { return settings.pane == pane }; return false }
        try expect(try !pillShown(app), "\(word) entered a mode")
        try app.dispatch(.settings(.closeWindow))
        try app.waitUntil("Settings closed") { if case .settings(let settings) = try app.send(.settings) { return settings.pane == nil }; return false }
        app.sleep(0.3)
        if try isOpen(app) { try app.dispatch(.commandBar(.dismiss)) }
    }

    /// `word` and a real Tab: the pill must show, or (`enters` false) the word must stay plain text.
    private static func typeWord(_ app: AppUnderTest, _ word: String, enters: Bool = true) throws {
        try type(app, word)
        app.sleep(0.2)
        try press(app, [], .tab)
        if enters {
            try app.waitUntil("\(word) and Tab entered") { try pillShown(app) && inputText(app).isEmpty }
        } else {
            app.sleep(0.2)
            try expect(try !pillShown(app), "\(word) entered a mode")
            let shown = try inputText(app)
            try expect(shown.hasPrefix(word), "\(word): the input reads \(shown)")
        }
    }

    /// A search engine on the fixture site as the default, so a search goes nowhere off this machine.
    private static func useFixtureEngine(_ app: AppUnderTest) throws {
        let profile = ProfileID.default
        try app.dispatch(.settings(.profile(profile, .addSiteSearch(name: "Fixture Search", keyword: "fixture", template: app.site.baseURL.absoluteString + "browser-basic-search.html?q={q}"))))
        try open(app)
        guard case .commandBar(let snapshot)? = try app.view().overlay, let engine = snapshot.siteSearch.first(where: { $0.name == "Fixture Search" }) else { throw Check(description: "no fixture engine") }
        try dismiss(app)
        try app.dispatch(.settings(.profile(profile, .searchEngine(engine.id))))
    }

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
            try useFixtureEngine(app)
            try open(app)
            try type(app, "tomorrow")
            let tomorrow = clock(calendar.date(byAdding: .day, value: 1, to: today)!, "EEEE d MMMM y", TimeZone.current.identifier)
            let bare = try waitForRows(app, "the answer under the typed row") { rows in
                guard let typed = rows.firstIndex(where: { $0.contains("tomorrow") }), typed + 1 < rows.count else { return false }
                return has(rows[typed + 1], tomorrow) && has(rows[typed + 1], "Copy Result")
            }
            try expect(!has(bare[0], "Copy Result"), "the answer must not be first: \(bare)")
            _ = try app.screenshot("bare-word")
            let searchesBefore = app.site.requestCount("/browser-basic-search.html")
            try press(app, [], .returnKey)
            try app.waitUntil("Return searched") { currentTab(try app.view())?.title == "query:tomorrow" }
            try expect(app.site.requestCount("/browser-basic-search.html") == searchesBefore + 1, "the search did not reach the fixture engine once")

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
                revealed = NativeSystemInput.closeWindow(owner: "Finder", titled: folder)
                if !revealed { app.sleep(0.25) }
            }
            try expect(revealed, "no Finder window for \(folder)")
            try WindowServerKeys.ensureFrontmost(app, app.window!)

            // The file prefix lists only files, more than the inline two.
            try open(app)
            try typeWord(app, "file")
            try type(app, "quickbar")
            let listed = try waitForRows(app, "the file prefix") { $0.count >= 5 && $0.allSatisfy { has($0, fileCaption) } }
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
            try typeWord(app, "file")
            try type(app, "quickbar-report")
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
        // Wait for the index itself before asking through the bar. A long compile elsewhere on the machine can keep the
        // indexer busy for minutes.
        try? tool("/usr/bin/mdimport", [root.path])
        var indexed = false
        for _ in 0..<480 where !indexed {
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
        guard indexed else { throw Skipped(description: "Spotlight did not index the fixture folder within 4 minutes") }
        try keepingPasteboard(app) {
            try open(app)
            try typeWord(app, "file")
            try type(app, "zqxquickbar")
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
        try dismiss(app)
        // The app prefix lists only apps, first.
        try open(app)
        try typeWord(app, "app")
        try type(app, "quickbarla")
        let listed = try waitForRows(app, "the app prefix") { $0.first.map { has($0, "Quickbarlauncher") } ?? false }
        try expect(listed.count == 1, "only the app: \(listed)")
        try dismiss(app)
        try open(app)
        try type(app, "quickbarla")
        try waitForRows(app, "the app's row again") { $0.contains { has($0, "Quickbarlauncher") } }
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
            try typeWord(app, "emoji")
            try type(app, "smile")
            let listed = try waitForRows(app, "emoji rows") { $0.count == 5 && $0.allSatisfy { has($0, "Copy Emoji") } }
            try expect(listed.contains { $0.contains { $0.contains("smil") } }, "no smiling name: \(listed)")
            _ = try app.screenshot("emoji")
            try dismiss(app)
            try open(app)
            try typeWord(app, "emoji")
            try type(app, "rocket")
            try waitForRows(app, "the rocket") { $0.first.map { $0.contains("rocket") } ?? false }
            try press(app, [], .returnKey)
            try app.waitUntil("the rocket copied") { try !isOpen(app) && pasteboard(app) == "🚀" }
            // No match: no rows.
            try open(app)
            try typeWord(app, "emoji")
            try type(app, "zzzqqq")
            app.sleep(0.3)
            let none = try rows(app)
            try expect(none.isEmpty, "\(none)")
            try dismiss(app)
            app.passed("emoji then smile lists five, Return copied 🚀, no match has no rows")
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
        try press(app, [.command], .a)
        try typeWord(app, "emoji", enters: false)
        try dismiss(app)

        // Site search.
        try open(app)
        try type(app, "wiki")
        app.sleep(0.3)
        try press(app, [], .tab)
        try type(app, "quickbar")
        try assertNoLocalRows("site search")
        try press(app, [.command], .a)
        try type(app, "file ")
        app.sleep(0.2)
        let inSite = try inputText(app)
        try expect(inSite == "file ", "a prefix inside site search: \(inSite)")
        try dismiss(app)

        // AI mode.
        try app.dispatch(.settings(.max(.feature(.commandBar, true))))
        try app.dispatch(.assist(.open(.question)))
        try app.waitUntil("AI mode") { if case .commandBar(let bar)? = try app.view().overlay { return bar.aiMode == .question }; return false }
        try app.waitUntil("its input focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
        try type(app, "quickbar")
        try assertNoLocalRows("AI mode")
        try press(app, [.command], .a)
        try type(app, "file ")
        app.sleep(0.2)
        let inAI = try inputText(app)
        try expect(inAI == "file ", "a prefix entered in AI mode: \(inAI)")
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
        // No prefix enters there either.
        try press(app, [.command], .a)
        try typeWord(app, "emoji", enters: false)
        try dismiss(app)
        app.passed("No file, app or answer rows over the address, in site search, in AI mode or in an empty pane")
    }

    // MARK: Prefix keys

    @Sendable static func prefixKeys(_ app: AppUnderTest) throws {
        try preflight(app)
        try useFixtureEngine(app)
        try keepingPasteboard(app) {
            // Tab after the whole word: the pill, an empty input. Case aside.
            try open(app)
            try typeWord(app, "emoji")
            _ = try app.screenshot("pill")
            // Backspace in the empty input gives the word back, and the word can be searched.
            try backspace(app)
            try app.waitUntil("Backspace left the mode") { try !pillShown(app) && inputText(app) == "emoji" }
            try type(app, " on a mug")
            app.sleep(0.2)
            let plain = try inputText(app)
            try expect(try !pillShown(app) && plain == "emoji on a mug", "the word did not stay plain: \(plain)")
            try press(app, [], .returnKey)
            try app.waitUntil("that search ran") { currentTab(try app.view())?.title == "query:emoji on a mug" }

            try open(app)
            try typeWord(app, "EMOJI")
            // Esc gives the word back too, and leaves the bar open; a second Esc closes it.
            try press(app, [], .escape)
            try app.waitUntil("Esc left the mode") { try !pillShown(app) && inputText(app) == "EMOJI" && isOpen(app) }
            try press(app, [], .escape)
            try app.waitUntil("a second Esc closed the bar") { try !isOpen(app) }

            // Each prefix's colour, for the eye: the pill and the offer beside the word.
            for feature in [AIFeature.commandBar, .askPage, .translation] { try app.dispatch(.settings(.max(.feature(feature, true)))) }
            // Two letters offer the prefix, as its chip beside the Tab key.
            for partial in ["cl", "sp", "tr", "em", "de"] {
                try open(app)
                try type(app, partial)
                app.sleep(0.25)
                _ = try app.screenshot("offer-" + partial)
                try dismiss(app)
            }
            for word in ["claude", "gpt", "gemini", "cursor", "ask", "page", "summarize", "split", "window", "translate", "define", "color", "file", "app", "emoji", "calc"] {
                try open(app)
                try type(app, word)
                app.sleep(0.15)
                try press(app, [], .tab)
                if (try? app.waitUntil("\(word)'s pill", timeout: 2) { try pillShown(app) }) != nil { _ = try app.screenshot("pill-" + word) }
                else { app.note("\(word) did not enter here: its agent or feature is off") }
                try dismiss(app)
            }
            for feature in [AIFeature.commandBar, .askPage, .translation] { try app.dispatch(.settings(.max(.feature(feature, false)))) }

            // A search can start with any of the words: typed with a real Space it stays a search.
            for text in ["split pea soup", "claude pricing", "app store", "translate this", "define me", "emoji movie"] {
                try open(app)
                try type(app, text)
                app.sleep(0.2)
                let typed = try inputText(app)
                try expect(try !pillShown(app) && typed == text, "Space entered a mode in \(text): \(typed)")
                try dismiss(app)
            }
            try open(app)
            try type(app, "split pea soup")
            try press(app, [], .returnKey)
            try app.waitUntil("that typed search ran") { currentTab(try app.view())?.title == "query:split pea soup" }

            // Pasted text never enters.
            let tabsBefore = todayIDs(try app.view()).count
            for text in ["split pea soup", "split "] {
                _ = try app.send(.pasteboard(text))
                try open(app)
                try press(app, [.command], .v)
                try app.waitUntil("the paste arrived") { try inputText(app) == text }
                app.sleep(0.2)
                try expect(try !pillShown(app), "pasted \(text) entered a mode")
                try dismiss(app)
            }
            _ = try app.send(.pasteboard("split pea soup"))
            try open(app)
            try press(app, [.command], .v)
            try app.waitUntil("the paste arrived") { try inputText(app) == "split pea soup" }
            _ = try app.screenshot("pasted")
            try press(app, [], .returnKey)
            try app.waitUntil("the pasted text searched") { currentTab(try app.view())?.title == "query:split pea soup" }
            try expect(todayIDs(try app.view()).count == tabsBefore + 1, "one new tab for the search")

            // Part of a word is offered beside the input; Tab enters what is offered; an engine's offer goes first.
            try open(app)
            try type(app, "fil")
            let card = try visible(app.native(), .commandBar).frame
            try app.waitUntil("Files offered beside the input") { try SidebarReviewScenarios.texts(app, in: card).contains("Files") }
            _ = try app.screenshot("offer")
            try press(app, [], .tab)
            try app.waitUntil("Tab entered Files") { try pillShown(app) && inputText(app).isEmpty }
            try dismiss(app)
            try open(app)
            try type(app, "wiki")
            try app.waitUntil("the engine's offer") { try SidebarReviewScenarios.texts(app, in: card).contains("Search Wikipedia") }
            try dismiss(app)

            // An engine of the same name wins over a prefix: its search, not the prefix's.
            try app.dispatch(.settings(.profile(ProfileID.default, .addSiteSearch(name: "Split Engine", keyword: "split", template: app.site.baseURL.absoluteString + "browser-basic-search.html?q=engine-{q}"))))
            try open(app)
            try typeWord(app, "split")
            try app.waitUntil("the engine's name in the pill") { try SidebarReviewScenarios.texts(app, in: card).contains("Split Engine") }
            try type(app, "abc")
            try waitForRows(app, "the engine's row") { $0.first.map { $0.contains("abc") } ?? false }
            try press(app, [], .returnKey)
            try app.waitUntil("the engine searched") { currentTab(try app.view())?.title == "query:engine-abc" }

            // A word in another script arrives as committed text, then a real Tab: the input method's route.
            try open(app)
            PhysicalKeys.type("文件", pid: app.hello!.pid)
            app.sleep(0.3)
            if try inputText(app) == "文件" {
                try press(app, [], .tab)
                try app.waitUntil("文件 and Tab entered") { try pillShown(app) && inputText(app).isEmpty }
            } else {
                app.note("Key events carrying 文件 did not reach the field here; the Chinese words are covered by unit tests.")
            }
            try dismiss(app)

            // The calc prefix: forced calculation, with the = word and a plain number.
            try open(app)
            try typeWord(app, "calc")
            try type(app, "2+2")
            try waitForRows(app, "calc") { $0.first.map { has($0, "4") } ?? false }
            try press(app, [], .returnKey)
            try app.waitUntil("calc copied") { try !isOpen(app) && pasteboard(app) == "4" }
            try open(app)
            try typeWord(app, "=")
            try type(app, "42")
            try waitForRows(app, "=") { $0.first.map { has($0, "42") } ?? false }
            try press(app, [], .returnKey)
            try app.waitUntil("= copied") { try !isOpen(app) && pasteboard(app) == "42" }
            app.passed("Tab enters, case aside; a real Space never does, so typed and pasted text starting with a word searches; Backspace and Esc give the word back; split pea soup searched; the offer; the engine won; calc and =")
        }
    }

    // MARK: AI prefixes

    @Sendable static func aiPrefix(_ app: AppUnderTest) throws {
        try preflight(app)
        for feature in [AIFeature.commandBar, .askPage] { try app.dispatch(.settings(.max(.feature(feature, true)))) }
        try open(app)
        guard case .commandBar(let bar)? = try app.view().overlay, bar.agentsFound.contains("claude"), bar.agentsFound.contains("codex") else {
            try dismiss(app)
            throw Skipped(description: "needs both claude and codex on this Mac's PATH")
        }
        try dismiss(app)
        func asks(_ word: String, _ question: String) throws {
            let before = aiCalls(app).count
            try open(app)
            try typeWord(app, word)
            try type(app, question)
            try waitForRows(app, "\(word)'s row") { $0.first.map { $0.contains(question) } ?? false }
            if word == "gpt" { _ = try app.screenshot("gpt-row") }
            try press(app, [], .returnKey)
            try app.waitUntil("\(word) answered", timeout: 15) { try app.view().ai?.busy == false && app.view().ai?.text.contains("Fixture answer") == true && aiCalls(app).count == before + 1 }
            try expect(aiCalls(app).last?["prompt"] as? String == question, "\(word) asked \(String(describing: aiCalls(app).last?["prompt"]))")
            try expect(try !isOpen(app), "the bar stayed open")
            try app.dispatch(.assist(.dismiss))
        }
        try asks("claude", "why is the sky blue?")
        try asks("gpt", "why is the sea blue?")
        try asks("codex", "why is grass green?")
        try asks("ask", "why is snow white?")
        try asks("ai", "why is coal black?")
        // Arc's own row: typing it is an ordinary query, however it begins.
        try open(app)
        try type(app, "ask on page")
        try waitForRows(app, "Ask on Page leads") { $0.first.map { has($0, "Ask on Page") } ?? false }
        try dismiss(app)
        // The fixture stands in for every agent here, so which one a word picks is pinned in the reducer's tests.
        app.note("The AI fixture stands in for every agent under the control socket: which agent each word picks is pinned by CommandBarQuickSourcesTests (Effect.ai's choice), not here.")

        // The page and a summary, by the Ask on Page route: its prompt carries the page's text.
        let url = app.site.url("ai.html"), item = try app.load(url), page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        for (word, question, fragment) in [("page", "what does it say", "what does it say"), ("summarize", "", "Summarize this page")] {
            let before = aiCalls(app).count
            try open(app)
            try typeWord(app, word)
            if !question.isEmpty { try type(app, question) }
            try waitForRows(app, "\(word)'s row") { $0.count == 1 }
            try press(app, [], .returnKey)
            try app.waitUntil("\(word) answered", timeout: 15) { try app.view().ai?.busy == false && app.view().ai?.text.contains("Fixture page answer") == true && aiCalls(app).count == before + 1 }
            let prompt = aiCalls(app).last?["prompt"] as? String ?? ""
            try expect(prompt.hasPrefix("BRK_PAGE_QUESTION") && prompt.contains(fragment), "\(word) asked \(prompt.prefix(200))")
            try app.dispatch(.assist(.dismiss))
        }

        // Gemini and Cursor, where they are on this Mac. Every agent is the same fixture here.
        for (word, question) in [("gemini", "why is rust red?"), ("cursor", "why is ink dark?")] where bar.agentsFound.contains(word) { try asks(word, question) }

        // Max's Ask off: the word says why beside the input, and Tab opens the settings that change it, not a prefix.
        try app.dispatch(.settings(.max(.feature(.commandBar, false))))
        try blockedWord(app, "claude", "Claude is off in Max settings", .max)
        try app.dispatch(.settings(.max(.feature(.askPage, false))))
        try blockedWord(app, "summarize", "Ask on Page is off in Advanced settings", .advanced)
        app.passed("claude, gpt, codex, ask and ai each asked with the typed text; page and summarize read the page; gemini and cursor asked where installed; with a switch off the word said why and Tab opened its settings; Max off left the words plain")
    }

    // MARK: Split

    @Sendable static func split(_ app: AppUnderTest) throws {
        try preflight(app)
        let first = try app.load(app.site.url("index.html"))
        try app.waitForPageInput(PageID(window: app.window!, item: first), at: app.site.url("index.html"))
        func panes() throws -> [ItemID] { try app.view().content.panes.map(\.tab) }
        func address(_ pane: ItemID) throws -> String { try BrkE2E.tab(pane, in: app.view())?.url?.absoluteString ?? "" }
        let host = app.site.baseURL.host ?? "127.0.0.1", port = app.site.baseURL.port ?? 0
        let page2 = "\(host):\(port)/page2.html"

        // The rest is an address: a new pane to the right.
        try open(app)
        try typeWord(app, "split")
        _ = try app.screenshot("empty")
        try type(app, page2)
        let opening = try waitForRows(app, "the new pane's row") { $0.first.map { has($0, "New pane on the right") } ?? false }
        try expect(has(opening[0], page2), "\(opening)")
        _ = try app.screenshot("address")
        try press(app, [], .returnKey)
        try app.waitUntil("the second pane") { try panes().count == 2 && !isOpen(app) }
        var now = try panes()
        try expect(now[0] == first, "the new pane should be right of the page: \(now)")
        try app.waitUntil("the second pane's page") { try address(panes()[1]).contains("page2.html") }
        try expect(try app.view().content.orientation == .horizontal, "side by side")

        // A side by name: left, before the focused pane.
        try open(app)
        try typeWord(app, "split")
        try type(app, "left " + page2 + "?left")
        try waitForRows(app, "the left row") { $0.first.map { has($0, "New pane on the left") } ?? false }
        try press(app, [], .returnKey)
        try app.waitUntil("a third pane") { try panes().count == 3 && !isOpen(app) }
        now = try panes()
        let leftPane = try XCTFirst(now.first { try address($0).contains("?left") }, "the left pane")
        try expect(now.firstIndex(of: leftPane) == 1, "left of the pane that was focused: \(now)")

        // The commands: expand runs, the row named outright leads.
        try open(app)
        try typeWord(app, "split")
        try type(app, "expand")
        let commands = try waitForRows(app, "Expand leads") { $0.first.map { has($0, "Expand") } ?? false }
        try expect(has(commands[1], "New pane on the right"), "\(commands)")
        try press(app, [], .returnKey)
        try app.waitUntil("expanded") { try app.view().content.expanded }
        try open(app)
        try typeWord(app, "split")
        _ = try app.screenshot("commands")
        try waitForRows(app, "Add Split View listed") { $0.contains { has($0, "Add Split View") } }
        try dismiss(app)
        try app.dispatch(.split(.restore))
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("back to one pane") { try panes().count == 1 }

        // Top: the stacked orientation.
        try open(app)
        try typeWord(app, "split")
        try type(app, "top " + page2 + "?top")
        try waitForRows(app, "the top row") { $0.first.map { has($0, "New pane on the top") } ?? false }
        try press(app, [], .returnKey)
        try app.waitUntil("two panes, stacked") { try panes().count == 2 && app.view().content.orientation == .vertical && !isOpen(app) }
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("one pane again") { try panes().count == 1 }

        // An open tab, by a part of its title: the tab itself joins, its live page with it, before any web search.
        let titled = try app.load(app.site.url("page2.html?titled"))
        try app.waitForPageInput(PageID(window: app.window!, item: titled), at: app.site.url("page2.html?titled"))
        try app.dispatch(.tab(.focus(first)))
        try app.waitUntil("back on the first tab") { try currentTab(app.view())?.id == first }
        let title = try BrkE2E.tab(titled, in: app.view())?.title ?? ""
        try open(app)
        try typeWord(app, "split")
        // No text: what is open is there already, and Return takes the first.
        let listedTabs = try waitForRows(app, "the open tabs") { $0.contains { has($0, title) } }
        _ = try app.screenshot("open-tabs")
        try expect(!has(listedTabs[0], "Add Split View"), "a tab should come first: \(listedTabs)")
        try type(app, String(title.lowercased().prefix(7)))
        let byTitle = try waitForRows(app, "the tab's row leads") { $0.first.map { has($0, title) } ?? false }
        _ = try app.screenshot("tab-by-title")
        try expect(byTitle.contains { has($0, "New pane on the right") }, "\(byTitle)")
        try press(app, [], .returnKey)
        try app.waitUntil("the tab itself in the split") { try panes() == [first, titled] && !isOpen(app) }
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("one pane once more") { try panes().count == 1 }

        // On a named side, and Return with no text.
        try app.dispatch(.tab(.focus(first)))
        try app.waitUntil("the first tab again") { try currentTab(app.view())?.id == first }
        try open(app)
        try typeWord(app, "split")
        try type(app, "left")
        try waitForRows(app, "the tabs on the left") { $0.first.map { has($0, "New pane on the left") } ?? false }
        try press(app, [], .returnKey)
        try app.waitUntil("a tab left of the page") { try panes().count == 2 && panes().last == first && !isOpen(app) }
        try app.dispatch(.split(.separateAll))
        try app.waitUntil("one pane again, after the left tab") { try panes().count == 1 }

        // An empty pane is still on offer, under the tabs.
        try open(app)
        try typeWord(app, "split")
        let withAdd = try waitForRows(app, "Add Split View") { $0.contains { has($0, "Add Split View") } }
        for _ in 0..<(withAdd.firstIndex { has($0, "Add Split View") } ?? 0) { try press(app, [], .downArrow) }
        app.sleep(0.2)
        try press(app, [], .returnKey)
        try app.waitUntil("the empty pane's bar") { if case .commandBar(let bar)? = try app.view().overlay { return bar.fillsPane }; return false }
        try expect(try panes().count == 2, "a pane was added")
        try dismiss(app)
        app.passed("An address and a side each opened in a new pane; expand ran; an open tab joined the split itself, by title and from the list, on either side; Add Split View stayed on offer")
    }

    private static func XCTFirst<T>(_ value: T?, _ what: String) throws -> T {
        guard let value else { throw Check(description: "no \(what)") }
        return value
    }

    // MARK: Window

    @Sendable static func windowPlaces(_ app: AppUnderTest) throws {
        try preflight(app)
        func place(_ text: String) throws {
            try open(app)
            try typeWord(app, "window")
            try type(app, text)
            try waitForRows(app, "\(text)'s row") { !$0.isEmpty }
            app.sleep(0.15)
            try press(app, [], .returnKey)
            try app.waitUntil("the bar closed") { try !isOpen(app) }
        }
        func frame() throws -> CGRect { try app.native().windowFrame }
        func near(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1 }
        func expectFrame(_ expected: CGRect, _ what: String) throws {
            var last = CGRect.zero
            do { try app.waitUntil(what, timeout: 3) { last = try frame(); return near(last, expected) } }
            catch { throw Check(description: "\(what): the frame is \(last), expected \(expected)") }
        }
        let original = try frame()
        try open(app)
        try typeWord(app, "window")
        let listed = try waitForRows(app, "the places") { $0.count == 5 }
        try expect(has(listed[0], "Left Half") && has(listed[4], "Maximize"), "\(listed)")
        _ = try app.screenshot("list")
        try dismiss(app)

        // The screen's visible frame, read off Maximize: inside the display and short of its menu bar.
        try place("maximize")
        try app.waitUntil("maximized") { try frame() != original }
        app.sleep(0.2)
        let visible = try frame()
        let display = CGDisplayBounds(CGMainDisplayID())
        try expect(visible.width <= display.width + 1 && visible.height < display.height, "\(visible) in \(display)")
        try place("left")
        try expectFrame(CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height), "left half")
        try place("right")
        try expectFrame(CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height), "right half")
        try place("top")
        try expectFrame(CGRect(x: visible.minX, y: visible.midY, width: visible.width, height: visible.height / 2), "top half")
        try place("bottom")
        try expectFrame(CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height / 2), "bottom half")
        try app.setWindowFrame(CGRect(x: visible.minX + 10, y: visible.minY + 10, width: 1000, height: 700))
        try place("centre")
        try expectFrame(CGRect(x: visible.midX - 500, y: visible.midY - 350, width: 1000, height: 700), "centre")
        // One display here means Next Display stays; with more it moves. Either way the row runs.
        var displays: UInt32 = 0
        _ = CGGetActiveDisplayList(0, nil, &displays)
        let before = try frame()
        try place("next")
        if displays == 1 { app.sleep(0.3); try expect(try near(frame(), before), "Next Display with one display moved the window") }
        else { try app.waitUntil("the next display") { try !near(frame(), before) } }
        app.note("Next Display ran on \(displays) display(s).")

        // The existing commands. Stay on Top keeps an open bar, as it always has.
        try open(app)
        try typeWord(app, "window")
        try type(app, "always")
        try waitForRows(app, "Stay on Top") { $0.first.map { has($0, "Stay on Top") } ?? false }
        app.sleep(0.15)
        try press(app, [], .returnKey)
        try app.waitUntil("Stay on Top") { try app.view().stayOnTop }
        try dismiss(app)
        try app.dispatch(.window(.toggleStayOnTop))
        try place("full")
        try app.waitUntil("full screen", timeout: 10) { let n = try app.native(); return n.fullscreen && n.fullscreenTransitioning != true }
        try app.dispatch(.app(.toggleFullScreen))
        try app.waitUntil("full screen left", timeout: 10) { let n = try app.native(); return !n.fullscreen && n.fullscreenTransitioning != true }
        try place("minimize")
        try app.waitUntil("minimized") { try app.native().miniaturized }
        _ = try app.send(.activate(window: app.window!))
        try app.waitUntil("back from the Dock") { try !app.native().miniaturized }

        // Ordinary text meets none of this, but an exact phrase has its row low down, the search first.
        try open(app)
        try type(app, "left")
        app.sleep(0.4)
        let plain = try rows(app)
        try expect(!plain.contains { has($0, "Left Half") }, "left alone: \(plain)")
        try dismiss(app)
        try open(app)
        try type(app, "left half")
        let exact = try waitForRows(app, "the phrase's row") { $0.last.map { has($0, "Left Half") } ?? false }
        try expect(exact.count > 1 && exact[0].contains("left half"), "the search should lead: \(exact)")
        _ = try app.screenshot("exact-phrase")
        try dismiss(app)
        try app.setWindowFrame(original)
        app.passed("Halves, maximize and centre landed on the visible frame; stay on top, full screen and minimize ran; ordinary text met none of it, left half showed low down")
    }

    // MARK: Translate

    @Sendable static func translate(_ app: AppUnderTest) throws {
        try preflight(app)
        try app.dispatch(.settings(.max(.feature(.translation, true))))
        try open(app)
        guard case .commandBar(let bar)? = try app.view().overlay, bar.askAgentFound else {
            try dismiss(app)
            throw Skipped(description: "no local agent on this Mac's PATH")
        }
        try keepingPasteboard(app) {
            let before = aiCalls(app).count
            try typeWord(app, "translate")
            try type(app, "hello world")
            // The pending row at once, then the answer.
            let pending = try waitForRows(app, "the pending row", timeout: 2) { $0.first.map { has($0, "Translating to Chinese") } ?? false }
            try expect(has(pending[0], "hello world"), "\(pending)")
            _ = try app.screenshot("pending")
            try waitForRows(app, "the answer", timeout: 15) { $0.first.map { has($0, "Fixture answer") && has($0, "Copy Result") } ?? false }
            _ = try app.screenshot("answer")
            let prompt = aiCalls(app).last?["prompt"] as? String ?? ""
            try expect(aiCalls(app).count == before + 1 && prompt.contains("hello world") && prompt.contains("Chinese"), "asked \(prompt.prefix(200))")
            try expect(try isOpen(app), "the bar stays open for the answer")
            try expect(try app.view().ai == nil, "the answer panel stayed out of it")
            try press(app, [], .returnKey)
            try app.waitUntil("Return copied the answer") { try !isOpen(app) && pasteboard(app).contains("Fixture answer") }

            // A trailing "to ja"; a quick run of keys asks once, for the final text.
            let count = aiCalls(app).count
            try open(app)
            try typeWord(app, "tr")
            try type(app, "good morning to ja")
            try waitForRows(app, "Japanese", timeout: 15) { $0.first.map { has($0, "Fixture answer") } ?? false }
            let asked = aiCalls(app)
            try expect(asked.count == count + 1, "\(asked.count - count) asks for one run of keys")
            let japanese = asked.last?["prompt"] as? String ?? ""
            try expect(japanese.contains("good morning") && !japanese.contains("to ja") && japanese.contains("Japanese"), japanese)
            // A change: the old answer leaves the row at once.
            try type(app, "x")
            try app.waitUntil("the answer gone with the change") { try !rows(app).contains { has($0, "Fixture answer") } }
            try dismiss(app)

            // translate page runs the page translation on the fixture's French page.
            let url = app.site.url("ai.html"), item = try app.load(url), page = PageID(window: app.window!, item: item)
            try app.waitForPageInput(page, at: url)
            try open(app)
            try typeWord(app, "translate")
            try type(app, "page to english")
            try waitForRows(app, "the page row") { $0.first.map { has($0, "Translate this page to English") } ?? false }
            _ = try app.screenshot("page-row")
            try press(app, [], .returnKey)
            try app.waitUntil("the page translated", timeout: 15) {
                if case .translated? = try app.view().urlPill.translation { return true }
                return false
            }
            // Translation off: the word says where its switch is, and Tab opens that pane.
            try app.dispatch(.settings(.max(.feature(.translation, false))))
            try blockedWord(app, "translate", "Translate Pages is off in Advanced settings", .advanced)
            app.passed("Pending, then the answer in the row and Return copied it; to ja asked once for the final text; translate page translated the page; off, the word said where its switch is and Tab opened it")
        }
    }

    // MARK: Dictionary

    /// Whether a program of this name is running now, so a scenario only quits what it started.
    private static func running(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    @Sendable static func define(_ app: AppUnderTest) throws {
        try preflight(app)
        try open(app)
        try typeWord(app, "define")
        try type(app, "apple")
        let found = try waitForRows(app, "the definition", timeout: 8) { $0.first.map { has($0, "Open Dictionary") } ?? false }
        try expect(has(found[0], "apple") && has(found[0], "noun"), "\(found)")
        _ = try app.screenshot("definition")
        try dismiss(app)
        try open(app)
        try typeWord(app, "def")
        try type(app, "zzzqqqxyz")
        try waitForRows(app, "nothing found", timeout: 8) { $0.first.map { has($0, "No definition for zzzqqqxyz") } ?? false }
        try press(app, [], .returnKey)
        app.sleep(0.3)
        try expect(try isOpen(app), "Return on nothing found closed the bar")
        try dismiss(app)

        // Return opens the word in Dictionary.app; the window is closed again, and the app quit if it was not running.
        let wasRunning = running("Dictionary")
        defer { if !wasRunning, running("Dictionary") { try? tool("/usr/bin/pkill", ["-x", "Dictionary"]) } }
        try open(app)
        try typeWord(app, "define")
        try type(app, "apple")
        try waitForRows(app, "the definition", timeout: 8) { $0.first.map { has($0, "Open Dictionary") } ?? false }
        try press(app, [], .returnKey)
        try app.waitUntil("the bar closed") { try !isOpen(app) }
        var opened = false
        for _ in 0..<60 where !opened {
            opened = NativeSystemInput.closeWindow(owner: "Dictionary")
            if !opened { app.sleep(0.25) }
        }
        try expect(opened, "no Dictionary window")
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        app.passed("The offline dictionary's first lines in the row; nothing found says so; Return opened Dictionary.app")
    }

    // MARK: Colour

    @Sendable static func color(_ app: AppUnderTest) throws {
        try preflight(app)
        try useFixtureEngine(app)
        try keepingPasteboard(app) {
            try open(app)
            try type(app, "#ff5500")
            let rowsShown = try waitForRows(app, "three forms") { $0.count >= 3 && has($0[0], "#FF5500") }
            try expect(has(rowsShown[1], "rgb(255, 85, 0)") && has(rowsShown[2], "hsl(20, 100%, 50%)"), "\(rowsShown)")
            _ = try app.screenshot("swatch")
            try press(app, [], .returnKey)
            try app.waitUntil("hex copied") { try !isOpen(app) && pasteboard(app) == "#FF5500" }
            // Each row copies its own form.
            try open(app)
            try type(app, "rgb(255,85,0)")
            try waitForRows(app, "rgb") { $0.first.map { has($0, "#FF5500") } ?? false }
            try press(app, [], .downArrow)
            app.sleep(0.2)
            try press(app, [], .returnKey)
            try app.waitUntil("the rgb form copied") { try !isOpen(app) && pasteboard(app) == "rgb(255, 85, 0)" }
            try open(app)
            try type(app, "hsl(20,100%,50%)")
            try waitForRows(app, "hsl") { $0.first.map { has($0, "#FF5500") } ?? false }
            try press(app, [], .downArrow)
            try press(app, [], .downArrow)
            app.sleep(0.2)
            try press(app, [], .returnKey)
            try app.waitUntil("the hsl form copied") { try !isOpen(app) && pasteboard(app) == "hsl(20, 100%, 50%)" }
            // The prefix reads CSS names; alone, a name is an ordinary word.
            try open(app)
            try typeWord(app, "color")
            try type(app, "tomato")
            try waitForRows(app, "tomato") { $0.first.map { has($0, "#FF6347") } ?? false }
            _ = try app.screenshot("named")
            try dismiss(app)
            try open(app)
            try type(app, "tomato")
            app.sleep(0.4)
            let word = try rows(app)
            try expect(!word.contains { has($0, "Copy Color") }, "tomato alone: \(word)")
            try dismiss(app)
            // Bare #abc: the search first, so Return searches, the colour below it; a hashtag has no colour row.
            try open(app)
            try type(app, "#abc")
            let bare = try waitForRows(app, "the colour under the search") { $0.count >= 4 && has($0[1], "#AABBCC") }
            try expect(bare[0].contains("#abc"), "\(bare)")
            _ = try app.screenshot("bare-hash")
            try press(app, [], .returnKey)
            try app.waitUntil("#abc searched") { currentTab(try app.view())?.title == "query:#abc" }
            try open(app)
            try type(app, "#hashtag")
            app.sleep(0.4)
            let hashtag = try rows(app)
            try expect(!hashtag.contains { has($0, "Copy Color") } && hashtag.first?.contains("#hashtag") == true, "\(hashtag)")
            try dismiss(app)
            app.passed("#ff5500, rgb() and hsl() each with a swatch and three forms, each form copied; tomato only after color; #abc still searched")
        }
    }
}
