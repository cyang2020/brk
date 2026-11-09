import BrkBase
@testable import BrkDomain
import XCTest

/// Brk's own AI words follow the language the user writes in a conversation (docs/design/ai-panel.md, "文字的语言"), a run
/// of steps reads as one plain line, the approval card says what the agent wants in one sentence, and the panel's New
/// Conversation puts the current one away for a fresh one.
final class AIPanelWordsTests: XCTestCase {
    func testTheLanguageIsTheLatestMessageThatTellsElseTheSystems() {
        XCTAssertEqual(AILanguage.of(text: "盯着这三个商品页的价格"), .zh)
        XCTAssertEqual(AILanguage.of(text: "帮我看 github 的 PR"), .zh, "any Han character is Chinese")
        XCTAssertEqual(AILanguage.of(text: "Summarize these"), .en)
        XCTAssertNil(AILanguage.of(text: "https://x.example/ 42 👍"), "no letters say nothing")
        XCTAssertEqual(AILanguage.of([], system: "en-US"), .en)
        XCTAssertEqual(AILanguage.of([], system: "zh-Hans-CN"), .zh)
        XCTAssertEqual(AILanguage.of([.user("你好"), .assistant("Hello"), .user("42")], system: "en-US"), .zh, "a message without letters does not change it")
        XCTAssertEqual(AILanguage.of([.user("你好"), .user("Now in English")], system: "zh-Hans"), .en, "the latest message wins")
    }

    func testARunOfStepsIsOnePlainLine() {
        func step(_ kind: AIStepKind?, _ title: String = "x") -> AIAgentStep { AIAgentStep(id: UUID().uuidString, title: title, state: .done, kind: kind) }
        let run = [step(.listTabs), step(.readTab), step(.readTab), step(.readTab), step(.makePage), step(.keepPage)]
        XCTAssertEqual(AIStepWords.summary(run, .zh), "读了 3 个 tab，做了一个页面，存成了 tab")
        XCTAssertEqual(AIStepWords.summary(run, .en), "read 3 tabs, made a page, kept it as a tab")
        XCTAssertEqual(AIStepWords.summary([step(.command), step(.command), step(nil, "Mystery")], .zh), "运行了 2 条命令，做了一步")
        XCTAssertEqual(AIStepWords.summary([step(.listTabs), step(.makePage)], .zh), "看了 tab，做了一个页面", "looking at tabs without reading one still shows")
        XCTAssertEqual(AIStepWords.title(AIAgentStep(id: "s", title: "Run: ls -la", state: .done, kind: .command, subject: "ls -la"), .zh), "运行了命令：ls -la")
        XCTAssertEqual(AIStepWords.title(AIAgentStep(id: "s", title: "Run: ls -la", state: .done, kind: .command, subject: "ls -la"), .en), "Ran: ls -la")
        XCTAssertEqual(AIStepWords.title(AIAgentStep(id: "s", title: "An agent's own tool", state: .done), .zh), "An agent's own tool", "a tool Brk has no name for keeps the agent's words")
    }

    func testTheApprovalSentenceSaysWhoWantsWhatWhere() {
        let home = NSHomeDirectory()
        let command = AIAgentApproval(id: "a", title: "Run: ls", detail: "ls", options: [], kind: .command, subject: "ls")
        XCTAssertEqual(AIStepWords.approval(command, agent: "Claude", folder: home + "/Desktop", .zh), "Claude 想在 ~/Desktop 里运行一条命令")
        XCTAssertEqual(AIStepWords.approval(command, agent: "Claude", folder: home + "/Desktop", .en), "Claude wants to run a command in ~/Desktop")
        XCTAssertEqual(AIStepWords.approval(command, agent: "Claude", folder: "/private/tmp/brk-bp-zb1nxu2q/brk-e2e-25333/ai-work", .zh), "Claude 想在 ai-work 里运行一条命令")
        let close = AIAgentApproval(id: "b", title: "Close 3 tabs?", detail: "", options: [], kind: .closeTabs, subject: "3")
        XCTAssertEqual(AIStepWords.approval(close, agent: "Codex", folder: nil, .zh), "Codex 想关掉 3 个 tab")
        XCTAssertEqual(AIStepWords.approval(close, agent: "Codex", folder: nil, .en), "Codex wants to close 3 tabs")
        let unknown = AIAgentApproval(id: "c", title: "Use the frobnicator", detail: "", options: [])
        XCTAssertEqual(AIStepWords.approval(unknown, agent: nil, folder: nil, .zh), "agent 想：Use the frobnicator")
    }

