import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Step 8 on a real-launched Brk (docs/design/ai-right-panel.md, "验收"), against the fixture agent's real session
/// protocol: conversations only in the right panel. Clicks, drags, keys and the pointer's moves are the window server's;
/// the control socket sets up (settings, a Space, a seeded old data folder) and reads state and frames. Each scenario
/// writes the facts it checked to `<id>.txt` beside its pictures.
enum AIRightPanelScenarios {
    static let all: [Scenario] = [
        Scenario("AIAgentRightPanel-Migration", "old data with a pinned, a foldered and an archived conversation row and one in another Space: after the launch no conversation row is left, each conversation is in its Space's list, the kept page's row and the emptied folder stay",
                 cefOnly: "native panel and a seeded data folder", migration),
        Scenario("AIAgentRightPanel-Toggle", "the title row's chat button: a click opens, a second closes, the open fill, the waiting count, the narrow row's … with its count, no button with AI off",
                 cefOnly: "native title row", toggle),
        Scenario("AIAgentRightPanel-EdgeDrop", "a tab dragged toward the window's right edge: the split slot over the page first, then the drop area in the last 40 pt; letting go opens a new conversation with the tab as a chip; a drop before the band still splits",
                 cefOnly: "native drag", edgeDrop),
    ]

    private typealias T = AIThreadsScenarios

    // MARK: Helpers

    /// The window at the screen's left edge and at most 1280 wide: macOS's permission dialogs sit at x ≥ 1295.
    static func place(_ app: AppUnderTest) throws {
        var frame = try app.native().windowFrame
        frame.origin.x = CGDisplayBounds(CGMainDisplayID()).minX
        frame.size.width = min(frame.width, 1280)
        try app.setWindowFrame(frame)
        app.sleep(0.5)
    }

    static func prepare(_ app: AppUnderTest) throws {
        try T.prepare(app)
        try place(app)
    }

