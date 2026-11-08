import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Brk's agent tab tools in the reducer: what they see, what they change, and how tabs reach a conversation.
final class AgentToolsTests: XCTestCase {
    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, true)))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        return d
    }
    private func act(_ d: Driver, _ act: AgentAct, call: String = "c1") -> AgentActOutcome? {
        d.system(.agentAct(AgentActRequest(call: call, window: d.window, act: act))).effects.lazy.compactMap { effect -> AgentActOutcome? in
            if case .agentActDone(call, let outcome) = effect { outcome } else { nil }
        }.first
    }
    private func readDone(_ t: Transition, call: String = "r1") -> AgentReadOutcome? {
        t.effects.lazy.compactMap { if case .agentReadDone(call, let outcome) = $0 { outcome } else { nil } }.first
    }
    /// The current page's document, ready.
    private func ready(_ d: Driver) throws -> (PageID, DocumentToken) {
        let page = try XCTUnwrap(d.state.findPage(in: d.window))
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let doc = DocumentToken(browser: browser, sequence: d.state.session.live[page]!.documentSequence + 1)
        d.page(page.item, .documentChanged(.loading(doc)))
        d.page(page.item, .documentChanged(.ready(doc)))
        return (page, doc)
    }
    private func otherProfileSpace(_ d: Driver) throws -> (ProfileID, SpaceID, ItemID) {
        let home = d.view.space.id
        d.user(.profile(.create(name: "Work", icon: nil)))
        let other = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.id != .default }?.profile.id)
        let space = d.newSpace("Work")
        d.user(.profile(.assign(.current, to: other)))
        let tab = d.open("https://work.example/secret")
        d.user(.space(.focus(home)))
        return (other, space, tab)
    }

    // MARK: Seeing

    func testToolsSeeTheConversationsProfileOnlyAndNeverAPrivateWindow() throws {
        let d = enabled()
        let mine = d.open("https://mine.example/a")
        let (other, _, theirs) = try otherProfileSpace(d)
        let open = d.state.agentOpenTabs(profile: .default, window: d.window)
        XCTAssertTrue(open.contains { $0.id == mine.rawValue })
        XCTAssertFalse(open.contains { $0.id == theirs.rawValue }, "another profile's Space")
        XCTAssertEqual(d.state.agentTab(theirs.rawValue, window: d.window)?.profile, other, "found by id, with its profile, for the tools to refuse")
        XCTAssertFalse(d.state.agentHistory(profile: .default).contains { $0.url?.host == "work.example" })
        XCTAssertTrue(d.state.agentHistory(profile: other).contains { $0.url?.host == "work.example" })
        // A private window's tab lives in its own tree: no query reaches it, and its window has no agent.
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .incognito }?.key)
        XCTAssertNil(d.state.agentProfile(in: privateWindow))
        let privateTabs = d.view(of: privateWindow).space.today.rows.map(\.id)
        for id in privateTabs { XCTAssertNil(d.state.agentTab(id.rawValue, window: d.window)) }
    }

    func testArchiveAndHistoryAreTheProfilesAndHaveTheirOwnIds() throws {
        let d = enabled()
        let tab = d.open("https://archived.example/")
        d.user(.tab(.close(.item(tab))))
        let archived = try XCTUnwrap(d.state.agentArchivedTabs(profile: .default).first { $0.url?.host == "archived.example" })
        XCTAssertTrue(archived.id.hasPrefix(AgentTabID.archivePrefix))
        XCTAssertEqual(d.state.agentTab(archived.id, window: d.window), archived)
        let visit = try XCTUnwrap(d.state.agentHistory(profile: .default).first { $0.url?.host == "archived.example" })
        XCTAssertTrue(visit.id.hasPrefix(AgentTabID.historyPrefix))
        XCTAssertTrue(d.state.agentKnows(URL(string: "https://archived.example/")!, profile: .default))
        XCTAssertFalse(d.state.agentKnows(URL(string: "https://archived.example/?leak=1")!, profile: .default), "only the exact address is known")
    }

    // MARK: Reading

    func testReadingALoadedTabAsksItsPageAndAnswersTheCall() throws {
        let d = enabled()
        let (page, doc) = try ready(d)
        let t = d.system(.agentRead(AgentReadRequest(call: "r1", window: d.window, tab: page.item.rawValue, part: .text)))
        let id = try XCTUnwrap(t.effects.lazy.compactMap { if case .aiRead(let id, doc) = $0 { id } else { nil } }.first)
        XCTAssertNil(d.view.ai, "a tool's read writes nothing in the panel")
        let content = AIPageContent(document: doc, url: start, title: "Source", language: "en", text: "Body", nodes: [AITextNode(id: 0, text: "Body")])
        XCTAssertEqual(readDone(d.system(.aiPageRead(id, page, content))), .content(content))
        XCTAssertNil(d.state.session.ai.requests[id])
    }

    func testReadingAnArchivedTabLoadsItOutOfSight() throws {
        let d = enabled()
        let tab = d.open("https://archived.example/")
        d.user(.tab(.close(.item(tab))))
        let archived = try XCTUnwrap(d.state.agentArchivedTabs(profile: .default).first)
        d.system(.agentRead(AgentReadRequest(call: "r1", window: d.window, tab: archived.id, part: .text)))
        let reader = try XCTUnwrap(d.snapshot.pages.first(where: \.isAIReader))
        XCTAssertEqual(reader.initialURL, URL(string: "https://archived.example/"))
        XCTAssertEqual(reader.context, .profile(.default))
        let token = BrowserToken(page: reader.id, generation: 1)
        let doc = DocumentToken(browser: token, sequence: 1)
        let read = d.system(.page(token, .browserCreated(reader.context, .ready(doc))))
        let id = try XCTUnwrap(read.effects.lazy.compactMap { if case .aiRead(let id, doc) = $0 { id } else { nil } }.first)
        let content = AIPageContent(document: doc, url: URL(string: "https://archived.example/")!, title: "Old", language: "en", text: "Kept", nodes: [])
        XCTAssertEqual(readDone(d.system(.aiPageRead(id, reader.id, content))), .content(content))
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
    }

    /// A page loaded out of sight did not answer the reader in time on a real launch: it is read like one not loaded.
    func testALoadedTabOutOfSightIsReadByAHiddenReader() throws {
        let d = enabled()
        let back = d.open("https://back.example/")
        _ = d.open("https://front.example/")
        XCTAssertNotEqual(d.current?.id, back)
        let t = d.system(.agentRead(AgentReadRequest(call: "r1", window: d.window, tab: back.rawValue, part: .text)))
        XCTAssertFalse(t.effects.contains { if case .aiRead = $0 { true } else { false } }, "not its own page")
        XCTAssertEqual(d.snapshot.pages.first(where: \.isAIReader)?.initialURL, URL(string: "https://back.example/"))
    }

    func testSelectionComesFromTheLivePageAndAnUnknownTabFails() throws {
        let d = enabled()
        let (page, _) = try ready(d)
        XCTAssertEqual(readDone(d.system(.agentRead(AgentReadRequest(call: "r1", window: d.window, tab: page.item.rawValue, part: .selection)))), .selection(page))
        guard case .failed? = readDone(d.system(.agentRead(AgentReadRequest(call: "r1", window: d.window, tab: "nope", part: .text)))) else { return XCTFail("an unknown id") }
    }

    // MARK: Changing

    func testOpenFocusAndCloseRunTheSidebarsRules() throws {
        let d = enabled()
        guard case .done(_, let ids)? = act(d, .open(URL(string: "https://new.example/")!, space: nil, background: false)) else { return XCTFail("open") }
        let opened = ItemID(try XCTUnwrap(ids.first))
        XCTAssertEqual(d.todayIDs.first, opened)
        XCTAssertEqual(d.current?.id, opened)
        let other = d.open("https://second.example/")
        XCTAssertEqual(act(d, .focus(opened)), .done("Showing it now.", ids: [opened.rawValue]))
        XCTAssertEqual(d.current?.id, opened)
        guard case .done? = act(d, .close([other])) else { return XCTFail("close") }
        XCTAssertFalse(d.todayIDs.contains(other))
        XCTAssertTrue(d.archive().contains { $0.url?.host == "second.example" }, "a closed Today tab is archived")
        guard case .refused? = act(d, .open(URL(string: "file:///etc/passwd")!, space: nil, background: false)) else { return XCTFail("file address") }
    }

    func testMoveIntoANewFolderAndGroupWithTidysUndo() throws {
        let d = enabled()
        let a = d.open("https://a.example/"), b = d.open("https://b.example/"), c = d.open("https://c.example/")
        let space = d.view.space.id
        guard case .done(_, let made)? = act(d, .move([a, b], to: AgentDestination(space: space, newFolder: "Reading"))) else { return XCTFail("move") }
        let folder = ItemID(try XCTUnwrap(made.first))
        XCTAssertEqual(d.state.doc.tree[folder]?.children, [a, b])
        guard case .done? = act(d, .move([c], to: AgentDestination(space: space, section: .pinned))) else { return XCTFail("pin") }
        XCTAssertTrue(d.pinnedIDs.contains(c))
        guard case .done(_, let groups)? = act(d, .group(space: space, section: .today, [AgentGroup(name: "One", tabs: [a]), AgentGroup(name: "Two", tabs: [b])])) else { return XCTFail("group") }
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { d.state.doc.tree[ItemID($0)]?.children ?? [] }, [[a], [b]])
        XCTAssertNotNil(d.state.session.ai.undo[d.window], "Tidy's undo")
        guard case .refused? = act(d, .group(space: space, section: .today, [AgentGroup(name: "Dup", tabs: [a]), AgentGroup(name: "Dup2", tabs: [a])])) else { return XCTFail("a tab twice") }
    }

    func testSplitAndTheOtherProfilesTabsAreRefused() throws {
        let d = enabled()
        let a = d.open("https://a.example/"), b = d.open("https://b.example/")
        guard case .done(_, let ids)? = act(d, .split([a, b])) else { return XCTFail("split") }
        XCTAssertEqual(d.state.doc.tree.splitContaining(a).map(\.rawValue), ids.first)
        let (_, workSpace, theirs) = try otherProfileSpace(d)
        guard case .refused? = act(d, .close([theirs])) else { return XCTFail("another profile's tab") }
        guard case .refused? = act(d, .move([a], to: AgentDestination(space: workSpace))) else { return XCTFail("another profile's Space") }
        XCTAssertNotNil(d.state.doc.tree[theirs])
    }

    // MARK: Giving tabs to the conversation

    func testAskAIStartsAConversationWithChipsAndTheFirstMessageCarriesThem() throws {
        let d = enabled()
        let a = d.open("https://a.example/"), b = d.open("https://b.example/")
        d.user(.assist(.attach([.tab(a.rawValue), .tab(b.rawValue), .tab(a.rawValue)])))
        let conversation = try XCTUnwrap(d.view.ai?.conversation)
        XCTAssertTrue(conversation.fresh && conversation.tabs)
        XCTAssertEqual(conversation.attached.map(\.id), [a.rawValue, b.rawValue], "a tab given twice is one chip")
        XCTAssertEqual(d.view.ai?.busy, false, "nothing runs before the first message")
        d.user(.assist(.detach(b.rawValue)))
        XCTAssertEqual(d.view.ai?.conversation?.attached.map(\.id), [a.rawValue])
        let t = d.user(.assist(.followUp("Summarize these")))
        let id = conversation.id
        let open = try XCTUnwrap(t.effects.firstIndex(of: .aiOpenConversation(id, folder: nil, choice: .auto, tabs: d.window)))
        let attach = try XCTUnwrap(t.effects.firstIndex { if case .aiAttach(id, let list) = $0 { list.map(\.id) == [a.rawValue] } else { false } })
        let ask = try XCTUnwrap(t.effects.firstIndex(of: .ai(id, .ask("Summarize these"), choice: .auto)))
        XCTAssertTrue(open < attach && attach < ask, "\(t.effects)")
        XCTAssertEqual(d.view.ai?.title, "Summarize these")
        XCTAssertEqual(d.view.ai?.conversation?.attached, [])
        XCTAssertTrue(d.view.ai?.conversation?.items.contains { if case .notice(let text) = $0 { text.hasPrefix("With ") } else { false } } == true)
        d.system(.aiResult(id, .text("Done.")))
        // A follow-up with a new chip: the chip goes just before its turn.
        d.user(.assist(.attach([.tab(b.rawValue)])))
        let next = d.user(.assist(.followUp("And this one?")))
        let attach2 = try XCTUnwrap(next.effects.firstIndex { if case .aiAttach(id, _) = $0 { true } else { false } })
        let turn = try XCTUnwrap(next.effects.firstIndex { if case .aiTurn(id, _, _) = $0 { true } else { false } })
        XCTAssertLessThan(attach2, turn)
    }

    func testAFolderAndASpaceBecomeOneChipEach() throws {
        let d = enabled()
        let a = d.open("https://a.example/"), b = d.open("https://b.example/")
        guard case .done(_, let made)? = act(d, .move([a, b], to: AgentDestination(space: d.view.space.id, newFolder: "Docs"))) else { return XCTFail("folder") }
        d.user(.assist(.attach([.folder(ItemID(made[0])), .space(d.view.space.id)])))
        let chips = try XCTUnwrap(d.view.ai?.conversation?.attached)
        XCTAssertEqual(chips.map(\.kind), [.folder, .space])
        XCTAssertEqual(chips[0].tabs.map(\.id), [a.rawValue, b.rawValue])
        XCTAssertTrue(Set(chips[1].tabs.map(\.id)).isSuperset(of: [a.rawValue, b.rawValue]))
    }

    func testAnotherProfilesTabGivenByTheUserIsMarkedSo() throws {
        let d = enabled()
        let (_, _, theirs) = try otherProfileSpace(d)
        d.user(.assist(.attach([.tab(theirs.rawValue)])))
        XCTAssertEqual(d.view.ai?.conversation?.attached.first?.tabs.first?.otherProfile, true)
    }

    func testAFolderSessionTakesNoTabs() {
        let d = enabled()
        d.system(.aiFolderChosen(d.window, "/tmp/project"))
        let tab = d.open("https://a.example/")
        d.user(.assist(.attach([.tab(tab.rawValue)])))
        XCTAssertEqual(d.view.ai?.conversation?.folder, "/tmp/project")
        XCTAssertEqual(d.view.ai?.conversation?.attached, [])
        XCTAssertTrue(d.view.ai?.conversation?.items.contains { if case .notice(let text) = $0 { text.contains("cannot read tabs") } else { false } } == true)
    }

    func testAtListsMatchesByTitleThenAddressAndASearchCanAddMore() throws {
        let d = enabled()
        let docs = d.open("https://docs.example/guide")
        d.page(docs, .titleChanged("Swift Guide"))
        let other = d.open("https://example.org/swift")
        d.page(other, .titleChanged("Example"))
        d.user(.assist(.attach([.tab(other.rawValue)])))
        let t = d.user(.assist(.mention("swift")))
        XCTAssertTrue(t.effects.contains(.aiMentionSearch(d.window, "swift")))
        let matches = try XCTUnwrap(d.view.ai?.conversation?.mention?.matches.map(\.id))
        XCTAssertEqual(matches.first, docs.rawValue, "title first, then address")
        XCTAssertTrue(matches.contains(other.rawValue))
        let extra = d.open("https://unrelated.example/")
        d.system(.aiMentionMatches(d.window, query: "swift", [extra.rawValue]))
        XCTAssertEqual(d.view.ai?.conversation?.mention?.matches.last?.id, extra.rawValue)
        d.system(.aiMentionMatches(d.window, query: "old", [docs.rawValue]))
        d.user(.assist(.mention(nil)))
        XCTAssertNil(d.view.ai?.conversation?.mention)
    }

    func testAskAIIsTheLastRowOfTheSidebarMenusOnlyWithMaxsPanelOn() throws {
        func popup(_ t: Transition) -> MenuModel? { t.effects.lazy.compactMap { if case .popupMenu(_, let model, _) = $0 { model } else { nil } }.first }
        let plain = Driver()
        let tab = plain.open("https://a.example/")
        let arc = try XCTUnwrap(popup(plain.user(.sidebar(.popupMenu(.item(tab), at: .zero)))))
        XCTAssertFalse(arc.entries.contains { if case .action("Ask AI", _, _) = $0 { true } else { false } }, "Arc's menu as Arc has it")
        let d = enabled()
        let mine = d.open("https://b.example/")
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(mine), at: .zero)))))
        guard case .action("Ask AI", let command, true)? = menu.entries.last else { return XCTFail("\(menu.entries.last as Any)") }
        XCTAssertEqual(command, .assist(.attach([.tab(mine.rawValue)])))
        guard case .separator? = menu.entries.dropLast().last else { return XCTFail("a separator before it") }
        let space = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.space(d.view.space.id), at: .zero)))))
        guard case .action("Ask AI", .assist(.attach([.space(d.view.space.id)])), true)? = space.entries.last else { return XCTFail("the Space menu") }
    }

    func testATabLinkInAnAnswerShowsTheTabOrBringsItBack() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        let b = d.open("https://b.example/")
        d.user(.assist(.openTabLink(a.rawValue)))
        XCTAssertEqual(d.current?.id, a)
        d.user(.tab(.close(.item(b))))
        let archived = try XCTUnwrap(d.state.agentArchivedTabs(profile: .default).first { $0.url?.host == "b.example" })
        d.user(.assist(.openTabLink(archived.id)))
        XCTAssertTrue(d.allTabRows.contains { $0.url?.host == "b.example" }, "restored from the archive")
        let (_, _, theirs) = try otherProfileSpace(d)
        let before = d.current?.id
        d.user(.assist(.openTabLink(theirs.rawValue)))
        XCTAssertEqual(d.current?.id, before, "another profile's tab is not shown from here")
    }

    func testTabLinksRoundTrip() {
        let link = AgentTabLink.markdown("item-7", title: "A [weird] title")
        XCTAssertEqual(link, "[A (weird) title](brk://tab/item-7)")
        XCTAssertEqual(AgentTabLink.id(URL(string: "brk://tab/item-7")!), "item-7")
        XCTAssertEqual(AgentTabLink.id(URL(string: "brk://tab/archive:a-1")!), "archive:a-1")
        XCTAssertNil(AgentTabLink.id(URL(string: "https://tab/item-7")!))
    }
}
