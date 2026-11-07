import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Every Max feature the way a person reaches it, on a real agent: real keys and real clicks through the window server
/// from a new user's state (Settings → Max, Turn On Max, the agent pop-up, then each feature from its own entry point),
/// the app started with a GUI app's short PATH. Nothing is dispatched; the control socket only reads state and takes
/// screenshots. Opt-in, registered only when BRK_E2E_REAL_UI_AGENT names an agent, since every step spends the user's
/// quota (about ten short prompts). Each feature's outcome goes into real-ui-<agent>.txt in the run's shots folder; one
/// feature failing does not stop the others. Written after the user found Max's features unusable on 2026-11-07 while
/// `AIRealScenarios` (which dispatches) passed them all.
enum AIRealUIScenarios {
    static var all: [Scenario] {
        guard let name = ProcessInfo.processInfo.environment["BRK_E2E_REAL_UI_AGENT"], let choice = AIProviderChoice(rawValue: name), choice.kind != nil else { return [] }
        return [Scenario("AIRealUI-\(name)", "real \(name), real input: Max pane, Tidy without pinned tabs, Ask, prefixes, page features, previews, titles, downloads, a folder session, restart",
                         cefOnly: "real agent, real input") { try route($0, choice) }]
    }

    private final class Log {
        let url: URL
        var failures = 0
        init(_ url: URL) { self.url = url; try? Data().write(to: url) }
        func write(_ line: String) {
            print("[real-ui] " + line)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        }
        func check(_ name: String, _ body: () throws -> String) {
            let start = Date()
            func seconds() -> String { String(format: "%.1f", Date().timeIntervalSince(start)) }
            do { let result = try body(); write("PASS \(name) (\(seconds()) s): \(result)") }
            catch { failures += 1; write("FAIL \(name) (\(seconds()) s): \(error)") }
        }
    }

    // MARK: Real input

    nonisolated(unsafe) private static var pid: Int32 = 0

