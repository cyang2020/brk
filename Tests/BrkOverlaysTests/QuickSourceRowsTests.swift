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

    // MARK: The typed modes

    func testTheFileModeListsOnlyFilesOnceTheyAreIn() {
        let text = "file budget"
        XCTAssertEqual(rank(text, bar()).first?.kind, .openTyped, "not in yet")
        let files = (1...7).map { hit("budget\($0).txt") }
        let rows = rank(text, bar(local: LocalResults(query: text, apps: [], files: files)))
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { $0.kind == .file })
        XCTAssertEqual(rank(text, bar(local: LocalResults(query: "file budge", apps: [], files: files))).first?.kind, .openTyped, "stale")
        XCTAssertEqual(rank(text, bar(local: LocalResults(query: text, apps: [], files: []))).first?.kind, .openTyped, "no file: the search is there")
    }

    func testEmojiMatchesListAndReturnCopies() throws {
        let rows = rank("emoji smile", bar())
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { $0.kind == .emoji })
        guard case .emoji(let emoji)? = rows[0].icon else { return XCTFail("no emoji picture") }
        XCTAssertEqual(rows[0].command, .commandBar(.copyAnswer(emoji)))
        XCTAssertEqual(rows[0].hint, "Copy Emoji")
        XCTAssertFalse(rank("emoji zzzqqq", bar()).contains { $0.kind == .emoji }, "no match: as usual")
        XCTAssertFalse(rank("emoji", bar()).contains { $0.kind == .emoji })
        var editing = bar()
        editing.createsTab = false
        XCTAssertFalse(rank("emoji smile", editing).contains { $0.kind == .emoji })
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

        let mode = view(tabBar(), sink)
        type("file budget", into: mode)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertTab(_:)), mode)
        XCTAssertEqual(sink.sent, [], "a typed mode")

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
        let text = "file budget"
        let local = LocalResults(query: text, apps: [], files: [hit("budget.txt")])
        let bar = view(bar(local: local), sink)
        type(text, into: bar)
        sink.sent.removeAll()
        press(#selector(NSResponder.insertNewline(_:)), bar)
        XCTAssertEqual(sink.sent, [.commandBar(.local(.open, path: "/Users/u/Documents/budget.txt"))])
    }
}
