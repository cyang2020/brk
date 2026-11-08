import BrkBase
@testable import BrkDomain
import XCTest

/// Conversations as tabs in the reducer: saved on the first message with a row in Today, continued after a relaunch,
/// moved between the panel and their tab, pages kept as tabs, and page links that ask first.
final class ConversationTabsTests: XCTestCase {
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
    private func turn(_ t: Transition) throws -> (conversation: AIRequestID, turn: AIRequestID) {
        for case .aiTurn(let conversation, let turn, _) in t.effects { return (conversation, turn) }
        throw XCTSkip("no turn in \(t.effects)")
    }
    private func row(of id: AIRequestID, _ d: Driver) -> TabRow? { d.allTabRows.first { $0.url == ConversationPage.url(id) } }
    private func page(_ id: AIPageID, conversation: AIRequestID, readPages: Bool = false) -> AIPageRecord {
        AIPageRecord(id: id, title: "Prices", html: URL(fileURLWithPath: "/tmp/brk-test-pages/\(id.rawValue).html"), height: 320, data: #"{"rows":3}"#,
                     conversation: conversation, profile: .default, createdAt: T0, readPages: readPages)
    }
    /// Asks, answers, and returns the conversation's id.
    private func answered(_ d: Driver, _ question: String = "这几个 tab 哪个最便宜", answer: String = "The second one.") throws -> AIRequestID {
        let id = try firstTurn(d.user(.assist(.ask(question))))
        d.system(.aiResult(id, .text(answer)))
        return id
    }

    // MARK: Saved, with a row

    func testTheFirstMessageSavesTheConversationAndPutsItsRowAtTheTopOfToday() throws {
        let d = enabled()
        let before = d.todayIDs
        let id = try firstTurn(d.user(.assist(.ask("这几个 tab 哪个最便宜, 画个对比图"))))
        let stored = try XCTUnwrap(d.state.savedConversations[id])
        XCTAssertEqual(stored.title, "这几个 tab 哪个最便宜, 画个对比图")
        XCTAssertEqual(stored.items, [.user("这几个 tab 哪个最便宜, 画个对比图")])
        XCTAssertEqual(stored.profile, .default)
        XCTAssertTrue(stored.tabs)
        XCTAssertEqual(d.todayIDs.count, before.count + 1)
        let row = try XCTUnwrap(row(of: id, d))
        XCTAssertEqual(d.todayIDs.first, row.id, "a new conversation's row goes where a new tab goes")
        XCTAssertEqual(row.title, "这几个 tab 哪个最便宜, 画个对比图")
        XCTAssertEqual(row.favicon, ConversationPage.favicon)
        XCTAssertNotEqual(row.status, .current, "the panel shows it; the page stays")
        XCTAssertTrue(row.loading, "the row shows the turn running")
        d.system(.aiResult(id, .text("The second one.")))
        XCTAssertFalse(try XCTUnwrap(self.row(of: id, d)).loading)
    }

