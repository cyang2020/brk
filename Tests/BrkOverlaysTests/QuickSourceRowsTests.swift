import AppKit
import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

/// The command bar's own sources beside Arc's rows: where they sit, when they stay out, and what Return, ⌘Return, ⌥Return
/// and Tab do on them.
@MainActor
final class QuickSourceRowsTests: XCTestCase {
    private let noon = Instant(milliseconds: 1_794_052_800_000)

    private func bar(tabs: [SwitchCandidate] = [], history: [HistoryCandidate] = [], suggestions: [String] = [], suggestedFor: String? = nil,
                     local: LocalResults? = nil, rates: CurrencyRates? = nil, fillsPane: Bool = false) -> CommandBarSnapshot {
        var bar = commandBar(tabs, history, actions: [], suggestions: suggestions, suggestedFor: suggestedFor)
        bar.createsTab = !fillsPane
        bar.fillsPane = fillsPane
        bar.local = local
        bar.rates = rates
        bar.now = noon
        return bar
    }

    private func rank(_ text: String, _ bar: CommandBarSnapshot, completing: String? = nil) -> [Suggestion] {
        Suggest.rank(query: text, bar: bar, appName: "Brk", resolve: { resolveTypedInput($0) }, completing: completing,
                     timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB"))
    }

    private func hit(_ name: String, _ folder: String = "/Users/u/Documents") -> LocalHit { LocalHit(path: folder + "/" + name, name: name) }
    private func app(_ name: String) -> LocalHit { LocalHit(path: "/Applications/" + name + ".app", name: name) }

    // MARK: Quick answers

    func testAnUnambiguousAnswerLeadsAndReturnCopiesIt() {
        let rows = rank("10ft in m", bar())
        XCTAssertEqual(rows[0].kind, .calculator)
        XCTAssertEqual(rows[0].title, "3.048 m")
        XCTAssertEqual(rows[0].subtitle, "10ft in m")
        XCTAssertEqual(rows[0].hint, "Copy Result")
        XCTAssertEqual(rows[0].command, .commandBar(.copyAnswer("3.048 m")))
        XCTAssertEqual(rows[1].kind, .openTyped, "the search stays one row down")
        XCTAssertTrue(rank("time in tokyo", bar())[0].title.contains("21:00"))
        XCTAssertEqual(rank("time in tokyo", bar())[0].kind, .calculator)
    }

    func testABareWordSitsBelowTheTypedRowSoReturnStillSearches() {
        for word in ["today", "tomorrow", "yesterday", "time", "now"] {
            let rows = rank(word, bar())
            XCTAssertEqual(rows[0].kind, .openTyped, word)
            XCTAssertEqual(rows[0].command, .commandBar(.submit(word)), word)
            XCTAssertEqual(rows[1].kind, .calculator, word)
        }
        XCTAssertTrue(rank("today", bar())[1].title.contains("7 November 2026"))
        // With the inline completion the site leads, the typed row follows it, the answer follows that.
        let completed = rank("time", bar(), completing: "time.com")
        XCTAssertEqual(Array(completed.map(\.kind).prefix(3)), [.topDomain, .openTyped, .calculator])
    }

    func testPlainArithmeticKeepsItsOneRow() {
        let rows = rank("2+2", bar())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].command, .commandBar(.calculate("2+2")))
        XCTAssertEqual(rows[0].title, "4")
    }

    func testACurrencyQuestionHasNoRowUntilRatesAreKnown() {
        XCTAssertNil(rank("100 usd in cny", bar()).first { $0.kind == .calculator }, "no network and no cache")
        XCTAssertEqual(rank("100 usd in cny", bar()).first?.kind, .openTyped)
        let rows = rank("100 usd in cny", bar(rates: CurrencyRates(date: "2026-11-06", perEuro: ["EUR": 1, "USD": 1.1, "CNY": 7.7])))
        XCTAssertEqual(rows[0].title, "700.00 CNY")
        XCTAssertEqual(rows[0].subtitle, "100 usd in cny · ECB 2026-11-06")
    }

    func testNoAnswerInAnEmptyPanesBar() {
        XCTAssertNil(rank("10ft in m", bar(fillsPane: true)).first { $0.kind == .calculator })
        XCTAssertNil(rank("today", bar(fillsPane: true)).first { $0.kind == .calculator })
    }

    func testAnOrdinarySearchOrAddressGetsNoAnswerRow() {
        for text in ["10 things", "best 10 ft in m", "example.com", "time.com"] {
            XCTAssertNil(rank(text, bar()).first { $0.kind == .calculator }, text)
        }
    }

    // MARK: Files and apps inline

    func testAppsAndFilesTakeTheLastPlacesAtMostTwo() {
        let suggestions = ["budget a", "budget b", "budget c"]
        let local = LocalResults(query: "budget", apps: [app("Budget")], files: [hit("budget.txt"), hit("budget2.txt")])
        let rows = rank("budget", bar(suggestions: suggestions, suggestedFor: "budget", local: local))
        XCTAssertEqual(rows.map(\.kind), [.openTyped, .searchSuggestion, .searchSuggestion, .app, .file])
        XCTAssertEqual(rows[3].title, "Budget")
        XCTAssertEqual(rows[3].hint, "Open App")
        XCTAssertEqual(rows[3].command, .commandBar(.local(.open, path: "/Applications/Budget.app")))
        XCTAssertEqual(rows[3].icon, .file("/Applications/Budget.app"))
        XCTAssertNil(rows[3].commandReturn)
        XCTAssertEqual(rows[4].title, "budget.txt")
        XCTAssertEqual(rows[4].subtitle, "/Users/u/Documents")
        XCTAssertEqual(rows[4].hint, "⌘↩ Reveal  ⌥↩ Copy Path")
        XCTAssertEqual(rows[4].command, .commandBar(.local(.open, path: "/Users/u/Documents/budget.txt")))
        XCTAssertEqual(rows[4].commandReturn, .commandBar(.local(.reveal, path: "/Users/u/Documents/budget.txt")))
        XCTAssertEqual(rows[4].optionReturn, .commandBar(.local(.copyPath, path: "/Users/u/Documents/budget.txt")))
    }

    func testTheyAreNeverTheTopHitOrTheTypedRow() {
        let local = LocalResults(query: "fixture", apps: [], files: [hit("fixture.txt"), hit("fixture2.txt")])
        let tabs = (1...4).map { candidate("t\($0)", "Fixture \($0)", "https://example.com/\($0)") }
        let rows = rank("fixture", bar(tabs: tabs, local: local))
        XCTAssertNotEqual(rows[0].kind, .file)
        XCTAssertTrue(rows.contains { $0.kind == .openTyped }, "the typed row stays")
        let typedAt = rows.firstIndex { $0.kind == .openTyped }!
        XCTAssertTrue(rows[...typedAt].allSatisfy { $0.kind != .file })
        XCTAssertEqual(rows.count, 5)
    }

    func testExactURLPrecedenceStaysAndAnAddressHasNoRows() {
        let tab = candidate("t1", "Home", "https://example.com/")
        let local = LocalResults(query: "https://example.com/", apps: [], files: [hit("example.txt")])
        let rows = rank("https://example.com/", bar(tabs: [tab], local: local))
        XCTAssertEqual(rows.first?.kind, .switchToTab)
        XCTAssertFalse(rows.contains { $0.kind == .file })
    }

    func testTheyWaitForThreeCharacters() {
        let local = LocalResults(query: "bu", apps: [], files: [hit("bu.txt")])
        XCTAssertFalse(rank("bu", bar(local: local)).contains { $0.kind == .file })
    }

    /// A stale answer: the bar's text has moved on, and the view must not show what answered the old one.
    func testAnAnswerToAnotherTextIsNotShown() {
        let local = LocalResults(query: "budget", apps: [app("Budget")], files: [hit("budget.txt")])
        XCTAssertEqual(rank("budget", bar(local: local)).filter { $0.kind == .file || $0.kind == .app }.count, 2)
        XCTAssertEqual(rank("budgets", bar(local: local)).filter { $0.kind == .file || $0.kind == .app }.count, 0)
        XCTAssertEqual(rank("budge", bar(local: local)).filter { $0.kind == .file || $0.kind == .app }.count, 0)
    }

    func testNoRowsInOtherBars() {
        let local = LocalResults(query: "budget", apps: [app("Budget")], files: [hit("budget.txt")])
        var editing = bar(local: local)
        editing.createsTab = false
        XCTAssertFalse(rank("budget", editing).contains { $0.kind == .file || $0.kind == .app }, "the bar over the page's address")
        XCTAssertFalse(rank("budget", bar(local: local, fillsPane: true)).contains { $0.kind == .file || $0.kind == .app })
        var ai = bar(local: local)
        ai.aiMode = .question
        XCTAssertFalse(rank("budget", ai).contains { $0.kind == .file || $0.kind == .app })
        let site = Suggest.rank(query: "budget", bar: bar(local: local), appName: "Brk", siteSearch: bing)
        XCTAssertFalse(site.contains { $0.kind == .file || $0.kind == .app })
    }

    /// With no new source matching, the rows are exactly what they were.
    func testArcsRowsDoNotChangeWhenNothingMatches() {
        let tabs = [candidate("t1", "GitHub", "https://github.com/arc"), candidate("t2", "Docs", "https://docs.example.com/")]
        let history = [visit("Budget tips", "https://example.org/budget", 100)]
        let suggestions = ["budget app", "budget planner"]
        for text in ["budget", "git", "doc", "how do browsers render fonts", "emoji", "file", "example.com"] {
            var plain = commandBar(tabs, history, actions: listedActions, suggestions: suggestions, suggestedFor: text)
            let before = Suggest.rank(query: text, bar: plain, appName: "Brk", resolve: { resolveTypedInput($0) })
            plain.createsTab = true
            plain.now = noon
            plain.local = LocalResults(query: text, apps: [], files: [])
            XCTAssertEqual(Suggest.rank(query: text, bar: plain, appName: "Brk", resolve: { resolveTypedInput($0) }), before, text)
        }
    }

    // MARK: Prefixes

    private func prefix(_ word: String, _ bar: CommandBarSnapshot) -> QuickPrefix { QuickPrefixes.entry(named: word, in: bar)! }

    private func ranked(_ text: String, word: String, _ bar: CommandBarSnapshot) -> [Suggestion] {
        Suggest.rank(query: text, bar: bar, appName: "Brk", prefix: prefix(word, bar), resolve: { resolveTypedInput($0) })
    }

    func testTheFilePrefixListsOnlyFilesOnceTheyAreIn() {
        XCTAssertEqual(ranked("budget", word: "file", bar()), [], "not in yet")
        let files = (1...7).map { hit("budget\($0).txt") }
        let rows = ranked("budget", word: "file", bar(local: LocalResults(query: "budget", scope: .files, apps: [], files: files)))
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { $0.kind == .file })
        XCTAssertEqual(ranked("budget", word: "file", bar(local: LocalResults(query: "budge", scope: .files, apps: [], files: files))), [], "stale")
        XCTAssertEqual(ranked("budget", word: "文件", bar(local: LocalResults(query: "budget", scope: .filesAndApps, apps: [], files: files))), [], "another question's answer")
    }

    func testTheAppPrefixListsOnlyApps() {
        let rows = ranked("bud", word: "app", bar(local: LocalResults(query: "bud", scope: .apps, apps: [app("Budget")], files: [])))
        XCTAssertEqual(rows.map(\.kind), [.app])
        XCTAssertEqual(rows[0].command, .commandBar(.local(.open, path: "/Applications/Budget.app")))
    }

    func testAIPrefixRows() {
        var snapshot = bar()
        snapshot.askProvider = "Claude"
        snapshot.askAgentFound = true
        snapshot.agentsFound = ["claude", "codex"]
        snapshot.askPageOn = true
        func only(_ text: String, _ word: String) -> Suggestion? {
            let rows = ranked(text, word: word, snapshot)
            XCTAssertLessThanOrEqual(rows.count, 1)
            return rows.first
        }
        XCTAssertEqual(only("why", "claude")?.command, .assist(.askAgent("why", agent: .claude)))
        XCTAssertEqual(only("why", "gpt")?.command, .assist(.askAgent("why", agent: .codex)))
        XCTAssertEqual(only("why", "codex")?.subtitle, "Ask Codex")
        XCTAssertEqual(only("why", "ask")?.command, .assist(.ask("why")))
        XCTAssertEqual(only("why", "问")?.subtitle, "Ask Claude")
        XCTAssertEqual(only("why", "page")?.command, .assist(.askPage("why")))
        XCTAssertNil(only("", "claude"), "nothing to send yet")
        XCTAssertNil(only("", "page"))
        XCTAssertEqual(only("", "summarize")?.command, .assist(.askPage("Summarize this page")), "Return with no text summarises")
        XCTAssertEqual(only("the costs", "总结")?.command, .assist(.askPage("Summarize this page: the costs")))
    }

    func testSplitRows() {
        var snapshot = bar(tabs: [candidate("t1", "Fixture Notes", "https://notes.example.com/"), candidate("t2", "Other", "https://other.example.com/")])
        snapshot.actions = [.addSplitView, .separateTabFromSplitView, .maximizeSplitPane, .splitHorizontal, .splitVertical, .removeSplitView]
        func tab(_ id: String, _ side: SplitEdge = .right) -> Command { .commandBar(.splitTab(side, ItemID(id))) }
        // No text: the open tabs, then an empty pane, then the commands.
        let empty = ranked("", word: "split", snapshot)
        XCTAssertEqual(empty.map(\.command), [tab("t1"), tab("t2"), .split(.addPane), .split(.separatePane(.focused)), .split(.toggleExpanded)])
        XCTAssertEqual(empty.first?.subtitle, "New pane on the right")
        // A side alone: the same, on that side.
        XCTAssertEqual(Array(ranked("left", word: "split", snapshot).map(\.command).prefix(3)), [tab("t1", .left), tab("t2", .left), .split(.addPaneAt(.left))])
        // A text: an open tab first; a web search only after what is open or was visited.
        let typed = ranked("fixture", word: "split", snapshot)
        XCTAssertEqual(typed.first?.title, "Fixture Notes")
        XCTAssertEqual(typed.first?.command, tab("t1"))
        XCTAssertEqual(typed[1].command, .commandBar(.splitOpen(.right, "fixture")))
        XCTAssertEqual(typed[1].symbol, "magnifyingglass")
        XCTAssertEqual(ranked("example", word: "split", snapshot).first?.command, tab("t1"), "by its address too")
        var visited = snapshot
        visited.history = [HistoryCandidate(url: URL(string: "https://guide.example.com/")!, title: "Fixture Guide", visitedAt: Instant(milliseconds: 1))]
        XCTAssertEqual(ranked("fixture", word: "split", visited).map(\.command).prefix(3).map { $0 }, [tab("t1"), .commandBar(.splitOpen(.right, "https://guide.example.com/")), .commandBar(.splitOpen(.right, "fixture"))])
        // An address leads, on any side, unless a tab has it.
        XCTAssertEqual(ranked("bottom example.com", word: "分屏", snapshot).first?.command, .commandBar(.splitOpen(.bottom, "example.com")))
        XCTAssertEqual(ranked("bottom example.com", word: "分屏", snapshot).first?.symbol, "globe")
        XCTAssertEqual(ranked("https://notes.example.com/", word: "split", snapshot).first?.command, tab("t1"))
        // A command named outright leads; the other commands follow what matches.
        XCTAssertEqual(ranked("expand", word: "split", snapshot).first?.command, .split(.toggleExpanded))
        XCTAssertEqual(ranked("expand", word: "split", snapshot)[1].command, .commandBar(.splitOpen(.right, "expand")))
        // Commands the menu has off do not show.
        snapshot.actions = [.addSplitView]
        XCTAssertEqual(ranked("", word: "split", snapshot).map(\.command), [tab("t1"), tab("t2"), .split(.addPane)])
    }

    func testWindowRows() {
        var snapshot = bar()
        snapshot.actions = [.fullscreen, .minimize, .toggleStayOnTop]
        let all = ranked("", word: "window", snapshot)
        XCTAssertEqual(all.count, 5, "the bar's five rows; a word narrows the rest")
        XCTAssertEqual(all.map(\.command), [.window(.place(.leftHalf)), .window(.place(.rightHalf)), .window(.place(.topHalf)), .window(.place(.bottomHalf)), .window(.place(.maximize))])
        XCTAssertEqual(ranked("cent", word: "窗口", snapshot).map(\.command), [.window(.place(.center))])
        XCTAssertEqual(ranked("centre", word: "window", snapshot).map(\.command), [.window(.place(.center))])
        XCTAssertEqual(ranked("next", word: "window", snapshot).map(\.command), [.window(.place(.nextDisplay))])
        XCTAssertEqual(ranked("full", word: "window", snapshot).first?.command, .app(.toggleFullScreen))
        XCTAssertEqual(ranked("minimize", word: "window", snapshot).first?.command, .app(.minimize))
        XCTAssertEqual(ranked("always", word: "window", snapshot).first?.command, .window(.toggleStayOnTop))
    }

    func testWindowRowsStayOutOfOrdinaryQueriesButAnExactPhrase() {
        for text in ["left", "half", "right", "maximize", "center", "next", "window", "display"] {
            XCTAssertFalse(rank(text, bar()).contains { if case .window(.place) = $0.command { true } else { false } }, text)
        }
        let rows = rank("left half", bar(suggestions: ["left half a", "left half b", "left half c"], suggestedFor: "left half"))
        XCTAssertEqual(rows.first?.kind, .openTyped, "Return still searches")
        XCTAssertEqual(rows.last?.command, .window(.place(.leftHalf)), "low down")
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rank("next display", bar()).last?.command, .window(.place(.nextDisplay)))
        var editing = bar()
        editing.createsTab = false
        XCTAssertFalse(rank("left half", editing).contains { if case .window(.place) = $0.command { true } else { false } })
        XCTAssertFalse(rank("left half", bar(fillsPane: true)).contains { if case .window(.place) = $0.command { true } else { false } })
    }

    func testTranslateRows() {
        var snapshot = bar()
        snapshot.translationOn = true
        snapshot.askAgentFound = true
        XCTAssertEqual(ranked("", word: "tr", snapshot), [])
        XCTAssertEqual(ranked("page to ja", word: "tr", snapshot).first?.command, .assist(.translate("Japanese")))
        // Waiting: says so, and Return has nothing to do.
        let waiting = ranked("hello", word: "tr", snapshot)
        XCTAssertEqual(waiting.first?.title, "Translating to Chinese (Simplified)…")
        XCTAssertEqual(waiting.first?.subtitle, "hello")
        XCTAssertEqual(waiting.first?.command, .commandBar(.copyAnswer("")))
        // The answer, one line in the row, whole on the pasteboard.
        var answered = BarTranslation(text: "hello", target: "Chinese (Simplified)")
        answered.answer = "你好\n世界"
        snapshot.translation = answered
        let done = ranked("hello", word: "翻译", snapshot)
        XCTAssertEqual(done.first?.title, "你好 世界")
        XCTAssertEqual(done.first?.command, .commandBar(.copyAnswer("你好\n世界")))
        XCTAssertEqual(done.first?.hint, "Copy Result")
        // An answer to another text is not this text's.
        XCTAssertEqual(ranked("hello there", word: "tr", snapshot).first?.command, .commandBar(.copyAnswer("")))
        // A failure says why.
        var failed = BarTranslation(text: "hello", target: "English")
        failed.failure = "no network"
        snapshot.translation = failed
        XCTAssertEqual(ranked("hello", word: "tr", snapshot).first?.title, "no network")
    }

    func testDefineRows() {
        var snapshot = bar()
        XCTAssertEqual(ranked("apple", word: "define", snapshot), [], "not in yet")
        snapshot.definition = BarDefinition(word: "apple", text: "the round fruit of a tree")
        let rows = ranked("apple", word: "查", snapshot)
        XCTAssertEqual(rows.first?.title, "the round fruit of a tree")
        XCTAssertEqual(rows.first?.hint, "Open Dictionary")
        XCTAssertEqual(rows.first?.command, .commandBar(.openDictionary("apple")))
        XCTAssertEqual(ranked("apples", word: "def", snapshot), [], "stale")
        snapshot.definition = BarDefinition(word: "zzz", text: nil)
        XCTAssertEqual(ranked("zzz", word: "def", snapshot).first?.title, "No definition for zzz")
        XCTAssertEqual(ranked("zzz", word: "def", snapshot).first?.command, .commandBar(.copyAnswer("")), "Return does nothing")
    }

    func testColorRowsWithNoPrefix() {
        let full = rank("#ff5500", bar())
        XCTAssertEqual(Array(full.map(\.title).prefix(3)), ["#FF5500", "rgb(255, 85, 0)", "hsl(20, 100%, 50%)"], "in full it leads")
        XCTAssertEqual(full[0].command, .commandBar(.copyAnswer("#FF5500")))
        XCTAssertEqual(full[1].command, .commandBar(.copyAnswer("rgb(255, 85, 0)")))
        XCTAssertEqual(full[2].command, .commandBar(.copyAnswer("hsl(20, 100%, 50%)")))
        XCTAssertEqual(full[0].icon, .swatch(QuickColor(red: 255, green: 85, blue: 0).rgba))
        XCTAssertEqual(full[3].kind, .openTyped, "the search is still there")
        XCTAssertEqual(rank("rgb(255,85,0)", bar())[0].title, "#FF5500")
        XCTAssertEqual(rank("hsl(20,100%,50%)", bar())[0].title, "#FF5500")
    }

    func testBareThreeDigitHashKeepsReturnSearching() {
        let rows = rank("#abc", bar())
        XCTAssertEqual(rows[0].kind, .openTyped)
        XCTAssertEqual(rows[0].command, .commandBar(.submit("#abc")))
        XCTAssertEqual(Array(rows[1...3].map(\.kind)), [.color, .color, .color])
        XCTAssertEqual(rows[1].title, "#AABBCC")
    }

    func testAHashtagAndWordsAreNoColor() {
        for text in ["#hashtag", "#ab", "tomato", "red", "rgb"] {
            XCTAssertFalse(rank(text, bar()).contains { $0.kind == .color }, text)
        }
        XCTAssertEqual(rank("#hashtag", bar()).first?.kind, .openTyped)
    }

    func testColorRowsNotInAnEmptyPane() {
        XCTAssertFalse(rank("#ff5500", bar(fillsPane: true)).contains { $0.kind == .color })
    }

    func testTheColorPrefixReadsNames() {
        let rows = ranked("tomato", word: "color", bar())
        XCTAssertEqual(rows.map(\.title), ["#FF6347", "rgb(255, 99, 71)", "hsl(9, 100%, 64%)"])
        XCTAssertEqual(rows[2].command, .commandBar(.copyAnswer("hsl(9, 100%, 64%)")))
        XCTAssertEqual(ranked("#f50", word: "颜色", bar()).first?.title, "#FF5500")
        XCTAssertEqual(ranked("nothing", word: "colour", bar()), [])
        XCTAssertEqual(ranked("", word: "color", bar()), [])
    }

    func testAPrefixHasTheListToItself() {
        var snapshot = bar()
        snapshot.actions = [.addSplitView]
        let rows = Suggest.rank(query: "view", bar: snapshot, appName: "Brk", prefix: prefix("split", snapshot), resolve: { resolveTypedInput($0) })
        XCTAssertEqual(rows.first?.command, .commandBar(.splitOpen(.right, "view")))
        XCTAssertEqual(Suggest.rank(query: "", bar: snapshot, appName: "Brk", prefix: prefix("split", snapshot), resolve: { resolveTypedInput($0) }).first?.title, "Add Split View")
    }

    func testTheCalcPrefixForcesCalculation() {
        for word in ["calc", "=", "算"] {
            XCTAssertEqual(ranked("2+2", word: word, bar()).first?.title, "4", word)
            XCTAssertEqual(ranked("2+2", word: word, bar()).first?.command, .commandBar(.copyAnswer("4")), word)
        }
        XCTAssertEqual(ranked("42", word: "calc", bar()).first?.title, "42", "a plain number is an answer here")
        XCTAssertEqual(ranked("10ft in m", word: "calc", bar()).first?.title, "3.048 m")
        XCTAssertEqual(ranked("hello", word: "calc", bar()), [])
        XCTAssertEqual(ranked("", word: "calc", bar()), [])
    }

    func testAPastedFileWordIsAnOrdinarySearch() {
        // As plain text, "file budget" is not a mode any more.
        XCTAssertEqual(rank("file budget", bar()).first?.kind, .openTyped)
        XCTAssertEqual(rank("emoji smile", bar()).first?.kind, .openTyped)
        XCTAssertFalse(rank("emoji smile", bar()).contains { $0.kind == .emoji })
    }

    func testEmojiMatchesListAndReturnCopies() throws {
        let rows = ranked("smile", word: "emoji", bar())
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { $0.kind == .emoji })
        guard case .emoji(let emoji)? = rows[0].icon else { return XCTFail("no emoji picture") }
        XCTAssertEqual(rows[0].command, .commandBar(.copyAnswer(emoji)))
        XCTAssertEqual(rows[0].hint, "Copy Emoji")
        XCTAssertEqual(ranked("zzzqqq", word: "表情", bar()), [])
    }

    func testTheSystemsNamesFindAnEmoji() {
        let entries = EmojiIndex.build(systemNames: ["😄": "grinning face with smiling eyes", "😼": "cat with wry smile", "👍": "thumbs up", "🐱": "cat face"])
        XCTAssertEqual(EmojiIndex.matches("smile", limit: 5, in: entries).first?.emoji, "😼", "the whole word first")
        XCTAssertEqual(EmojiIndex.matches("smile", limit: 5, in: entries).map(\.emoji), ["😼", "😄"], "the stem finds smiling")
        XCTAssertEqual(EmojiIndex.matches("thumbs up", limit: 5, in: entries).map(\.emoji), ["👍"])
        XCTAssertEqual(EmojiIndex.matches("CAT", limit: 5, in: entries).map(\.emoji), ["🐱", "😼"])
        XCTAssertEqual(EmojiIndex.matches("zzz", limit: 5, in: entries), [])
        // With no system file, Unicode's own names through the standard library.
        let fallback = EmojiIndex.build(systemNames: [:])
        XCTAssertFalse(fallback.isEmpty)
        XCTAssertTrue(EmojiIndex.matches("rocket", limit: 5, in: fallback).contains { $0.emoji == "🚀" })
    }

    // MARK: Keys

    private final class Box { var sent: [Command] = [] }
    private let box = CGRect(x: 0, y: 0, width: 640, height: 338)

    private func view(_ bar: CommandBarSnapshot, _ sink: Box) -> CommandBarView {
        let view = CommandBarView(dispatch: { sink.sent.append($0) })
        view.resolve = { resolveTypedInput($0) }
        view.show(bar, in: box, scheme: .light)
        return view
    }

    private func type(_ text: String, into view: CommandBarView) {
        view.input.stringValue = text
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.input))
    }

    private func press(_ selector: Selector, _ view: CommandBarView) {
        _ = view.control(view.input, textView: NSTextView(), doCommandBy: selector)
    }

    private func tabBar(asks: Bool = true) -> CommandBarSnapshot {
        var snapshot = bar()
        snapshot.askProvider = asks ? "Claude" : nil
        snapshot.askAgentFound = asks
        snapshot.siteSearch = [bing]
        return snapshot
    }

    func testTabSendsTheTypedTextToTheLocalAI() {
        let sink = Box(), bar = view(tabBar(), sink)
        type("why is the sky blue", into: bar)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), bar)
        XCTAssertEqual(sink.sent, [.assist(.ask("why is the sky blue"))])
    }

    func testSiteSearchAndTheToolsNameKeepTabFirst() {
        let sink = Box(), offered = view(tabBar(), sink)
        type("bi", into: offered)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), offered)
        XCTAssertEqual(offered.siteSearch?.id, bing.id)
        XCTAssertFalse(sink.sent.contains(.assist(.ask("bi"))))

        let named = view(tabBar(), sink)
        type("cla", into: named)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), named)
        XCTAssertEqual(sink.sent, [.assist(.open(.question))])
    }

    func testTabStaysAsItWasWithNoTextAMaxOffOrAnAddress() {
        let sink = Box()
        let empty = view(tabBar(), sink)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), empty)
        XCTAssertEqual(sink.sent, [], "no text")

        let off = view(tabBar(asks: false), sink)
        type("why is the sky blue", into: off)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), off)
        XCTAssertEqual(sink.sent, [], "Max off")

        var missing = tabBar()
        missing.askAgentFound = false
        let noAgent = view(missing, sink)
        type("why is the sky blue", into: noAgent)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), noAgent)
        XCTAssertEqual(sink.sent, [], "no agent found")

        let address = view(tabBar(), sink)
        type("example.com", into: address)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), address)
        XCTAssertEqual(sink.sent, [], "an address")

        var editing = tabBar()
        editing.createsTab = false
        let edit = view(editing, sink)
        type("why is the sky blue", into: edit)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), edit)
        XCTAssertEqual(sink.sent, [], "the bar over the page's address")
    }

    func testReturnOnAFileRowOpensIt() {
        let sink = Box()
        let local = LocalResults(query: "budget", scope: .files, apps: [], files: [hit("budget.txt")])
        let bar = view(bar(local: local), sink)
        type("file", into: bar)
        press(#selector(NSResponder.insertTab(_:)), bar)
        type("budget", into: bar)
        XCTAssertEqual(sink.sent.last, .commandBar(.prefixQuery(.files, "budget")))
        sink.sent.removeAll()
        press(#selector(NSResponder.insertNewline(_:)), bar)
        XCTAssertEqual(sink.sent, [.commandBar(.local(.open, path: "/Users/u/Documents/budget.txt"))])
    }

    // MARK: Entering and leaving a prefix

    /// Character by character, as a keyboard types: each key changes the text by one.
    private func typeKeys(_ text: String, into view: CommandBarView) {
        for character in text { type(view.typed + String(character), into: view) }
    }

    private func enterWord(_ word: String, into view: CommandBarView) {
        type(word, into: view)
        press(#selector(NSResponder.insertTab(_:)), view)
    }

    func testAWholeWordThenTabEntersAndThePillShowsIt() {
        let sink = Box(), bar = view(bar(), sink)
        enterWord("emoji", into: bar)
        XCTAssertEqual(bar.prefix?.action, .emoji)
        XCTAssertEqual(bar.typed, "")
        XCTAssertEqual(bar.input.stringValue, "")
        let cased = view(self.bar(), sink)
        enterWord("EMOJI", into: cased)
        XCTAssertEqual(cased.prefix?.action, .emoji, "case aside")
    }

    /// A search can start with any of the words: Space is always a space, and only Tab enters.
    func testSpaceNeverEntersAndTabEntersEveryWord() {
        let sink = Box()
        var snapshot = bar()
        snapshot.actions = [.addSplitView]
        snapshot.askProvider = "Claude"
        snapshot.askAgentFound = true
        snapshot.agentsFound = ["claude", "codex", "gemini", "cursor"]
        snapshot.askPageOn = true
        snapshot.translationOn = true
        for word in QuickPrefixes.all.flatMap(\.words) {
            let plain = view(snapshot, sink)
            typeKeys(word + " pea soup", into: plain)
            XCTAssertNil(plain.prefix, word)
            XCTAssertEqual(plain.typed, word + " pea soup")
            let tabbed = view(snapshot, sink)
            enterWord(word, into: tabbed)
            XCTAssertNotNil(tabbed.prefix, word)
        }
    }

    func testPastedTextNeverEnters() {
        let sink = Box()
        for text in ["file report notes", "file ", "emoji smile", "calc 2+2"] {
            let bar = view(bar(), sink)
            type(text, into: bar)   // the whole text arrives in one change, as a paste does
            XCTAssertNil(bar.prefix, text)
            XCTAssertEqual(bar.typed, text)
        }
    }

    func testBackspaceAndEscGiveTheWordBack() {
        let sink = Box(), bar = view(bar(), sink)
        enterWord("emoji", into: bar)
        press(#selector(NSResponder.deleteBackward(_:)), bar)
        XCTAssertNil(bar.prefix)
        XCTAssertEqual(bar.input.stringValue, "emoji")
        XCTAssertEqual(bar.typed, "emoji")
        // The word can now be typed as a search.
        typeKeys(" report", into: bar)
        XCTAssertNil(bar.prefix)
        XCTAssertEqual(bar.typed, "emoji report")
        XCTAssertEqual(sink.sent.last, .commandBar(.queryChanged("emoji report")))
        // Tab on the word again.
        type("", into: bar)
        enterWord("emoji", into: bar)
        XCTAssertEqual(bar.prefix?.action, .emoji)
        press(#selector(NSResponder.cancelOperation(_:)), bar)
        XCTAssertNil(bar.prefix)
        XCTAssertEqual(bar.input.stringValue, "emoji")
        // Esc again closes the bar, as in site search.
        sink.sent.removeAll()
        press(#selector(NSResponder.cancelOperation(_:)), bar)
        XCTAssertEqual(sink.sent, [.commandBar(.dismiss)])
    }

    func testTheChineseWordsEnterToo() {
        let sink = Box()
        for (word, action) in [("文件", QuickPrefixAction.files), ("应用", .apps), ("表情", .emoji), ("算", .calculate), ("分屏", .split), ("窗口", .window), ("查", .define), ("颜色", .color)] {
            let bar = view(self.bar(), sink)
            var snapshot = self.bar()
            snapshot.actions = [.addSplitView]
            bar.show(snapshot, in: box, scheme: .light)
            type(word, into: bar)
            XCTAssertEqual(bar.prefixOffer?.action, action, word)
            press(#selector(NSResponder.insertTab(_:)), bar)
            XCTAssertEqual(bar.prefix?.action, action, word)
        }
    }

    func testBackspaceOnTextInThePillDoesNotLeave() {
        let sink = Box(), bar = view(bar(), sink)
        enterWord("emoji", into: bar)
        typeKeys("a", into: bar)
        press(#selector(NSResponder.deleteBackward(_:)), bar)
        XCTAssertNotNil(bar.prefix, "only in the empty input")
    }

    func testAnEngineOfTheSameNameWinsOverAPrefix() {
        let sink = Box()
        var snapshot = bar()
        let named = SearchEngineCandidate(id: SearchEngineID("mine"), name: "File", keyword: "file")
        snapshot.siteSearch = [named]
        let spaced = view(snapshot, sink)
        typeKeys("file ", into: spaced)
        XCTAssertEqual(spaced.siteSearch?.id, named.id)
        XCTAssertNil(spaced.prefix)
        let tabbed = view(snapshot, sink)
        type("file", into: tabbed)
        press(#selector(NSResponder.insertTab(_:)), tabbed)
        XCTAssertEqual(tabbed.siteSearch?.id, named.id)
    }

    /// The real list: nothing in Brk's table is an engine's name or keyword.
    func testNoCollisionWithTheBuiltInEngines() {
        let engines = (SearchEngine.builtIn + SearchEngine.siteSearchSites).flatMap { [$0.name, $0.keyword] }.map(Suggest.fold)
        for word in QuickPrefixes.all.flatMap(\.words) {
            XCTAssertFalse(engines.contains(Suggest.fold(word)), word)
        }
    }

    func testNotInOtherBarsOrAPrivateWindow() {
        let sink = Box()
        var editing = bar()
        editing.createsTab = false
        let edit = view(editing, sink)
        enterWord("emoji", into: edit)
        XCTAssertNil(edit.prefix, "the bar over the page's address")
        let pane = view(bar(fillsPane: true), sink)
        enterWord("emoji", into: pane)
        XCTAssertNil(pane.prefix, "an empty pane's bar")
        var ai = bar()
        ai.aiMode = .question
        let question = view(ai, sink)
        enterWord("emoji", into: question)
        XCTAssertNil(question.prefix, "AI mode")
        // Site search: the words are plain text in it.
        var withEngine = bar()
        withEngine.siteSearch = [bing]
        let site = view(withEngine, sink)
        typeKeys("bing ", into: site)
        XCTAssertEqual(site.siteSearch?.id, bing.id)
        enterWord("emoji", into: site)
        XCTAssertNil(site.prefix, "site search")
        XCTAssertEqual(site.typed, "emoji")
        // A private window lists nothing of the user's.
        var incognito = bar()
        incognito.isPrivate = true
        let secret = view(incognito, sink)
        enterWord("file", into: secret)
        XCTAssertNil(secret.prefix)
        XCTAssertEqual(secret.typed, "file")
        let calc = view(incognito, sink)
        enterWord("calc", into: calc)
        XCTAssertEqual(calc.prefix?.action, .calculate, "nothing personal in a calculation")
    }

    /// Each prefix is told apart at a glance, and its name stays legible on its colour.
    /// Each prefix is told apart at a glance, its colour lies lightly over the card, and its word reads at 4.5:1 on it in
    /// light and dark bars.
    func testEveryPrefixHasItsOwnColourAndItsWordReads() {
        for prefix in QuickPrefixes.all {
            for dark in [false, true] {
                let card = dark ? QuickChipColors.darkCard : QuickChipColors.lightCard
                let fill = QuickChipColors.mix(card, prefix.tint, dark ? QuickChipColors.fillAlpha.dark : QuickChipColors.fillAlpha.light)
                let text = QuickChipColors.text(prefix.tint, on: fill, dark: dark)
                XCTAssertGreaterThanOrEqual(QuickChipColors.contrast(text, fill), 4.5, "\(prefix.title) dark: \(dark)")
            }
        }
        XCTAssertEqual(Set(QuickPrefixes.all.map(\.tint)).count, QuickPrefixes.all.count)
    }

    private func srgb(_ color: CGColor?) -> [CGFloat] {
        color?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
    }

    func testAPrefixsPillWearsItsColourLightlyAndAnEnginesStaysAsItWas() {
        let sink = Box()
        var snapshot = bar()
        snapshot.siteSearch = [bing]
        let plain = view(snapshot, sink)
        enterWord("emoji", into: plain)
        let tint = try! XCTUnwrap(plain.prefix?.tint)
        let filled = srgb(plain.sitePill.layer?.backgroundColor)
        XCTAssertEqual(filled[0], CGFloat(tint.red), accuracy: 0.01)
        XCTAssertEqual(filled[1], CGFloat(tint.green), accuracy: 0.01)
        XCTAssertEqual(filled[2], CGFloat(tint.blue), accuracy: 0.01)
        XCTAssertEqual(filled[3], CGFloat(QuickChipColors.fillAlpha.light), accuracy: 0.01, "the card shows through")
        let word = QuickChipColors.of(tint, dark: false).text
        XCTAssertEqual(plain.sitePill.label.textColor, word)
        press(#selector(NSResponder.cancelOperation(_:)), plain)
        XCTAssertTrue(plain.sitePill.isHidden)
        let site = view(snapshot, sink)
        typeKeys("bing ", into: site)
        XCTAssertEqual(site.siteSearch?.id, bing.id)
        XCTAssertEqual(srgb(site.sitePill.layer?.backgroundColor)[3], 0.04, accuracy: 0.005, "a search engine's pill stays Arc's grey")
    }

    /// The pill's word stands on the input's baseline and in the middle of the pill across; the offer's word is level with Tab.
    func testThePillsWordIsOnTheInputsLineAndCentred() {
        let sink = Box()
        for word in ["emoji", "summarize", "calc", "分屏"] {
            var snapshot = bar()
            snapshot.actions = [.addSplitView]
            snapshot.askPageOn = true
            snapshot.askProvider = "Claude"
            snapshot.askAgentFound = true
            let bar = view(snapshot, sink)
            enterWord(word, into: bar)
            bar.layoutSubtreeIfNeeded()
            let pill = bar.sitePill, label = pill.label
            let pillBaseline = pill.frame.minY + label.frame.minY + label.firstBaselineOffsetFromTop
            let inputBaseline = bar.input.frame.minY + bar.input.firstBaselineOffsetFromTop
            XCTAssertEqual(pillBaseline, inputBaseline, accuracy: 0.01, word)
            XCTAssertEqual(label.frame.midX, pill.bounds.midX, accuracy: 0.01, "\(word): centred across")
            // The capitals sit in the middle of the pill.
            let font = try! XCTUnwrap(label.font)
            XCTAssertEqual(label.frame.minY + label.firstBaselineOffsetFromTop - font.capHeight / 2, pill.bounds.midY, accuracy: 0.01, word)
        }
    }

    func testAPrefixOnOfferShowsAsItsChipBesideTab() {
        let sink = Box()
        var snapshot = bar()
        snapshot.siteSearch = [bing]
        let offered = view(snapshot, sink)
        XCTAssertTrue(offered.offerChip.isHidden)
        type("em", into: offered)
        offered.layoutSubtreeIfNeeded()
        XCTAssertFalse(offered.offerChip.isHidden, "Emoji is on offer")
        XCTAssertEqual(offered.offerChip.title, "Emoji")
        XCTAssertEqual(srgb(offered.offerChip.layer?.backgroundColor)[3], CGFloat(QuickChipColors.fillAlpha.light), accuracy: 0.01)
        type("bi", into: offered)
        offered.layoutSubtreeIfNeeded()
        XCTAssertNotNil(offered.offer)
        XCTAssertTrue(offered.offerChip.isHidden, "an engine's offer is Arc's words")
    }

    /// With Max off, or the agent missing, an AI prefix's word says why beside the input, and Tab opens the settings that
    /// change it, instead of doing nothing and leaving the word to run into the next one ("claudehello").
    func testABlockedAIPrefixSaysWhyAndTabOpensItsSettings() {
        let sink = Box()
        var off = bar()
        off.agentsFound = ["claude"]
        let bar = view(off, sink)
        type("claude", into: bar)
        XCTAssertNil(bar.prefixOffer)
        XCTAssertEqual(bar.blockedPrefix?.reason, "Claude is off in Max settings")
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), bar)
        XCTAssertEqual(sink.sent, [.settings(.openPane(.max))])
        XCTAssertNil(bar.prefix)

        var on = off
        on.askProvider = "Codex"
        on.askAgentFound = true
        on.agentsFound = ["codex"]
        XCTAssertEqual(QuickPrefixes.blocked(for: "cla", in: on)?.reason, "Claude is not installed")
        XCTAssertEqual(QuickPrefixes.blocked(for: "page", in: on)?.pane, .advanced, "Ask on Page's switch is in Advanced")
        XCTAssertNil(QuickPrefixes.blocked(for: "gpt", in: on), "it works")
        XCTAssertNil(QuickPrefixes.blocked(for: "c", in: on), "one letter")
        XCTAssertNil(QuickPrefixes.blocked(for: "emoji", in: off), "not an AI prefix")
        var secret = off
        secret.isPrivate = true
        XCTAssertNil(QuickPrefixes.blocked(for: "claude", in: secret), "a private window has no AI to turn on")
    }

    /// Part of the tool's name offers the tool's prefix, and Tab enters what is offered.
    func testPartOfTheToolsNameOffersItsPrefixAndTabEntersIt() {
        let sink = Box()
        var snapshot = tabBar()
        snapshot.agentsFound = ["claude"]
        let bar = view(snapshot, sink)
        type("cl", into: bar)
        XCTAssertEqual(bar.prefixOffer?.title, "Claude")
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), bar)
        XCTAssertEqual(bar.prefix?.title, "Claude")
        XCTAssertFalse(sink.sent.contains(.assist(.open(.question))))
    }

    func testPartOfAWordIsOfferedBesideTheInputOnlyWithoutASiteSearchOffer() {
        let sink = Box()
        let plain = view(bar(), sink)
        type("f", into: plain)
        XCTAssertNil(plain.prefixOffer, "one letter")
        type("fi", into: plain)
        XCTAssertEqual(plain.prefixOffer?.action, .files, "two letters, as Arc offers a site search")
        press(#selector(NSResponder.insertTab(_:)), plain)
        XCTAssertEqual(plain.prefix?.action, .files, "Tab enters what is offered")

        var withEngine = bar()
        withEngine.siteSearch = [SearchEngineCandidate(id: SearchEngineID("mine"), name: "Filings", keyword: "filings")]
        let offered = view(withEngine, sink)
        type("fil", into: offered)
        XCTAssertNotNil(offered.offer)
        XCTAssertNil(offered.prefixOffer, "the engine's offer goes first")

        let spaced = view(bar(), sink)
        type("fil ter", into: spaced)
        XCTAssertNil(spaced.prefixOffer, "one word")
    }

    func testAToolsPartNameStillOpensQuestionMode() {
        let sink = Box(), bar = view(tabBar(), sink)
        type("cla", into: bar)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), bar)
        XCTAssertEqual(sink.sent, [.assist(.open(.question))])
    }
}
