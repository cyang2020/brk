import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The basic AI layer the way a person meets it, on a real agent's small model: real keys and clicks at the window
/// server from a new user's state (Settings → Max, Turn On Max, the agent), then Name Tabs, a title the user typed,
/// a tab that moves to another site, Tidy's named groups, Name with AI on a group, Place New Tabs' suggestion and its
/// click, the cleanup list beside Tidy, the bar's translate prefix, a 5-Second Preview and the month's usage. Nothing is
/// dispatched; the control socket reads state and takes screenshots. Opt-in (BRK_E2E_REAL_BASIC_AGENT=claude|codex),
/// since it spends the user's quota (about fifteen small-model requests). Results go to real-basic-<agent>.txt.
enum AIBasicRealUIScenarios {
    static var all: [Scenario] {
        guard let name = ProcessInfo.processInfo.environment["BRK_E2E_REAL_BASIC_AGENT"], let choice = AIProviderChoice(rawValue: name), choice.kind != nil else { return [] }
        return [Scenario("AIRealUIBasic-\(name)", "real \(name) on its small model, real input: Max pane, Name Tabs, Tidy names, Name with AI, Place New Tabs, cleanup, translate, preview, usage",
                         cefOnly: "real agent, real input") { try route($0, choice) }]
    }

    private final class Log {
        let url: URL
        var failures = 0
        init(_ url: URL) { self.url = url; try? Data().write(to: url) }
        func write(_ line: String) {
            print("[real-basic] " + line)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        }
        func check(_ name: String, _ body: () throws -> String) {
            let start = Date()
            func seconds() -> String { String(format: "%.1f", Date().timeIntervalSince(start)) }
            do { let result = try body(); write("PASS \(name) (\(seconds()) s): \(result)") }
            catch { failures += 1; write("FAIL \(name) (\(seconds()) s): \(error)") }
        }
    }

    // MARK: Real input (the same window-server events AIRealUIScenarios posts)

