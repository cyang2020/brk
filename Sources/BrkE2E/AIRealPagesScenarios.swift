import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Conversations as tabs and pages in answers, the way a person uses them, on a real agent (docs/design/ai-native.md, 对话是
/// tab, 在回答里显示页面; the user's own examples): three shop tabs given to the panel with Ask AI and "这几个 tab 哪个最便宜,
/// 画个对比图", whose answer must show a chart page; Keep as Tab on that page; a real ⌘Q and a relaunch, after which the
/// conversation's row and the page's row are back and show what they showed; the next message in the conversation's tab,
/// which continues the agent's own session; and in a new conversation "我上次问的那个比价结果是什么", which must find the old one
/// with Brk's conversation tools. Real clicks and keys through the window server (Chinese by paste); the control socket
/// only reads state and takes screenshots. Opt-in: BRK_E2E_REAL_PAGES_AGENT=claude|codex, BRK_E2E_REAL_PAGES_MODEL for the
/// text typed into the model pop-up (spend little: Haiku, GPT-6-Luna), BRK_E2E_REAL_PAGES_PART=chart,keep,relaunch,continue,recall
/// to pick steps (each needs the ones before it). Results: real-pages-<agent>.txt in the shots folder.
enum AIRealPagesScenarios {
    static var all: [Scenario] {
        guard let name = ProcessInfo.processInfo.environment["BRK_E2E_REAL_PAGES_AGENT"], let choice = AIProviderChoice(rawValue: name), choice.kind != nil else { return [] }
        return [Scenario("AIRealPages-\(name)", "real \(name), real input: a chart page in the answer, Keep as Tab, quit and relaunch, continue, recall an old conversation",
                         cefOnly: "real agent, real input") { try route($0, choice) }]
    }

    private final class Log {
        let url: URL
        var failures = 0
        init(_ url: URL) { self.url = url; try? Data().write(to: url) }
        func write(_ line: String) {
            print("[real-pages] " + line)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        }
        func check(_ name: String, _ body: () throws -> String) {
            let start = Date()
            do { let result = try body(); write("PASS \(name) (\(String(format: "%.1f", Date().timeIntervalSince(start))) s): \(result)") }
            catch { failures += 1; write("FAIL \(name) (\(String(format: "%.1f", Date().timeIntervalSince(start))) s): \(error)") }
        }
    }

    nonisolated(unsafe) private static var pid: Int32 = 0
    nonisolated(unsafe) private static weak var app: AppUnderTest?

    // MARK: Real input (as AIRealTabsScenarios does it)

    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ".": (47, false), "-": (27, false), "/": (44, false), ":": (41, true), "?": (44, true), "_": (27, true)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) {
            map[letter] = (code, false); map[Character(letter.uppercased())] = (code, true)
        }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()
    private static func brkActive() throws {
        guard case .native(let facts) = try? app?.send(.native(window: nil)), facts.appActive == true else { throw Check(description: "Brk is not the active app; no key posted") }
    }
    private static func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: down) else { return }
        event.flags = flags; event.post(tap: .cghidEventTap); usleep(14_000)
    }
    private static func type(_ text: String) throws {
        try brkActive()
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
    private static func paste(_ text: String) throws {
        let saved = shell("/usr/bin/pbpaste", input: nil)
        _ = shell("/usr/bin/pbcopy", input: text)
        defer { _ = shell("/usr/bin/pbcopy", input: saved) }
        try key(.command, .v)
        usleep(300_000)
    }
    private static func shell(_ path: String, input: String?) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.environment = ["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        let output = Pipe(), feed = Pipe()
        process.standardOutput = output; process.standardInput = feed
        guard (try? process.run()) != nil else { return "" }
        if let input { feed.fileHandleForWriting.write(Data(input.utf8)) }
        try? feed.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + point.x, y: top + point.y)
    }
    private static func mouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, flags: CGEventFlags = []) throws {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: button) else { throw Check(description: "mouse event") }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
    private static func click(_ app: AppUnderTest, at point: CGPoint, right: Bool = false, flags: CGEventFlags = []) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let target = try screen(app, point)
        guard let front = PhysicalPointer.frontmost(at: target), front.pid == pid else { throw Check(description: "another window is in front at \(target); nothing posted") }
        try clickScreen(target, right: right, flags: flags)
    }
    private static func clickScreen(_ target: CGPoint, right: Bool = false, flags: CGEventFlags = []) throws {
        try mouse(.mouseMoved, at: target); usleep(150_000)
        try mouse(right ? .rightMouseDown : .leftMouseDown, at: target, button: right ? .right : .left, flags: flags); usleep(70_000)
        try mouse(right ? .rightMouseUp : .leftMouseUp, at: target, button: right ? .right : .left, flags: flags); usleep(400_000)
    }
    private static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
    private static func frame(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect { try visible(app.native(), id).frame }
    private static func clickControl(_ app: AppUnderTest, _ name: String) throws { try click(app, at: centre(frame(app, .aiControl(name)))) }
    private static func chooseMenu(_ title: String) throws {
        var found: CGRect?
        try app!.waitUntil("“\(title)” in the menu", timeout: 6) { found = NativeSystemInput.frame(pid: pid, title: title, roles: ["AXMenuItem"]); return found != nil }
        try clickScreen(centre(found!))
    }
    /// Scrolls the panel's or tab's transcript with the wheel, as a person would, until the view is in its visible part.
    private static func reveal(_ app: AppUnderTest, _ id: ViewID, in container: ViewID) throws {
        for _ in 0..<20 {
            let facts = try app.native()
            guard let target = facts.actual[id.identifier]?.frame, let box = facts.actual[container.identifier]?.frame else { throw Check(description: "no \(id.identifier)") }
            if target.minY >= box.minY + 8, target.maxY <= box.maxY - 8 { return }
            let point = try screen(app, CGPoint(x: box.midX, y: box.midY))
            try mouse(.mouseMoved, at: point); usleep(100_000)
            guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: target.minY < box.minY ? 60 : -60, wheel2: 0, wheel3: 0) else { return }
            wheel.location = point
            wheel.post(tap: .cghidEventTap)
            usleep(250_000)
        }
        throw Check(description: "\(id.identifier) stayed out of sight")
    }
    private static func clickAX(identifier: String, _ what: String) throws {
        var found: CGRect?
        try app!.waitUntil("\(what) on screen", timeout: 8) { found = NativeSystemInput.frame(pid: pid, identifier: identifier); return found != nil }
        try clickScreen(centre(found!))
    }
    private static func choosePopUp(_ identifier: String, _ text: String) throws {
        try clickAX(identifier: identifier, "the pop-up")
        app!.sleep(0.5)
        try type(text)
        app!.sleep(0.3)
        try key([], .returnKey)
        app!.sleep(0.8)
    }

    private static func shot(_ app: AppUnderTest, _ name: String) { _ = try? app.screenshot("AIRealPages-\(name)") }
    private static func short(_ text: String?) -> String { String((text ?? "nil").replacingOccurrences(of: "\n", with: " ⏎ ").prefix(400)) }
    private static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "no settings") }
        return settings
    }
    private static func tabRows(_ rows: [Row]) -> [TabRow] {
        rows.flatMap { row -> [TabRow] in
            switch row {
            case .tab(let t): [t]
            case .split(let s): s.panes
            case .folder(let f): tabRows(f.children)
            }
        }
    }
    private static func todayRow(_ app: AppUnderTest, _ matches: (TabRow) -> Bool) throws -> TabRow {
        try XCTUnwrapValue(tabRows(try app.view().space.today.rows).first(where: matches))
    }
    private static func open(_ app: AppUnderTest, _ path: String) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try key(.command, .t)
        try app.waitUntil("the command bar") { if case .commandBar? = try app.view().overlay { true } else { false } }
        try type(app.site.url(path).absoluteString)
        app.sleep(0.6)
        try key([], .returnKey)
        try app.waitUntil("\(path) shown", timeout: 15) { try tabRows(app.view().space.today.rows).contains { $0.status == .current && $0.url?.absoluteString.hasSuffix(path) == true } }
        app.sleep(1)
    }

    // MARK: The live conversation, in the panel or its tab

    private enum Place { case panel, tab }
    private static func answer(_ app: AppUnderTest, _ place: Place) throws -> AIAnswerSnapshot? {
        place == .panel ? try app.view().ai : try app.view().conversations.first?.answer
    }
    private static func pending(_ ai: AIAnswerSnapshot?) -> AIAgentApproval? {
        ai?.conversation?.items.lazy.compactMap { if case .approval(let a) = $0, a.answer == nil { a } else { nil } }.first
    }
    private static func steps(_ ai: AIAnswerSnapshot?) -> [String] {
        ai?.conversation?.items.compactMap { if case .step(let s) = $0 { s.title + (s.state == .done ? " ✓" : s.state == .failed ? " ✗" : " …") } else { nil } } ?? []
    }
    private static func notices(_ ai: AIAnswerSnapshot?) -> [String] {
        ai?.conversation?.items.compactMap { if case .notice(let text) = $0 { text } else { nil } } ?? []
    }
    private static func pages(_ ai: AIAnswerSnapshot?) -> [AIPageRef] {
        ai?.conversation?.items.compactMap { if case .page(let page) = $0 { page } else { nil } } ?? []
    }
    /// What the agent said in its latest turn: the rows after the last message of the user.
    private static func lastReply(_ ai: AIAnswerSnapshot?) -> String {
        let items = ai?.conversation?.items ?? []
        let start = items.lastIndex { if case .user = $0 { true } else { false } }.map { $0 + 1 } ?? 0
        return items[start...].compactMap { if case .assistant(let text) = $0 { text } else { nil } }.joined(separator: "\n")
    }
    /// Answers each approval the turn asks for with Deny (this run never lets an agent's own tool run), until it ends.
    private static func run(_ app: AppUnderTest, _ log: Log, _ place: Place, _ label: String, timeout: Double = 300) throws -> AIAnswerSnapshot {
        var asked = 0
        while true {
            try app.waitUntil("an approval or the end of the turn", timeout: timeout) {
                let ai = try answer(app, place)
                return ai?.busy == false || pending(ai) != nil
            }
            let ai = try XCTUnwrapValue(try answer(app, place))
            guard let approval = pending(ai) else { return ai }
            asked += 1
            log.write("  approval \(asked): \(short(approval.title)) | \(short(approval.detail)) -> deny")
            shot(app, "\(label)-approval-\(asked)")
            try clickControl(app, "approval-deny")
            try app.waitUntil("the approval answered") { pending(try answer(app, place))?.id != approval.id }
        }
    }
    private static func send(_ app: AppUnderTest, _ place: Place, _ text: String) throws {
        try clickControl(app, "input")
        try paste(text)
        try key([], .returnKey)
        try app.waitUntil("the turn started", timeout: 15) { try answer(app, place)?.busy == true }
    }
    private static func chinese(_ text: String) -> Bool {
        let letters = text.replacingOccurrences(of: #"\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression).unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let han = letters.filter { (0x4E00...0x9FFF).contains($0.value) }
        return han.count >= 6 && han.count * 3 >= letters.count
    }
    private static func namesToaster(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("toaster") || lower.contains("24.5") || lower.contains("24,5") || text.contains("烤面包")
    }
    private static func wanted(_ part: String) -> Bool {
        guard let parts = ProcessInfo.processInfo.environment["BRK_E2E_REAL_PAGES_PART"], !parts.isEmpty else { return true }
        return parts.split(separator: ",").contains { $0 == part }
    }
    /// The page view on screen, from the view tree.
    private static func pageOnScreen(_ app: AppUnderTest, _ page: AIPageID) throws -> CGRect {
        guard let fact = try app.native().actual[ViewID.aiControl("page-" + page.rawValue).identifier] else { throw Check(description: "no view for page \(page.rawValue)") }
        try expect(!fact.hidden && fact.frame.height >= Double(AIPageLimits.minHeight) - 1 && fact.frame.width > 100, "the page view: \(fact)")
        return fact.frame
    }
    private static func savedConversation(_ app: AppUnderTest, _ id: AIRequestID) -> [String: Any]? {
        let file = app.dataDirectory.appendingPathComponent("Conversations/\(id.rawValue).json")
        return (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    // MARK: The route

    private static func route(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting events is not allowed for this runner") }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        pid = hello.pid
        Self.app = app
        let name = choice.rawValue, kind = choice.kind!
        let log = Log(app.shotsDirectory.appendingPathComponent("real-pages-\(name).txt"))
        defer { try? NativeSystemInput.setShift(false); PhysicalKeys.clearSystemModifiers(KeyChord([.command, .shift, .option, .control], .a)) }

        var ready = false
        log.check("Max pane: Turn On Max, \(kind.displayName), a small model") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .comma)
            var tab: CGRect?
            try app.waitUntil("the Max tab", timeout: 8) { tab = NativeSystemInput.frame(pid: pid, title: "Max"); return tab != nil }
            try clickScreen(centre(tab!))
            app.sleep(1)
            try clickAX(identifier: ViewID.settingsField("enableMax").identifier, "Turn On Max")
            try app.waitUntil("Max on") { try settings(app).max.settings.enabled(.commandBar) }
            // The basic layer would name the shop tabs with its own requests; this run spends only the conversation's.
            for feature in AIFeature.basicLayer { try app.dispatch(.settings(.max(.feature(feature, false)))) }
            for attempt in 1...2 {
                try choosePopUp(ViewID.settingsField("agentChoice").identifier, kind.displayName)
                do { try app.waitUntil("\(kind.displayName) chosen") { try settings(app).max.settings.provider == choice }; break }
                catch { if attempt == 2 { throw error }; try key([], .escape) }
            }
            var status: AIAgentStatus?
            try app.waitUntil("the agent's status", timeout: 40) {
                status = try settings(app).max.agents.first { $0.kind == kind }
                return status != nil && status?.state != .checking
            }
            ready = status?.state == .ready
            if ready, let model = ProcessInfo.processInfo.environment["BRK_E2E_REAL_PAGES_MODEL"], !model.isEmpty {
                try choosePopUp(ViewID.settingsField("agentModel").identifier, model)
                try app.waitUntil("the model chosen") { try settings(app).max.settings.agentOptions?[kind]?.model != nil }
            }
            try key(.command, .w)
            return "state \(String(describing: status?.state)), model \(try settings(app).max.settings.agentOptions?[kind]?.model ?? "default")"
        }
        guard ready else { log.write("failures: \(log.failures + 1) (\(kind.displayName) not ready)"); throw Check(description: "\(kind.displayName) is not ready") }

        log.check("three shop pages from the command bar") {
            for page in ["shop-kettle.html", "shop-toaster.html", "shop-blender.html"] { try open(app, page) }
            return "kettle, toaster, blender"
        }

        var conversation: AIRequestID?
        var page: AIPageID?
        if wanted("chart") { log.check("Ask AI on three tabs: “这几个 tab 哪个最便宜, 画个对比图” answers with a chart page") {
            let tabs = try ["kettle", "toaster", "blender"].map { shop in try todayRow(app) { $0.url?.absoluteString.hasSuffix("shop-\(shop).html") == true }.id }
            try click(app, at: centre(frame(app, .row(tabs[0]))))
            for tab in tabs.dropFirst() { try click(app, at: centre(frame(app, .row(tab))), flags: .maskCommand) }
            try click(app, at: centre(frame(app, .row(tabs[2]))), right: true)
            try chooseMenu("Ask AI")
            try app.waitUntil("the panel with three chips") { try app.view().ai?.conversation?.attached.count == 3 }
            try send(app, .panel, "这几个 tab 哪个最便宜, 画个对比图")
            conversation = try app.view().ai?.conversation?.id
            let ai = try run(app, log, .panel, "chart")
            shot(app, "chart-answer")
            let found = pages(ai)
            log.write("  steps: \(steps(ai))")
            log.write("  reply: \(short(lastReply(ai)))")
            try expect(steps(ai).contains { $0.hasPrefix("Read a tab") }, "no tab was read: \(steps(ai))")
            try expect(!found.isEmpty, "no page in the answer: \(steps(ai)); \(short(lastReply(ai)))")
            page = found.last?.id
            let rect = try pageOnScreen(app, found.last!.id)
            try expect(namesToaster(lastReply(ai)), "the toaster (€24.50) is the cheapest; the reply: \(short(lastReply(ai)))")
            let row = try todayRow(app) { $0.url == ConversationPage.url(conversation!) }
            return "steps \(steps(ai)); page “\(found.last!.title)” \(Int(rect.width))×\(Int(rect.height)) on screen; preview first: \(steps(ai).contains { $0.hasPrefix("Preview a page") }); row “\(row.title)”; model \(ai.conversation?.model ?? "?")"
        } }

        if wanted("keep"), let page { log.check("Keep as Tab under the page, clicked, opens the page as a tab") {
            try reveal(app, .aiControl("keep-" + page.rawValue), in: .aiControl("transcript"))
            shot(app, "keep-button")
            try clickControl(app, "keep-" + page.rawValue)
            try app.waitUntil("the page's tab shown", timeout: 8) { try app.view().aiPages.first?.content?.id == page }
            app.sleep(1.5)
            shot(app, "page-tab")
            let card = try XCTUnwrapValue(try app.native().actual[ViewID.aiControl("page-card").identifier])
            try expect(!card.hidden && card.frame.height > 200, "the page card: \(card)")
            let row = try todayRow(app) { $0.url == AIPageTab.url(page) }
            try expect(row.status == .current, "the page's row is not the shown one")
            return "row “\(row.title)”, card \(Int(card.frame.width))×\(Int(card.frame.height))"
        } }

        if wanted("relaunch"), let conversation, let page { log.check("⌘Q and a relaunch bring the conversation's tab and the page's tab back") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .q)
            let start = ProcessInfo.processInfo.systemUptime
            while kill(pid, 0) == 0, ProcessInfo.processInfo.systemUptime - start < 20 { usleep(200_000) }
            try expect(kill(pid, 0) != 0, "Brk did not quit on ⌘Q")
            let outcome = try app.quit()
            try expect(outcome.clean, "the quit: \(outcome.exit)")
            try expect(savedConversation(app, conversation) != nil, "no conversation file after the quit")
            try app.launch()
            guard case .hello(let again) = try app.send(.hello) else { throw Check(description: "no hello after the relaunch") }
            Self.pid = again.pid
            try app.waitUntil("the rows are back", timeout: 15) {
                let rows = tabRows(try app.view().space.today.rows)
                return rows.contains { $0.url == ConversationPage.url(conversation) } && rows.contains { $0.url == AIPageTab.url(page) }
            }
            let conversationRow = try todayRow(app) { $0.url == ConversationPage.url(conversation) }
            try click(app, at: centre(frame(app, .row(conversationRow.id))))
            try app.waitUntil("the conversation's tab shows it", timeout: 8) { try app.view().conversations.first?.answer.conversation?.id == conversation }
            app.sleep(2)
            let card = try XCTUnwrapValue(try app.view().conversations.first?.answer)
            try expect(pages(card).contains { $0.id == page }, "the page is not in the transcript after the relaunch")
            try expect(namesToaster(card.conversation?.items.compactMap { if case .assistant(let t) = $0 { t } else { nil } }.joined() ?? ""), "the answer is gone")
            let tab = try XCTUnwrapValue(try app.native().actual[ViewID.aiControl("conversation-tab").identifier])
            try expect(!tab.hidden, "the conversation's tab view is hidden")
            let inline = try pageOnScreen(app, page)
            shot(app, "relaunch-conversation-tab")
            let pageRow = try todayRow(app) { $0.url == AIPageTab.url(page) }
            try click(app, at: centre(frame(app, .row(pageRow.id))))
            try app.waitUntil("the page's tab shows it", timeout: 8) { try app.view().aiPages.first?.content?.id == page }
            app.sleep(1.5)
            shot(app, "relaunch-page-tab")
            return "rows “\(conversationRow.title)” and “\(pageRow.title)”; transcript with \(card.conversation?.items.count ?? 0) items, page inline \(Int(inline.width))×\(Int(inline.height))"
        } }

        if wanted("continue"), let conversation { log.check("the next message in the conversation's tab continues it") {
            let row = try todayRow(app) { $0.url == ConversationPage.url(conversation) }
            try click(app, at: centre(frame(app, .row(row.id))))
            try app.waitUntil("the conversation's tab") { try app.view().conversations.first?.answer.conversation?.id == conversation }
            app.sleep(1)
            try send(app, .tab, "第二便宜的是哪个? 一句话回答")
            let ai = try run(app, log, .tab, "continue")
            shot(app, "continue-answer")
            let reply = lastReply(ai)
            let lower = reply.lowercased()
            try expect(lower.contains("kettle") || reply.contains("39") || reply.contains("水壶"), "the kettle (€39.00) is second: \(short(reply))")
            let fresh = notices(ai).contains { $0.contains("could not continue") }
            let resume = savedConversation(app, conversation)?["resume"] as? String
            return "reply: \(short(reply)); continued the agent's own session: \(!fresh) (saved session id \(resume == nil ? "none" : "present")); steps \(steps(ai))"
        } }

        if wanted("recall"), let conversation { log.check("a new conversation, “我上次问的那个比价结果是什么”, finds the old one") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key([.option, .command], .g)
            try app.waitUntil("the question bar") { if case .commandBar? = try app.view().overlay { true } else { false } }
            try paste("我上次问的那个比价结果是什么")
            try key([], .returnKey)
            try app.waitUntil("a new conversation in the panel", timeout: 15) { try app.view().ai?.conversation?.id != nil && app.view().ai?.conversation?.id != conversation }
            let ai = try run(app, log, .panel, "recall")
            shot(app, "recall-answer")
            let reply = lastReply(ai)
            try expect(steps(ai).contains { $0.hasPrefix("Search conversations") || $0.hasPrefix("List conversations") || $0.hasPrefix("Read a conversation") },
                       "no conversation tool ran: \(steps(ai))")
            try expect(namesToaster(reply), "the old answer (the toaster) is not in the reply: \(short(reply))")
            try expect(chinese(reply), "asked in Chinese, answered otherwise: \(short(reply))")
            return "steps \(steps(ai)); links the old conversation: \(reply.contains("brk://conversation/\(conversation.rawValue)")); reply: \(short(reply))"
        } }

        log.write("failures: \(log.failures)")
        try expect(log.failures == 0, "\(log.failures) steps failed; see real-pages-\(name).txt")
    }
}