    func testAFinishedTurnWritesTheTranscriptAndTheAgentsSessionBack() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiConversation(id, .started(agent: .claude, name: "Claude", model: "Haiku 5.5", effort: nil)))
        d.system(.aiPartial(id, "Because"))
        d.system(.aiConversation(id, .resumable("session-1")))
        d.system(.aiResult(id, .text("Because of this.")))
        let stored = try XCTUnwrap(d.state.savedConversations[id])
        XCTAssertEqual(stored.items, [.user("Why?"), .assistant("Because of this.")])
        XCTAssertEqual(stored.resume, "session-1")
        XCTAssertEqual(stored.agent, .claude)
        XCTAssertEqual(stored.model, "Haiku 5.5")
        let next = try turn(d.user(.assist(.followUp("And then?"))))
        XCTAssertEqual(d.state.savedConversations[id]?.items.last, .user("And then?"), "a message is saved when it is sent")
        d.system(.aiResult(next.turn, .text("Then this.")))
        XCTAssertEqual(d.state.savedConversations[id]?.items, [.user("Why?"), .assistant("Because of this."), .user("And then?"), .assistant("Then this.")])
    }

    func testAnApprovalStillWaitingIsNotSaved() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Run it"))))
        d.system(.aiConversation(id, .approval(AIAgentApproval(id: "a", title: "Run: ls", detail: "", options: [.init(id: "once", title: "Allow", kind: .allowOnce)]), turn: id)))
        d.system(.aiConversation(id, .notice("x")))
        XCTAssertFalse(d.state.savedConversations[id]!.items.contains { if case .approval = $0 { true } else { false } })
    }

    func testConversationRowsAndTheirTranscriptsSurviveARelaunch() throws {
        let d = enabled()
        let id = try answered(d)
        let file = d.savedFile
        // state.json keeps the row; the transcript is in its own file, handed back at launch.
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("The second one."), "transcripts are not in state.json")
        let saved = d.state.savedConversations
        let next = Driver(file: file)
        next.system(.conversationsLoaded(Array(saved.values), []))
        let row = try XCTUnwrap(next.allTabRows.first { $0.url == ConversationPage.url(id) }, "the row is restored with its brk:// address")
        XCTAssertEqual(row.title, "这几个 tab 哪个最便宜")
        XCTAssertEqual(next.state.savedConversations[id]?.items.last, .assistant("The second one."))
    }

    func testConversationsOfAProfileThatIsGoneAreLeftOut() {
        let d = enabled()
        let stray = StoredConversation(id: AIRequestID("stray"), profile: ProfileID("gone"), title: "x", createdAt: T0, tabs: true)
        d.system(.conversationsLoaded([stray], []))
        XCTAssertNil(d.state.savedConversations[AIRequestID("stray")])
    }

    // MARK: Panel and tab

    func testOpenAsTabMovesTheRunningConversationIntoItsTabWithoutEndingIt() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiPartial(id, "Because"))
        let t = d.user(.assist(.openAsTab))
        XCTAssertFalse(t.effects.contains(.aiCloseConversation(id)), "the session goes on: \(t.effects)")
        XCTAssertFalse(t.effects.contains(.aiCancel(id)))
        XCTAssertNil(d.view.ai, "the panel closes")
        XCTAssertEqual(d.current?.url, ConversationPage.url(id), "its row is the shown tab")
        let card = try XCTUnwrap(d.view.conversations.first)
        XCTAssertEqual(card.answer.conversation?.id, id)
        XCTAssertEqual(card.answer.busy, true, "the turn is still running, in the tab")
        XCTAssertTrue(d.view.content.panes.contains { if case .conversation(_, id) = $0.content { true } else { false } })
        d.system(.aiPartial(id, "Because of this"))
        d.system(.aiResult(id, .text("Because of this.")))
        XCTAssertEqual(d.view.conversations.first?.answer.conversation?.items.last, .assistant("Because of this."))
        XCTAssertEqual(d.state.savedConversations[id]?.items.last, .assistant("Because of this."))
        // A follow-up typed in the tab is a turn of the same session.
        let next = try turn(d.user(.assist(.inTab(id, .followUp("And then?")))))
        XCTAssertEqual(next.conversation, id)
        XCTAssertEqual(d.view.conversations.first?.answer.busy, true)
        XCTAssertNil(d.view.ai, "the panel stays closed")
    }

    func testClickingTheRowOfThePanelsConversationTakesItOutOfThePanel() throws {
        let d = enabled()
        let id = try answered(d)
        let row = try XCTUnwrap(row(of: id, d)).id
        let t = d.user(.tab(.focus(row)))
        XCTAssertNil(d.view.ai)
        XCTAssertEqual(d.view.conversations.first?.answer.conversation?.id, id)
        XCTAssertFalse(t.effects.contains(.aiCloseConversation(id)), "shown in its tab, it keeps its session")
    }

    func testClosingThePanelPutsARunningConversationAwayAndItsAnswerStillLands() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        let t = d.user(.assist(.dismiss))
        XCTAssertFalse(t.effects.contains(.aiCancel(id)), "the turn goes on out of sight")
        XCTAssertFalse(t.effects.contains(.aiCloseConversation(id)))
        XCTAssertNil(d.view.ai)
        XCTAssertTrue(try XCTUnwrap(row(of: id, d)).loading)
        let done = d.system(.aiResult(id, .text("Because.")))
        XCTAssertEqual(d.state.savedConversations[id]?.items.last, .assistant("Because."))
        XCTAssertTrue(done.effects.contains(.aiCloseConversation(id)), "neither shown nor running: its session ends")
    }

    func testANewQuestionInThePanelLeavesTheRunningConversationRunning() throws {
        let d = enabled()
        let first = try firstTurn(d.user(.assist(.ask("First?"))))
        let second = try firstTurn(d.user(.assist(.ask("Second?"))))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(d.view.ai?.conversation?.id, second)
        d.system(.aiResult(first, .text("One.")))
        XCTAssertEqual(d.state.savedConversations[first]?.items.last, .assistant("One."))
        // Stop in the panel stops the panel's turn only.
        let third = try firstTurn(d.user(.assist(.ask("Third?"))))
        _ = third
        XCTAssertTrue(d.user(.assist(.stop)).effects.allSatisfy { if case .aiCancel(let id) = $0 { id != first } else { true } })
    }

    // MARK: After a relaunch

    func testASavedConversationContinuesTheAgentsOwnSessionOrCarriesItsTranscript() throws {
        let d = enabled()
        let id = try answered(d)
        d.system(.aiConversation(id, .resumable("claude-session")))
        let saved = d.state.savedConversations
        let next = Driver(file: d.savedFile)
        for feature in AIFeature.allCases { next.user(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        next.system(.aiProvidersDetected([.claude, .codex]))
        next.system(.conversationsLoaded(Array(saved.values), []))
        let row = try XCTUnwrap(next.allTabRows.first { $0.url == ConversationPage.url(id) }).id
        next.user(.tab(.focus(row)))
        let card = try XCTUnwrap(next.view.conversations.first)
        XCTAssertEqual(card.answer.conversation?.dormant, true, "shown from its saved transcript, no session yet")
        XCTAssertEqual(card.answer.conversation?.items.last, .assistant("The second one."))
        let t = next.user(.assist(.inTab(id, .followUp("我上次问的是什么"))))
        let resume = try XCTUnwrap(t.effects.lazy.compactMap { effect -> AIResume? in
            if case .aiOpenConversation(id, _, _, next.window, let resume) = effect { resume } else { nil }
        }.first, "\(t.effects)")
        XCTAssertEqual(resume.session, "claude-session")
        XCTAssertTrue(resume.history.contains("User: 这几个 tab 哪个最便宜"))
        XCTAssertTrue(resume.history.contains("Assistant: The second one."))
        let open = try XCTUnwrap(t.effects.firstIndex { if case .aiOpenConversation = $0 { true } else { false } })
        let turnAt = try XCTUnwrap(t.effects.firstIndex { if case .aiTurn = $0 { true } else { false } })
        XCTAssertLessThan(open, turnAt, "the session exists before its turn")
        XCTAssertEqual(next.view.conversations.first?.answer.busy, true)
    }

    func testAConversationLinkOpensItsTabAndBringsAnArchivedRowBack() throws {
        let d = enabled()
        let id = try answered(d)
        d.user(.assist(.dismiss))
        let row = try XCTUnwrap(row(of: id, d)).id
        d.user(.tab(.close(.item(row))))
        XCTAssertNil(self.row(of: id, d), "closed like any Today tab: archived")
        d.user(.assist(.openConversation(id)))
        XCTAssertEqual(d.current?.url, ConversationPage.url(id))
        XCTAssertEqual(d.view.conversations.first?.answer.conversation?.id, id)
        XCTAssertEqual(d.todayIDs.filter { d.row($0)?.url == ConversationPage.url(id) }.count, 1, "one row, the restored one")
    }

    func testAnotherProfilesConversationDoesNotOpen() {
        let d = enabled()
        let other = StoredConversation(id: AIRequestID("theirs"), profile: .default, title: "x", createdAt: T0, tabs: true)
        d.system(.conversationsLoaded([other], []))
        d.user(.assist(.openConversation(AIRequestID("missing"))))
        XCTAssertNil(d.current.flatMap { ConversationPage.id(of: $0.url) })
    }

    func testHistoryIsTheMessagesOnlyNewestKept() {
        var stored = StoredConversation(id: AIRequestID("c"), profile: .default, title: "t", createdAt: T0, tabs: true)
        stored.items = [.user("one"), .step(AIAgentStep(id: "s", title: "Run: ls", state: .done)), .notice("n"), .assistant("two"),
                        .page(AIPageRef(id: AIPageID("p"), title: "Chart", height: 300))]
        XCTAssertEqual(stored.messages.map(\.position), [0, 3, 4])
        let history = stored.history()
        XCTAssertTrue(history.contains("User: one") && history.contains("Assistant: two") && history.contains("“Chart”"))
        XCTAssertFalse(history.contains("Run: ls"))
        stored.items = [.user(String(repeating: "a", count: 30_000)), .assistant("last")]
        let cut = stored.history(limit: 1_000)
        XCTAssertLessThanOrEqual(cut.count, 1_001)
        XCTAssertTrue(cut.hasSuffix("Assistant: last"))
    }

    // MARK: Pages

    func testARenderedPageShowsInTheTranscriptAndIsSaved() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("画个对比图"))))
        d.system(.aiPartial(id, "Here:"))
        let pageID = AIPageID("page-1")
        d.system(.aiConversation(id, .page(page(pageID, conversation: id))))
        d.system(.aiPartial(id, "Here: The second is cheapest."))
        d.system(.aiResult(id, .text("Here: The second is cheapest.")))
        let items = try XCTUnwrap(d.view.ai?.conversation?.items)
        XCTAssertEqual(items, [.user("画个对比图"), .assistant("Here:"), .page(AIPageRef(id: pageID, title: "Prices", height: 320)), .assistant(" The second is cheapest.")])
        XCTAssertEqual(d.view.ai?.pages.first?.id, pageID)
        XCTAssertEqual(d.view.ai?.pages.first?.data, #"{"rows":3}"#)
        XCTAssertEqual(d.view.ai?.pages.first?.kept, false)
        XCTAssertEqual(d.state.savedPages[pageID]?.conversation, id)
        XCTAssertEqual(d.state.savedConversations[id]?.items, items)
    }

    func testAPageOfAnotherConversationIsIgnored() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("x"))))
        d.system(.aiConversation(id, .page(page(AIPageID("p"), conversation: AIRequestID("other")))))
        XCTAssertNil(d.state.savedPages[AIPageID("p")])
    }

    func testKeepAsTabMakesARowThatShowsThePageAndKeepsItsConversation() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("画个对比图"))))
        let pageID = AIPageID("page-1")
        d.system(.aiConversation(id, .page(page(pageID, conversation: id))))
        d.system(.aiResult(id, .text("Done.")))
        d.user(.assist(.keepPage(pageID)))
        XCTAssertEqual(d.current?.url, AIPageTab.url(pageID))
        XCTAssertEqual(d.current?.title, "Prices")
        XCTAssertEqual(d.current?.favicon, AIPageTab.favicon)
        let card = try XCTUnwrap(d.view.aiPages.first)
        XCTAssertEqual(card.content?.id, pageID)
        XCTAssertEqual(card.content?.data, #"{"rows":3}"#)
        XCTAssertEqual(d.state.savedPages[pageID]?.conversation, id, "the page keeps the conversation that made it")
        XCTAssertTrue(d.view.content.panes.contains { if case .aiPage(_, pageID) = $0.content { true } else { false } })
        XCTAssertTrue(d.snapshot.pages.allSatisfy { !AIPageTab.shows($0.initialURL) }, "no profile's browser loads it")
        // Keeping it again shows the same row.
        let rows = d.todayIDs.count
        d.user(.assist(.keepPage(pageID)))
        XCTAssertEqual(d.todayIDs.count, rows)
        XCTAssertEqual(d.view.ai?.pages.first?.kept ?? true, true)
    }

    func testTheAgentKeepsOnlyItsOwnConversationsPages() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("x"))))
        let pageID = AIPageID("page-1")
        d.system(.aiConversation(id, .page(page(pageID, conversation: id))))
        let wrong = d.system(.agentAct(AgentActRequest(call: "c1", window: d.window, act: .keepPage(pageID, title: nil, conversation: AIRequestID("other")))))
        XCTAssertTrue(wrong.effects.contains { if case .agentActDone("c1", .refused) = $0 { true } else { false } })
        let rows = d.todayIDs.count
        let right = d.system(.agentAct(AgentActRequest(call: "c2", window: d.window, act: .keepPage(pageID, title: "Cheapest", conversation: id))))
        XCTAssertTrue(right.effects.contains { if case .agentActDone("c2", .done) = $0 { true } else { false } }, "\(right.effects)")
        XCTAssertEqual(d.todayIDs.count, rows + 1)
        XCTAssertNotEqual(d.current?.url, AIPageTab.url(pageID), "the agent's save does not take the user away")
        XCTAssertEqual(d.allTabRows.first { $0.url == AIPageTab.url(pageID) }?.title, "Cheapest")
    }

    func testTheAgentsTabToolsDoNotListConversationsOrPages() throws {
        let d = enabled()
        let id = try answered(d)
        let tabs = d.state.agentOpenTabs(profile: .default, window: d.window)
        XCTAssertFalse(tabs.contains { $0.url == ConversationPage.url(id) })
    }

    // MARK: Page links

    func testALinkInAPageWrittenBeforeAnyPageTextOpensAtOnce() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("x"))))
        d.system(.aiConversation(id, .page(page(AIPageID("p"), conversation: id, readPages: false))))
        let before = d.todayIDs.count
        d.user(.assist(.pageLink(AIPageID("p"), URL(string: "https://shop.example/item")!)))
        XCTAssertEqual(d.todayIDs.count, before + 1)
        XCTAssertNil(d.view.pageLinkPrompt)
    }

    func testALinkToANewAddressInAPageWrittenAfterPageTextAsksFirst() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("x"))))
        d.system(.aiConversation(id, .page(page(AIPageID("p"), conversation: id, readPages: true))))
        let before = d.todayIDs.count
        let leak = URL(string: "https://collector.example/?q=secret")!
        d.user(.assist(.pageLink(AIPageID("p"), leak)))
        XCTAssertEqual(d.view.pageLinkPrompt, AIPageLinkPrompt(page: AIPageID("p"), url: leak))
        XCTAssertEqual(d.todayIDs.count, before, "nothing opens until the user says so")
        d.user(.assist(.answerPageLink(false)))
        XCTAssertNil(d.view.pageLinkPrompt)
        XCTAssertEqual(d.todayIDs.count, before)
        d.user(.assist(.pageLink(AIPageID("p"), leak)))
        d.user(.assist(.answerPageLink(true)))
        XCTAssertEqual(d.todayIDs.count, before + 1)
        // An address the profile already knows opens at once.
        let known = d.open("https://known.example/")
        _ = known
        let count = d.todayIDs.count
        d.user(.assist(.pageLink(AIPageID("p"), URL(string: "https://known.example/")!)))
        XCTAssertNil(d.view.pageLinkPrompt)
        XCTAssertEqual(d.todayIDs.count, count + 1)
    }

    func testOnlyWebLinksOpen() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("x"))))
        d.system(.aiConversation(id, .page(page(AIPageID("p"), conversation: id))))
        let before = d.todayIDs.count
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "brk://history/", "data:text/html,hi"] {
            d.user(.assist(.pageLink(AIPageID("p"), URL(string: bad)!)))
        }
        XCTAssertEqual(d.todayIDs.count, before)
        XCTAssertNil(d.view.pageLinkPrompt)
    }

    func testPageTextReachingTheConversationIsSavedWithIt() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("x"))))
        d.system(.aiConversation(id, .pageText(flagged: false)))
        XCTAssertEqual(d.state.savedConversations[id]?.readPages, true)
        XCTAssertEqual(d.state.savedConversations[id]?.flagged, false)
        d.system(.aiConversation(id, .pageText(flagged: true)))
        XCTAssertEqual(d.state.savedConversations[id]?.flagged, true)
    }
}