    func testBrksNoticesTakeTheConversationsLanguage() {
        XCTAssertEqual(AIWords.refreshed("商品价格监控", at: "11:32", summary: "水壶降了 €4.50", .zh), "11:32 已更新 · 水壶降了 €4.50")
        XCTAssertEqual(AIWords.refreshed("Price Watch", at: "11:32", summary: nil, .en), "11:32 Updated “Price Watch”")
        XCTAssertEqual(AIWords.with(["Steel Kettle", AIWords.group("Shops", tabs: 3, .zh)], .zh), "附上 Steel Kettle · Shops（3 个 tab）")
        XCTAssertEqual(AIWords.stopped(.en), "Stopped.")
        XCTAssertEqual(AIWords.clock(Instant(milliseconds: 1_790_000_000_000), calendar: Driver.calendar), "14:13")
    }

    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        d.system(.aiAgents([AIAgentStatus(kind: .claude, state: .ready), AIAgentStatus(kind: .codex, state: .ready)]))
        return d
    }

    func testTabsGivenInAChineseConversationAreNamedInChinese() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        d.user(.assist(.attach([.tab(a.rawValue)])))
        d.user(.assist(.followUp("帮我总结这个页面")))
        let notices: [String] = d.view.ai?.conversation?.items.compactMap { item -> String? in if case .notice(let text) = item { text } else { nil } } ?? []
        XCTAssertEqual(notices.count, 1)
        XCTAssertTrue(notices[0].hasPrefix("附上 "), "\(notices)")
    }

    func testAFoldersFirstNoticeTakesTheLanguageOfTheFirstMessage() throws {
        let d = enabled()
        d.system(.aiFolderChosen(d.window, "/tmp/project"))
        XCTAssertEqual(d.view.ai?.conversation?.items, [.notice(AIWords.workingIn("/tmp/project", .en))], "before the user writes: the system's language")
        d.user(.assist(.followUp("看看这个文件夹里有什么")))
        XCTAssertEqual(d.view.ai?.conversation?.items.first, .notice(AIWords.workingIn("/tmp/project", .zh)))
        XCTAssertEqual(AIWords.reword("Something the agent said.", to: .zh), "Something the agent said.")
        XCTAssertEqual(AIWords.reword(AIWords.cannotReadTabs(.zh), to: .en), AIWords.cannotReadTabs(.en))
    }

    func testNewConversationPutsTheShownOneAwayAndStartsAFreshOne() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        d.user(.assist(.attach([.tab(a.rawValue)])))
        d.user(.assist(.followUp("What is this?")))
        let first = try XCTUnwrap(d.view.ai?.conversation?.id)
        d.system(.aiResult(first, .text("A page.")))
        XCTAssertEqual(d.view.ai?.name, "What is this?", "a conversation is called by its first message until it has a name")
        d.user(.assist(.newConversation))
        let fresh = try XCTUnwrap(d.view.ai?.conversation)
        XCTAssertNotEqual(fresh.id, first)
        XCTAssertTrue(fresh.fresh && fresh.tabs)
        XCTAssertEqual(fresh.items, [])
        XCTAssertNotNil(d.state.savedConversations[first], "the first one is kept, its tab shows it")
    }

    func testAPagesScheduleReachesThePanel() throws {
        let d = enabled()
        let t = d.user(.assist(.ask("盯着价格")))
        let id = try XCTUnwrap(t.effects.lazy.compactMap { if case .ai(let id, _, _) = $0 { id } else { nil } }.first)
        d.system(.aiConversation(id, .started(agent: .claude, name: "Claude", model: "Haiku 5.5", effort: nil)))
        let page = AIPageID("page-1")
        d.system(.aiConversation(id, .page(AIPageRecord(id: page, title: "商品价格监控", html: URL(fileURLWithPath: "/tmp/brk-test-pages/page-1.html"), height: 200,
                                                        data: #"{"items":[]}"#, conversation: id, profile: .default, createdAt: T0, readPages: true,
                                                        schema: #"{"type":"object"}"#, sources: []))))
        XCTAssertNil(d.view.ai?.pages.first?.schedule)
        d.system(.agentAct(AgentActRequest(call: "save", window: d.window, act: .keepPage(page, title: nil, conversation: id, live: [.schedule(.hourly)]))))
        XCTAssertEqual(d.view.ai?.pages.first?.schedule, .hourly)
    }
}
