import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The reducer's side of the command bar's quick sources: what asks for files, apps and rates, what is dropped as stale,
/// what is never acted on, and that nothing reaches history or the search engine beyond what the bar already sent.
final class CommandBarQuickSourcesTests: XCTestCase {
    private func request(_ query: String, scope: LocalScope = .filesAndApps) -> LocalSearchRequest {
        LocalSearchRequest(query: query, name: query, scope: scope)
    }

    private func local(_ t: Transition) -> [LocalSearchRequest] {
        t.effects.compactMap { if case .searchLocal(_, let request) = $0 { request } else { nil } }
    }

    private func fetches(_ t: Transition) -> Int {
        t.effects.filter { if case .fetchSuggestions = $0 { true } else { false } }.count
    }

    private func needsRates(_ t: Transition) -> Bool { t.effects.contains(.needCurrencyRates) }

    func testWhatAsksTheFileAndAppSources() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budget")))), [request("budget")])
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("  my notes  ")))), [request("my notes")])
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("bu")))), [], "under three characters")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("example.com")))), [], "an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("report.pdf")))), [], "reads as an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("https://example.com/budget")))), [], "an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("localhost:5173")))), [], "an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("1+1")))), [], "arithmetic")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("10ft in m")))), [], "a question the bar answers")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("file report")))), [request("file report")], "as plain text it is an ordinary text")
        XCTAssertEqual(local(d.user(.commandBar(.prefixQuery(.files, "report.pdf")))), [request("report.pdf", scope: .files)], "the prefix takes any name")
        XCTAssertEqual(local(d.user(.commandBar(.prefixQuery(.apps, "safari")))), [request("safari", scope: .apps)])
        XCTAssertEqual(local(d.user(.commandBar(.prefixQuery(.files, "a")))), [], "the prefix wants two characters")
        XCTAssertEqual(local(d.user(.commandBar(.prefixQuery(.emoji, "smile")))), [], "emoji are not files")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("")))), [])
    }

    func testOnlyANewTabBarAsks() {
        let d = Driver()
        d.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budget")))), [], "the bar over the page's address")
        d.user(.commandBar(.dismiss))

        d.user(.split(.addPane))
        guard case .commandBar? = d.view.overlay else { return XCTFail("the empty pane's bar") }
        XCTAssertEqual(d.bar?.fillsPane, true)
        let t = d.user(.commandBar(.queryChanged("budget")))
        XCTAssertEqual(local(t), [], "the empty pane's bar")
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("100 usd in cny")))), "the empty pane's bar")
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("10ft in m")))), 1, "still an ordinary search there")
        XCTAssertEqual(d.user(.commandBar(.prefixQuery(.files, "budget"))).effects, [], "no prefix in that bar")
    }

    func testAPrivateWindowListsNoFilesAndFetchesNothing() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.open(.newTab)), in: window)
        XCTAssertEqual(d.user(.commandBar(.queryChanged("budget")), in: window).effects, [])
        XCTAssertEqual(d.user(.commandBar(.prefixQuery(.files, "budget")), in: window).effects, [])
        XCTAssertEqual(d.user(.commandBar(.queryChanged("100 usd in cny")), in: window).effects, [])
        d.system(.currencyRates(CurrencyRates(date: "2026-11-06", perEuro: ["EUR": 1, "USD": 1.1])))
        guard case .commandBar(let bar)? = d.view(of: window).overlay else { return XCTFail("the bar") }
        XCTAssertNotNil(bar.rates, "rates already known still answer")
    }

    func testAIModeAndSiteSearchAskNothing() {
        let d = Driver()
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.user(.assist(.open(.question)))
        XCTAssertEqual(d.bar?.aiMode, .question)
        XCTAssertEqual(d.user(.commandBar(.queryChanged("budget"))).effects, [])

        let site = Driver()
        site.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(local(site.user(.commandBar(.queryChangedForSite(SearchEngine.bing.id, "budget")))), [])
    }

    func testAnAnswerIsKeptForTheViewAndForgottenOnANewOpening() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.queryChanged("budget")))
        let hit = LocalHit(path: "/Users/u/Documents/budget.txt", name: "budget.txt")
        d.system(.localResults(d.window, LocalResults(query: "budget", apps: [], files: [hit])))
        XCTAssertEqual(d.bar?.local?.files, [hit])
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budget")))), [], "this text has its answer")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budgets")))), [request("budgets")])
        d.user(.commandBar(.dismiss))
        XCTAssertNil(d.bar)
        d.system(.localResults(d.window, LocalResults(query: "budget", apps: [], files: [hit])))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(d.bar?.local, "a late answer does not reach the next opening")

        // Only the new-tab bar takes one.
        let other = Driver()
        other.user(.commandBar(.open(.editCurrent)))
        other.system(.localResults(other.window, LocalResults(query: "budget", apps: [], files: [hit])))
        XCTAssertNil(other.bar?.local)
    }

    func testAShownFileCanBeOpenedRevealedAndCopiedAndNothingElse() {
        let hit = LocalHit(path: "/Users/u/Documents/budget.txt", name: "budget.txt"), app = LocalHit(path: "/Applications/Budget.app", name: "Budget")
        func opened(_ action: LocalAction, _ path: String) -> (Transition, Driver) {
            let d = Driver()
            d.user(.commandBar(.open(.newTab)))
            d.user(.commandBar(.queryChanged("budget")))
            d.system(.localResults(d.window, LocalResults(query: "budget", apps: [app], files: [hit])))
            return (d.user(.commandBar(.local(action, path: path))), d)
        }
        var (t, d) = opened(.open, hit.path)
        XCTAssertEqual(t.effects, [.openLocalFile(hit.path)])
        XCTAssertNil(d.bar)
        (t, d) = opened(.reveal, hit.path)
        XCTAssertEqual(t.effects, [.revealFile(hit.path)])
        XCTAssertNil(d.bar)
        (t, d) = opened(.copyPath, hit.path)
        XCTAssertEqual(t.effects, [.copyToPasteboard(hit.path)])
        (t, d) = opened(.open, app.path)
        XCTAssertEqual(t.effects, [.openLocalFile(app.path)])

        (t, d) = opened(.open, "/etc/passwd")
        XCTAssertEqual(t.effects, [], "not a path the bar shows")
        XCTAssertNotNil(d.bar)

        let closed = Driver()
        XCTAssertEqual(closed.user(.commandBar(.local(.open, path: hit.path))).effects, [], "no bar")
    }

    func testNothingFromTheseSourcesReachesHistoryOrTheEngine() {
        let d = Driver()
        let visits = d.state.doc.history.count
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(fetches(d.user(.commandBar(.prefixQuery(.files, "secret plan")))), 0, "a file name is not a web search")
        XCTAssertEqual(fetches(d.user(.commandBar(.prefixQuery(.apps, "secret plan")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.prefixQuery(.emoji, "smile")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("10ft in m")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("time in tokyo")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("100 usd in cny")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("today")))), 1, "also an ordinary search")
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("budget")))), 1, "an ordinary search, as before")

        let hit = LocalHit(path: "/Users/u/budget.txt", name: "budget.txt")
        d.system(.localResults(d.window, LocalResults(query: "budget", apps: [], files: [hit])))
        d.user(.commandBar(.local(.open, path: hit.path)))
        XCTAssertEqual(d.state.doc.history.count, visits)
    }

    func testOnlyACurrencyQuestionAsksForRates() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertTrue(needsRates(d.user(.commandBar(.queryChanged("100 usd in cny")))))
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("100 usd")))))
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("budget")))))
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("10ft in m")))))
        let rates = CurrencyRates(date: "2026-11-06", perEuro: ["EUR": 1, "USD": 1.1])
        d.system(.currencyRates(rates))
        XCTAssertEqual(d.bar?.rates, rates)
    }

    func testCopyAnswerCopiesAndCloses() {
        let d = Driver()
        XCTAssertEqual(d.user(.commandBar(.copyAnswer("3.048 m"))).effects, [], "no bar")
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.user(.commandBar(.copyAnswer("3.048 m"))).effects, [.copyToPasteboard("3.048 m")])
        XCTAssertNil(d.bar)
    }

    func testTheBarsClockMovesOnOpeningADateQuestionAndTheTick() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.now, T0)
        d.advance(minute)
        XCTAssertFalse(d.user(.commandBar(.queryChanged("budget"))).changed, "an ordinary keystroke re-renders nothing")
        XCTAssertEqual(d.bar?.now, T0)
        d.user(.commandBar(.queryChanged("time")))
        XCTAssertEqual(d.bar?.now, T0.advanced(by: minute))
        d.advance(minute)
        d.system(.clockTick)
        XCTAssertEqual(d.bar?.now, T0.advanced(by: minute * 2))
    }

    func testTheAgentFoundFlag() {
        let d = Driver()
        d.system(.aiProvidersDetected([]))
        XCTAssertFalse(d.state.askAgentFound, "Automatic with nothing on this Mac")
        d.system(.aiProvidersDetected([.codex]))
        XCTAssertTrue(d.state.askAgentFound)
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.askAgentFound, true)
        d.user(.settings(.max(.provider(.claude))))
        XCTAssertFalse(d.state.askAgentFound, "Claude chosen, only Codex found")
        d.system(.aiProvidersDetected([.claude]))
        XCTAssertTrue(d.state.askAgentFound)
        d.user(.settings(.max(.provider(.off))))
        XCTAssertFalse(d.state.askAgentFound)
    }

    // MARK: Asking one agent

    private func choices(_ t: Transition) -> [AIProviderChoice] {
        t.effects.compactMap { if case .ai(_, _, let choice) = $0 { choice } else { nil } }
    }

    func testANamedAgentIsTheOneAskedWhateverTheSettingSays() {
        let d = Driver()
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.system(.aiProvidersDetected([.claude, .codex]))
        d.user(.settings(.max(.provider(.claude))))
        d.user(.commandBar(.open(.newTab)))
        let t = d.user(.assist(.askAgent("why", agent: .codex)))
        XCTAssertEqual(choices(t), [.codex], "the named agent, not the setting's")
        XCTAssertNil(d.bar, "the bar closed")
        XCTAssertEqual(d.view.ai?.title, "why")
        XCTAssertEqual(choices(d.user(.assist(.ask("why again")))), [.claude], "the default still follows the setting")
    }

    func testAMissingAgentIsNeverReplacedByAnother() {
        let d = Driver()
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.system(.aiProvidersDetected([.claude]))
        let t = d.user(.assist(.askAgent("why", agent: .codex)))
        XCTAssertEqual(choices(t), [], "Codex is not here and Claude does not stand in")
        XCTAssertTrue(d.view.ai?.text.contains("not available") == true)
        d.user(.assist(.dismiss))
        d.user(.settings(.max(.provider(.off))))
        d.system(.aiProvidersDetected([.claude, .codex]))
        XCTAssertEqual(choices(d.user(.assist(.askAgent("why", agent: .claude)))), [], "Max's tool is off")
        d.user(.settings(.max(.provider(.auto))))
        d.user(.settings(.max(.feature(.commandBar, false))))
        XCTAssertEqual(choices(d.user(.assist(.askAgent("why", agent: .claude)))), [], "Ask is off")
    }

    func testTheAgentPrefixesFollowWhatIsOnThisMac() {
        let d = Driver()
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.user(.settings(.max(.feature(.askPage, true))))
        d.system(.aiProvidersDetected([.claude]))
        d.user(.commandBar(.open(.newTab)))
        func prefix(_ word: String) -> QuickPrefixAction? { QuickPrefixes.entry(named: word, in: d.bar!)?.action }
        XCTAssertEqual(prefix("claude"), .askAgent("claude"))
        XCTAssertEqual(prefix("CLAUDE"), .askAgent("claude"))
        XCTAssertNil(prefix("gpt"), "Codex is not on this Mac: plain text")
        XCTAssertNil(prefix("codex"))
        XCTAssertEqual(prefix("ask"), .ask)
        XCTAssertEqual(prefix("ai"), .ask)
        XCTAssertEqual(prefix("问"), .ask)
        XCTAssertEqual(prefix("page"), .askPage)
        XCTAssertEqual(prefix("问页面"), .askPage)
        XCTAssertEqual(prefix("summarize"), .summarize)
        XCTAssertEqual(prefix("总结"), .summarize)
        // Lines ready for the agents that branch adds: inactive until AIProviderChoice has them.
        XCTAssertNil(prefix("gemini"))
        XCTAssertNil(prefix("cursor"))
        XCTAssertTrue(QuickPrefixes.all.contains { $0.words.contains("gemini") })
        XCTAssertTrue(QuickPrefixes.all.contains { $0.words.contains("cursor") })

        d.system(.aiProvidersDetected([.claude, .codex]))
        XCTAssertEqual(prefix("gpt"), .askAgent("codex"))
        XCTAssertEqual(prefix("codex"), .askAgent("codex"))

        d.user(.settings(.max(.provider(.off))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(prefix("claude"), "Max's AI is off")
        XCTAssertNil(prefix("ask"))
        d.user(.settings(.max(.provider(.auto))))
        d.user(.settings(.max(.feature(.commandBar, false))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(prefix("claude"), "Ask in Command Bar is off")
        d.user(.settings(.max(.feature(.askPage, false))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(prefix("page"))
        XCTAssertNil(prefix("summarize"))
        d.system(.aiProvidersDetected([]))
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(prefix("ask"), "no agent found")
    }

    // MARK: Split

    private func panes(_ d: Driver) -> [ItemID] { d.view.content.panes.map(\.tab) }

    func testSplitOpensTheTextInANewPaneOnThatSide() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        let first = try XCTUnwrap(panes(d).first)
        d.user(.commandBar(.splitOpen(.right, "example.com")))
        XCTAssertNil(d.bar, "the bar closed")
        XCTAssertEqual(panes(d).count, 2)
        XCTAssertEqual(panes(d).first, first, "right of the current page")
        let added = panes(d)[1]
        XCTAssertEqual(d.state.session.live[PageID(window: d.window, item: added)]?.requestedURL, url("https://example.com/"))

        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.splitOpen(.left, "two words")))
        XCTAssertEqual(panes(d).count, 3)
        XCTAssertEqual(d.view.content.panes.first { $0.focused }?.tab, panes(d).first { $0 != first && $0 != added })
        let searched = try XCTUnwrap(d.view.content.panes.first { $0.focused }?.tab)
        XCTAssertEqual(panes(d).firstIndex(of: searched).map { $0 < panes(d).firstIndex(of: added)! }, true, "before the focused pane")
        XCTAssertEqual(d.state.session.live[PageID(window: d.window, item: searched)]?.requestedURL?.query, "q=two%20words")
        XCTAssertEqual(d.view.content.orientation, .horizontal)
    }

    func testSplitTopUsesTheStackedOrientation() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.splitOpen(.top, "example.com")))
        XCTAssertEqual(panes(d).count, 2)
        XCTAssertEqual(d.view.content.orientation, .vertical)
    }

    func testASplitThatCannotBeAddedLeavesNoOpenBar() {
        let d = Driver()
        for _ in 0..<(Metrics.content.maxPanes.value - 1) {
            d.user(.commandBar(.open(.newTab)))
            d.user(.commandBar(.splitOpen(.right, "example.com")))
        }
        let full = panes(d).count
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.splitOpen(.right, "example.org")))
        XCTAssertEqual(panes(d).count, full, "a full split")
        XCTAssertNil(d.bar)
    }

    func testTheSplitWordStaysPlainWhereNoPaneCanBeAdded() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(QuickPrefixes.entry(named: "split", in: d.bar!)?.action, .split)
        XCTAssertEqual(QuickPrefixes.entry(named: "分屏", in: d.bar!)?.action, .split)
        var little = d.bar!
        little.actions.removeAll { $0 == .addSplitView }
        XCTAssertNil(QuickPrefixes.entry(named: "split", in: little))
    }

    func testSplitSides() {
        XCTAssertEqual(QuickSplit.parse("left example.com").edge, .left)
        XCTAssertEqual(QuickSplit.parse("left example.com").rest, "example.com")
        XCTAssertEqual(QuickSplit.parse("TOP  a b").edge, .top)
        XCTAssertEqual(QuickSplit.parse("TOP  a b").rest, "a b")
        XCTAssertEqual(QuickSplit.parse("bottom").edge, .bottom)
        XCTAssertEqual(QuickSplit.parse("bottom").rest, "")
        XCTAssertNil(QuickSplit.parse("lefty x").edge)
        XCTAssertEqual(QuickSplit.parse("lefty x").rest, "lefty x")
        XCTAssertNil(QuickSplit.parse("").edge)
    }

    // MARK: Window

    func testPlacingTheWindowIsAnEffectAndClosesTheBar() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.user(.window(.place(.leftHalf))).effects, [.window(d.window, .place(.leftHalf))])
        XCTAssertNil(d.bar)
    }

    func testPlacements() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 800), current = CGRect(x: 300, y: 200, width: 400, height: 300)
        XCTAssertEqual(WindowSnap.leftHalf.frame(current: current, visible: visible), CGRect(x: 100, y: 50, width: 500, height: 800))
        XCTAssertEqual(WindowSnap.rightHalf.frame(current: current, visible: visible), CGRect(x: 600, y: 50, width: 500, height: 800))
        XCTAssertEqual(WindowSnap.topHalf.frame(current: current, visible: visible), CGRect(x: 100, y: 450, width: 1000, height: 400), "AppKit's y grows upward")
        XCTAssertEqual(WindowSnap.bottomHalf.frame(current: current, visible: visible), CGRect(x: 100, y: 50, width: 1000, height: 400))
        XCTAssertEqual(WindowSnap.maximize.frame(current: current, visible: visible), visible)
        XCTAssertEqual(WindowSnap.center.frame(current: current, visible: visible), CGRect(x: 400, y: 300, width: 400, height: 300))
        // The same share and place on another screen, and back.
        let other = CGRect(x: 1100, y: 0, width: 2000, height: 1600)
        XCTAssertEqual(WindowSnap.moved(current, from: visible, to: other), CGRect(x: 1500, y: 300, width: 800, height: 600))
        XCTAssertEqual(WindowSnap.moved(WindowSnap.moved(current, from: visible, to: other), from: other, to: visible), current)
    }

    func testExactPhrases() {
        XCTAssertEqual(WindowSnap.exact("left half"), .leftHalf)
        XCTAssertEqual(WindowSnap.exact("Next Display"), .nextDisplay)
        XCTAssertEqual(WindowSnap.exact("centre window"), .center)
        for text in ["left", "half", "maximize", "center", "left half of a page", "window"] { XCTAssertNil(WindowSnap.exact(text), text) }
    }

    // MARK: Translate

    private func translationBar() -> Driver {
        let d = Driver()
        d.user(.settings(.max(.feature(.translation, true))))
        d.system(.aiProvidersDetected([.claude]))
        d.user(.commandBar(.open(.newTab)))
        return d
    }

    private func aiEffects(_ t: Transition) -> [(AIRequestID, AITask)] {
        t.effects.compactMap { if case .ai(let id, let task, _) = $0 { (id, task) } else { nil } }
    }

    func testATranslationWaitsForAPauseAsksAndAnswersInTheRow() throws {
        let d = translationBar()
        let typed = d.user(.commandBar(.prefixQuery(.translate, "你好世界")))
        XCTAssertEqual(typed.effects, [.barTranslationDue(d.window, "你好世界")], "no agent at a key press")
        XCTAssertEqual(d.bar?.translation, BarTranslation(text: "你好世界", target: "English"))
        let due = d.system(.barTranslationDue(d.window, "你好世界"))
        let (id, task) = try XCTUnwrap(aiEffects(due).first)
        guard case .ask(let prompt) = task else { return XCTFail("\(task)") }
        XCTAssertTrue(prompt.contains("你好世界") && prompt.contains("English"), prompt)
        XCTAssertNotNil(d.bar, "the bar stays open")
        XCTAssertNil(d.view.ai, "the answer panel stays out of it")
        d.system(.aiResult(id, .text(" Hello, world \n")))
        XCTAssertEqual(d.bar?.translation?.answer, "Hello, world")
        XCTAssertNil(d.view.ai)
        XCTAssertEqual(d.user(.commandBar(.copyAnswer("Hello, world"))).effects, [.copyToPasteboard("Hello, world")])
        XCTAssertNil(d.bar)
    }

    func testChangingTheTextCancelsAtOnce() throws {
        let d = translationBar()
        d.user(.commandBar(.prefixQuery(.translate, "hello")))
        let due = d.system(.barTranslationDue(d.window, "hello"))
        let (id, _) = try XCTUnwrap(aiEffects(due).first)
        let changed = d.user(.commandBar(.prefixQuery(.translate, "hello there")))
        XCTAssertTrue(changed.effects.contains(.aiCancel(id)))
        XCTAssertEqual(d.bar?.translation?.text, "hello there")
        XCTAssertNil(d.bar?.translation?.answer)
        // The old agent's late answer lands nowhere.
        d.system(.aiResult(id, .text("old")))
        XCTAssertNil(d.bar?.translation?.answer)
        // A pause for a text since changed does nothing.
        XCTAssertEqual(aiEffects(d.system(.barTranslationDue(d.window, "hello"))).count, 0)
    }

    func testClosingTheBarByAnyCommandCancels() throws {
        let d = translationBar()
        d.user(.commandBar(.prefixQuery(.translate, "hello")))
        let (id, _) = try XCTUnwrap(aiEffects(d.system(.barTranslationDue(d.window, "hello"))).first)
        let dismissed = d.user(.commandBar(.dismiss))
        XCTAssertTrue(dismissed.effects.contains(.aiCancel(id)))
        let other = translationBar()
        other.user(.commandBar(.prefixQuery(.translate, "hello")))
        let (second, _) = try XCTUnwrap(aiEffects(other.system(.barTranslationDue(other.window, "hello"))).first)
        let toggled = other.user(.sidebar(.toggle))
        XCTAssertNil(other.bar)
        XCTAssertTrue(toggled.effects.contains(.aiCancel(second)))
    }

    func testAFailureIsTheRowsAndEmptyAnswersCopyNothing() throws {
        let d = translationBar()
        d.user(.commandBar(.prefixQuery(.translate, "hello")))
        let (id, _) = try XCTUnwrap(aiEffects(d.system(.barTranslationDue(d.window, "hello"))).first)
        d.system(.aiResult(id, .failed("no network")))
        XCTAssertEqual(d.bar?.translation?.failure, "no network")
        XCTAssertNil(d.view.ai)
        XCTAssertEqual(d.user(.commandBar(.copyAnswer(""))).effects, [])
        XCTAssertNotNil(d.bar, "the bar stays")
    }

    func testTranslatePrefixNeedsTranslationAndAnAgent() {
        let d = translationBar()
        XCTAssertEqual(QuickPrefixes.entry(named: "tr", in: d.bar!)?.action, .translate)
        XCTAssertEqual(QuickPrefixes.entry(named: "翻译", in: d.bar!)?.action, .translate)
        d.system(.aiProvidersDetected([]))
        XCTAssertNil(QuickPrefixes.entry(named: "translate", in: d.bar!))
        d.system(.aiProvidersDetected([.claude]))
        d.user(.settings(.max(.feature(.translation, false))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(QuickPrefixes.entry(named: "translate", in: d.bar!))
    }

    func testReadingATranslation() {
        func read(_ text: String) -> QuickTranslation.Request? { QuickTranslation.parse(text, systemTarget: "English") }
        let chinese = "Chinese (Simplified)"
        XCTAssertEqual(read("你好世界"), .text("你好世界", target: "English"), "mostly Chinese")
        XCTAssertEqual(read("hello world"), .text("hello world", target: chinese), "otherwise")
        XCTAssertEqual(read("这是 a test 的句子"), .text("这是 a test 的句子", target: chinese), "five Latin letters against five Han: not mostly Chinese")
        XCTAssertEqual(read("这是一个很长的句子 ok"), .text("这是一个很长的句子 ok", target: "English"))
        XCTAssertEqual(read("hello to ja"), .text("hello", target: "Japanese"))
        XCTAssertEqual(read("hello to japanese"), .text("hello", target: "Japanese"))
        XCTAssertEqual(read("HELLO TO KO"), .text("HELLO", target: "Korean"))
        XCTAssertEqual(read("你好到日文"), .text("你好", target: "Japanese"))
        XCTAssertEqual(read("你好 到日文"), .text("你好", target: "Japanese"))
        XCTAssertEqual(read("going to school"), .text("going to school", target: chinese), "school is no language")
        XCTAssertEqual(read("to be"), .text("to be", target: chinese), "not Belarusian")
        XCTAssertEqual(read("我到家了"), .text("我到家了", target: "English"), "家了 is no language")
        XCTAssertEqual(read("page"), .page(target: "English"))
        XCTAssertEqual(read("page to ja"), .page(target: "Japanese"))
        XCTAssertEqual(read("页面"), .page(target: "English"))
        XCTAssertNil(read(""))
        XCTAssertNil(read("  "))
        XCTAssertNil(read("to ja"), "nothing to translate")
    }

    // MARK: Dictionary

    func testTheDictionaryIsAskedAndItsAnswerKept() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.user(.commandBar(.prefixQuery(.define, "apple"))).effects, [.lookUpWord(d.window, "apple")])
        XCTAssertEqual(d.user(.commandBar(.prefixQuery(.define, ""))).effects, [])
        d.system(.definition(d.window, BarDefinition(word: "apple", text: "the round fruit")))
        XCTAssertEqual(d.bar?.definition?.text, "the round fruit")
        XCTAssertEqual(d.user(.commandBar(.prefixQuery(.define, "apple"))).effects, [], "this word has its answer")
        XCTAssertEqual(d.user(.commandBar(.openDictionary("apple"))).effects, [.openDictionary("apple")])
        XCTAssertNil(d.bar)
        XCTAssertEqual(d.user(.commandBar(.openDictionary("apple"))).effects, [], "no bar")
        d.system(.definition(d.window, BarDefinition(word: "late", text: "x")))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(d.bar?.definition, "a late answer does not reach the next opening")
    }

    // MARK: The pure rules

    func testWhatIsLeftOut() {
        let home = "/Users/u"
        for path in ["/Users/u/.ssh/key.txt", "/Users/u/.hidden", "/Users/u/Library/Application Support/Arc/Cookies", "/Users/u/Documents/.git/config",
                     "/Applications/Safari.app", "/Applications/Safari.app/Contents/Info.plist", "/Users/u/Downloads/Foo.app/Contents/x"] {
            XCTAssertTrue(LocalSources.isExcluded(path, home: home), path)
        }
        for path in ["/Users/u/Documents/report.pdf", "/Users/u/notes.txt", "/Users/u/Projects/Library/notes.txt", "/Applications/Readme.txt"] {
            XCTAssertFalse(LocalSources.isExcluded(path, home: home), path)
        }
        // A fixture folder under a hidden one is judged from the folder down.
        XCTAssertFalse(LocalSources.isExcluded("/repo/.build/fixture/Documents/a.txt", home: "/repo/.build/fixture"))
        XCTAssertTrue(LocalSources.isExcluded("/repo/.build/fixture/.secret/a.txt", home: "/repo/.build/fixture"))
        XCTAssertTrue(LocalSources.isExcluded("/repo/.build/fixture/Library/a.txt", home: "/repo/.build/fixture"))
    }

    func testRankingHits() {
        func hit(_ name: String) -> LocalHit { LocalHit(path: "/d/" + name, name: name) }
        let hits = ["my-budget.txt", "budgeting.txt", "budget.txt", "abudget.txt", "travel.txt", "budget 2026.xlsx"].map(hit)
        XCTAssertEqual(LocalSources.rank(hits, needle: "budget").map(\.name), ["budget.txt", "budgeting.txt", "budget 2026.xlsx", "my-budget.txt", "abudget.txt"])
        XCTAssertEqual(LocalSources.rank(hits, needle: "BUDGET", limit: 1).map(\.name), ["budget.txt"])
        XCTAssertEqual(LocalSources.rank(hits, needle: "2026 budget").map(\.name), ["budget 2026.xlsx"], "all the words, any order")
        XCTAssertEqual(LocalSources.rank([hit("Café Menu.pdf")], needle: "cafe").count, 1, "accents aside")
        XCTAssertEqual(LocalSources.rank(hits, needle: "zzz"), [])
    }
}