    nonisolated(unsafe) private static var pid: Int32 = 0
    nonisolated(unsafe) private static weak var app: AppUnderTest?

    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ":": (41, true), ";": (41, false), "-": (27, false), "_": (27, true), ".": (47, false), ",": (43, false),
                                                   "/": (44, false), "?": (44, true), "'": (39, false), "=": (24, false), "|": (42, true), "!": (18, true)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) {
            map[letter] = (code, false); map[Character(letter.uppercased())] = (code, true)
        }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()

    private static func ours(at point: CGPoint) throws {
        guard let front = PhysicalPointer.frontmost(at: point), front.pid == pid else {
            throw Check(description: "another window is in front at \(point); nothing posted")
        }
    }
    private static func brkActive() throws {
        guard case .native(let facts) = try? app?.send(.native(window: nil)), facts.appActive == true else { throw Check(description: "Brk is not the active app; no key posted") }
    }
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
    private static func mouse(_ point: CGPoint, _ types: [CGEventType], button: CGMouseButton = .left, clicks: Int64 = 1) throws {
        try ours(at: point)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in types {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { throw Check(description: "mouse event") }
            if clicks > 1 { event.setIntegerValueField(.mouseEventClickState, value: clicks) }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 60_000)
        }
        usleep(300_000)
    }
    private static func click(_ point: CGPoint) throws { try mouse(point, [.mouseMoved, .leftMouseDown, .leftMouseUp]) }
    private static func rightClick(_ point: CGPoint) throws { try mouse(point, [.mouseMoved, .rightMouseDown, .rightMouseUp], button: .right) }
    private static func screen(_ app: AppUnderTest, _ frame: CGRect) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + frame.midX, y: top + frame.midY)
    }
    private static func frame(_ app: AppUnderTest, _ view: ViewID) throws -> CGRect { try visible(app.native(), view).frame }
    private static func click(_ app: AppUnderTest, _ view: ViewID) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try click(try screen(app, try frame(app, view)))
    }
    private static func hover(_ app: AppUnderTest, _ view: ViewID) throws {
        let f = try frame(app, view)
        try PhysicalPointer.move(app, to: CGPoint(x: f.midX, y: f.midY), window: app.window!)
        app.sleep(0.8)
    }
    private static func click(identifier: String? = nil, title: String? = nil, roles: [String] = [], _ what: String) throws {
        var found: CGRect?
        try app!.waitUntil("\(what) on screen", timeout: 8) { found = NativeSystemInput.frame(pid: pid, identifier: identifier, title: title, roles: roles); return found != nil }
        try click(CGPoint(x: found!.midX, y: found!.midY))
    }
    /// A menu item chosen the way a person can without the mouse: its first letters, then Return.
    private static func chooseInMenu(_ text: String) throws {
        app!.sleep(0.6)
        try type(text)
        app!.sleep(0.3)
        try key([], .returnKey)
        app!.sleep(0.8)
    }
    private static func choose(popUp identifier: String, typing text: String, _ what: String) throws {
        try click(identifier: identifier, what)
        try chooseInMenu(text)
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
    private static func tabs(_ app: AppUnderTest) throws -> [TabRow] {
        func walk(_ rows: [Row]) -> [TabRow] {
            rows.flatMap { row -> [TabRow] in
                switch row {
                case .tab(let t): [t]
                case .split(let s): s.panes
                case .folder(let f): walk(f.children)
                }
            }
        }
        let view = try app.view()
        return walk(view.space.pinned.rows) + walk(view.space.today.rows)
    }
    private static func folders(_ app: AppUnderTest) throws -> [FolderRow] {
        try app.view().space.today.rows.compactMap { if case .folder(let f) = $0 { f } else { nil } }
    }
    /// A page opened from the command bar as a new tab; returns the tab.
    @discardableResult
    private static func open(_ app: AppUnderTest, _ url: URL) throws -> TabRow {
        let before = Set(try tabs(app).map(\.id))
        try bar(app, url.absoluteString)
        try key([], .returnKey)
        var found: TabRow?
        try app.waitUntil("\(url.lastPathComponent) shown", timeout: 20) {
            found = try tabs(app).first { $0.status == .current && $0.url?.absoluteString == url.absoluteString && !before.contains($0.id) }
            return found != nil
        }
        app.sleep(0.8)
        return found!
    }
    private static func shot(_ app: AppUnderTest, _ name: String) { _ = try? app.screenshot("AIBasicRealUI-\(name)") }
    private static func toast(_ app: AppUnderTest) -> String? { (try? app.view().tabTools.toast).flatMap { $0.map { $0.text + ($0.subtitle.map { " " + $0 } ?? "") } } }
    private static func capture(_ app: AppUnderTest, _ name: String, window: Int? = nil) {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let out = app.shotsDirectory.appendingPathComponent("AIBasicRealUI-\(name).png").path
        capture.arguments = window.map { ["-x", "-l", String($0), out] } ?? ["-x", out]
        try? capture.run(); capture.waitUntilExit()
    }
    private static func settingsWindow(_ app: AppUnderTest) throws -> Int? {
        try app.native().appWindows.first(where: { $0.className == "NSWindow" && $0.isVisible })?.number
    }

    private static func wanted(_ part: String) -> Bool {
        guard let parts = ProcessInfo.processInfo.environment["BRK_E2E_REAL_BASIC_PART"], !parts.isEmpty else { return true }
        return parts.split(separator: ",").contains { $0 == part }
    }

    // MARK: The route

    private static func route(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting events is not allowed for this runner") }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        pid = hello.pid
        Self.app = app
        let name = choice.rawValue, kind = choice.kind!
        let log = Log(app.shotsDirectory.appendingPathComponent("real-basic-\(name).txt"))
        defer { try? NativeSystemInput.setShift(false); PhysicalKeys.clearSystemModifiers(KeyChord([.command, .shift, .option, .control], .a)) }
        let small = AIAgentOptions.basicDefault(kind)?.model ?? "?"

        var ready = false
        log.check("Max pane: Turn On Max, \(kind.displayName), the basic model is \(small)") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .comma)
            try click(title: "Max", "the Max tab")
            app.sleep(1)
            try click(identifier: ViewID.settingsField("enableMax").identifier, "Turn On Max")
            try app.waitUntil("Max on") { try settings(app).max.settings.isOn }
            try choose(popUp: ViewID.settingsField("agentChoice").identifier, typing: kind.displayName, "the agent pop-up")
            try app.waitUntil("\(kind.displayName) chosen") { try settings(app).max.settings.provider == choice }
            var status: AIAgentStatus?
            try app.waitUntil("the agent's status", timeout: 40) {
                status = try settings(app).max.agents.first { $0.kind == kind }
                return status != nil && status?.state != .checking
            }
            ready = status?.state == .ready
            let max = try settings(app).max
            try expect(AIFeature.basicLayer.allSatisfy(max.settings.enabled), "Turn On Max left the Brk features off: \(max.settings.features ?? [:])")
            try expect(max.basicRoute == .cli(kind, model: small, effort: AIAgentOptions.basicDefault(kind)?.effort), "basic route \(max.basicRoute)")
            app.sleep(0.6)
            if let number = try settingsWindow(app) { capture(app, "max-pane-top", window: number) }
            // The Brk cards below Arc's six rows: scroll the pane with the wheel, as a person does.
            if let window = try app.native().appWindows.first(where: { $0.className == "NSWindow" && $0.isVisible }),
               let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.number)) as? [[String: Any]])?.first,
               let bounds = info[kCGWindowBounds as String] as? [String: Double] {
                // Window-server bounds are top-left, as mouse events are.
                let center = CGPoint(x: (bounds["X"] ?? 0) + (bounds["Width"] ?? 0) / 2, y: (bounds["Y"] ?? 0) + (bounds["Height"] ?? 0) / 2)
                try mouse(center, [.mouseMoved])
                for _ in 0..<12 {
                    let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .line, wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0)
                    event?.location = center; event?.post(tap: .cghidEventTap); usleep(40_000)
                }
                app.sleep(0.6)
                capture(app, "max-pane-accounts", window: window.number)
            }
            try key(.command, .w)
            return "state \(String(describing: status?.state)), basic route \(MaxRouteText.text(max.basicRoute)), decisions \(max.decisionRoute)"
        }
        guard ready else { log.write("failures: \(log.failures)"); try expect(false, "\(kind.displayName) is not ready; see real-basic-\(name).txt"); return }

        let site = app.site
        let localhost = { (path: String) in URL(string: site.url(path).absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost"))! }
        var kyoto: TabRow?, swift: TabRow?

        if wanted("names") { log.check("Name Tabs: three new tabs get short names") {
            let soup = try open(app, site.url("basic-soup.html"))
            kyoto = try open(app, site.url("basic-kyoto.html"))
            swift = try open(app, site.url("basic-swift.html"))
            let long = [soup.id: "Grandma's Chicken", kyoto!.id: "Kyoto Travel Guide 2026", swift!.id: "Swift Concurrency Explained"]
            try app.waitUntil("the three tabs named", timeout: 120) {
                let rows = try tabs(app)
                return long.allSatisfy { id, prefix in rows.first { $0.id == id }.map { !$0.title.hasPrefix(prefix) && !$0.title.isEmpty } ?? false }
            }
            shot(app, "names")
            return try tabs(app).filter { long[$0.id] != nil }.map { "\"\($0.title)\"" }.joined(separator: ", ")
        } }

        if wanted("names"), let swift { log.check("A title the user types is never touched") {
            let row = try frame(app, .row(swift.id))
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try mouse(try screen(app, row), [.mouseMoved, .leftMouseDown, .leftMouseUp], clicks: 1)
            try mouse(try screen(app, row), [.leftMouseDown, .leftMouseUp], clicks: 2)
            app.sleep(0.6)
            try key(.command, .a)
            try type("My Swift notes")
            try key([], .returnKey)
            try app.waitUntil("the typed title") { try tabs(app).first { $0.id == swift.id }?.title == "My Swift notes" }
            // Its page moves on; Name Tabs would ask again for a new site, but this title is the user's.
            try key(.command, .l)
            try type(localhost("basic-rust.html").absoluteString)
            try key([], .returnKey)
            app.sleep(12)
            let title = try tabs(app).first { $0.id == swift.id }?.title
            try expect(title == "My Swift notes", "the user's title became \(title ?? "nil")")
            return "kept \"My Swift notes\" after the tab went to another site"
        } }

        if wanted("names"), let kyoto { log.check("A tab that moves to another site is named again") {
            let before = try tabs(app).first { $0.id == kyoto.id }?.title ?? ""
            let row = try frame(app, .row(kyoto.id))
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try click(try screen(app, row))
            try key(.command, .l)
            try type(localhost("basic-lisbon.html").absoluteString)
            try key([], .returnKey)
            try app.waitUntil("a new name for the new site", timeout: 120) {
                guard let row = try tabs(app).first(where: { $0.id == kyoto.id }), row.url?.host == "localhost" else { return false }
                return row.title != before && !row.title.hasPrefix("48 Hours in Lisbon") && !row.title.isEmpty
            }
            let after = try tabs(app).first { $0.id == kyoto.id }?.title ?? ""
            shot(app, "renamed-after-move")
            return "\"\(before)\" → \"\(after)\""
        } }

        var group: FolderRow?
        if wanted("tidy") { log.check("Tidy groups Today and names each group") {
            for path in ["basic-bread.html", "basic-salad.html", "basic-rust.html", "basic-cleanup.html"] where try app.view().space.today.rows.count < 7 { try open(app, site.url(path)) }
            try app.waitUntil("Tidy offered") { try app.view().space.today.canTidy }
            try hover(app, .todayTidy)
            try click(app, .todayTidy)
            try app.waitUntil("Today in groups", timeout: 150) { try !folders(app).isEmpty || (toast(app).map { !$0.hasPrefix("Tidied") } ?? false) }
            let names = try folders(app).map(\.title)
            shot(app, "tidy")
            try expect(!names.isEmpty && toast(app)?.hasPrefix("Tidied Tabs!") == true, "after Tidy: \(toast(app) ?? "no notice"), groups \(names)")
            group = try folders(app).max { $0.children.count < $1.children.count }
            return "groups \(names)"
        } }

        if wanted("tidy"), let target = group { log.check("Name with AI on a group's right-click menu") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try rightClick(try screen(app, try frame(app, .row(target.id))))
            try chooseInMenu("Name with")
            try app.waitUntil("the group named", timeout: 120) { toast(app)?.hasPrefix("Named “") == true || toast(app)?.hasPrefix(AIFeature.folderNames.title) == true }
            let notice = toast(app) ?? ""
            let title = try folders(app).first { $0.id == target.id }?.title ?? ""
            shot(app, "name-with-ai")
            try expect(notice.hasPrefix("Named “"), "the notice is \(notice)")
            return "\"\(target.title)\" → \"\(title)\" (\(notice))"
        } }

        if wanted("place") { log.check("Place New Tabs: a new recipe tab gets a one-click suggestion, and the click moves it") {
            guard try !folders(app).isEmpty else { throw Check(description: "no groups to place into (run with tidy)") }
            let pie = try open(app, site.url("basic-pie.html"))
            var suggestion: String?
            try app.waitUntil("a suggestion or a move", timeout: 120) {
                suggestion = try tabs(app).first { $0.id == pie.id }?.aiSuggestion
                return suggestion != nil || toast(app)?.hasPrefix("Moved to") == true
            }
            shot(app, "placement-suggestion")
            if toast(app)?.hasPrefix("Moved to") == true { return "moved at once: \(toast(app)!)" }
            try click(app, .tabTool("ai-suggestion-" + pie.id.rawValue))
            try app.waitUntil("the tab in its group") { try folders(app).contains { $0.children.contains { $0.id == pie.id } } }
            let into = try folders(app).first { $0.children.contains { $0.id == pie.id } }?.title ?? "?"
            shot(app, "placement-moved")
            return "suggested \"\(suggestion ?? "")\", clicked, now in \"\(into)\""
        } }

        if wanted("cleanup") { log.check("Suggest Tabs to Close: a duplicate is listed beside Tidy and closed from the list") {
            guard let some = try tabs(app).first(where: { $0.url?.lastPathComponent == "basic-soup.html" }) else { throw Check(description: "no soup tab") }
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try rightClick(try screen(app, try frame(app, .row(some.id))))
            try chooseInMenu("Dup")
            try app.waitUntil("the duplicate") { try tabs(app).filter { $0.url?.lastPathComponent == "basic-soup.html" }.count == 2 }
            try app.waitUntil("the cleanup count") { try app.view().space.today.cleanup > 0 }
            try hover(app, .tabTool("today-cleanup"))
            shot(app, "cleanup-button")
            let count = try app.view().space.today.cleanup
            try click(app, .tabTool("today-cleanup"))
            app.sleep(0.8)
            capture(app, "cleanup-menu")
            try chooseInMenu("Close")
            try app.waitUntil("one copy left") { try tabs(app).filter { $0.url?.lastPathComponent == "basic-soup.html" }.count == 1 }
            return "\(count) listed; Close took the duplicate"
        } }

        if wanted("translate") { log.check("The bar's translate prefix answers in its row") {
            try bar(app, "translate")
            try key([], .tab)
            try type("good morning, friends to French")
            var answer: String?
            func barTranslation() throws -> BarTranslation? { if case .commandBar(let bar)? = try app.view().overlay { bar.translation } else { nil } }
            try app.waitUntil("the translation", timeout: 90) {
                answer = try barTranslation()?.answer
                return try answer != nil || barTranslation()?.failure != nil
            }
            shot(app, "bar-translation")
            let failure = try barTranslation()?.failure
            try key([], .escape)
            try expect(answer != nil, "failed: \(failure ?? "")")
            return "\"\(answer!)\""
        } }

        if wanted("preview") { log.check("5-Second Previews: Shift held over a link") {
            _ = try open(app, site.url("basic-bread.html#preview"))
            let card = try frame(app, .card(0))
            // The first link on the page ("Soup"), in the line under the paragraph.
            try PhysicalPointer.move(app, to: CGPoint(x: card.minX + 58, y: card.minY + 148), window: app.window!)
            try NativeSystemInput.setShift(true)
            defer { try? NativeSystemInput.setShift(false) }
            try app.waitUntil("the preview card's summary", timeout: 90) { let p = try app.view().aiPreview; return p?.busy == false && (p?.details.isEmpty == false || p?.failure != nil) }
            let preview = try XCTUnwrapValue(try app.view().aiPreview)
            shot(app, "preview")
            try expect(preview.failure == nil, "the card says \(preview.failure ?? "")")
            return "\(preview.title): \(preview.details.map { $0.label + " " + $0.info })"
        } }

        log.check("This month's usage, per feature, on the subscription") {
            let usage = try settings(app).max.settings.usage
            let rows = (usage?.rows ?? [:]).sorted { $0.key < $1.key }
            try expect(!rows.isEmpty, "no usage recorded")
            try expect(rows.allSatisfy { $0.key.way == .subscription && $0.value.cost == nil }, "a subscription row with a cost: \(rows)")
            return rows.map { "\($0.key.feature): \($0.value.requests) req, \($0.value.inputTokens) in, \($0.value.outputTokens) out" }.joined(separator: "; ")
        }

        log.write("failures: \(log.failures)")
        try expect(log.failures == 0, "see real-basic-\(name).txt")
    }
}

/// The pane's route line, for the log.
enum MaxRouteText {
    static func text(_ route: AIBasicRoute) -> String {
        switch route {
        case .cli(let kind, let model, let effort): "\(kind.displayName) CLI, \(model ?? "default")\(effort.map { ", effort " + $0 } ?? "")"
        case .api(let service, let model, _): "\(service.displayName) API, \(model)"
        case .unavailable(let reason): "unavailable: \(reason)"
        }
    }
}
