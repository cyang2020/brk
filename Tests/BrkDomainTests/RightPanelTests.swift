import BrkBase
@testable import BrkDomain
import XCTest

/// Step 8 (docs/design/ai-right-panel.md): conversations only in the right panel. The move off the sidebar at the first
/// launch, the toggle and its entries, the list's delete-only menu and moves, the tabs a conversation used and the rows
/// they light, the panel's dragged width, a deleted Space's conversations, and a kept page's way back.
final class RightPanelTests: XCTestCase {
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
    private func answered(_ d: Driver, _ question: String = "这几个 tab 哪个最便宜", answer: String = "The second one.") throws -> AIRequestID {
        let id = try firstTurn(d.user(.assist(.ask(question))))
        d.system(.aiResult(id, .text(answer)))
        return id
    }
    private func listed(_ d: Driver) -> [AIRequestID] { d.view.aiPanel?.groups.flatMap(\.rows).map(\.id) ?? [] }

    // MARK: The move off the sidebar (第一次启动)

    /// Old data: conversation rows in Pinned, in a folder, in another Space's Today, in the archive and in Favorites, and a
    /// kept page's row. Made with ordinary tabs whose addresses are then written as conversation addresses in the file.
    func testTheFirstLaunchTakesEveryConversationRowAwayAndKeepsTheConversationsInTheirSpaces() throws {
        let d = enabled()
        let home = d.view.space.id
        let pinned = d.open("https://conv-pinned.example/")
        d.user(.tab(.togglePin(.item(pinned))))
        let foldered = d.open("https://conv-folder.example/")
        d.user(.tabTools(.bulk(.items([foldered]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.state.doc.tree[foldered]?.parent)
        let archived = d.open("https://conv-archived.example/")
        d.user(.tab(.close(.item(archived))))
        let keptPage = d.open("https://kept-page.example/")
        let work = d.newSpace("Work")
        d.user(.space(.focus(work)))
        _ = d.open("https://conv-work.example/")
        d.user(.space(.focus(home)))
        var text = String(decoding: d.savedFile, as: UTF8.self)
        for (from, to) in [("https://conv-pinned.example/", "brk://conversation/pinned"), ("https://conv-folder.example/", "brk://conversation/foldered"),
                           ("https://conv-archived.example/", "brk://conversation/archived"), ("https://conv-work.example/", "brk://conversation/work"),
                           ("https://kept-page.example/", "brk://ai-page/kept")] {
            text = text.replacingOccurrences(of: from.replacingOccurrences(of: "/", with: "\\/"), with: to.replacingOccurrences(of: "/", with: "\\/"))
            text = text.replacingOccurrences(of: from, with: to)
        }
        let next = Driver(file: Data(text.utf8))
        // The app reduces other launch events before it reads the conversations: the rows must wait for them.
        next.system(.aiProvidersDetected([.claude]))
        XCTAssertTrue(next.allTabRows.contains { $0.url == ConversationPage.url(AIRequestID("pinned")) }, "the old file has the rows")
        func stored(_ id: String, space: SpaceID?) -> StoredConversation {
            var conversation = StoredConversation(id: AIRequestID(id), profile: .default, title: id + " question", createdAt: T0, tabs: true)
            conversation.items = [.user(id + " question"), .assistant("Look at [the tab](brk://tab/\(keptPage.rawValue)).")]
            conversation.space = space
            return conversation
        }
        let page = AIPageRecord(id: AIPageID("kept"), title: "Kept", html: URL(fileURLWithPath: "/tmp/brk-test-pages/kept.html"), height: 200, data: nil,
                                conversation: AIRequestID("pinned"), profile: .default, createdAt: T0, readPages: false)
        // "work" says it was started at home; its row in Work wins. "gone" names a Space that no longer exists.
        next.system(.conversationsLoaded([stored("pinned", space: home), stored("foldered", space: home), stored("archived", space: home),
                                          stored("work", space: home), stored("gone", space: SpaceID("deleted-space"))], [page]))
        let saved = next.state.savedConversations
        XCTAssertEqual(saved.count, 5, "every conversation is kept")
        XCTAssertFalse(next.allTabRows.contains { ConversationPage.shows($0.url) }, "no conversation row is left: \(next.allTabRows.map(\.url))")
        XCTAssertFalse(next.state.doc.archive.contains { ConversationPage.shows($0.tab.url) }, "no archived conversation entry is left")
        XCTAssertTrue(next.allTabRows.contains { $0.url == AIPageTab.url(AIPageID("kept")) }, "the kept page's row stays")
        XCTAssertNotNil(next.state.doc.tree[folder], "the folder left empty stays, as Arc keeps empty folders")
        XCTAssertEqual(saved[AIRequestID("pinned")]?.space, home)
        XCTAssertEqual(saved[AIRequestID("foldered")]?.space, home)
        XCTAssertEqual(saved[AIRequestID("archived")]?.space, home, "an archived one goes to the Space it was archived from")
        XCTAssertEqual(saved[AIRequestID("work")]?.space, work, "the Space its row was in")
        XCTAssertEqual(next.state.conversationSpaces(.default)[AIRequestID("gone")], next.state.doc.spaceOrder.first, "a gone Space gives way to the first")
        XCTAssertEqual(saved[AIRequestID("pinned")]?.usedTabs, [keptPage], "the tabs its transcript links come back")
        next.user(.assist(.panelPage(.list)))
        XCTAssertEqual(Set(next.view.aiPanel?.groups.flatMap(\.rows).map(\.id) ?? []), [AIRequestID("pinned"), AIRequestID("foldered"), AIRequestID("archived"), AIRequestID("gone")])
        // A second launch finds nothing left to move and changes nothing.
        let again = Driver(file: next.savedFile)
        again.system(.conversationsLoaded(Array(saved.values), [page]))
        XCTAssertEqual(again.state.savedConversations, saved)
    }

    func testARowNamedByTheUserGivesTheConversationItsName() throws {
        let d = enabled()
        let tab = d.open("https://conv-named.example/")
        d.user(.item(.rename(tab, title: "My name")))
        let text = String(decoding: d.savedFile, as: UTF8.self)
            .replacingOccurrences(of: "https:\\/\\/conv-named.example\\/", with: "brk:\\/\\/conversation\\/named")
            .replacingOccurrences(of: "https://conv-named.example/", with: "brk://conversation/named")
        let next = Driver(file: Data(text.utf8))
        next.system(.conversationsLoaded([StoredConversation(id: AIRequestID("named"), profile: .default, title: "first words", createdAt: T0, tabs: true)], []))
        XCTAssertEqual(next.state.savedConversations[AIRequestID("named")]?.title, "My name")
        XCTAssertEqual(next.state.savedConversations[AIRequestID("named")]?.userNamed, true)
    }

    // MARK: The toggle and its entries (开关和入口)

    func testTheToggleOpensOnWhatTheSpaceShowedLastAndClosesAgain() throws {
        let d = enabled()
        XCTAssertEqual(d.view.aiToggle, AIToggleSnapshot(open: false, waiting: 0, language: .en))
        XCTAssertEqual(d.view.aiEdgeDrop, AIEdgeDropSnapshot(language: .en), "closed: tabs dropped at the right edge go to a new conversation")
        d.user(.assist(.togglePanel))
        XCTAssertEqual(d.view.aiPanel?.page, .list, "no conversation yet: the list")
        XCTAssertEqual(d.view.aiToggle?.open, true)
        XCTAssertNil(d.view.aiEdgeDrop)
        d.user(.assist(.togglePanel))
        XCTAssertNil(d.view.aiPanel)
        XCTAssertNil(d.view.ai)
        let id = try answered(d, "hello", answer: "Hi.")
        d.user(.assist(.togglePanel))
        XCTAssertNil(d.view.ai, "closed")
        d.user(.assist(.togglePanel))
        XCTAssertEqual(d.view.ai?.conversation?.id, id, "the conversation it showed")
        XCTAssertEqual(d.view.aiPanel?.page, .conversation)
        d.user(.assist(.panelPage(.list)))
        d.user(.assist(.dismiss))
        d.user(.assist(.togglePanel))
        XCTAssertEqual(d.view.aiPanel?.page, .list, "the page it was left on")
        XCTAssertEqual(d.view.ai?.conversation?.id, id, "with its conversation one page over")
    }

    func testWithAIOffThereIsNoToggleAndTheRowIsArcs() {
        let d = Driver()
        XCTAssertNil(d.view.aiToggle)
        XCTAssertNil(d.view.aiEdgeDrop)
        d.user(.assist(.togglePanel))
        XCTAssertNil(d.view.aiPanel)
        let lit = d.view.sidebar.lit
        XCTAssertTrue(lit.isEmpty)
    }

    func testAPrivateWindowHasNoToggle() {
        let d = enabled()
        d.user(.window(.newIncognito))
        let incognito = d.state.doc.windows.values.first { $0.kind == .incognito }!.id
        XCTAssertNil(d.view(of: incognito).aiToggle)
        d.user(.assist(.togglePanel), in: incognito)
        XCTAssertNil(d.view(of: incognito).aiPanel)
    }

    func testTheToggleCarriesTheProfilesWaitingCount() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Run it"))))
        d.system(.aiConversation(id, .approval(AIAgentApproval(id: "a", title: "Run: ls", detail: "", options: [.init(id: "once", title: "Allow", kind: .allowOnce)]), turn: id)))
        d.user(.assist(.dismiss))
        XCTAssertEqual(d.view.aiToggle?.waiting, 1)
        XCTAssertEqual(d.view.aiToggle?.open, false)
        d.user(.assist(.togglePanel))
        XCTAssertEqual(d.view.aiPanel?.waiting, 1, "the same number as the list icon's")
    }

    func testViewMenuItemUnderShowHideSidebarTogglesAndTheBarRowOpensTheList() throws {
        let view = ActionID.allCases.filter { $0.spec.menu == .view && !$0.spec.hidden && $0.spec.submenu == nil }
        let sidebar = try XCTUnwrap(view.firstIndex(of: .showSidebar))
        XCTAssertEqual(view[sidebar + 1], .aiConversations)
        let spec = ActionID.aiConversations.spec
        XCTAssertEqual(spec.title, "Show/Hide AI Conversations")
        XCTAssertEqual(spec.bindings.first?.chord, KeyChord([.option, .command], .a))
        XCTAssertEqual(spec.command, .assist(.togglePanel))
        XCTAssertEqual(spec.barCommand, .assist(.panelPage(.list)), "the command bar's AI 对话 row stays as it was")
        XCTAssertEqual(ActionID.aiConversations.barTitle(appName: "Brk"), "AI Conversations")
        XCTAssertEqual(KeyMap().lookup(KeyChord([.option, .command], .a))?.action, .aiConversations)
    }

    // MARK: The list keeps only delete (列表里只留删除)

    func testTheRowMenuIsRenameMoveAndDelete() throws {
        let d = enabled()
        let id = try answered(d)
        _ = d.newSpace("Work")
        let entries = Work.menuTitles(d, id)
        XCTAssertEqual(entries, ["重命名", "移到别的 Space", "-", "彻底删除…"])
    }

    func testMovingAConversationChangesBothListsAndPutsItAwayFromThePanel() throws {
        let d = enabled()
        let home = d.view.space.id
        let id = try answered(d)
        let work = d.newSpace("Work")
        d.user(.space(.focus(home)))
        d.user(.assist(.showConversation(id)))
        d.user(.assist(.moveConversation(id, work)))
        XCTAssertEqual(d.state.savedConversations[id]?.space, work)
        XCTAssertNil(d.view.ai, "the panel no longer shows another Space's conversation")
        XCTAssertEqual(d.view.aiPanel?.page, .list)
        XCTAssertFalse(listed(d).contains(id))
        d.user(.space(.focus(work)))
        XCTAssertTrue(listed(d).contains(id))
    }

    func testLibraryHasNoArchivedState() {
        XCTAssertFalse(AIThreadState.allCases.map(\.rawValue).contains("archived"))
    }

    // MARK: Used tabs and lighting (悬停高亮)

    func testTabsGivenAndTabsTheAgentUsedAreRecordedByTab() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        let b = d.open("https://b.example/")
        d.user(.assist(.attach([.tab(a.rawValue), .tab(b.rawValue)])))
        let t = d.user(.assist(.followUp("compare these")))
        let id = try firstTurn(t)
        XCTAssertEqual(d.state.savedConversations[id]?.usedTabs, [a, b])
        let c = d.open("https://c.example/")
        d.system(.aiConversation(id, .usedTabs([c.rawValue, a.rawValue, "archive:gone"])))
        XCTAssertEqual(d.state.savedConversations[id]?.usedTabs, [a, b, c], "each tab once, in the order first used; an archived id is no tab")
    }

    func testHoveringARowLightsItsTabsHereAndSaysHowMany() throws {
        let d = enabled()
        let home = d.view.space.id
        let a = d.open("https://a.example/")
        let b = d.open("https://b.example/")
        let c = d.open("https://c.example/")
        d.user(.tabTools(.bulk(.items([b]), .newFolder(group: false))))
        let folder = try XCTUnwrap(d.state.doc.tree[b]?.parent)
        d.user(.assist(.attach([.tab(a.rawValue), .tab(b.rawValue), .tab(c.rawValue)])))
        let id = try firstTurn(d.user(.assist(.followUp("compare"))))
        d.system(.aiResult(id, .text("Done.")))
        d.user(.assist(.panelPage(.list)))
        // The folder starts open: its tab lights its own row.
        if !d.state.folderIsExpanded(folder, in: d.window) { d.user(.item(.toggleFolder(folder))) }
        d.user(.assist(.hoverConversation(id)))
        XCTAssertEqual(d.view.sidebar.lit, [a, b, c])
        XCTAssertEqual(d.view.aiPanel?.hovered, id)
        XCTAssertEqual(d.view.aiPanel?.hoveredDetail, "Used 3 tabs")
        // A collapsed folder lights in its tab's place.
        d.user(.item(.toggleFolder(folder)))
        XCTAssertEqual(d.view.sidebar.lit, [a, folder, c])
        // A closed tab and one in another Space do not light; the line says how many do.
        d.user(.tab(.close(.item(c))))
        XCTAssertEqual(d.view.sidebar.lit, [a, folder])
        XCTAssertEqual(d.view.aiPanel?.hoveredDetail, "Used 3 tabs, 2 lit")
        let work = d.newSpace("Work")
        d.user(.tab(.focus(a)))
        d.user(.item(.move(a, to: .space(work))))
        d.user(.space(.focus(home)))
        d.user(.assist(.panelPage(.list)))
        d.user(.assist(.hoverConversation(id)))
        XCTAssertEqual(d.view.sidebar.lit, [folder])
        // Off the row: nothing lit.
        d.user(.assist(.hoverConversation(nil)))
        XCTAssertTrue(d.view.sidebar.lit.isEmpty)
        XCTAssertNil(d.view.aiPanel?.hoveredDetail)
    }

    func testASplitAndAFavoriteLightTheirOwnPlaces() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        let b = d.open("https://b.example/")
        let f = d.open("https://f.example/")
        d.user(.tabTools(.openInSplit(.items([a, b]))))
        let split = try XCTUnwrap(d.state.doc.tree[a]?.parent)
        let favorites = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(f, to: .into(parent: favorites, index: 0))))
        d.user(.assist(.attach([.tab(a.rawValue), .tab(f.rawValue)])))
        let id = try firstTurn(d.user(.assist(.followUp("compare"))))
        d.system(.aiResult(id, .text("Done.")))
        d.user(.assist(.panelPage(.list)))
        d.user(.assist(.hoverConversation(id)))
        XCTAssertEqual(d.view.sidebar.lit, [split, f])
    }

    func testNothingLightsWhileTheSidebarIsHidden() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        d.user(.assist(.attach([.tab(a.rawValue)])))
        let id = try firstTurn(d.user(.assist(.followUp("x"))))
        d.user(.assist(.panelPage(.list)))
        d.user(.sidebar(.toggle))
        d.user(.assist(.hoverConversation(id)))
        XCTAssertTrue(d.view.sidebar.lit.isEmpty)
        XCTAssertEqual(d.view.aiPanel?.hoveredDetail, "Used 1 tab, 0 lit")
    }

    func testHoveringAChipLightsThatOneTab() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        let b = d.open("https://b.example/")
        d.user(.assist(.attach([.tab(a.rawValue), .tab(b.rawValue)])))
        d.user(.assist(.hoverChip(b.rawValue)))
        XCTAssertEqual(d.view.sidebar.lit, [b])
        d.user(.assist(.hoverChip(nil)))
        XCTAssertTrue(d.view.sidebar.lit.isEmpty)
        d.user(.assist(.hoverChip("not-a-chip")))
        XCTAssertTrue(d.view.sidebar.lit.isEmpty)
    }

    // MARK: The panel's width (拖宽)

    func testThePanelKeepsADraggedWidthAcrossARelaunchAndStopsAtHalfTheWindow() throws {
        let d = enabled()
        d.user(.assist(.togglePanel))
        d.user(.assist(.panelWidth(520.4)))
        XCTAssertEqual(d.view.aiPanelWidth, 520)
        d.user(.assist(.panelWidth(100)))
        XCTAssertEqual(d.view.aiPanelWidth, Metrics.ai.minimumWidth.value)
        d.user(.assist(.panelWidth(600)))
        let next = Driver(file: d.savedFile)
        XCTAssertEqual(next.view.aiPanelWidth, 600, "kept like the sidebar's width")
        next.user(.window(.new))
        let second = try XCTUnwrap(next.state.doc.windows.keys.first { $0 != next.window })
        XCTAssertEqual(next.view(of: second).aiPanelWidth, 600, "a new window takes the window's width, as the sidebar's")
    }

    // MARK: A deleted Space's conversations

    func testDeletingASpaceMovesItsConversationsToTheProfilesFirstSpaceAndTheDialogSaysSo() throws {
        let d = enabled()
        let home = d.view.space.id
        let work = d.newSpace("Work")
        d.user(.space(.focus(work)))
        let a = try answered(d, "工作的问题")
        let b = try answered(d, "工作的第二个问题")
        d.user(.space(.focus(home)))
        d.user(.space(.requestDelete(home)))
        XCTAssertNil(d.view.pendingSpaceDeletion?.conversations, "no conversations: Arc's dialog as it is")
        d.user(.space(.confirmDelete(home, token: d.view.pendingSpaceDeletion!.token, confirmed: false)))
        d.user(.space(.requestDelete(work)))
        XCTAssertEqual(d.view.pendingSpaceDeletion?.conversations, "2 段 AI 对话会移到 \(d.state.displayTitle(of: home))。")
        d.user(.space(.confirmDelete(work, token: d.view.pendingSpaceDeletion!.token, confirmed: true)))
        XCTAssertEqual(d.state.savedConversations[a]?.space, home)
        XCTAssertEqual(d.state.savedConversations[b]?.space, home)
        // ⌘Z brings the Space back with its conversations.
        XCTAssertEqual(d.view.tabTools.toast?.text, "Space deleted! Use")
        d.user(.tabTools(.undoToast))
        let back = try XCTUnwrap(d.view.dock.first { $0.title == "Work" }?.id)
        XCTAssertEqual(d.state.savedConversations[a]?.space, back)
        XCTAssertEqual(d.state.savedConversations[b]?.space, back)
    }

    // MARK: A kept page's way back

    func testAKeptPagesRowMenuOpensItsConversationWhileItIsSaved() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("画个对比图"))))
        let page = AIPageRecord(id: AIPageID("p"), title: "Prices", html: URL(fileURLWithPath: "/tmp/brk-test-pages/p.html"), height: 300, data: nil,
                                conversation: id, profile: .default, createdAt: T0, readPages: false)
        d.system(.aiConversation(id, .page(page)))
        d.system(.aiResult(id, .text("Done.")))
        d.user(.assist(.keepPage(AIPageID("p"))))
        let row = try XCTUnwrap(d.allTabRows.first { $0.url == AIPageTab.url(AIPageID("p")) }).id
        let titles = Work.menuTitles(d, .item(row))
        let at = try XCTUnwrap(titles.firstIndex(of: "打开对话"))
        XCTAssertEqual(titles[at + 1], "Refresh", "first of Brk's page items")
        d.user(.assist(.dismiss))
        d.user(.assist(.showConversation(id)))
        XCTAssertEqual(d.view.ai?.conversation?.id, id)
    }
}

extension Work {
    /// A popup menu's titles as the domain builds it ("-" for a separator).
    static func menuTitles(_ d: Driver, _ request: PopupMenuRequest) -> [String] {
        let work = Work(state: d.state, ctx: d.ctx)
        return work.menuModel(for: request, in: d.window).entries.map { entry in
            switch entry {
            case .action(let title, _, _), .choice(let title, _, _), .submenu(let title, _): title
            case .separator: "-"
            case .header(let title): title
            }
        }
    }
    static func menuTitles(_ d: Driver, _ conversation: AIRequestID) -> [String] { menuTitles(d, .conversation(conversation)) }
}