    private static func listed(_ app: AppUnderTest) throws -> [AIRequestID] { try T.rows(app).map(\.id) }
    private static func conversationRows(_ v: WindowSnapshot) -> [TabRow] { allTabs(v).filter { ConversationPage.shows($0.url) } }
    static func conversationRowsIn(_ v: WindowSnapshot) -> [TabRow] { conversationRows(v) }
    private static func frame(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect { try T.still(app, id) }
    private static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    /// A question asked as a person does: the composer of the open panel (the list's or the conversation's).
    private static func askInPanel(_ app: AppUnderTest, _ text: String, list: Bool) throws -> AIRequestID {
        try T.click(app, .aiControl(list ? "list-input" : "input"))
        try T.type(text, enter: true)
        try app.waitUntil("the answer to \(text)", timeout: 20) { try app.view().ai?.busy == false && app.view().ai?.text.contains(text) == true }
        return try XCTUnwrapValue(try app.view().ai?.conversation?.id)
    }

    private static func ask(_ app: AppUnderTest, _ text: String) throws -> AIRequestID {
        try app.dispatch(.assist(.ask(text)))
        try app.waitUntil("the answer to \(text)", timeout: 20) { try app.view().ai?.busy == false && app.view().ai?.text.contains(text) == true }
        return try XCTUnwrapValue(try app.view().ai?.conversation?.id)
    }

    private static func openPanelByButton(_ app: AppUnderTest) throws {
        if try app.view().aiToggle?.open == true { return }
        try T.click(app, .aiControl("toggle"))
        try app.waitUntil("the panel open by the chat button", timeout: 5) { try app.view().aiToggle?.open == true }
    }

    private static func closePanel(_ app: AppUnderTest) throws {
        guard try app.view().aiToggle?.open == true else { return }
        try T.click(app, .aiControl("toggle"))
        try app.waitUntil("the panel closed by the chat button", timeout: 5) { try app.view().aiToggle?.open == false }
    }

    /// Mouse events at screen points, for a drag held across several checks.
    private static func mouse(_ type: CGEventType, _ point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }
    private static func glide(_ from: CGPoint, _ to: CGPoint, steps: Int = 24) {
        for step in 1...steps {
            let t = Double(step) / Double(steps), eased = t * t * (3 - 2 * t)
            mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased))
            usleep(10_000)
        }
    }
    /// A held drag from `start` through `stops` (window content points); `at(i)` runs at each stop with the button down;
    /// the release is at the last stop.
    private static func heldDrag(_ app: AppUnderTest, from start: CGPoint, through stops: [CGPoint], at: (Int) throws -> Void) throws {
        let first = try T.screen(app, start)
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        guard case .hello(let hello) = try app.send(.hello), PhysicalPointer.frontmost(at: first)?.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(first); nothing posted")
        }
        mouse(.mouseMoved, first); usleep(150_000)
        mouse(.leftMouseDown, first); usleep(150_000)
        var current = first
        var failure: (any Error)?
        for (index, stop) in stops.enumerated() {
            let next = try T.screen(app, stop)
            glide(current, next)
            current = next
            // The page's drop rule reads the newest position once per 100 ms (brk-arc-page-drop-rule).
            usleep(350_000)
            do { try at(index) } catch { failure = error; break }
        }
        mouse(.leftMouseUp, current); usleep(400_000)
        if let failure { throw failure }
    }

    // MARK: No row


    // MARK: The move off the sidebar

    private static func stored(_ id: String, space: SpaceID, title: String, link tab: ItemID? = nil) -> StoredConversation {
        let now = Instant(milliseconds: Int64(Date().timeIntervalSince1970 * 1000))
        var conversation = StoredConversation(id: AIRequestID(id), profile: .default, title: title, createdAt: now, tabs: true)
        conversation.agent = .claude
        conversation.agentName = "Claude"
        conversation.items = [.user(title), .assistant(tab.map { "See [the tab](brk://tab/\($0.rawValue))." } ?? "Done.")]
        conversation.space = space
        return conversation
    }

    @Sendable static func migration(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        let home = try app.view().space.id
        // A data folder as Brk left it before step 8: ordinary tabs made now, written into state.json as conversation rows.
        let pinned = try app.load(app.site.url("index.html?conv=pinned"))
        try app.dispatch(.tab(.togglePin(.item(pinned))))
        let foldered = try app.load(app.site.url("index.html?conv=folder"))
        try app.dispatch(.tabTools(.bulk(.items([foldered]), .newFolder(group: false))))
        let archived = try app.load(app.site.url("index.html?conv=archived"))
        try app.dispatch(.tab(.close(.item(archived))))
        let page = try app.load(app.site.url("index.html?kept=page"))
        let work = try createSpace(app, title: "Work")
        _ = try app.load(app.site.url("index.html?conv=work"))
        try app.dispatch(.space(.focus(home)))
        try app.waitUntil("home") { try app.view().space.id == home }
        func folderID(_ rows: [Row]) -> ItemID? {
            for row in rows {
                if case .folder(let folder) = row {
                    if folder.children.contains(where: { $0.id == foldered }) { return folder.id }
                    if let inner = folderID(folder.children) { return inner }
                }
            }
            return nil
        }
        let folder = try XCTUnwrapValue(folderID(try app.view().space.pinned.rows) ?? folderID(try app.view().space.today.rows))
        try app.waitUntil("state.json written", timeout: 8) {
            ((try? String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)) ?? "").contains("conv=work")
        }
        let outcome = try app.quit()
        try expect(outcome.clean, "the quit: \(outcome.exit)")
        let state = app.dataDirectory.appendingPathComponent("state.json")
        var text = try String(contentsOf: state, encoding: .utf8)
        func swap(_ from: URL, _ to: String) {
            let a = from.absoluteString
            text = text.replacingOccurrences(of: a, with: to)
            text = text.replacingOccurrences(of: a.replacingOccurrences(of: "/", with: "\\/"), with: to.replacingOccurrences(of: "/", with: "\\/"))
        }
        swap(app.site.url("index.html?conv=pinned"), "brk://conversation/old-pinned")
        swap(app.site.url("index.html?conv=folder"), "brk://conversation/old-folder")
        swap(app.site.url("index.html?conv=archived"), "brk://conversation/old-archived")
        swap(app.site.url("index.html?conv=work"), "brk://conversation/old-work")
        swap(app.site.url("index.html?kept=page"), "brk://ai-page/old-page")
        try Data(text.utf8).write(to: state)
        let conversations = app.dataDirectory.appendingPathComponent("Conversations", isDirectory: true)
        let pages = app.dataDirectory.appendingPathComponent("AI Pages", isDirectory: true)
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        // Every one says it started at home; the work one's row was in Work, which wins.
        for (id, title) in [("old-pinned", "pinned conversation"), ("old-folder", "foldered conversation"), ("old-archived", "archived conversation"), ("old-work", "work conversation")] {
            try JSONEncoder().encode(stored(id, space: home, title: title)).write(to: conversations.appendingPathComponent(id + ".json"))
        }
        let html = pages.appendingPathComponent("old-page.html")
        try Data("<!doctype html><p>kept page</p>".utf8).write(to: html)
        let record = AIPageRecord(id: AIPageID("old-page"), title: "Old page", html: html, height: 160, data: nil, conversation: AIRequestID("old-pinned"),
                                  profile: .default, createdAt: Instant(milliseconds: 0), readPages: false)
        try JSONEncoder().encode(record).write(to: pages.appendingPathComponent("old-page.json"))
        try app.launch()
        try place(app)
        log.check("no conversation row is left: Pinned, the folder, Today, the other Space, the archive") {
            let v = try app.view()
            try expect(conversationRows(v).isEmpty, "rows: \(conversationRows(v).map(\.url))")
            try expect(allTabs(v).contains { $0.url == AIPageTab.url(AIPageID("old-page")) }, "the kept page's row went")
            func folderRow(_ rows: [Row]) -> FolderRow? {
                for row in rows { if case .folder(let f) = row { if f.id == folder { return f }; if let inner = folderRow(f.children) { return inner } } }
                return nil
            }
            let emptied = folderRow(v.space.pinned.rows) ?? folderRow(v.space.today.rows)
            try expect(emptied != nil && emptied!.children.isEmpty, "the folder: \(String(describing: emptied))")
            try app.dispatch(.library(.open(.archive)))
            try app.waitUntil("the archive") { isArchive(try app.view().overlay) }
            guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no Library") }
            let archive = library.archive?.groups.flatMap(\.entries) ?? []
            try expect(!archive.contains { ConversationPage.shows($0.url) }, "an archived conversation entry stayed")
            T.shot(app, "1-archive")
            try app.dispatch(.library(.close))
            try app.waitUntil("the Library closed") { try app.view().overlay == nil }
            try app.dispatch(.space(.focus(work)))
            try app.waitUntil("Work") { try app.view().space.id == work }
            try expect(conversationRows(try app.view()).isEmpty, "a conversation row in Work")
            try app.dispatch(.space(.focus(home)))
            try app.waitUntil("home") { try app.view().space.id == home }
            T.shot(app, "2-sidebar")
            return "no row anywhere; the kept page's row and the emptied folder stay; \(archive.count) archive entries, none a conversation"
        }
        log.check("each conversation is in its Space's list") {
            try openPanelByButton(app)
            try app.waitUntil("home's list", timeout: 5) { Set(try listed(app)) == [AIRequestID("old-pinned"), AIRequestID("old-folder"), AIRequestID("old-archived")] }
            T.shot(app, "3-home-list")
            try T.click(app, .dockSpace(work))
            try app.waitUntil("Work's list", timeout: 6) { try app.view().space.id == work && listed(app) == [AIRequestID("old-work")] }
            T.shot(app, "4-work-list")
            try T.click(app, .aiControl("thread-old-work"))
            try app.waitUntil("its transcript") { try app.view().ai?.conversation?.id == AIRequestID("old-work") }
            return "home: pinned, foldered, archived; Work: work"
        }
        log.check("the files say so after the next save") {
            try app.waitUntil("the work conversation's file names Work", timeout: 10) {
                let data = try Data(contentsOf: conversations.appendingPathComponent("old-work.json"))
                return try JSONDecoder().decode(StoredConversation.self, from: data).space == work
            }
            return "Conversations/old-work.json has space \(work.rawValue)"
        }
        _ = page
        try log.finish()
    }

    // MARK: The chat button

    @Sendable static func toggle(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        let home = try app.view().space.id
        log.check("the chat button ends the title row") {
            let button = try frame(app, .aiControl("toggle"))
            let row = try visible(app.native(), .titleRow).frame
            try expect(abs(button.maxX - (row.maxX - Metrics.sidebar.titleRowRightInset.value)) < 1.5, "button \(button), row \(row)")
            return "button \(button) in row \(row)"
        }
        log.check("a click opens the panel on the list, the button keeps its fill; a second click closes it") {
            try T.click(app, .aiControl("toggle"))
            try app.waitUntil("open", timeout: 5) { try T.panel(app)?.page == .list && app.view().aiToggle?.open == true }
            T.shot(app, "1-open")
            try T.click(app, .aiControl("toggle"))
            try app.waitUntil("closed", timeout: 5) { try T.panel(app) == nil && app.view().aiToggle?.open == false }
            return "open, then closed"
        }
        log.check("an approval waiting in another Space: the count on the button with the panel closed") {
            let work = try createSpace(app, title: "Work")
            try app.dispatch(.assist(.ask("fixture:tool")))
            try app.waitUntil("the approval", timeout: 15) { try T.pending(app) != nil }
            try T.click(app, .dockSpace(home))
            try app.waitUntil("home") { try app.view().space.id == home }
            try closePanel(app)
            try app.waitUntil("the count", timeout: 5) { try app.view().aiToggle?.waiting == 1 && T.shown(app, .aiControl("toggle-badge")) }
            T.shot(app, "2-badge")
            _ = work
            return "count 1 on the button"
        }
        log.check("narrow: reload into … first, then the chat button, whose … item carries the count") {
            // Arc's default width (228) holds the toggle and four compact buttons: reload is the one in "…".
            try app.dispatch(.sidebar(.resize(width: Metrics.sidebar.defaultWidth.value)))
            try app.waitUntil("reload folded, the chat button at the end", timeout: 5) { try T.shown(app, .aiControl("toggle")) && T.shown(app, .tabTool("title-more")) }
            guard case .menuItems(let first) = try app.send(.captureClickMenu(view: .tabTool("title-more"))) else { throw Check(description: "no … menu") }
            try expect(first == ["Reload"], "the … menu at 228: \(first)")
            T.shot(app, "3-compact")
            try app.dispatch(.sidebar(.resize(width: 190)))
            try app.waitUntil("the chat button folded", timeout: 5) { try !T.shown(app, .aiControl("toggle")) && T.shown(app, .tabTool("title-more")) }
            guard case .menuItems(let items) = try app.send(.captureClickMenu(view: .tabTool("title-more"), choose: "AI Conversations")) else {
                throw Check(description: "no … menu")
            }
            try expect(items.contains("AI Conversations") && items.contains("Reload"), "the … menu at 190: \(items)")
            try app.waitUntil("the panel by the … item", timeout: 5) { try app.view().aiToggle?.open == true }
            T.shot(app, "4-folded-open")
            try app.dispatch(.sidebar(.resize(width: 300)))
            try app.waitUntil("all five at 300", timeout: 5) { try T.shown(app, .aiControl("toggle")) && !T.shown(app, .tabTool("title-more")) }
            T.shot(app, "5-wide-row")
            try app.dispatch(.sidebar(.resize(width: Metrics.sidebar.defaultWidth.value)))
            return "228: … holds \(first); 190: … holds \(items.joined(separator: " · ")); 300: all five"
        }
        log.check("AI off: no chat button, the row is Arc's") {
            try app.dispatch(.settings(.max(.feature(.commandBar, false))))
            try app.waitUntil("no button", timeout: 5) { try app.view().aiToggle == nil && !T.shown(app, .aiControl("toggle")) }
            T.shot(app, "6-ai-off")
            try app.dispatch(.settings(.max(.feature(.commandBar, true))))
            return "button gone with Ask in Command Bar off"
        }
        try log.finish()
    }

    // MARK: ⌥⌘A, the View menu, the command bar

    @Sendable static func entries(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        let id = try ask(app, "entries question")
        try app.dispatch(.assist(.dismiss))
        try app.waitUntil("closed") { try app.view().aiToggle?.open == false }
        log.check("⌥⌘A opens on the conversation it showed, and closes again") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try T.key([.option, .command], .a)
            try app.waitUntil("open by ⌥⌘A", timeout: 5) { try app.view().ai?.conversation?.id == id && T.panel(app)?.page == .conversation }
            try T.key([.option, .command], .a)
            try app.waitUntil("closed by ⌥⌘A", timeout: 5) { try app.view().aiToggle?.open == false }
            return "⌥⌘A → open, ⌥⌘A → closed"
        }
        log.check("View: Show AI Conversations under Hide Sidebar, with ⌥⌘A; it toggles") {
            guard case .menuItems(let lines) = try app.send(.menuBarItems(menu: "View")) else { throw Check(description: "no View menu") }
            let titles = lines.map { String($0.drop(while: { $0 == " " }).split(separator: "\t").first ?? "") }
            let sidebar = try XCTUnwrapValue(titles.firstIndex(of: "Hide Sidebar"))
            try expect(titles.indices.contains(sidebar + 1) && titles[sidebar + 1] == "Show AI Conversations", "View: \(titles)")
            let row = lines.first { $0.contains("Show AI Conversations") } ?? ""
            try expect(row.contains("⌥⌘A") || row.contains("opt+cmd+a") || row.lowercased().contains("a"), "no shortcut: \(row)")
            try app.perform(.menuAction("Show AI Conversations"))
            try app.waitUntil("open by the menu", timeout: 5) { try app.view().aiToggle?.open == true }
            guard case .menuItems(let open) = try app.send(.menuBarItems(menu: "View")) else { throw Check(description: "no View menu") }
            try expect(open.contains { $0.contains("Hide AI Conversations") }, "the row did not turn to Hide: \(open)")
            try app.perform(.menuAction("Hide AI Conversations"))
            try app.waitUntil("closed by the menu", timeout: 5) { try app.view().aiToggle?.open == false }
            return "row “\(row.replacingOccurrences(of: "\t", with: " "))” after Hide Sidebar"
        }
        log.check("the command bar's AI Conversations opens the list") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try T.key(.command, .t)
            try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
            try T.type("ai conversations")
            guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
            let bar = try visible(app.native(), .commandBar).frame
            let onScreen = CGRect(origin: try T.screen(app, bar.origin), size: bar.size)
            var row: CGRect?, last: CGRect?
            try app.waitUntil("the row, still", timeout: 8) {
                row = NativeSystemInput.staticTexts(pid: hello.pid).first { $0.text == "AI Conversations" && onScreen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }?.frame
                defer { last = row }
                usleep(400_000)
                return row != nil && row == last
            }
            try PhysicalPointer.click(app, at: CGPoint(x: row!.minX + 12, y: row!.midY), window: app.window!)
            try app.waitUntil("the list", timeout: 5) { try T.panel(app)?.page == .list }
            T.shot(app, "1-bar-list")
            return "bar row → list"
        }
        try log.finish()
    }

    // MARK: The right edge

    @Sendable static func edgeDrop(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        let a = try app.load(app.site.url("page2.html"))
        let b = try app.load(app.site.url("index.html?edge=b"))
        app.sleep(1)
        log.check("over the page the split slot; within 40 pt of the right edge the drop area and no slot; letting go: a new conversation with the tab") {
            try expect(try app.view().aiEdgeDrop != nil, "no edge drop while the panel is closed")
            let row = try frame(app, .row(a))
            let width = try app.native().windowFrame.width
            let card = try XCTUnwrapValue(try app.native().computed.cards.first?.rect)
            var notes: [String] = []
            try heldDrag(app, from: centre(row), through: [CGPoint(x: card.midX - 80, y: card.midY), CGPoint(x: width - 20, y: card.midY)]) { stop in
                let n = try app.native()
                if stop == 0 {
                    try expect(isShown(n, .splitDropPreview), "no split slot over the page")
                    try expect(!isShown(n, .aiControl("edge-drop")), "the drop area shows before the band")
                    T.shot(app, "1-split-slot")
                    notes.append("slot over the page")
                } else {
                    try expect(isShown(n, .aiControl("edge-drop")), "no drop area in the band")
                    try expect(!isShown(n, .splitDropPreview), "a split slot shows in the drop area")
                    T.shot(app, "2-edge-area")
                    notes.append("area \(try visible(n, .aiControl("edge-drop")).frame)")
                }
            }
            try app.waitUntil("a new conversation with the tab", timeout: 6) {
                let c = try app.view().ai?.conversation
                return c?.fresh == true && c?.attached.contains { $0.id == a.rawValue } == true
            }
            try expect(try app.view().content.split == nil, "a split was made")
            T.shot(app, "3-chip")
            return notes.joined(separator: "; ") + "; chip for \(a.rawValue)"
        }
        log.check("a drop over the page before the band still makes a split") {
            try app.dispatch(.assist(.dismiss))
            try app.waitUntil("closed") { try app.view().aiToggle?.open == false }
            try app.dispatch(.tab(.focus(b)))
            app.sleep(0.6)
            let row = try frame(app, .row(a))
            let card = try XCTUnwrapValue(try app.native().computed.cards.first?.rect)
            try heldDrag(app, from: centre(row), through: [CGPoint(x: card.minX + card.width * 0.25, y: card.midY)]) { _ in }
            try app.waitUntil("the split", timeout: 6) { try app.view().content.split != nil }
            try expect(try app.view().ai == nil, "the panel opened")
            T.shot(app, "4-split")
            return "split made"
        }
        try log.finish()
    }

    // MARK: Hover lighting

    @Sendable static func hover(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        let a = try app.load(app.site.url("page2.html"))
        let b = try app.load(app.site.url("index.html?hover=b"))
        let c = try app.load(app.site.url("index.html?hover=c"))
        try app.dispatch(.tabTools(.bulk(.items([b]), .newFolder(group: false))))
        app.sleep(0.5)
        func folderOf(_ rows: [Row]) -> ItemID? {
            for row in rows { if case .folder(let f) = row { if f.children.contains(where: { $0.id == b }) { return f.id }; if let inner = folderOf(f.children) { return inner } } }
            return nil
        }
        let folder = try XCTUnwrapValue(folderOf(try app.view().space.pinned.rows) ?? folderOf(try app.view().space.today.rows))
        // The three tabs given to a conversation (Ask AI's command), then its first message typed.
        try app.dispatch(.assist(.attach([.tab(a.rawValue), .tab(b.rawValue), .tab(c.rawValue)])))
        try app.waitUntil("three chips") { try app.view().ai?.conversation?.attached.count == 3 }
        let id = try askInPanel(app, "compare these three", list: false)
        log.check("the pointer over the list row lights the three tabs and says so") {
            try T.click(app, .aiControl("list"))
            try app.waitUntil("the list") { try T.panel(app)?.page == .list }
            let row = try frame(app, .aiControl("thread-\(id.rawValue)"))
            try PhysicalPointer.move(app, to: centre(row), window: app.window!)
            try app.waitUntil("lit", timeout: 5) { try app.view().sidebar.lit == [a, b, c] }
            try app.waitUntil("the lit marks on screen") { try [a, b, c].allSatisfy { try T.shown(app, .tabTool("ai-lit-" + $0.rawValue)) } }
            let detail = try T.panel(app)?.hoveredDetail
            try expect(detail == "Used 3 tabs", "the second line: \(String(describing: detail))")
            T.shot(app, "1-lit")
            return "lit \([a, b, c].map(\.rawValue)); “\(detail ?? "")”"
        }
        log.check("off the row nothing is lit") {
            let search = try frame(app, .aiControl("list-search"))
            try PhysicalPointer.move(app, to: centre(search), window: app.window!)
            try app.waitUntil("unlit", timeout: 5) { try app.view().sidebar.lit.isEmpty }
            return "none lit"
        }
        log.check("a collapsed folder lights in its tab's place") {
            if try app.state(folderExpanded: folder) { try app.dispatch(.item(.toggleFolder(folder))) }
            app.sleep(0.4)
            let row = try frame(app, .aiControl("thread-\(id.rawValue)"))
            try PhysicalPointer.move(app, to: centre(row), window: app.window!)
            try app.waitUntil("lit with the folder", timeout: 5) { try app.view().sidebar.lit == [a, folder, c] }
            try app.waitUntil("the folder's mark") { try T.shown(app, .tabTool("ai-lit-" + folder.rawValue)) }
            T.shot(app, "2-folder")
            return "lit \(a.rawValue), folder \(folder.rawValue), \(c.rawValue)"
        }
        log.check("over a chip only that tab lights") {
            try app.dispatch(.assist(.attach([.tab(a.rawValue), .tab(c.rawValue)])))
            try app.waitUntil("two chips") { try app.view().ai?.conversation?.attached.count == 2 && T.panel(app)?.page == .conversation }
            let chip = try frame(app, .aiControl("chip-" + c.rawValue))
            try PhysicalPointer.move(app, to: CGPoint(x: chip.minX + 12, y: chip.midY), window: app.window!)
            try app.waitUntil("one lit", timeout: 5) { try app.view().sidebar.lit == [c] }
            T.shot(app, "3-chip")
            return "chip \(c.rawValue) → lit \(c.rawValue)"
        }
        try log.finish()
    }

    // MARK: The panel's width

    @Sendable static func width(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        var widened = 0.0
        log.check("dragging the gap left widens the panel, up to half the window") {
            try openPanelByButton(app)
            let before = try XCTUnwrapValue(try app.native().computed.aiPanel).width
            let handle = try frame(app, .aiControl("panel-resize"))
            try PhysicalPointer.drag(app, through: [centre(handle), CGPoint(x: handle.midX - 180, y: handle.midY)], window: app.window!) {}
            try app.waitUntil("wider", timeout: 5) { (try app.view().aiPanelWidth ?? 0) > before + 100 }
            widened = try XCTUnwrapValue(try app.view().aiPanelWidth)
            let shown = try XCTUnwrapValue(try app.native().computed.aiPanel).width
            let window = try app.native().windowFrame.width
            try expect(abs(shown - min(widened, window / 2)) < 1.5, "shown \(shown), kept \(widened), window \(window)")
            T.shot(app, "1-wide")
            return "\(Int(before)) → \(Int(shown)) (kept \(Int(widened)))"
        }
        log.check("after a relaunch the panel opens as wide") {
            try app.restart()
            try place(app)
            let kept = try app.view().aiPanelWidth
            try expect(kept == widened, "kept \(String(describing: kept))")
            try openPanelByButton(app)
            let shown = try XCTUnwrapValue(try app.native().computed.aiPanel).width
            let window = try app.native().windowFrame.width
            try expect(abs(shown - widened) < 1.5 || shown >= window / 2 - 1, "shown \(shown), kept \(widened)")
            T.shot(app, "2-relaunched")
            return "width \(Int(shown)) after the relaunch"
        }
        try log.finish()
    }

    // MARK: A kept page's way back



    // MARK: A list row onto a Space's dot


    // MARK: Pictures

    @Sendable static func look(_ app: AppUnderTest) throws {
        try prepare(app)
        let log = T.Log(app)
        let home = try app.view().space.id
        try app.dispatch(.space(.update(home, title: "购物", icon: nil, theme: SpaceTheme(colors: [RGBA(hex: "#C9DDF5")], texture: .grain, intensity: 0.25, appearance: .light))))
        let dark = try createSpace(app, title: "工作")
        try app.dispatch(.space(.update(dark, title: "工作", icon: nil, theme: SpaceTheme(colors: [ThemePresets.drab[8]], texture: .grain, intensity: 0.25, appearance: .dark))))
        // Something waits for the user in each Space: the other Space's button shows the count.
        for space in [home, dark] {
            try app.dispatch(.space(.focus(space)))
            try app.waitUntil("the Space") { try app.view().space.id == space }
            try app.dispatch(.assist(.ask("fixture:tool")))
            try app.waitUntil("an approval", timeout: 15) { try T.pending(app) != nil }
            try app.dispatch(.assist(.dismiss))
        }
        for (space, name) in [(home, "light"), (dark, "dark")] {
            log.check("\(name): the five pictures") {
                try app.dispatch(.space(.focus(space)))
                try app.waitUntil("the Space") { try app.view().space.id == space }
                let a = try app.load(app.site.url("shop-kettle.html"))
                let b = try app.load(app.site.url("shop-toaster.html"))
                _ = try app.load(app.site.url("shop-blender.html"))
                app.sleep(1)
                try closePanel(app)
                try app.waitUntil("the badge") { try T.shown(app, .aiControl("toggle-badge")) }
                T.shot(app, "\(name)-1-badge")
                // A conversation with the two tabs, hovered in the list.
                try app.dispatch(.assist(.attach([.tab(a.rawValue), .tab(b.rawValue)])))
                try app.waitUntil("chips") { try app.view().ai?.conversation?.attached.count == 2 }
                let id = try askInPanel(app, "look at these two", list: false)
                try T.click(app, .aiControl("list"))
                try app.waitUntil("the list") { try T.panel(app)?.page == .list }
                try PhysicalPointer.move(app, to: centre(try frame(app, .aiControl("thread-\(id.rawValue)"))), window: app.window!)
                try app.waitUntil("lit", timeout: 5) { try app.view().sidebar.lit == [a, b] }
                T.shot(app, "\(name)-2-hover")
                try closePanel(app)
                let width = try app.native().windowFrame.width
                let card = try XCTUnwrapValue(try app.native().computed.cards.first?.rect)
                try heldDrag(app, from: centre(try frame(app, .row(a))), through: [CGPoint(x: card.midX, y: card.midY), CGPoint(x: width - 20, y: card.midY)]) { stop in
                    if stop == 1 { T.shot(app, "\(name)-3-edge-drop") }
                }
                try app.waitUntil("the dropped tab's conversation") { try app.view().ai?.conversation?.fresh == true }
                try app.dispatch(.assist(.panelWidth(560)))
                try app.dispatch(.assist(.showConversation(id)))
                try app.waitUntil("the conversation, wide") { try app.view().ai?.conversation?.id == id && (try app.native().computed.aiPanel?.width ?? 0) > 500 }
                app.sleep(0.6)
                T.shot(app, "\(name)-4-wide")
                try app.dispatch(.assist(.panelWidth(Metrics.ai.width.value)))
                // A kept page in this Space, shown as a tab: its caption row.
                try app.dispatch(.assist(.ask("盯着这三个商品页的价格，每小时更新一次")))
                try app.waitUntil("a kept page", timeout: 30) { try app.view().ai?.busy == false && allTabs(try app.view()).contains { AIPageTab.shows($0.url) } }
                let pageRow = try XCTUnwrapValue(try app.view().space.today.rows.lazy.compactMap { row -> TabRow? in if case .tab(let t) = row, AIPageTab.shows(t.url) { t } else { nil } }.first)
                try T.click(app, .row(pageRow.id))
                try app.waitUntil("the page's caption") { try T.shown(app, .aiControl("page-conversation")) }
                app.sleep(1)
                T.shot(app, "\(name)-5-caption")
                return "five pictures in \(name)"
            }
        }
        try log.finish()
    }
}

