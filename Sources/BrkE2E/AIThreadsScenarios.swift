import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Conversation lists on a real-launched Brk (docs/design/ai-threads.md, "验收"), against the fixture agent's real session
/// protocol. Swipes are phased scroll events posted to the window server, clicks and keys are the window server's;
/// the control socket sets up (settings, a question, a Space) and reads state and frames. Each scenario writes the
/// facts it checked to `<id>.txt` beside its pictures.
enum AIThreadsScenarios {
    static let all: [Scenario] = [
        Scenario("AIAgentThreads-Swipe", "a two-finger swipe over the panel goes to this Space's list and back; the list icon, a row and the dots do the same by click; the sidebar's Space swipe still switches Spaces",
                 cefOnly: "native panel, real scroll events", swipe),
        Scenario("AIAgentThreads-Spaces", "each Space has its own list; switching Space on the left switches the panel's list and brings back the conversation that Space showed; the list's composer starts one there",
                 cefOnly: "native panel", spaces),
        Scenario("AIAgentThreads-Waiting", "an approval in another Space: the strip at the list's top, the ring on its dot, the count on the list icon; the strip's click shows the approval there; Allow clears all three; a notification while Brk is not in front opens the conversation",
                 cefOnly: "native panel", waiting),
        Scenario("AIAgentThreads-Menu", "the row menu has rename, move to another Space and delete for good only (step 8: no archive, no Open in Tab); rename by typing; move to Other",
                 cefOnly: "native panel and menus", menu),
        Scenario("AIAgentThreads-Library", "the Library's AI conversations page: a word said only in a reply finds its conversation, the Space filter narrows the list, Continue opens it in its Space, Delete for Good asks and deletes",
                 cefOnly: "native Library", library),
        Scenario("AIAgentThreads-Bar", "the command bar finds a conversation by a word said in it, names its Space, and opens it",
                 cefOnly: "native command bar", bar),
        Scenario("AIAgentThreads-Names", "with Name Tabs on, the first answer names the conversation with the small model in a schema; the name shows in the header and the list; a name the user typed is kept",
                 cefOnly: "native panel", names),
        Scenario("AIAgentThreads-Models", "the + menu's Agent and Model opens the ready agents with their models, the current one checked; a pick goes to the next message",
                 cefOnly: "native panel", models),
        Scenario("AIAgentThreads-Look", "the list page, the strip, a ringed Space dot and the Library page, in a light Space and a dark Space; the approval card's Show Command in both",
                 cefOnly: "native panel", look),
    ]

    // MARK: Helpers

    final class Log {
        let url: URL
        var failures: [String] = []
        init(_ app: AppUnderTest) {
            url = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent(app.scenarioID + ".txt")
            try? Data().write(to: url)
        }
        func write(_ line: String) {
            print("[threads] " + line)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        }
        func check(_ name: String, _ body: () throws -> String) {
            do { write("PASS \(name): \(try body())") } catch { failures.append(name); write("FAIL \(name): \(error)") }
        }
        func finish() throws {
            if !failures.isEmpty { throw Check(description: "failed: " + failures.joined(separator: "; ")) }
        }
    }

    static func prepare(_ app: AppUnderTest, names: Bool = false) throws {
        // The basic layer would start small-model requests of its own; only Name Tabs where a scenario asks for it.
        for feature in AIFeature.allCases {
            let on = !AIFeature.basicLayer.contains(feature) || (names && feature == .tabNames)
            try app.dispatch(.settings(.max(.feature(feature, on))))
        }
        try app.dispatch(.settings(.max(.provider(.claude))))
        try app.dispatch(.settings(.advanced(.hapticsOnReorder(false))))
        try AIPanelLookScenarios.clearOfSystemDialogs(app)
    }

