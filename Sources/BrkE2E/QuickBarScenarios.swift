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
        Scenario("QuickBar-Answers", "percent, root, units, CSS, dates and times answer inline, Return copies; bare words sit under the typed row; searches stay searches", answers),
        Scenario("QuickBar-Files", "file rows from the fixture folder: ranked as commands, hidden and Library left out, Return opens, Cmd+Return reveals, Option+Return copies, the file mode, no stale rows", files),
        Scenario("QuickBar-Prefix", "a whole word and Tab enters through site search's pill; a real Space never does, so the words can begin a search; Backspace and Esc give it back; an engine of the same name wins; part of a word is offered", prefixKeys),
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

    /// Text as a US keyboard types it, posted at the window server while this Brk is the active app. "\t" is Tab and "\r"
    /// Return, struck in the same burst as the letters before them.
    private static func type(_ app: AppUnderTest, _ text: String) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try PhysicalKeys.strike(text)
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

            // Plain arithmetic leads, the search under it.
            try open(app)
            try type(app, "2+3*4")
            let plain = try waitForRows(app, "arithmetic") { $0.first.map { has($0, "14") } ?? false }
            try expect(plain.count > 1 && plain[1].contains("2+3*4"), "the search should follow the answer: \(plain)")
            try press(app, [], .returnKey)
            try app.waitUntil("the arithmetic copied") { try pasteboard(app) == "14" }
            app.passed("Percent, root, units, CSS, days, timespan, time zones and bare words answered through real keys; searches and addresses did not")
        }
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
            // Inline: ranked as commands are (Arc's typeTravel archetype), at most two, the search still listed.
            try open(app)
            try type(app, "quickbar")
            let inline = try waitForRows(app, "file rows with the typed row") { $0.contains { has($0, fileCaption) } }
            try expect(inline.contains { $0.contains("quickbar") }, "the typed row should be listed: \(inline)")
            let fileRows = inline.indices.filter { has(inline[$0], fileCaption) }
            try expect(fileRows.count <= 2, "more than two inline: \(inline)")
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


    // MARK: C


    // MARK: D

    private static func aiCalls(_ app: AppUnderTest) -> [[String: Any]] {
        let data = (try? String(contentsOf: app.dataDirectory.appendingPathComponent("ai-fixture.jsonl"), encoding: .utf8)) ?? ""
        return data.split(whereSeparator: \.isNewline).compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
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
            // At a person's speed: the word and Tab in one burst, nothing waiting for the chip or the rows in between. With
            // the agent on, a Tab that missed the prefix would ask it (the README recording, 2026-11-10).
            let calls = aiCalls(app).count
            for word in ["emoji", "define", "window", "split"] {
                try open(app)
                try type(app, word + "\t")
                try app.waitUntil("\(word) and an immediate Tab entered") { try pillShown(app) && inputText(app).isEmpty }
                try dismiss(app)
            }
            // Return at once chooses for the whole text, not for the keystroke before it ("query:split pea sou").
            try open(app)
            try type(app, "split pea soup\r")
            try app.waitUntil("split pea soup searched at once") { currentTab(try app.view())?.title == "query:split pea soup" }
            app.sleep(0.3)
            try expect(aiCalls(app).count == calls, "a fast Tab or Return asked the agent: \(aiCalls(app).dropFirst(calls).map { $0["prompt"] ?? "" })")
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
