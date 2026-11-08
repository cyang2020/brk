import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// A saved conversation with a page, written into the data folder as a past launch would have left it, then real input on
/// it: its row and tab after a relaunch, Keep as Tab from the page's own context menu, and a link in the page that asks
/// before it opens a new address (the page was written after page text reached its conversation). No agent runs; the
/// setup's one dispatch opens the conversation the way its link would.
enum AIPagesFixtureScenarios {
    static let all: [Scenario] = [
        Scenario("AIPagesFixture", "a saved conversation's page after a relaunch: its tab, Keep as Tab from the page's menu, a link that asks first",
                 cefOnly: "native panel and page sandbox", route),
    ]

    private static let conversation = AIRequestID("5E0C0A11-0000-4000-8000-00000000C0DE")
    private static let page = AIPageID("5E0C0A11-0000-4000-8000-00000000BA6E")

    private static func html(_ link: URL) -> String {
        """
        <!doctype html><html><head><style>
        .bar { height: 26px; border-radius: var(--radius); background: var(--chart-1); margin: 8px 0; }
        a.big { display: block; height: 70px; line-height: 70px; padding: 0 16px; border-radius: var(--radius); background: var(--card); }
        </style></head><body>
        <a class="big" id="shop" href="\(link.absoluteString)">Open the kettle's shop page</a>
        <div class="bar" style="width: 40%"></div><div class="bar" style="width: 65%"></div><div class="bar" style="width: 100%"></div>
        </body></html>
        """
    }

    private static func seed(_ app: AppUnderTest) throws {
        let pages = app.dataDirectory.appendingPathComponent("AI Pages", isDirectory: true)
        let conversations = app.dataDirectory.appendingPathComponent("Conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        let file = pages.appendingPathComponent(page.rawValue + ".html")
        try Data(html(app.site.url("shop-kettle.html")).utf8).write(to: file)
        let now = Instant(milliseconds: Int64(Date().timeIntervalSince1970 * 1000))
        let record = AIPageRecord(id: page, title: "Fixture prices", html: file, height: 220, data: #"{"cheapest":"toaster"}"#, conversation: conversation,
                                  profile: .default, createdAt: now, readPages: true)
        var stored = StoredConversation(id: conversation, profile: .default, title: "Which is cheapest? (fixture)", createdAt: now, tabs: true)
        stored.agent = .claude
        stored.agentName = "Claude"
        stored.readPages = true
        stored.items = [.user("Which is cheapest? (fixture)"), .assistant("Here is a chart."), .page(AIPageRef(id: page, title: "Fixture prices", height: 220)),
                        .assistant("The toaster is cheapest.")]
        try JSONEncoder().encode(record).write(to: pages.appendingPathComponent(page.rawValue + ".json"))
        try JSONEncoder().encode(stored).write(to: conversations.appendingPathComponent(conversation.rawValue + ".json"))
    }

    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + point.x, y: top + point.y)
    }
    private static func mouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left) {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }
    private static func click(_ app: AppUnderTest, pid: Int32, at point: CGPoint, right: Bool = false) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        let target = try screen(app, point)
        guard PhysicalPointer.frontmost(at: target)?.pid == pid else { throw Check(description: "another window is in front at \(target); nothing posted") }
        mouse(.mouseMoved, at: target); usleep(150_000)
        mouse(right ? .rightMouseDown : .leftMouseDown, at: target, button: right ? .right : .left); usleep(80_000)
        mouse(right ? .rightMouseUp : .leftMouseUp, at: target, button: right ? .right : .left); usleep(400_000)
    }

    private static func route(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting events is not allowed for this runner") }
        try seed(app)
        try app.restart()
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        let pid = hello.pid
        // The conversation is saved; opening it is what its link or its row does.
        try app.dispatch(.assist(.openConversation(conversation)))
        try app.waitUntil("the conversation's tab", timeout: 8) { try app.view().conversations.first?.answer.conversation?.id == conversation }
        let row = try XCTUnwrapValue(try app.view().space.today.rows.lazy.compactMap { row -> TabRow? in if case .tab(let t) = row, t.url == ConversationPage.url(conversation) { t } else { nil } }.first)
        try expect(row.title == "Which is cheapest? (fixture)", "the row's title: \(row.title)")
        let pageView = ViewID.aiControl("page-" + page.rawValue)
        try app.waitUntil("the page in the transcript", timeout: 10) { try app.native().actual[pageView.identifier]?.hidden == false }
        app.sleep(1.5)
        _ = try app.screenshot("AIPagesFixture-tab")
        let frame = try XCTUnwrapValue(try app.native().actual[pageView.identifier]?.frame)
        try expect(frame.height >= 120 && frame.width > 300, "the page's frame: \(frame)")

        // Keep as Tab from the page's own menu, with the right button.
        try click(app, pid: pid, at: CGPoint(x: frame.midX, y: frame.maxY - 30), right: true)
        // What the screen shows (the control socket's screenshots leave menus out): Brk's window only.
        let window = try app.native().windowFrame
        let top = CGDisplayBounds(CGMainDisplayID()).height - window.maxY
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-R", "\(Int(window.minX)),\(Int(top)),\(Int(window.width)),\(Int(window.height))", app.shotsDirectory.appendingPathComponent("AIPagesFixture-menu-screen.png").path]
        try? capture.run(); capture.waitUntilExit()
        // The menu is up at the pointer (the screen capture shows it); Accessibility does not list a menu a web view
        // opens, so the item is chosen with the keyboard, as a person can: Down, then Return.
        try NativeSystemInput.postSystemWide(KeyChord([], .downArrow)); usleep(250_000)
        try NativeSystemInput.postSystemWide(KeyChord([], .returnKey)); usleep(500_000)
        try app.waitUntil("the page's tab", timeout: 8) { try app.view().aiPages.first?.content?.id == page }
        app.sleep(1)
        _ = try app.screenshot("AIPagesFixture-page-tab")
        let card = try XCTUnwrapValue(try app.native().actual[ViewID.aiControl("page-card").identifier])
        try expect(!card.hidden, "the page card is hidden")

        // A link in the page: the address is new to the profile and the page was written after page text, so it asks.
        let before = try app.view().space.today.rows.count
        let link = CGPoint(x: card.frame.minX + Metrics.ai.tabColumnInset.value + 60, y: card.frame.minY + Metrics.ai.tabColumnInset.value + 35)
        try click(app, pid: pid, at: link)
        try app.waitUntil("the link asks first", timeout: 6) { try app.view().pageLinkPrompt != nil }
        let prompt = try XCTUnwrapValue(try app.view().pageLinkPrompt)
        try expect(prompt.url == app.site.url("shop-kettle.html"), "the prompt's address: \(prompt.url)")
        try expect(try app.view().space.today.rows.count == before, "a tab opened before the answer")
        _ = try app.screenshot("AIPagesFixture-link-prompt")
        let open = try XCTUnwrapValue(try app.native().actual[ViewID.aiControl("page-link-open").identifier]?.frame)
        try click(app, pid: pid, at: CGPoint(x: open.midX, y: open.midY))
        try app.waitUntil("the shop opened as a tab", timeout: 10) {
            try app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.status == .current && t.url?.absoluteString.hasSuffix("shop-kettle.html") == true } else { false } }
        }
        try expect(try app.view().pageLinkPrompt == nil, "the prompt stayed")
        _ = try app.screenshot("AIPagesFixture-link-opened")
    }
}