    static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + point.x, y: top + point.y)
    }
    /// A control's frame once two reads 0.2 s apart agree.
    static func still(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect {
        var last: CGRect?
        for _ in 0..<25 {
            let now = try visible(app.native(), id).frame
            if now == last { return now }
            last = now
            usleep(200_000)
        }
        return try XCTUnwrapValue(last)
    }
    static func click(_ app: AppUnderTest, _ id: ViewID) throws {
        let frame = try still(app, id)
        try PhysicalPointer.click(app, at: try screen(app, CGPoint(x: frame.midX, y: frame.midY)), window: app.window!)
        usleep(350_000)
    }
    static func shown(_ app: AppUnderTest, _ id: ViewID) throws -> Bool { isShown(try app.native(), id) }
    static func shot(_ app: AppUnderTest, _ name: String) { _ = try? app.screenshot(app.scenarioID + "-" + name) }
    static func panel(_ app: AppUnderTest) throws -> AIPanelSnapshot? { try app.view().aiPanel }
    static func rows(_ app: AppUnderTest) throws -> [AIThreadRow] { try panel(app)?.groups.flatMap(\.rows) ?? [] }

    private static func ask(_ app: AppUnderTest, _ text: String, answer: String? = nil) throws -> AIRequestID {
        try app.dispatch(.assist(.ask(text)))
        try app.waitUntil("the answer to \(text)", timeout: 20) {
            let ai = try app.view().ai
            return ai?.busy == false && ai?.text.contains(answer ?? text) == true
        }
        return try XCTUnwrapValue(try app.view().ai?.conversation?.id)
    }

    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ":": (41, true), "-": (27, false), ".": (47, false), "/": (44, false), "?": (44, true)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) { map[letter] = (code, false) }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()
    static func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: down) else { return }
        event.flags = flags; event.post(tap: .cghidEventTap); usleep(15_000)
    }
    /// Real key codes at the window server, into whatever has the keys: lower-case ASCII only.
    static func type(_ text: String, enter: Bool = false) throws {
        for character in text {
            guard let (code, shifted) = codes[character] else { throw Check(description: "no key for \(character)") }
            if shifted { post(56, true, .maskShift) }
            post(code, true, shifted ? .maskShift : []); post(code, false, shifted ? .maskShift : [])
            if shifted { post(56, false, []) }
        }
        if enter { post(36, true, []); post(36, false, []) }
        usleep(200_000)
    }
    static func key(_ modifiers: Modifiers, _ key: Key) throws {
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(250_000)
    }

    /// Two fingers over the panel, `points` to the right (positive: toward the list) or the left.
    private static func swipePanel(_ app: AppUnderTest, _ points: Double) throws {
        let frame = try visible(app.native(), .aiControl("panel")).frame
        let at = CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.45)
        let step = points / 10
        try PhysicalPointer.swipe(app, at: at, steps: Array(repeating: (step, 0.0), count: 10), window: app.window!)
        app.sleep(0.5)
    }

    // MARK: Swipe

    @Sendable static func swipe(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let home = try app.view().space.id
        let id = try ask(app, "hello there")
        log.check("the answer opens the conversation page, the list one page to its left") {
            try app.waitUntil("the panel with its list") { try panel(app)?.page == .conversation && panel(app)?.hasConversation == true }
            try expect(try shown(app, .aiControl("list")), "no list icon in the header")
            try expect(try shown(app, .aiControl("page-dot-list")) && shown(app, .aiControl("page-dot-conversation")), "no page dots")
            shot(app, "1-conversation")
            return "page \(try panel(app)!.page), dots and the list icon shown"
        }
        log.check("two fingers to the right over the panel: the list") {
            try swipePanel(app, 160)
            try app.waitUntil("the list page", timeout: 5) { try panel(app)?.page == .list }
            try app.waitUntil("the list on screen") { try shown(app, .aiControl("thread-list")) && !shown(app, .aiControl("transcript")) }
            try expect(try shown(app, .aiControl("thread-\(id.rawValue)")), "the conversation's row is not in the list")
            try expect(try app.view().space.id == home, "the sidebar switched Space")
            shot(app, "2-list-by-swipe")
            return "the list, with the conversation's row; the Space stayed"
        }
        log.check("two fingers to the left: the conversation again") {
            try swipePanel(app, -160)
            try app.waitUntil("the conversation page", timeout: 5) { try panel(app)?.page == .conversation }
            try app.waitUntil("the transcript on screen") { try shown(app, .aiControl("transcript")) }
            return "back on the conversation"
        }
        log.check("a short swipe that stops goes back where it was") {
            let frame = try visible(app.native(), .aiControl("panel")).frame
            try PhysicalPointer.swipe(app, at: CGPoint(x: frame.midX, y: frame.midY), steps: Array(repeating: (4.0, 0.0), count: 10), pause: 0.25, window: app.window!)
            app.sleep(0.6)
            try expect(try panel(app)?.page == .conversation, "a 40 pt swipe that stopped changed the page")
            return "stayed on the conversation"
        }
        log.check("the list icon, a row, and the dots by click") {
            try click(app, .aiControl("list"))
            try app.waitUntil("the list by the icon") { try panel(app)?.page == .list }
            try click(app, .aiControl("thread-\(id.rawValue)"))
            try app.waitUntil("the conversation by its row") { try panel(app)?.page == .conversation }
            try click(app, .aiControl("page-dot-list"))
            try app.waitUntil("the list by its dot") { try panel(app)?.page == .list }
            try click(app, .aiControl("list-back"))
            try app.waitUntil("the conversation by the list's back") { try panel(app)?.page == .conversation }
            return "icon → list, row → conversation, dot → list, back → conversation"
        }
        log.check("⌥⌘A closes the panel and opens it again on the page it showed (step 8: a toggle)") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key([.option, .command], .a)
            try app.waitUntil("the panel closed by ⌥⌘A") { try panel(app) == nil && app.view().ai == nil }
            try key([.option, .command], .a)
            try app.waitUntil("the conversation again by ⌥⌘A", timeout: 5) { try panel(app)?.page == .conversation && app.view().ai?.conversation?.id == id }
            try click(app, .aiControl("list"))
            try app.waitUntil("the list") { try panel(app)?.page == .list }
            try expect(try shown(app, .aiControl("thread-\(id.rawValue)")), "the conversation's row is not in the list")
            try click(app, .aiControl("thread-\(id.rawValue)"))
            try app.waitUntil("the conversation by its row") { try panel(app)?.page == .conversation }
            return "⌥⌘A → closed; ⌥⌘A → the conversation; list icon → list with the row; row → conversation"
        }
        log.check("the sidebar's own swipe still switches Spaces, with the panel open") {
            let second = try createSpace(app, title: "Second")
            try click(app, .dockSpace(home))
            try app.waitUntil("back home") { try app.view().space.id == home }
            app.sleep(0.4)
            let list = try XCTUnwrapValue(try app.native().computed.sidebar?.tablistViewport)
            try PhysicalPointer.swipe(app, at: CGPoint(x: list.midX, y: list.midY), steps: Array(repeating: (-15.0, 0.0), count: 10), window: app.window!)
            try app.waitUntil("the next Space by the sidebar's swipe", timeout: 5) { try app.view().space.id == second }
            return "the sidebar's swipe went to \(second.rawValue)"
        }
        try log.finish()
    }

    // MARK: One list per Space

    @Sendable static func spaces(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let home = try app.view().space.id
        let shopping = try ask(app, "kettle prices")
        var work = home
        var feishu = shopping
        log.check("a new Space shows its own empty list") {
            work = try createSpace(app, title: "Work")
            try app.waitUntil("Work's list") { try panel(app)?.page == .list && panel(app)?.space == work }
            let listed = try rows(app).map(\.title)
            try expect(listed.isEmpty, "Work lists \(listed)")
            try expect(try app.view().ai == nil, "the other Space's conversation is still in the panel")
            shot(app, "1-empty-list")
            return "empty list, no conversation"
        }
        log.check("the list's composer starts a conversation in this Space") {
            try click(app, .aiControl("list-input"))
            try type("weekly report", enter: true)
            try app.waitUntil("the new conversation's answer", timeout: 20) { try app.view().ai?.busy == false && app.view().ai?.text.contains("weekly report") == true }
            feishu = try XCTUnwrapValue(try app.view().ai?.conversation?.id)
            try expect(try panel(app)?.page == .conversation, "the composer's message did not open its conversation")
            try expect(try !app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.url == ConversationPage.url(feishu) } else { false } }, "a conversation row is in Work's Today")
            try click(app, .aiControl("list"))
            try app.waitUntil("Work's list has it") { try rows(app).first { $0.id == feishu }?.space == work }
            try click(app, .aiControl("thread-\(feishu.rawValue)"))
            try app.waitUntil("its conversation again") { try panel(app)?.page == .conversation }
            return "\(feishu.rawValue) in Work"
        }
        log.check("switching Space on the left brings back each Space's last conversation") {
            try click(app, .dockSpace(home))
            try app.waitUntil("home's conversation in the panel", timeout: 6) { try app.view().ai?.conversation?.id == shopping && panel(app)?.page == .conversation }
            let homeRows = try rows(app)
            try expect(homeRows.map(\.id) == [shopping], "home lists \(homeRows.map(\.title))")
            shot(app, "2-home")
            try click(app, .aiControl("list"))
            try app.waitUntil("home's list") { try panel(app)?.page == .list }
            try click(app, .dockSpace(work))
            try app.waitUntil("Work's conversation", timeout: 6) { try app.view().ai?.conversation?.id == feishu && panel(app)?.page == .conversation }
            shot(app, "3-work")
            try click(app, .dockSpace(home))
            try app.waitUntil("home again, on the list page it was left on", timeout: 6) { try panel(app)?.page == .list && app.view().ai?.conversation?.id == shopping }
            shot(app, "4-home-list")
            return "home ↔ Work, each with its own conversation and page"
        }
        try log.finish()
    }

    // MARK: Waiting elsewhere

    static func pending(_ app: AppUnderTest) throws -> AIAgentApproval? {
        try app.view().ai?.conversation?.items.lazy.compactMap { item -> AIAgentApproval? in if case .approval(let a) = item, a.answer == nil { a } else { nil } }.first
    }

    @Sendable static func waiting(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let home = try app.view().space.id
        _ = try ask(app, "hello home")
        let work = try createSpace(app, title: "Work")
        try app.dispatch(.assist(.ask("fixture:tool")))
        try app.waitUntil("the approval in Work", timeout: 15) { try pending(app) != nil }
        let id = try XCTUnwrapValue(try app.view().ai?.conversation?.id)
        log.check("from home: the strip, the ring and the count") {
            try click(app, .dockSpace(home))
            try app.waitUntil("home's panel") { try app.view().space.id == home }
            try click(app, .aiControl("list"))
            try app.waitUntil("the strip", timeout: 5) { try shown(app, .aiControl("strip-\(id.rawValue)")) }
            let strip = try XCTUnwrapValue(try panel(app)?.strips.first)
            try expect(strip.id == id && strip.state == .waiting && strip.spaceTitle == "Work", "strip \(strip)")
            try expect(try app.view().dock.first { $0.id == work }?.attention == true, "Work's dot has no ring")
            try expect(try app.view().dock.first { $0.id == home }?.attention == false, "home's dot rings")
            let count = try panel(app)?.waiting
            try expect(count == 1, "count \(String(describing: count))")
            shot(app, "1-strip")
            return "strip “\(strip.spaceTitle) · \(strip.title)” \(strip.pill ?? ""), Work's dot ringed, count 1"
        }
        log.check("the list icon shows the count on the conversation page") {
            try click(app, .aiControl("list-back"))
            try app.waitUntil("home's conversation") { try panel(app)?.page == .conversation }
            try expect(try shown(app, .aiControl("list-badge")), "no count on the list icon")
            shot(app, "2-badge")
            try click(app, .aiControl("list"))
            return "badge shown"
        }
        log.check("the strip's click goes to Work and shows the approval") {
            try click(app, .aiControl("strip-\(id.rawValue)"))
            try app.waitUntil("Work with the approval", timeout: 6) { try app.view().space.id == work && app.view().ai?.conversation?.id == id }
            try app.waitUntil("the approval card") { try shown(app, .aiControl("approval-allowOnce")) }
            shot(app, "3-approval")
            return "Work, approval card shown"
        }
        log.check("Allow ends the wait; home has no strip, no ring, no count") {
            try click(app, .aiControl("approval-allowOnce"))
            try app.waitUntil("the turn finished", timeout: 15) { try app.view().ai?.busy == false }
            try click(app, .dockSpace(home))
            try app.waitUntil("home") { try app.view().space.id == home }
            try app.waitUntil("nothing waits", timeout: 5) {
                let v = try app.view()
                return v.aiPanel?.strips.isEmpty == true && v.aiPanel?.waiting == 0 && v.dock.first { $0.id == work }?.attention == false
            }
            try expect(!(try shown(app, .aiControl("list-badge"))), "the count is still shown")
            shot(app, "4-cleared")
            return "strip, ring and count gone"
        }
        log.check("Brk in the back: an approval posts a notification; its click opens the conversation") {
            try click(app, .dockSpace(work))
            try app.waitUntil("Work") { try app.view().space.id == work }
            // Another app in front, as when the user is elsewhere.
            let finder = Process()
            finder.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            finder.arguments = ["-a", "Finder"]
            try finder.run(); finder.waitUntilExit()
            app.sleep(1.0)
            try app.dispatch(.assist(.followUp("fixture:tool")))
            var lines: [String] = []
            try app.waitUntil("a notification", timeout: 15) {
                guard case .menuItems(let items) = try app.send(.aiNotifications) else { return false }
                lines = items
                return items.contains { $0.hasPrefix("approval\t" + id.rawValue) }
            }
            try click(app, .dockSpace(home)) // brings Brk to the front again and leaves Work
            try app.waitUntil("home") { try app.view().space.id == home }
            try app.perform(.openAINotification(conversation: id))
            try app.waitUntil("the conversation shown by the notification", timeout: 6) { try app.view().space.id == work && app.view().ai?.conversation?.id == id }
            if try pending(app) != nil { try click(app, .aiControl("approval-deny")) }
            return "posted: " + lines.map { $0.replacingOccurrences(of: "\t", with: " | ") }.joined(separator: "; ")
        }
        try log.finish()
    }

    // MARK: The row menu: rename, move, delete

    @Sendable static func menu(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let home = try app.view().space.id
        let id = try ask(app, "move me")
        let other = try createSpace(app, title: "Other")
        try click(app, .dockSpace(home))
        try app.waitUntil("home") { try app.view().space.id == home }
        func menu(_ choose: String) throws -> [String] {
            let frame = try still(app, .aiControl("thread-\(id.rawValue)"))
            guard case .menuItems(let items) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: frame.midX, y: frame.midY), choose: choose)) else {
                throw Check(description: "no row menu")
            }
            app.sleep(0.5)
            return items
        }
        log.check("the row's menu") {
            try click(app, .aiControl("list"))
            try app.waitUntil("the list") { try panel(app)?.page == .list }
            let items = try menu("Rename")
            try expect(items == ["Rename", "Move to Another Space", "Delete for Good…"], "menu \(items)")
            try app.waitUntil("the rename field") { try shown(app, .aiControl("thread-rename")) }
            try key(.command, .a)
            try type("renamed", enter: true)
            try app.waitUntil("the new name") { try rows(app).first { $0.id == id }?.title == "renamed" }
            return items.joined(separator: " · ") + "; renamed by typing"
        }
        log.check("no row anywhere in the sidebar") {
            try expect(try !app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.url == ConversationPage.url(id) } else { false } }, "a conversation row is in Today")
            try expect(try !app.view().space.pinned.rows.contains { if case .tab(let t) = $0 { t.url == ConversationPage.url(id) } else { false } }, "a conversation row is in Pinned")
            shot(app, "1-list")
            return "Pinned and Today hold no conversation row"
        }
        log.check("Move to Another Space › Other") {
            try app.waitUntil("the list") { try panel(app)?.page == .list }
            _ = try menu("Move to Another Space › Other")
            try app.waitUntil("its row in Other", timeout: 5) { try rows(app).allSatisfy { $0.id != id } }
            try click(app, .dockSpace(other))
            try app.waitUntil("Other lists it", timeout: 6) { try app.view().space.id == other && rows(app).contains { $0.id == id } }
            return "moved to Other"
        }
        try log.finish()
    }

    // MARK: Library

    static func library(_ app: AppUnderTest) throws -> LibraryConversationsSnapshot? {
        if case .library(let l)? = try app.view().overlay { return l.conversations }
        return nil
    }

    @Sendable static func library(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let home = try app.view().space.id
        let first = try ask(app, "first question")
        try app.dispatch(.assist(.followUp("the zebrafish note")))
        try app.waitUntil("the follow-up's answer", timeout: 20) { try app.view().ai?.busy == false && app.view().ai?.conversation?.items.count ?? 0 >= 4 }
        let work = try createSpace(app, title: "Work")
        let second = try ask(app, "second question")
        log.check("the Library's AI conversations page, after Archived Tabs") {
            try click(app, .dockLibrary)
            try app.waitUntil("the Library") { if case .library? = try app.view().overlay { true } else { false } }
            let cells = try app.native()
            let archive = try XCTUnwrapValue(cells.actual[ViewID.libraryPage(.archive).identifier]?.frame)
            let mine = try XCTUnwrapValue(cells.actual[ViewID.libraryPage(.conversations).identifier]?.frame)
            try expect(mine.minY > archive.minY, "AI conversations is not after Archived Tabs")
            try click(app, .libraryPage(.conversations))
            try app.waitUntil("the page with both", timeout: 5) { Set(try library(app)?.rows.map(\.id) ?? []) == [first, second] }
            try app.waitUntil("the selected conversation in full") { try shown(app, .aiControl("library-preview")) }
            shot(app, "1-page")
            return "both Spaces' conversations; the first shows in full"
        }
        log.check("a word said only in a follow-up finds its conversation") {
            try click(app, .aiControl("library-search"))
            try type("zebrafish")
            try app.waitUntil("only the first", timeout: 5) { try library(app)?.rows.map(\.id) == [first] }
            try expect(try library(app)?.rows.first?.snippet?.contains("zebrafish") == true, "no snippet")
            shot(app, "2-search")
            // Emptied by selecting it all and deleting (Esc in the Library's search closes the Library once it is empty).
            try key(.command, .a)
            post(51, true, []); post(51, false, [])
            try app.waitUntil("both again", timeout: 5) { try library(app)?.rows.count == 2 }
            return "“zebrafish” → \(first.rawValue)"
        }
        log.check("Filter › Space › Work") {
            guard case .menuItems(let items) = try app.send(.captureClickMenu(view: .aiControl("library-filter"), choose: "Space › Work")) else { throw Check(description: "no Filter menu") }
            try app.waitUntil("only Work's", timeout: 5) { try library(app)?.rows.map(\.id) == [second] }
            shot(app, "3-filter")
            _ = try app.send(.captureClickMenu(view: .aiControl("library-filter"), choose: "Space › Work"))
            try app.waitUntil("both again", timeout: 5) { try library(app)?.rows.count == 2 }
            return "menu \(items.joined(separator: " · ")); Work → \(second.rawValue)"
        }
        log.check("Delete for Good… asks, then deletes") {
            try click(app, .aiControl("library-thread-\(second.rawValue)"))
            try app.waitUntil("second selected") { try library(app)?.selected?.id == second }
            try click(app, .aiControl("library-delete"))
            try app.waitUntil("the question") { try app.view().pendingConversationDeletion?.id == second }
            shot(app, "4-delete-question")
            try click(app, .spaceToolsControl("alert-confirm"))
            try app.waitUntil("deleted", timeout: 5) { try library(app)?.rows.map(\.id) == [first] }
            try expect(try app.view().pendingConversationDeletion == nil, "the question stayed")
            return "deleted, the Library still open"
        }
        log.check("Continue opens it in its Space's panel") {
            try click(app, .aiControl("library-thread-\(first.rawValue)"))
            try click(app, .aiControl("library-continue"))
            try app.waitUntil("home with the conversation", timeout: 6) {
                let v = try app.view()
                return v.overlay == nil && v.space.id == home && v.ai?.conversation?.id == first
            }
            _ = work
            return "Library closed, home, conversation in the panel"
        }
        try log.finish()
    }

    // MARK: Command bar

    @Sendable static func bar(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let id = try ask(app, "bar question")
        try app.dispatch(.assist(.followUp("the narwhal detail")))
        try app.waitUntil("the follow-up's answer", timeout: 20) { try app.view().ai?.busy == false && app.view().ai?.conversation?.items.count ?? 0 >= 4 }
        try app.dispatch(.assist(.dismiss))
        let pid: Int32 = try { guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }; return hello.pid }()
        log.check("the bar finds it by a word said in it, with its Space") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .t)
            try app.waitUntil("the command bar") { if case .commandBar? = try app.view().overlay { true } else { false } }
            try type("narwhal")
            let bar = try XCTUnwrapValue(try app.native().actual[ViewID.commandBar.identifier]?.frame)
            let onScreen = CGRect(origin: try screen(app, bar.origin), size: bar.size)
            var row: CGRect?, last: CGRect?
            try app.waitUntil("the conversation's row in the bar, still", timeout: 8) {
                row = NativeSystemInput.staticTexts(pid: pid).first { $0.text == "bar question" && onScreen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }?.frame
                defer { last = row }
                usleep(400_000)
                return row != nil && row == last
            }
            let space = try app.view().space.title
            // The row's second part: the Space's name, then what was said around the word ("— Space 1 · …the narwhal detail").
            let subtitle = NativeSystemInput.staticTexts(pid: pid).first { $0.text.contains(space + " · ") && $0.text.contains("narwhal") && onScreen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            try expect(subtitle != nil, "no “\(space) · …narwhal…” beside it")
            shot(app, "1-bar")
            try PhysicalPointer.click(app, at: CGPoint(x: row!.minX + 12, y: row!.midY), window: app.window!)
            try app.waitUntil("it in the panel", timeout: 8) { try app.view().ai?.conversation?.id == id && panel(app)?.page == .conversation }
            try expect(try !app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.url == ConversationPage.url(id) } else { false } }, "the bar opened a conversation row")
            return "row “bar question”, subtitle “\(subtitle!.text.prefix(60))”, opened in the panel"
        }
        try log.finish()
    }

    // MARK: Names

    @Sendable static func names(_ app: AppUnderTest) throws {
        try prepare(app, names: true)
        let log = Log(app)
        let id = try ask(app, "plan my weekend trip")
        log.check("the small model names it after the first answer") {
            try app.waitUntil("the name", timeout: 20) { try app.view().ai?.name == "Named plan my" }
            let calls = (try? String(contentsOf: app.dataDirectory.appendingPathComponent("ai-fixture.jsonl"), encoding: .utf8)) ?? ""
            try expect(calls.contains("conversation_name"), "no structured request with the conversation_name schema in the fixture's log")
            try click(app, .aiControl("list"))
            try app.waitUntil("the list") { try rows(app).first { $0.id == id }?.title == "Named plan my" }
            shot(app, "1-named")
            return "header and list read “Named plan my”"
        }
        log.check("a name typed by the user is kept") {
            try app.dispatch(.assist(.renameConversation(id, "my trip")))
            try click(app, .aiControl("thread-\(id.rawValue)"))
            try app.dispatch(.assist(.followUp("and sunday")))
            try app.waitUntil("the follow-up's answer", timeout: 20) { try app.view().ai?.busy == false && app.view().ai?.text.contains("sunday") == true }
            app.sleep(1.5)
            let name = try app.view().ai?.name
            try expect(name == "my trip", "renamed to \(String(describing: name))")
            return "still “my trip”"
        }
        try log.finish()
    }

    // MARK: Models

    @Sendable static func models(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        try app.dispatch(.settings(.openPane(.max)))
        try app.waitUntil("the agents answered", timeout: 25) {
            guard case .settings(let settings) = try app.send(.settings) else { return false }
            return settings.max.agents.filter { $0.state == .ready }.count >= 2
        }
        try app.dispatch(.settings(.closeWindow))
        _ = try ask(app, "which model")
        log.check("the + menu's Agent and Model opens the agents and their models") {
            try click(app, .aiControl("plus"))
            try app.waitUntil("the + menu") { try shown(app, .aiControl("agent")) }
            try click(app, .aiControl("agent"))
            try app.waitUntil("the agent list") { try shown(app, .aiControl("agent-pick-codex-fixture-sol")) }
            try expect(try shown(app, .aiControl("agent-header-claude")) && shown(app, .aiControl("agent-pick-claude-fixture-haiku")), "Claude's models missing")
            shot(app, "1-agents")
            return "Claude › Fixture Haiku, Codex › Fixture Sol, and the rest"
        }
        log.check("picking Codex · Fixture Sol sends the next message there") {
            try click(app, .aiControl("agent-pick-codex-fixture-sol"))
            try app.waitUntil("the pick") { try app.view().ai?.conversation?.pick == AIAgentPick(kind: .codex, model: "fixture-sol") }
            try click(app, .aiControl("input"))
            try type("now codex", enter: true)
            try app.waitUntil("Codex answers", timeout: 25) { try app.view().ai?.busy == false && app.view().ai?.conversation?.agent == .codex }
            let calls = (try? String(contentsOf: app.dataDirectory.appendingPathComponent("ai-fixture.jsonl"), encoding: .utf8)) ?? ""
            let codex = calls.split(whereSeparator: \.isNewline).last { $0.contains("now codex") }.map(String.init) ?? ""
            try expect(codex.contains("codex"), "the message did not reach Codex: \(codex.prefix(300))")
            try click(app, .aiControl("plus"))
            try app.waitUntil("the + menu") { try shown(app, .aiControl("agent")) }
            shot(app, "2-after")
            try click(app, .aiControl("plus"))
            return "answered by Codex; " + String(codex.prefix(160))
        }
        try log.finish()
    }

    // MARK: Look

    /// Chinese goes in as a person's input method leaves it: pasted. The pasteboard is put back after.
    static func paste(_ text: String) throws {
        func shell(_ path: String, _ input: String?) -> String {
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
        let saved = shell("/usr/bin/pbpaste", nil)
        _ = shell("/usr/bin/pbcopy", text)
        defer { _ = shell("/usr/bin/pbcopy", saved) }
        try key(.command, .v)
        usleep(300_000)
    }

    /// A folder session in the window's Space whose agent asks to run a command, the message in Chinese.
    private static func waitingInFolder(_ app: AppUnderTest) throws {
        try app.dispatch(.assist(.chooseFolder))
        try app.waitUntil("a folder session", timeout: 15) { try app.view().ai?.conversation?.folder != nil && app.view().ai?.conversation?.agent != nil }
        try click(app, .aiControl("input"))
        try paste("看看这个文件夹里有什么 fixture:command")
        post(36, true, []); post(36, false, [])
        try app.waitUntil("the approval card", timeout: 15) { try shown(app, .aiControl("approval-command")) }
        app.sleep(0.4)
    }

    @Sendable static func look(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = Log(app)
        let light = try app.view().space.id
        try app.dispatch(.space(.update(light, title: "购物", icon: nil, theme: nil)))
        let lightTheme = SpaceTheme(colors: [ThemePresets.pastel[7]], texture: .grain, intensity: 0.25, appearance: .light)
        try app.dispatch(.space(.update(light, title: nil, icon: nil, theme: lightTheme)))
        let folder = app.dataDirectory.appendingPathComponent("ai-work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try ask(app, "比较三款降噪耳机", answer: "比较三款降噪耳机")
        _ = try ask(app, "这家店能退货吗", answer: "这家店能退货吗")
        try waitingInFolder(app)
        try app.dispatch(.space(.create(title: "工作", icon: .none, theme: SpaceTheme(colors: [ThemePresets.drab[0]], texture: .grain, intensity: 0.25, appearance: .dark))))
        try app.waitUntil("the dark Space") { try app.view().space.title == "工作" }
        let dark = try app.view().space.id
        _ = try ask(app, "整理这周的周报", answer: "整理这周的周报")
        func set(_ name: String, here: SpaceID, other: SpaceID) throws -> String {
            try click(app, .dockSpace(here))
            try app.waitUntil("\(name)") { try app.view().space.id == here }
            app.sleep(0.6)
            if try panel(app)?.page != .list { try click(app, .aiControl("list")) }
            try app.waitUntil("the list") { try panel(app)?.page == .list }
            app.sleep(0.5)
            shot(app, "\(name)-list")
            let view = try app.view()
            let ring = view.dock.first { $0.id == other }?.attention == true
            let strips = view.aiPanel?.strips.map { "\($0.spaceTitle) · \($0.title) · \($0.pill ?? "")" } ?? []
            let words = [view.aiPanel?.spaceTitle, view.aiPanel?.groups.map(\.title).joined(separator: "/")].compactMap { $0 }
            try click(app, .dockLibrary)
            try app.waitUntil("the Library") { if case .library? = try app.view().overlay { true } else { false } }
            try click(app, .libraryPage(.conversations))
            try app.waitUntil("the conversations page") { try library(app) != nil && shown(app, .aiControl("library-preview")) }
            app.sleep(0.6)
            shot(app, "\(name)-library")
            try click(app, .libraryClose)
            try app.waitUntil("Library closed") { try app.view().overlay == nil }
            return "\(name): strips \(strips), groups \(words), the other Space's dot ringed: \(ring)"
        }
        log.check("the dark Space: the light Space's waiting conversation as a strip, its dot ringed") {
            try set("dark", here: dark, other: light)
        }
        log.check("the light Space's approval card, Show Command readable") {
            try click(app, .dockSpace(light))
            try app.waitUntil("light with the approval", timeout: 6) { try app.view().space.id == light && pending(app) != nil }
            if try panel(app)?.page == .list { try click(app, .aiControl("list-back")) }
            try app.waitUntil("the card") { try shown(app, .aiControl("approval-command")) }
            shot(app, "light-approval")
            try click(app, .aiControl("approval-command"))
            app.sleep(0.4)
            shot(app, "light-approval-open")
            return "light card shot, command shown"
        }
        log.check("the dark Space's approval card, then the light Space with the dark one waiting") {
            try click(app, .dockSpace(dark))
            try app.waitUntil("dark") { try app.view().space.id == dark }
            try waitingInFolder(app)
            shot(app, "dark-approval")
            try click(app, .aiControl("approval-command"))
            app.sleep(0.4)
            shot(app, "dark-approval-open")
            return try set("light", here: light, other: dark)
        }
        try log.finish()
    }
}

/// The conversation lists on a real agent (docs/design/ai-threads.md, "验收": 用真实的 Claude 在两个 Space 各开一个对话): a
/// question about a shop page in one Space, named by the small model; a question in a second Space whose agent asks to
/// run a command; from the first Space the strip, the ring and the count; the strip's click, Allow, and all three gone;
/// the Library's search. Real clicks and keys, Chinese pasted as an input method leaves it. Opt-in:
/// BRK_E2E_REAL_THREADS_AGENT=claude (BRK_E2E_REAL_THREADS_MODEL: a word of the model's name, default haiku). Results:
/// AIRealThreads-<agent>.txt beside the shots.
enum AIRealThreadsScenarios {
    static var all: [Scenario] {
        guard let name = ProcessInfo.processInfo.environment["BRK_E2E_REAL_THREADS_AGENT"], let choice = AIProviderChoice(rawValue: name), choice.kind != nil else { return [] }
        return [Scenario("AIRealThreads-\(name)", "real \(name): conversations in two Spaces, the cross-Space strip, ring and count, Allow from the strip, the AI name, the Library's search",
                         cefOnly: "real agent, real input") { try route($0, choice) }]
    }

    private static func send(_ app: AppUnderTest, _ text: String, input: ViewID) throws {
        try AIThreadsScenarios.click(app, input)
        try AIThreadsScenarios.paste(text)
        try NativeSystemInput.postSystemWide(KeyChord([], .returnKey))
        usleep(400_000)
    }

    private static func route(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        let log = AIThreadsScenarios.Log(app)
        let kind = choice.kind!
        try AIThreadsScenarios.prepare(app, names: true)
        try app.dispatch(.settings(.max(.provider(choice))))
        try app.dispatch(.settings(.openPane(.max)))
        var models: [AIAgentModel] = []
        try app.waitUntil("the agent reported", timeout: 60) {
            guard case .settings(let settings) = try app.send(.settings), let status = settings.max.agents.first(where: { $0.kind == kind }), status.state == .ready else { return false }
            models = status.models
            return true
        }
        let word = ProcessInfo.processInfo.environment["BRK_E2E_REAL_THREADS_MODEL"] ?? "haiku"
        let model = models.first { $0.id.lowercased().contains(word) || $0.name.lowercased().contains(word) }
        try app.dispatch(.settings(.max(.agentModel(kind, model?.id))))
        try app.dispatch(.settings(.max(.basicModel(kind, model?.id))))
        try app.dispatch(.settings(.closeWindow))
        log.write("model \(model?.id ?? "default") of \(models.map(\.id))")
        let home = try app.view().space.id
        try app.dispatch(.space(.update(home, title: "购物", icon: nil, theme: nil)))
        try app.dispatch(.commandBar(.open(.newTab)))
        try app.dispatch(.commandBar(.submit(app.site.url("shop-kettle.html").absoluteString)))
        app.sleep(2)
        var shopping = AIRequestID("")
        log.check("a question in 购物, answered, then named by the small model") {
            try app.dispatch(.assist(.newConversation))
            try app.waitUntil("a new conversation") { try app.view().ai?.conversation?.fresh == true }
            try send(app, "这个页面上的商品叫什么、多少钱？一句话回答。", input: .aiControl("input"))
            try app.waitUntil("the answer", timeout: 180) { try app.view().ai?.busy == false && app.view().ai?.conversation?.items.contains { if case .assistant = $0 { true } else { false } } == true }
            shopping = try XCTUnwrapValue(try app.view().ai?.conversation?.id)
            try app.waitUntil("the AI name", timeout: 90) { try app.view().ai?.name.map { $0 != "这个页面上的商品叫什么、多少钱？一句话回答。" } == true }
            AIThreadsScenarios.shot(app, "1-named")
            return "named “\(try app.view().ai?.name ?? "")”"
        }
        let work = try createSpace(app, title: "工作")
        var waiting = AIRequestID("")
        log.check("a question in 工作 whose agent asks to run a command") {
            try app.waitUntil("工作's list") { try app.view().aiPanel?.space == work }
            try send(app, "请用 Bash 工具运行 echo brk-threads，然后告诉我输出。", input: .aiControl("list-input"))
            try app.waitUntil("the approval", timeout: 180) { try AIThreadsScenarios.pending(app) != nil }
            waiting = try XCTUnwrapValue(try app.view().ai?.conversation?.id)
            AIThreadsScenarios.shot(app, "2-approval")
            return "waits: “\(try AIThreadsScenarios.pending(app)?.title ?? "")”"
        }
        log.check("from 购物: the strip, the ring and the count") {
            try AIThreadsScenarios.click(app, .dockSpace(home))
            try app.waitUntil("购物 with its conversation", timeout: 8) { try app.view().space.id == home && app.view().ai?.conversation?.id == shopping }
            try expect(try AIThreadsScenarios.shown(app, .aiControl("list-badge")), "no count on the list icon")
            try AIThreadsScenarios.click(app, .aiControl("list"))
            try app.waitUntil("the strip", timeout: 6) { try AIThreadsScenarios.shown(app, .aiControl("strip-\(waiting.rawValue)")) }
            try expect(try app.view().dock.first { $0.id == work }?.attention == true, "工作's dot has no ring")
            AIThreadsScenarios.shot(app, "3-strip")
            let strip = try XCTUnwrapValue(try app.view().aiPanel?.strips.first)
            return "strip “\(strip.spaceTitle) · \(strip.title) · \(strip.detail)”, ring, count \(try app.view().aiPanel?.waiting ?? 0)"
        }
        log.check("the strip's click, Allow, and nothing waits any more") {
            try AIThreadsScenarios.click(app, .aiControl("strip-\(waiting.rawValue)"))
            try app.waitUntil("工作 with the approval", timeout: 8) { try app.view().space.id == work && AIThreadsScenarios.shown(app, .aiControl("approval-allowOnce")) }
            try AIThreadsScenarios.click(app, .aiControl("approval-allowOnce"))
            try app.waitUntil("the reply", timeout: 180) { try app.view().ai?.busy == false }
            let said = try app.view().ai?.conversation?.items.compactMap { if case .assistant(let t) = $0 { t } else { nil } }.joined(separator: " ") ?? ""
            try AIThreadsScenarios.click(app, .dockSpace(home))
            try app.waitUntil("nothing waits", timeout: 8) {
                let v = try app.view()
                return v.space.id == home && v.aiPanel?.waiting == 0 && v.dock.first { $0.id == work }?.attention == false
            }
            AIThreadsScenarios.shot(app, "4-cleared")
            return "reply: “\(said.prefix(120))”"
        }
        log.check("the Library finds the 工作 conversation by what was said") {
            try AIThreadsScenarios.click(app, .dockLibrary)
            try app.waitUntil("the Library") { if case .library? = try app.view().overlay { true } else { false } }
            try AIThreadsScenarios.click(app, .libraryPage(.conversations))
            try app.waitUntil("both conversations", timeout: 6) { Set(try AIThreadsScenarios.library(app)?.rows.map(\.id) ?? []) == [shopping, waiting] }
            try AIThreadsScenarios.click(app, .aiControl("library-search"))
            try AIThreadsScenarios.type("brk-threads")
            try app.waitUntil("found", timeout: 6) { try AIThreadsScenarios.library(app)?.rows.map(\.id) == [waiting] }
            AIThreadsScenarios.shot(app, "5-library")
            return "“brk-threads” → \(waiting.rawValue)"
        }
        try log.finish()
    }
}