/// The spec's full example on a real agent (docs/design/ai-right-panel.md, 验收 10): two tabs dragged onto the panel, one
/// question, the page kept as a tab, the pointer over the list row lighting the two tabs, and back to the conversation
/// from the page's caption button. `BRK_E2E_REAL_RIGHT_AGENT=claude`, `BRK_E2E_REAL_RIGHT_MODEL=haiku`.
enum AIRealRightPanelScenarios {
    static var all: [Scenario] {
        guard let name = ProcessInfo.processInfo.environment["BRK_E2E_REAL_RIGHT_AGENT"], let choice = AIProviderChoice(rawValue: name), choice.kind != nil else { return [] }
        return [Scenario("AIRealRightPanel-\(name)", "real \(name): two tabs dragged in, one question, the page kept as a tab, the list row's hover lights the two tabs, the page's button opens the conversation",
                         cefOnly: "real agent, real input") { try route($0, choice) }]
    }

    private typealias T = AIThreadsScenarios

    private static func route(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        let log = T.Log(app)
        let kind = choice.kind!
        try T.prepare(app)
        try AIRightPanelScenarios.place(app)
        try app.dispatch(.settings(.max(.provider(choice))))
        try app.dispatch(.settings(.openPane(.max)))
        var models: [AIAgentModel] = []
        try app.waitUntil("the agent reported", timeout: 60) {
            guard case .settings(let settings) = try app.send(.settings), let status = settings.max.agents.first(where: { $0.kind == kind }), status.state == .ready else { return false }
            models = status.models
            return true
        }
        let word = ProcessInfo.processInfo.environment["BRK_E2E_REAL_RIGHT_MODEL"] ?? "haiku"
        let model = models.first { $0.id.lowercased().contains(word.lowercased()) || $0.name.lowercased().contains(word.lowercased()) }
        try app.dispatch(.settings(.max(.agentModel(kind, model?.id))))
        try app.dispatch(.settings(.closeWindow))
        log.write("model \(model?.id ?? "default") of \(models.map(\.id))")
        try AIRightPanelScenarios.place(app)
        let kettle = try app.load(app.site.url("shop-kettle.html"))
        let toaster = try app.load(app.site.url("shop-toaster.html"))
        app.sleep(2)
        func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
        log.check("the chat button opens the panel; the two tabs dragged onto it are chips") {
            try T.click(app, .aiControl("toggle"))
            try app.waitUntil("the panel", timeout: 5) { try app.view().aiToggle?.open == true }
            for tab in [kettle, toaster] {
                let row = try T.still(app, .row(tab))
                let panel = try T.still(app, .aiControl("panel"))
                try PhysicalPointer.drag(app, through: [centre(row), CGPoint(x: panel.midX, y: panel.midY - 60), CGPoint(x: panel.midX, y: panel.maxY - 120)], window: app.window!) {}
                app.sleep(0.6)
            }
            try app.waitUntil("two chips", timeout: 6) { Set(try app.view().ai?.conversation?.attached.map(\.id) ?? []) == [kettle.rawValue, toaster.rawValue] }
            T.shot(app, "1-chips")
            return "chips \(try app.view().ai?.conversation?.attached.map(\.title) ?? [])"
        }
        var conversation: AIRequestID?
        var page: AIPageID?
        log.check("one question; the agent reads the two tabs and draws a page") {
            try T.click(app, .aiControl("input"))
            try T.paste("这两个 tab 里的商品哪个更便宜？读一下两个 tab，用 brk_html_preview 和 brk_html_render 画一个价格对比的页面。")
            try NativeSystemInput.postSystemWide(KeyChord([], .returnKey))
            try app.waitUntil("the turn started", timeout: 15) { try app.view().ai?.busy == true }
            conversation = try app.view().ai?.conversation?.id
            // The agent may reach for a tool of its own (Codex searches files with rg); Brk asks before each such call
            // (ai-native.md rule 3). A person refuses those here, and the agent goes on with Brk's tab tools.
            var refused = 0
            while true {
                try app.waitUntil("the answer or an approval", timeout: 400) { try app.view().ai?.busy == false || T.pending(app) != nil }
                guard try app.view().ai?.busy == true, try T.pending(app) != nil, refused < 5 else { break }
                try T.click(app, .aiControl("approval-deny"))
                refused += 1
            }
            let ai = try XCTUnwrapValue(try app.view().ai)
            page = ai.pages.last?.id
            T.shot(app, "2-answer")
            try expect(page != nil, "no page: \(ai.conversation?.items.suffix(4) ?? [])")
            try expect(AIRightPanelScenarios.conversationRowsIn(try app.view()).isEmpty, "a conversation row in the sidebar")
            return "page \(ai.pages.last?.title ?? "")"
        }
        log.check("Keep as Tab under the page") {
            guard let page else { throw Check(description: "no page") }
            if try !app.view().space.today.rows.contains(where: { if case .tab(let t) = $0 { t.url == AIPageTab.url(page) } else { false } }) {
                let transcript = try T.still(app, .aiControl("transcript"))
                for _ in 0..<6 where !(try T.shown(app, .aiControl("keep-" + page.rawValue))) {
                    try PhysicalPointer.scroll(app, lines: -5, at: centre(transcript), window: app.window!)
                }
                try T.click(app, .aiControl("keep-" + page.rawValue))
            }
            try app.waitUntil("the page's row", timeout: 8) { try app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.url == AIPageTab.url(page) } else { false } } }
            T.shot(app, "3-kept")
            return "kept as a tab"
        }
        log.check("the pointer over the list row lights the two tabs") {
            guard let conversation else { throw Check(description: "no conversation") }
            try T.click(app, .aiControl("list"))
            try app.waitUntil("the list") { try T.panel(app)?.page == .list }
            let row = try T.still(app, .aiControl("thread-\(conversation.rawValue)"))
            try PhysicalPointer.move(app, to: centre(row), window: app.window!)
            try app.waitUntil("lit", timeout: 6) { try app.view().sidebar.lit.isSuperset(of: [kettle, toaster]) }
            T.shot(app, "4-hover")
            return "lit \(try app.view().sidebar.lit.map(\.rawValue).sorted()); “\(try T.panel(app)?.hoveredDetail ?? "")”"
        }
        log.check("back to the conversation from the kept page's button") {
            guard let page, let conversation else { throw Check(description: "no page") }
            try T.click(app, .aiControl("toggle"))
            try app.waitUntil("closed") { try app.view().aiToggle?.open == false }
            let row = try XCTUnwrapValue(try app.view().space.today.rows.lazy.compactMap { row -> TabRow? in if case .tab(let t) = row, t.url == AIPageTab.url(page) { t } else { nil } }.first)
            try T.click(app, .row(row.id))
            try app.waitUntil("the page's card", timeout: 8) { try app.view().aiPages.first?.content?.id == page }
            try app.waitUntil("its caption button") { try T.shown(app, .aiControl("page-conversation")) }
            T.shot(app, "5-caption")
            try T.click(app, .aiControl("page-conversation"))
            try app.waitUntil("the conversation in the panel", timeout: 8) { try app.view().ai?.conversation?.id == conversation }
            T.shot(app, "6-back")
            return "page card → conversation"
        }
        try log.finish()
    }
}

extension AppUnderTest {
    /// Whether `folder` is open in this window, read from the sidebar as drawn.
    func state(folderExpanded folder: ItemID) throws -> Bool {
        func find(_ rows: [Row]) -> FolderRow? {
            for row in rows { if case .folder(let f) = row { if f.id == folder { return f }; if let inner = find(f.children) { return inner } } }
            return nil
        }
        let v = try view()
        return !(find(v.space.pinned.rows) ?? find(v.space.today.rows))!.collapsed
    }
}
