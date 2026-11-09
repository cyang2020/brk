import BrkBase
@testable import BrkDomain
import XCTest

/// Conversation lists in the reducer (docs/design/ai-threads.md): the panel's two pages, one list per Space that follows
/// the window's Space, what waits in other Spaces (strip, ring, count, notification), the list's search and row menu, the
/// Library's "AI 对话" page, and the command bar's candidates.
final class ConversationListsTests: XCTestCase {
    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        return d
    }
    private func firstTurn(_ t: Transition) throws -> AIRequestID {
        for case .ai(let id, _, _) in t.effects { return id }
        throw XCTSkip("no AI request in \(t.effects)")
    }
    private func turn(_ t: Transition) throws -> AIRequestID {
        for case .aiTurn(_, let turn, _) in t.effects { return turn }
        throw XCTSkip("no turn in \(t.effects)")
    }
    /// Asks in the window's Space and answers; the conversation's id.
    private func answered(_ d: Driver, _ question: String, answer: String = "Done.") throws -> AIRequestID {
        let id = try firstTurn(d.user(.assist(.ask(question))))
        d.system(.aiResult(id, .text(answer)))
        return id
    }
    private func approval(_ id: String = "a") -> AIAgentApproval {
        AIAgentApproval(id: id, title: "Run: ls", detail: "ls", options: [.init(id: "once", title: "Allow", kind: .allowOnce), .init(id: "no", title: "Deny", kind: .deny)], kind: .command, subject: "ls")
    }
    private func rows(_ d: Driver) -> [AIThreadRow] { d.view.aiPanel?.groups.flatMap(\.rows) ?? [] }
    private func row(of id: AIRequestID, _ d: Driver) -> TabRow? { d.allTabRows.first { $0.url == ConversationPage.url(id) } }

    // MARK: Two pages

    func testThePanelHasTheListBeforeTheConversationAndMovesBetweenThem() throws {
        let d = enabled()
        let id = try answered(d, "这几个 tab 哪个最便宜")
        let panel = try XCTUnwrap(d.view.aiPanel)
        XCTAssertEqual(panel.page, .conversation, "an answer opens the conversation page")
        XCTAssertTrue(panel.hasConversation)
        XCTAssertEqual(panel.spaceTitle, d.view.space.title)
        d.user(.assist(.panelPage(.list)))
        XCTAssertEqual(d.view.aiPanel?.page, .list)
        XCTAssertEqual(d.view.ai?.conversation?.id, id, "the conversation stays where it is, one page to the right")
        XCTAssertEqual(rows(d).map(\.id), [id])
        XCTAssertTrue(rows(d)[0].current)
        XCTAssertEqual(d.view.aiPanel?.groups.first?.title, "今天", "the list's own words follow the most recent conversation's language")
        d.user(.assist(.panelPage(.conversation)))
        XCTAssertEqual(d.view.aiPanel?.page, .conversation)
        d.user(.assist(.dismiss))
        XCTAssertNil(d.view.aiPanel, "Close closes the panel, whichever page it is on")
        XCTAssertNil(d.view.ai)
    }

    func testOptionCommandAOrTheCommandBarOpensTheListWithThePanelClosed() {
        let spec = ActionID.aiConversations.spec
        XCTAssertEqual(spec.bindings.map(\.chord), [KeyChord([.option, .command], .a)])
        XCTAssertEqual(KeyMap().lookup(KeyChord([.option, .command], .a))?.action, .aiConversations)
        XCTAssertTrue(spec.commandBar?.triggers.contains("AI 对话") == true, "the command bar finds it by its Chinese name too")
        let d = enabled()
        XCTAssertNil(d.view.aiPanel)
        d.user(spec.command)
        XCTAssertEqual(d.view.aiPanel?.page, .list)
    }

    func testTheListIconOpensAClosedPanelOnTheListAndCloseClosesIt() {
        let d = enabled()
        XCTAssertNil(d.view.aiPanel)
        d.user(.assist(.panelPage(.list)))
        let panel = d.view.aiPanel
        XCTAssertEqual(panel?.page, .list)
        XCTAssertEqual(panel?.hasConversation, false)
        XCTAssertEqual(panel?.groups, [])
        d.user(.assist(.panelPage(.conversation)))
        XCTAssertEqual(d.view.aiPanel?.page, .list, "nothing to show on the conversation page")
        d.user(.assist(.dismiss))
        XCTAssertNil(d.view.aiPanel)
    }

    func testTheListComposerStartsANewConversationInThisSpace() throws {
        let d = enabled()
        d.user(.assist(.panelPage(.list)))
        let t = d.user(.assist(.listAsk("比较三款降噪耳机")))
        let id = try firstTurn(t)
        XCTAssertEqual(d.view.aiPanel?.page, .conversation)
        XCTAssertEqual(d.state.savedConversations[id]?.space, d.view.space.id)
        XCTAssertNotNil(row(of: id, d), "its row is in this Space's Today")
        d.user(.assist(.panelPage(.list)))
        XCTAssertEqual(d.view.aiPanel?.groups.first?.kind, .running, "a turn that runs is 进行中")
        XCTAssertEqual(rows(d).first?.state, .running)
    }

    // MARK: One list per Space

    func testSwitchingSpacePutsTheConversationAwayAndBringsTheOtherSpacesBack() throws {
        let d = enabled()
        let home = d.view.space.id
        let shopping = try answered(d, "盯着这三个商品页的价格")
        let work = d.newSpace("工作")
        XCTAssertEqual(d.view.aiPanel?.page, .list, "a Space never visited shows its list")
        XCTAssertNil(d.view.ai, "the other Space's conversation left the panel")
        XCTAssertEqual(rows(d), [], "only this Space's conversations")
        let feishu = try answered(d, "把这几个 tab 总结成飞书文档")
        XCTAssertEqual(d.state.savedConversations[feishu]?.space, work)
        d.user(.space(.focus(home)))
        XCTAssertEqual(d.view.ai?.conversation?.id, shopping, "back to the conversation that Space showed last")
        XCTAssertEqual(d.view.aiPanel?.page, .conversation)
        XCTAssertEqual(rows(d).map(\.id), [shopping])
        d.user(.assist(.panelPage(.list)))
        d.user(.space(.focus(work)))
        XCTAssertEqual(d.view.ai?.conversation?.id, feishu)
        d.user(.space(.focus(home)))
        XCTAssertEqual(d.view.aiPanel?.page, .list, "each Space keeps the page it was left on")
        XCTAssertEqual(d.view.ai?.conversation?.id, shopping)
    }

    func testARunningTurnGoesOnOutOfSightWhenTheWindowMovesToAnotherSpace() throws {
        let d = enabled()
        let home = d.view.space.id
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        let t = d.user(.space(.create(title: "Other", icon: .none, theme: .default, profile: .default)))
        XCTAssertFalse(t.effects.contains(.aiCancel(id)), "\(t.effects)")
        XCTAssertFalse(t.effects.contains(.aiCloseConversation(id)))
        d.system(.aiResult(id, .text("Because.")))
        XCTAssertEqual(d.state.savedConversations[id]?.items.last, .assistant("Because."))
        XCTAssertEqual(d.view.aiPanel?.strips.map(\.id), [id], "its reply waits for the user, shown from the other Space")
        XCTAssertEqual(d.view.aiPanel?.strips.first?.state, .unread)
        XCTAssertEqual(d.view.dock.first { $0.id == home }?.attention, true)
    }

    func testAnotherProfilesSpaceDoesNotCancelTheTurnAndListsNothingOfTheFirst() throws {
        let d = enabled()
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.state.doc.profiles.values.first { $0.name == "Work" }?.id)
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        let t = d.user(.space(.create(title: "Office", icon: .none, theme: .default, profile: work)))
        XCTAssertFalse(t.effects.contains(.aiCancel(id)), "the turn belongs to its own profile: \(t.effects)")
        d.system(.aiResult(id, .text("Because.")))
        XCTAssertEqual(d.state.savedConversations[id]?.items.last, .assistant("Because."))
        XCTAssertEqual(d.view.aiPanel?.strips, [], "other profiles' conversations never show")
        XCTAssertEqual(d.view.aiPanel?.waiting, 0)
    }

    // MARK: What waits elsewhere

    func testAnApprovalInAnotherSpaceShowsAsStripRingAndCountAndClearsOnceAnswered() throws {
        let d = enabled()
        let home = d.view.space.id
        let work = d.newSpace("工作")
        let id = try firstTurn(d.user(.assist(.ask("把这几个 tab 总结成飞书文档"))))
        d.user(.space(.focus(home)))
        let t = d.system(.aiConversation(id, .approval(approval(), turn: id)))
        XCTAssertTrue(t.effects.contains { if case .aiNotify(let n) = $0 { n.conversation == id && n.kind == .approval } else { false } }, "\(t.effects)")
        d.user(.assist(.panelPage(.list)))
        let strip = try XCTUnwrap(d.view.aiPanel?.strips.first)
        XCTAssertEqual(strip.id, id)
        XCTAssertEqual(strip.spaceTitle, "工作")
        XCTAssertEqual(strip.state, .waiting)
        XCTAssertEqual(strip.pill, "等你确认")
        XCTAssertEqual(strip.detail, "想运行一条命令")
        XCTAssertEqual(d.view.aiPanel?.waiting, 1)
        XCTAssertEqual(d.view.dock.first { $0.id == work }?.attention, true, "the waiting Space's dot rings")
        XCTAssertEqual(d.view.dock.first { $0.id == home }?.attention, false)
        // The strip's click: that Space, the conversation in the panel with its approval.
        d.user(.assist(.showConversation(id)))
        XCTAssertEqual(d.view.space.id, work)
        XCTAssertEqual(d.view.ai?.conversation?.id, id)
        XCTAssertEqual(d.view.aiPanel?.page, .conversation)
        XCTAssertNotNil(d.view.ai?.conversation?.items.first { if case .approval(let a) = $0 { a.answer == nil } else { false } })
        d.user(.assist(.approve(approval: "a", option: "once")))
        d.system(.aiResult(id, .text("Written.")))
        d.user(.space(.focus(home)))
        XCTAssertEqual(d.view.aiPanel?.strips, [], "seen and answered: nothing waits")
        XCTAssertEqual(d.view.aiPanel?.waiting, 0)
        XCTAssertEqual(d.view.dock.first { $0.id == work }?.attention, false)
    }

    func testAReplyIsUnreadUntilItsConversationShows() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.user(.assist(.panelPage(.list)))
        d.advance(.seconds(30))
        d.system(.aiResult(id, .text("Because.")))
        XCTAssertEqual(rows(d).first?.state, .unread, "the list was up: nobody saw the reply")
        XCTAssertEqual(d.view.aiPanel?.groups.first?.kind, .needsUser)
        XCTAssertEqual(rows(d).first?.detail, "Replied just now")
        XCTAssertEqual(d.view.aiPanel?.waiting, 1)
        d.user(.assist(.panelPage(.conversation)))
        XCTAssertEqual(rows(d).first?.state, .idle)
        XCTAssertEqual(d.view.aiPanel?.waiting, 0)
    }

    func testAReplyThatTookAMinuteAsksForANotification() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.advance(.seconds(30))
        var t = d.system(.aiResult(id, .text("Quick.")))
        XCTAssertFalse(t.effects.contains { if case .aiNotify = $0 { true } else { false } })
        let next = try turn(d.user(.assist(.followUp("And then?"))))
        d.advance(.seconds(75))
        t = d.system(.aiResult(next, .text("Slow.")))
        let notice = try XCTUnwrap(t.effects.lazy.compactMap { if case .aiNotify(let n) = $0 { n } else { nil } }.first)
        XCTAssertEqual(notice.kind, .replied)
        XCTAssertEqual(notice.body, "Slow.")
        XCTAssertEqual(notice.title, "Why?")
    }

    // MARK: Archived, rename, move, delete

    func testAnArchivedConversationIsGreyAndComesBackOnClick() throws {
        let d = enabled()
        let id = try answered(d, "Why?")
        let tab = try XCTUnwrap(row(of: id, d))
        d.user(.assist(.dismiss))
        d.user(.tab(.archive(.item(tab.id))))
        XCTAssertNil(row(of: id, d))
        d.user(.assist(.panelPage(.list)))
        XCTAssertEqual(rows(d).first?.state, .archived)
        XCTAssertEqual(rows(d).first?.detail, "Archived")
        d.user(.assist(.showConversation(id)))
        XCTAssertNotNil(row(of: id, d), "its row is back")
        XCTAssertEqual(d.view.ai?.conversation?.id, id)
        XCTAssertEqual(d.view.ai?.conversation?.dormant, true, "shown from its transcript; the next message continues it")
        XCTAssertEqual(rows(d).first?.state, .idle)
    }

    func testTheRowMenuRenamesArchivesRestoresMovesAndAsksBeforeDeleting() throws {
        let d = enabled()
        let id = try answered(d, "Why?")
        let other = d.newSpace("Other")
        d.user(.space(.focus(d.state.doc.spaceOrder.first!)))
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.conversation(id), at: .zero)))))
        XCTAssertEqual(layout(menu), ["Open in Tab", "Rename", "Archive", "Move to Another Space ▸", "|", "Delete for Good…"])
        XCTAssertEqual(command(submenu(menu, "Move to Another Space")!, "Other"), .assist(.moveConversation(id, other)))
        d.user(.assist(.beginRenameConversation(id)))
        XCTAssertEqual(d.view.aiPanel?.renaming, id)
        d.user(.assist(.renameConversation(id, "价格")))
        XCTAssertNil(d.view.aiPanel?.renaming)
        XCTAssertEqual(row(of: id, d)?.title, "价格")
        XCTAssertEqual(d.state.savedConversations[id]?.title, "价格")
        d.user(.assist(.renameConversation(id, nil)))
        XCTAssertEqual(row(of: id, d)?.title, "价格", "nil cancels")
        d.user(.assist(.archiveConversation(id)))
        XCTAssertNil(row(of: id, d))
        XCTAssertEqual(titles(try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.conversation(id), at: .zero)))))).contains("Restore"), true)
        d.user(.assist(.restoreConversation(id)))
        XCTAssertNotNil(row(of: id, d))
        d.user(.assist(.moveConversation(id, other)))
        XCTAssertEqual(d.state.conversationPlaces(.default)[id]?.space, other, "its row went to the other Space's Today")
        XCTAssertNotNil(d.state.conversationPlaces(.default)[id]?.row)
        d.user(.assist(.panelPage(.list)))
        XCTAssertEqual(rows(d), [], "the list of the Space it left")
        d.user(.library(.requestDeleteConversation(id)))
        let request = try XCTUnwrap(d.view.pendingConversationDeletion)
        XCTAssertEqual(request.id, id)
        d.user(.library(.confirmDeleteConversation(id, token: request.token, confirmed: false)))
        XCTAssertNotNil(d.state.savedConversations[id], "Cancel keeps it")
        d.user(.library(.requestDeleteConversation(id)))
        let again = try XCTUnwrap(d.view.pendingConversationDeletion)
        d.user(.library(.confirmDeleteConversation(id, token: again.token, confirmed: true)))
        XCTAssertNil(d.state.savedConversations[id])
        XCTAssertNil(row(of: id, d))
        XCTAssertNil(d.view.pendingConversationDeletion)
    }

    // MARK: Search

    func testTheListSearchesTitlesAndWhatWasSaid() throws {
        let d = enabled()
        let kettle = try answered(d, "盯着这三个商品页的价格", answer: "电热水壶降了 €4.50，烤面包机没变。")
        _ = try answered(d, "这家店能退货吗", answer: "可以，30 天内。")
        d.user(.assist(.panelPage(.list)))
        d.user(.assist(.listSearch("烤面包机")))
        XCTAssertEqual(rows(d).map(\.id), [kettle], "found in what was said")
        XCTAssertEqual(rows(d).first?.snippet?.contains("烤面包机"), true)
        d.user(.assist(.listSearch("")))
        XCTAssertEqual(rows(d).count, 2)
    }

    func testTheLibraryPageSearchesEverySpaceFiltersAndSelects() throws {
        let d = enabled()
        let home = d.view.space.id
        let kettle = try answered(d, "盯着这三个商品页的价格", answer: "the toaster stays at €24.50")
        let work = d.newSpace("工作")
        let feishu = try answered(d, "总结成飞书文档", answer: "done")
        d.user(.library(.open(.conversations)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no Library") }
        let page = try XCTUnwrap(library.conversations)
        XCTAssertEqual(Set(page.rows.map(\.id)), [kettle, feishu], "every Space of the profile")
        XCTAssertEqual(page.selected?.id, page.rows.first?.id, "the first one shows until another is chosen")
        XCTAssertEqual(page.spaces.map(\.id), [home, work])
        d.user(.library(.conversationQuery(ConversationLibraryQuery(text: "toaster"))))
        XCTAssertEqual(libraryRows(d), [kettle], "a word said only in the reply")
        d.user(.library(.conversationQuery(ConversationLibraryQuery(spaces: [work]))))
        XCTAssertEqual(libraryRows(d), [feishu])
        d.user(.library(.selectConversation(kettle)))
        guard case .library(let again)? = d.view.overlay else { return XCTFail("the Library closed") }
        XCTAssertEqual(again.conversations?.selected?.id, kettle)
        XCTAssertTrue(again.conversations?.selected?.meta.hasPrefix(d.state.displayTitle(of: home)) == true)
        d.user(.library(.moveConversation(kettle, work)))
        guard case .library? = d.view.overlay else { return XCTFail("moving keeps the Library") }
        XCTAssertEqual(d.state.conversationPlaces(.default)[kettle]?.space, work)
        d.user(.assist(.showConversation(kettle)))
        XCTAssertNil(d.view.overlay, "Continue closes the Library")
        XCTAssertEqual(d.view.space.id, work)
        XCTAssertEqual(d.view.ai?.conversation?.id, kettle)
    }

    private func libraryRows(_ d: Driver) -> [AIRequestID] {
        guard case .library(let library)? = d.view.overlay else { return [] }
        return library.conversations?.rows.map(\.id) ?? []
    }

    func testCommandBarCandidatesCarryAllTheTextAndTheSpace() throws {
        let d = enabled()
        let id = try answered(d, "Why?", answer: String(repeating: "word ", count: 2_000) + "needle")
        d.user(.commandBar(.open(.newTab)))
        let candidate = try XCTUnwrap(d.bar?.conversations.first { $0.id == id })
        XCTAssertTrue(candidate.text.hasSuffix("needle"), "all that was said, past the old 6000 characters")
        XCTAssertEqual(candidate.space, d.view.space.title)
        XCTAssertEqual(ConversationSearch.search("needle", in: [candidate]).first?.0.id, id)
    }

    func testSearchFindsTheTitleFirstThenEveryWordSaid() {
        let a = ConversationCandidate(id: AIRequestID("a"), title: "Kettle prices", text: "nothing")
        let b = ConversationCandidate(id: AIRequestID("b"), title: "Other", text: "the kettle and the toaster")
        let c = ConversationCandidate(id: AIRequestID("c"), title: "Third", text: "the toaster only")
        XCTAssertEqual(ConversationSearch.search("kettle", in: [b, a, c]).map(\.0.id), [AIRequestID("a"), AIRequestID("b")])
        XCTAssertEqual(ConversationSearch.search("toaster kettle", in: [a, b, c]).map(\.0.id), [AIRequestID("b")])
        if case .text(let snippet)? = ConversationSearch.find("TOASTER", title: "x", text: "the toaster only") { XCTAssertEqual(snippet, "the toaster only") }
        else { XCTFail("case and accents are ignored") }
        XCTAssertNil(ConversationSearch.find("  ", title: "x", text: "y"))
    }

    // MARK: Words

    func testWordsFollowTheConversationsLanguage() {
        let ask = approval()
        XCTAssertEqual(AIThreadWords.wants(ask, .zh), "想运行一条命令")
        XCTAssertEqual(AIThreadWords.wants(ask, .en), "Wants to run a command")
        let now = Instant(milliseconds: 1_000_000_000)
        XCTAssertEqual(AIThreadWords.replied(Instant(milliseconds: now.milliseconds - 120_000), now: now, .zh), "2 分钟前回复了")
        XCTAssertEqual(AIThreadWords.replied(Instant(milliseconds: now.milliseconds - 120_000), now: now, .en), "Replied 2 min ago")
        XCTAssertEqual(AIThreadWords.listTitle("购物", .zh), "购物 的对话")
        XCTAssertEqual(AIThreadWords.pages(1, .zh), "1 个 AI 页面")
    }

    // MARK: AI names

    private func naming(_ t: Transition) -> (AIRequestID, AITask)? {
        for case .ai(let id, let task, _) in t.effects { if case .nameConversation = task { return (id, task) } }
        return nil
    }
    private func namesOn() -> Driver {
        let d = enabled()
        d.user(.settings(.max(.feature(.tabNames, true))))
        return d
    }

    func testTheFirstAnswerNamesTheConversationWithTheSmallModelInItsLanguage() throws {
        let d = namesOn()
        let id = try firstTurn(d.user(.assist(.ask("盯着这三个商品页的价格，每小时更新一次"))))
        let t = d.system(.aiResult(id, .text("好的，已经设好了。")))
        let (request, task) = try XCTUnwrap(naming(t), "one request for a name: \(t.effects)")
        guard case .nameConversation(let asked, let question, let answer, let language) = task else { return XCTFail() }
        XCTAssertEqual(asked, id)
        XCTAssertEqual(question, "盯着这三个商品页的价格，每小时更新一次")
        XCTAssertEqual(answer, "好的，已经设好了。")
        XCTAssertEqual(language, .zh)
        XCTAssertTrue(task.isBasic, "the basic channel, answered in a schema")
        d.system(.aiResult(request, .reply(.text("商品价格监控"))))
        XCTAssertEqual(d.state.savedConversations[id]?.title, "商品价格监控")
        XCTAssertEqual(row(of: id, d)?.title, "商品价格监控", "the sidebar row")
        XCTAssertEqual(d.view.ai?.name, "商品价格监控", "the panel's header")
        d.user(.assist(.panelPage(.list)))
        XCTAssertEqual(rows(d).first?.title, "商品价格监控", "the list")
        let next = try turn(d.user(.assist(.followUp("再加一个"))))
        XCTAssertNil(naming(d.system(.aiResult(next, .text("好。")))), "named once")
    }

    func testANameTheUserGaveIsNeverReplacedAndNothingIsAskedWithoutARouteOrWithNameTabsOff() throws {
        let d = namesOn()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.user(.assist(.renameConversation(id, "Mine")))
        XCTAssertNil(naming(d.system(.aiResult(id, .text("Because.")))), "the user named it")
        XCTAssertEqual(d.state.savedConversations[id]?.title, "Mine")
        // A name asked for before the user typed one does not replace it either.
        let other = try firstTurn(d.user(.assist(.ask("How?"))))
        let (request, _) = try XCTUnwrap(naming(d.system(.aiResult(other, .text("Like this.")))))
        let tab = try XCTUnwrap(row(of: other, d))
        d.user(.item(.rename(tab.id, title: "Typed")))
        d.system(.aiResult(request, .reply(.text("How To"))))
        XCTAssertEqual(row(of: other, d)?.title, "Typed")
        XCTAssertNotEqual(d.state.savedConversations[other]?.title, "How To")
        // Name Tabs off: the first message stays.
        let off = enabled()
        let plain = try firstTurn(off.user(.assist(.ask("Where?"))))
        XCTAssertNil(naming(off.system(.aiResult(plain, .text("Here.")))))
        // No agent and no key: nothing to ask.
        let none = Driver()
        for feature in AIFeature.allCases { none.user(.settings(.max(.feature(feature, true)))) }
        none.system(.aiProvidersDetected([.gemini]))
        none.user(.settings(.max(.provider(.gemini))))
        let lonely = try firstTurn(none.user(.assist(.ask("When?"))))
        XCTAssertNil(naming(none.system(.aiResult(lonely, .text("Now.")))), "Gemini has no basic route and there is no key")
        XCTAssertEqual(none.state.savedConversations[lonely]?.title, "When?")
    }

    // MARK: The + menu's agents

    func testTheMenusAgentListAndAChoiceForTheNextMessage() throws {
        let d = enabled()
        d.system(.aiAgents([AIAgentStatus(kind: .claude, state: .ready, models: [AIAgentModel(id: "haiku", name: "Haiku 5.5", isDefault: true), AIAgentModel(id: "opus", name: "Opus 5.5")]),
                            AIAgentStatus(kind: .codex, state: .ready, models: [AIAgentModel(id: "sol", name: "GPT-6 Sol")])]))
        let menu = try XCTUnwrap(d.view.aiAgents)
        XCTAssertEqual(menu.agents.map(\.kind), [.claude, .codex], "what Settings → Max lists")
        let id = try answered(d, "Why?")
        var t = d.user(.assist(.pickAgent(.codex, model: "sol")))
        XCTAssertTrue(t.effects.contains(.aiPick(id, AIAgentPick(kind: .codex, model: "sol"))), "\(t.effects)")
        XCTAssertEqual(d.view.ai?.conversation?.pick, AIAgentPick(kind: .codex, model: "sol"))
        XCTAssertEqual(d.state.savedConversations[id]?.pick, AIAgentPick(kind: .codex, model: "sol"), "kept for its next messages")
        XCTAssertTrue(d.user(.assist(.pickAgent(.codex, model: "nope"))).effects.isEmpty, "a model the agent does not offer")
        // Put away and shown again: the next message starts the chosen agent.
        d.user(.assist(.dismiss))
        d.user(.assist(.showConversation(id)))
        t = d.user(.assist(.followUp("And then?")))
        XCTAssertTrue(t.effects.contains(.aiPick(id, AIAgentPick(kind: .codex, model: "sol"))))
        XCTAssertTrue(t.effects.contains { if case .aiOpenConversation(id, _, .codex, _, _) = $0 { true } else { false } }, "\(t.effects)")
        // Before the first message of a new conversation.
        d.user(.assist(.newConversation))
        let fresh = try XCTUnwrap(d.view.ai?.conversation?.id)
        d.user(.assist(.pickAgent(.claude, model: "opus")))
        t = d.user(.assist(.followUp("Hi")))
        XCTAssertTrue(t.effects.contains { if case .ai(fresh, _, .claude) = $0 { true } else { false } }, "\(t.effects)")
        XCTAssertEqual(d.state.savedConversations[fresh]?.pick, AIAgentPick(kind: .claude, model: "opus"))
    }

    // MARK: Not in incognito

    func testAnIncognitoWindowHasNoList() throws {
        let d = enabled()
        _ = try answered(d, "Why?")
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.state.doc.windows.first { $0.value.kind == .incognito }?.key)
        d.user(.assist(.panelPage(.list)), in: window)
        XCTAssertNil(d.view(of: window).aiPanel)
        d.user(.assist(.ask("x")), in: window)
        XCTAssertNil(d.view(of: window).aiPanel, "only the notice, no list of anyone's conversations")
        XCTAssertNotNil(d.view(of: window).ai)
    }
}