    /// Real key codes at the window server (a US layout), Shift where the character needs it.
    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ":": (41, true), ";": (41, false), "-": (27, false), "_": (27, true), ".": (47, false), ",": (43, false),
                                                   "/": (44, false), "?": (44, true), "'": (39, false), "=": (24, false), "|": (42, true), "!": (18, true)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) {
            map[letter] = (code, false); map[Character(letter.uppercased())] = (code, true)
        }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()

    /// The frontmost window at a screen point is this Brk's (any of its windows: the browser, settings, a sheet).
    private static func ours(at point: CGPoint) throws {
        guard let front = PhysicalPointer.frontmost(at: point), front.pid == pid else {
            throw Check(description: "another window is in front at \(point) (\(String(describing: PhysicalPointer.frontmost(at: point)))); nothing posted")
        }
    }
    /// Keys go to the active app: only while Brk is it.
    private static func brkActive() throws {
        guard case .native(let facts) = try? app?.send(.native(window: nil)), facts.appActive == true else { throw Check(description: "Brk is not the active app; no key posted") }
    }
    nonisolated(unsafe) private static weak var app: AppUnderTest?

    private static func type(_ text: String) throws {
        try brkActive()
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags; event.post(tap: .cghidEventTap); usleep(14_000)
        }
        for character in text {
            guard let (code, shifted) = codes[character] else { throw Check(description: "no key for \(character)") }
            if shifted { post(56, true, .maskShift) }
            post(code, true, shifted ? .maskShift : []); post(code, false, shifted ? .maskShift : [])
            if shifted { post(56, false, []) }
            usleep(18_000)
        }
    }
    private static func key(_ modifiers: Modifiers, _ key: Key) throws {
        try brkActive()
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(250_000)
    }
    /// A left click at a screen point; the point must be on one of this Brk's windows.
    private static func click(_ point: CGPoint) throws {
        try ours(at: point)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 60_000)
        }
        usleep(300_000)
    }
    private static func screen(_ app: AppUnderTest, _ frame: CGRect) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + frame.midX, y: top + frame.midY)
    }
    private static func click(_ app: AppUnderTest, _ view: ViewID) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try click(try screen(app, try visible(app.native(), view).frame))
    }
    /// A control of a window the socket does not describe (settings, a popover, a sheet), found through Accessibility.
    private static func click(identifier: String? = nil, title: String? = nil, roles: [String] = [], _ what: String) throws {
        var frame: CGRect?
        try app!.waitUntil("\(what) on screen", timeout: 8) { frame = NativeSystemInput.frame(pid: pid, identifier: identifier, title: title, roles: roles); return frame != nil }
        try click(CGPoint(x: frame!.midX, y: frame!.midY))
    }
    /// A pop-up button opened with a real click; its item chosen by typing its first letters and Return, as a person can.
    private static func choose(popUp identifier: String, typing text: String, _ what: String) throws {
        try click(identifier: identifier, what)
        app!.sleep(0.5)
        try type(text)
        app!.sleep(0.3)
        try key([], .returnKey)
        app!.sleep(0.8)
    }

    private static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "no settings") }
        return settings
    }
    private static func bar(_ app: AppUnderTest, _ text: String) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try key(.command, .t)
        try app.waitUntil("the command bar") { if case .commandBar? = try app.view().overlay { true } else { false } }
        try type(text)
        app.sleep(0.8)
    }
    private static func open(_ app: AppUnderTest, _ path: String) throws {
        let before = try app.view().space.today.rows.count
        try bar(app, app.site.url(path).absoluteString)
        try key([], .returnKey)
        try app.waitUntil("\(path) open", timeout: 15) { try app.view().space.today.rows.count > before }
        app.sleep(1)
    }
    /// The NSOpenPanel a feature opened: Go to Folder with ⇧⌘G, the path typed, Return, Return on the default button.
    private static func choosePanelFolder(_ app: AppUnderTest, _ folder: URL) throws {
        app.sleep(1.2)
        try key([.command, .shift], .g)
        app.sleep(0.8)
        try type(folder.path)
        app.sleep(0.5)
        try key([], .returnKey)
        app.sleep(1.0)
        try key([], .returnKey)
        app.sleep(1.2)
    }
    private static func shot(_ app: AppUnderTest, _ name: String) { _ = try? app.screenshot("AIRealUI-\(name)") }
    private static func short(_ text: String?) -> String { String((text ?? "nil").replacingOccurrences(of: "\n", with: " ⏎ ").prefix(240)) }
    private static func toast(_ app: AppUnderTest) -> String? { (try? app.view().tabTools.toast).flatMap { $0.map { $0.text + ($0.subtitle.map { " " + $0 } ?? "") } } }

    private static func answer(_ app: AppUnderTest, timeout: Double = 150) throws -> AIAnswerSnapshot {
        try app.waitUntil("the panel's answer", timeout: timeout) { try app.view().ai?.busy == false }
        return try XCTUnwrapValue(try app.view().ai)
    }
    private static func closePanel(_ app: AppUnderTest) throws {
        guard try app.view().ai != nil else { return }
        try click(app, .aiControl("close"))
        try app.waitUntil("the panel closed") { try app.view().ai == nil }
    }

    // MARK: The route

    private static func route(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting events is not allowed for this runner") }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        pid = hello.pid
        Self.app = app
        let name = choice.rawValue, kind = choice.kind!
        let log = Log(app.shotsDirectory.appendingPathComponent("real-ui-\(name).txt"))
        defer { try? NativeSystemInput.setShift(false); PhysicalKeys.clearSystemModifiers(KeyChord([.command, .shift, .option, .control], .a)) }

        // A new user: Settings, the Max tab, Turn On Max, the agent.
        var ready = false
        log.check("Max pane: Turn On Max and choose \(kind.displayName)") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .comma)
            try click(title: "Max", roles: ["AXButton", "AXRadioButton", "AXToolbarButton"], "the Max tab")
            app.sleep(1)
            try expect(try !settings(app).max.settings.isOn, "Max is on before Turn On Max")
            try click(identifier: ViewID.settingsField("enableMax").identifier, "Turn On Max")
            try app.waitUntil("Max on") { try settings(app).max.settings.isOn }
            let on = try settings(app).max.settings
            try expect(on.tidyOn && on.titlesOn && AIFeature.allCases.allSatisfy(on.enabled), "Turn On Max left \(on)")
            try choose(popUp: ViewID.settingsField("agentChoice").identifier, typing: kind.displayName, "the agent pop-up")
            try app.waitUntil("\(kind.displayName) chosen") { try settings(app).max.settings.provider == choice }
            var status: AIAgentStatus?
            try app.waitUntil("the agent's status", timeout: 40) {
                status = try settings(app).max.agents.first { $0.kind == kind }
                return status != nil && status?.state != .checking
            }
            ready = status?.state == .ready
            app.sleep(0.5)
            try captureSettings(app, "max-pane")
            try key(.command, .w)
            return "state \(String(describing: status?.state)), version \(status?.version ?? "?"), \(status?.models.count ?? 0) models"
        }
        guard ready else {
            // A signed-out or missing agent: what the person is told where they use Max.
            log.check("The message when \(kind.displayName) cannot answer") {
                try bar(app, "what is two plus two")
                try key([], .tab)
                let reply = try answer(app, timeout: 60)
                shot(app, "\(name)-cannot")
                try expect(reply.conversation?.items.contains { if case .notice(let text) = $0 { text.contains("not signed in") || text.contains("not installed") } else { false } } == true || reply.text.contains("not signed in"), "the panel says: \(reply.text)")
                return short(reply.text)
            }
            log.write("failures: \(log.failures)")
            try expect(log.failures == 0, "see real-ui-\(name).txt")
            return
        }

        // Tidy: no pinned tabs, six Today tabs (nothing offered), then seven.
        log.check("Tidy Tabs without pinned tabs, from the divider") {
            for path in ["ai.html", "ai-source.html", "page2.html", "red.html", "news-site.html"] where try app.view().space.today.rows.count < 6 { try open(app, path) }
            try expect(try app.view().space.pinned.rows.isEmpty, "this run should have no pinned tabs")
            try expect(try !app.view().space.today.canTidy, "Tidy offered with six Today tabs")
            try open(app, "find.html")
            try expect(try app.view().space.today.canTidy, "no Tidy with seven Today tabs")
            let tidy = try XCTUnwrapValue(try app.native().actual[ViewID.todayTidy.identifier]).frame
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try PhysicalPointer.move(app, to: CGPoint(x: tidy.midX, y: tidy.midY), window: app.window!)
            app.sleep(1.2)
            shot(app, "tidy-hover")
            try click(try screen(app, tidy))
            try app.waitUntil("Today in groups", timeout: 150) { try app.view().space.today.rows.contains { if case .folder = $0 { true } else { false } } || toast(app) != nil && !(toast(app)?.hasPrefix("Tidied") ?? false) }
            let toastText = toast(app) ?? ""
            shot(app, "tidy-done")
            try expect(toastText.hasPrefix("Tidied Tabs!"), "after Tidy the notice is \(toastText)")
            try key(.command, .z)
            try app.waitUntil("⌘Z put the tabs back") { try !app.view().space.today.rows.contains { if case .folder = $0 { true } else { false } } }
            return "grouped, \"\(toastText)\", ⌘Z undid it"
        }

        log.check("Ask in the command bar: a question and Tab, a follow-up, Stop, Close") {
            try bar(app, "In one short sentence, what does HTTP stand for")
            try key([], .tab)
            var reply = try answer(app)
            try expect(reply.text.lowercased().contains("transfer"), "answer: \(reply.text)")
            shot(app, "ask")
            try click(app, .aiControl("input"))
            try type("What did I just ask about? Three words at most.")
            try key([], .returnKey)
            app.sleep(1)
            reply = try answer(app)
            try expect(reply.text.uppercased().contains("HTTP"), "follow-up: \(reply.text)")
            try click(app, .aiControl("input"))
            try type("Write a 400 word essay about rivers.")
            try key([], .returnKey)
            try app.waitUntil("the essay is being written", timeout: 60) { let ai = try app.view().ai; return ai?.busy == true && (ai?.text.count ?? 0) > 60 }
            try click(app, .aiControl("stop"))
            try app.waitUntil("Stopped", timeout: 10) { try app.view().ai?.conversation?.items.last == .notice("Stopped.") }
            shot(app, "stopped")
            try closePanel(app)
            return "answered, followed up and stopped: \(short(reply.text))"
        }

        log.check("The agent's own prefix and Tab") {
            let word = kind == .codex ? "gpt" : kind.rawValue
            try bar(app, word)
            try key([], .tab)
            try type("Say hello in French, one word.")
            try key([], .returnKey)
            let reply = try answer(app)
            try expect(reply.conversation?.agent == kind && !reply.text.isEmpty, "\(word): \(String(describing: reply.conversation?.agent)) \(reply.text)")
            shot(app, "prefix")
            try closePanel(app)
            return "\(word) → \(reply.conversation?.agentName ?? "?") \(reply.conversation?.model ?? ""): \(short(reply.text))"
        }

        log.check("Ask on Page from the command bar on a French page") {
            try open(app, "ai.html")
            try bar(app, "ask on page")
            try key([], .returnKey)
            try app.waitUntil("the Ask on Page bar") { try app.view().overlay != nil }
            try type("What is the page's main heading? Quote it.")
            try key([], .returnKey)
            let reply = try answer(app)
            try expect(reply.text.contains("Bonjour"), "answer: \(reply.text)")
            try expect(!reply.sources.isEmpty, "no source under the answer")
            shot(app, "ask-page")
            try closePanel(app)
            return short(reply.text)
        }

        log.check("Translate Pages from the pill's Translation Available (P50-g)") {
            try app.waitUntil("Translation Available", timeout: 15) { try app.view().urlPill.translation == .available }
            try click(app, .aiControl("pill-translation"))
            try click(identifier: ViewID.aiControl("translation-translate").identifier, "the popover's Translate")
            try app.waitUntil("Translated", timeout: 150) { try app.view().urlPill.translation == .translated(from: "French") }
            shot(app, "translated")
            return "the page is in English, the pill says Translated"
        }

        log.check("5-Second Previews: Shift held over a link") {
            let card = try visible(app.native(), .card(0)).frame
            try PhysicalPointer.move(app, to: CGPoint(x: card.minX + 60, y: card.minY + 50), window: app.window!)
            try NativeSystemInput.setShift(true)
            defer { try? NativeSystemInput.setShift(false) }
            try app.waitUntil("the preview card's summary", timeout: 90) { let p = try app.view().aiPreview; return p?.busy == false && (p?.details.isEmpty == false || p?.failure != nil) }
            let preview = try XCTUnwrapValue(try app.view().aiPreview)
            shot(app, "preview")
            try expect(preview.failure == nil, "the card says \(preview.failure ?? "")")
            return "\(preview.title): \(preview.details.map(\.label))"
        }

        log.check("Instant Links: Shift+Return in the bar") {
            try PhysicalPointer.move(app, to: CGPoint(x: 900, y: 700), window: app.window!)
            try bar(app, "wikipedia arc browser")
            try key(.shift, .returnKey)
            try app.waitUntil("a Wikipedia page opened", timeout: 120) {
                try app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.url?.host?.contains("wikipedia") == true } else { false } }
                    || app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.instant == .failed } else { false } }
            }
            shot(app, "instant")
            try expect(try app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.url?.host?.contains("wikipedia") == true } else { false } }, "the row failed: \(toast(app) ?? "")")
            return "opened"
        }

        log.check("Tidy Tab Titles: ⌘D on a tab with a long title") {
            try open(app, "news-site.html")
            let tab = try XCTUnwrapValue(app.view().space.today.rows.compactMap { if case .tab(let t) = $0, t.status == .current { t } else { nil } }.first)
            try click(app, .card(0))
            try key(.command, .d)
            try app.waitUntil("a tidier title", timeout: 120) {
                try app.view().space.pinned.rows.contains { if case .tab(let t) = $0 { t.id == tab.id && t.title != tab.title } else { false } } || toast(app)?.hasPrefix("Tidy Tab Titles") == true
            }
            shot(app, "titles")
            let row = try app.view().space.pinned.rows.compactMap { if case .tab(let t) = $0, t.id == tab.id { t } else { nil } }.first
            try expect(row?.title != tab.title, "not renamed: \(toast(app) ?? "")")
            return "\(tab.title) → \(row?.title ?? "")"
        }

        log.check("Tidy Downloads: a real download, into a folder chosen in Profiles") {
            let folder = app.dataDirectory.appendingPathComponent("downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .comma)
            try click(title: "Profiles", roles: ["AXButton", "AXRadioButton", "AXToolbarButton"], "the Profiles tab")
            try choose(popUp: ViewID.settingsField("downloadLocation-default").identifier, typing: "Other", "Download location")
            try choosePanelFolder(app, folder)
            try key(.command, .w)
            try open(app, "ai-download.html")
            let card = try visible(app.native(), .card(0)).frame
            try PhysicalPointer.click(app, at: try screen(app, CGRect(x: card.minX + 120, y: card.minY + 92, width: 1, height: 1)), window: app.window!)
            try app.waitUntil("the download renamed", timeout: 120) {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                return names.contains { !$0.hasPrefix("scan_00231") && $0.hasSuffix(".txt") } || toast(app)?.hasPrefix("Tidy Downloads") == true
            }
            app.sleep(0.5)
            let notice = toast(app) ?? ""
            shot(app, "download")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            try expect(notice.hasPrefix("Download renamed to:"), "the notice is \(notice); files \(names)")
            return "\(names) \"\(notice)\""
        }

        log.check("Work in a Folder…: Deny, then Allow, with the agent's default model") {
            let work = app.dataDirectory.appendingPathComponent("work-\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let file = work.appendingPathComponent("hello.txt")
            try bar(app, "say ok")
            try key([], .tab)
            _ = try answer(app)
            try click(app, .aiControl("folder"))
            try choosePanelFolder(app, work)
            try app.waitUntil("a session in the folder", timeout: 20) { try app.view().ai?.conversation?.folder != nil }
            func ask() throws -> AIAnswerSnapshot {
                try click(app, .aiControl("input"))
                try type("Create the file hello.txt in this folder containing the word hi. Use your file writing tool.")
                try key([], .returnKey)
                try app.waitUntil("an approval or the end of the turn", timeout: 150) {
                    let ai = try app.view().ai
                    return ai?.busy == false || ai?.conversation?.items.contains { if case .approval(let a) = $0 { a.answer == nil } else { false } } == true
                }
                return try XCTUnwrapValue(try app.view().ai)
            }
            var notes: [String] = []
            var reply = try ask()
            if reply.busy == false, let limit = reply.conversation?.items.compactMap({ if case .notice(let text) = $0 { text } else { nil } }).last(where: { $0.lowercased().contains("limit") }) {
                // The default model has no quota left: the panel's Agent… leads to the model, the next message uses it.
                notes.append("default model: \(limit)")
                shot(app, "folder-limit")
                try click(app, .aiControl("agent-settings"))
                try choose(popUp: ViewID.settingsField("agentModel").identifier, typing: "Haiku", "the model pop-up")
                try key(.command, .w)
                reply = try ask()
            }
            try expect(reply.busy, "no approval: \(short(reply.conversation.map { "\($0.items)" }))")
            shot(app, "folder-approval")
            try click(app, .aiControl("approval-deny"))
            _ = try answer(app)
            try expect(!FileManager.default.fileExists(atPath: file.path), "Deny wrote the file")
            reply = try ask()
            try expect(reply.busy, "no approval the second time")
            try click(app, .aiControl("approval-allowOnce"))
            reply = try answer(app)
            shot(app, "folder-allowed")
            try expect(FileManager.default.fileExists(atPath: file.path), "Allow did not write the file: \(short(reply.text))")
            try closePanel(app)
            return (notes + ["Deny wrote nothing, Allow wrote hello.txt; model \(reply.conversation?.model ?? "?")"]).joined(separator: "; ")
        }

        log.check("After a restart: Max still on, the choices kept, Tidy still offered") {
            try app.flush()
            _ = try app.quit()
            try app.launch()
            pid = { if case .hello(let h)? = try? app.send(.hello) { h.pid } else { 0 } }()
            let max = try settings(app).max.settings
            try expect(max.isOn && max.provider == choice && max.tidyOn && AIFeature.allCases.allSatisfy(max.enabled), "after restart: \(max)")
            try expect(try app.view().space.today.canTidy, "no Tidy after restart")
            return "provider \(max.provider.rawValue), options \(String(describing: max.agentOptions))"
        }

        log.write("failures: \(log.failures)")
        try expect(log.failures == 0, "see real-ui-\(name).txt")
    }

    /// The settings window by its number, for the eye.
    private static func captureSettings(_ app: AppUnderTest, _ name: String) throws {
        guard let window = try app.native().appWindows.first(where: { $0.className == "NSWindow" && $0.isVisible }) else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.number), app.shotsDirectory.appendingPathComponent("AIRealUI-\(name).png").path]
        try capture.run(); capture.waitUntilExit()
    }
}
