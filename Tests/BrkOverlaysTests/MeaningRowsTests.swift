import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

/// The command bar's rows found by meaning (slice B2): each ranks as the page it is (an open tab, a visited page) in Arc's
/// scorer, never one another row already offers, only for the text they answer.
@MainActor
final class MeaningRowsTests: XCTestCase {
    private func bar(tabs: [SwitchCandidate] = [], history: [HistoryCandidate] = [], meaning: MeaningCandidates? = nil, suggestions: [String] = [],
                     suggestedFor: String? = nil) -> CommandBarSnapshot {
        var bar = commandBar(tabs, history, actions: [], suggestions: suggestions, suggestedFor: suggestedFor)
        bar.createsTab = true
        bar.meaning = meaning
        return bar
    }

    private func rank(_ text: String, _ bar: CommandBarSnapshot) -> [Suggestion] {
        Suggest.rank(query: text, bar: bar, appName: "Brk", resolve: { resolveTypedInput($0) })
    }

    private let mysql = candidate("t1", "MySQL 索引优化实战 - 掘金", "https://juejin.cn/post/1")
    private let soup = candidate("t2", "Chicken soup", "https://recipes.example/soup", focused: true)

    private func found(_ text: String) -> MeaningCandidates {
        MeaningCandidates(text: text, rows: [
            MeaningCandidate(place: .tab, title: "MySQL 索引优化实战 - 掘金", url: URL(string: "https://juejin.cn/post/1")!, tab: ItemID("t1")),
            MeaningCandidate(place: .history, title: "Use The Index, Luke!", url: URL(string: "https://use-the-index-luke.com/")!),
            MeaningCandidate(place: .archive, title: "深入理解 B+ 树索引", url: URL(string: "https://blog.csdn.net/x")!),
        ])
    }

    func testRowsFoundByMeaningRankAsThePageTheyAre() {
        let text = "上周那篇讲数据库的"
        let rows = rank(text, bar(tabs: [mysql, soup], meaning: found(text), suggestions: ["上周那篇讲数据库的文章"], suggestedFor: text))
        XCTAssertEqual(rows.first?.kind, .openTyped, "nothing matches the words: the search leads")
        let meaning = rows.filter { $0.kind == .meaning }
        XCTAssertEqual(meaning.count, 2, "two at most")
        XCTAssertEqual(meaning[0].title, "MySQL 索引优化实战 - 掘金", "an open tab outranks a visited page")
        XCTAssertEqual(meaning[0].command, .tab(.focus(ItemID("t1"))), "an open tab switches")
        XCTAssertEqual(meaning[0].hint, "Switch to Tab")
        XCTAssertEqual(meaning[0].symbol, "sparkle.magnifyingglass")
        XCTAssertNil(meaning[0].favicon, "the mark says where it came from")
        XCTAssertEqual(meaning[1].command, .commandBar(.submit("https://use-the-index-luke.com/")))
        XCTAssertNil(meaning[1].hint)
    }

    func testAPageAnotherRowShowsIsNotRepeated() {
        let text = "mysql"
        let rows = rank(text, bar(tabs: [mysql, soup], meaning: found(text)))
        XCTAssertEqual(rows.filter { $0.command == .tab(.focus(ItemID("t1"))) }.count, 1, "the word match already switches to it")
        XCTAssertEqual(rows.first { $0.kind == .meaning }?.title, "Use The Index, Luke!")
        let archived = rank("index", bar(meaning: MeaningCandidates(text: "index", rows: [found("index").rows[2]])))
        XCTAssertEqual(archived.first { $0.kind == .meaning }?.hint, "Archived")
    }

    func testNothingChangesWithoutAnAnswerForThisText() {
        let text = "上周那篇讲数据库的"
        let plain = rank(text, bar(tabs: [mysql, soup]))
        XCTAssertEqual(rank(text, bar(tabs: [mysql, soup], meaning: found("上周那篇"))), plain, "an answer for another text")
        XCTAssertFalse(plain.contains { $0.kind == .meaning })
        XCTAssertFalse(rank("juejin.cn", bar(tabs: [mysql], meaning: found("juejin.cn"))).contains { $0.kind == .meaning }, "an address")
        let focusedOnly = MeaningCandidates(text: "soup", rows: [MeaningCandidate(place: .tab, title: "Chicken soup", url: URL(string: "https://recipes.example/soup")!, tab: ItemID("t2"))])
        XCTAssertFalse(rank("soup", bar(tabs: [soup], meaning: focusedOnly)).contains { $0.kind == .meaning }, "never the tab already shown")
    }
}
