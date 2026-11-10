import BrkBase
@testable import BrkDomain
import XCTest

/// Slice B2's wiring as the reducer sees it: search by meaning in the command bar and on the History page (asked only
/// while the search model is ready, kept only for the text it answers), the index keys resolved against the state, and
/// Place New Tabs' hint for JevK5.
final class LocalWiringDomainTests: XCTestCase {
    private func searchReady(_ d: Driver, ready: Bool = true) {
        let row = LocalModelRow(kind: .search, title: "EmbeddingGemma 2", purpose: "Finds tabs by meaning.", bytes: 309_855_456,
                                license: "Apache 2.0", languages: "100+ languages", residentMB: 500, stage: ready ? .ready : .absent, runtimeFound: true)
        d.system(.localModels(LocalModelsSnapshot(rows: [row], indexed: nil)))
    }

    private func meaning(_ t: Transition) -> [MeaningQuery] {
        t.effects.compactMap { if case .searchByMeaning(_, let query) = $0 { query } else { nil } }
    }

    func testTheBarAsksByMeaningOnlyWhileTheSearchModelIsReady() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("上周那篇讲数据库的")))), [], "no search model: nothing changes")
        searchReady(d)
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("上周那篇讲数据库的")))), [MeaningQuery(text: "上周那篇讲数据库的", scope: .commandBar, profile: .default)])
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("  database article  ")))).map(\.text), ["database article"])
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("a")))), [], "one character")
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("example.com")))), [], "an address")
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("https://example.com/x")))), [], "an address")
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("1+1")))), [], "arithmetic")
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("")))), [])
        searchReady(d, ready: false)
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("database article")))), [], "the model went away")
    }

    func testAPrivateWindowNeverAsks() {
        let d = Driver()
        searchReady(d)
        d.user(.window(.newIncognito))
        let window = d.state.doc.windows.first { $0.value.kind == .incognito }!.key
        d.user(.commandBar(.open(.newTab)), in: window)
        XCTAssertEqual(meaning(d.user(.commandBar(.queryChanged("database article")), in: window)), [])
        d.system(.meaningResults(window, MeaningResults(text: "database article", scope: .commandBar, hits: [MeaningHit(key: "history:https://a.example/", score: 0.9)])))
        XCTAssertNil(d.state.session.windows[window]?.meaning[.commandBar])
    }

    func testTheBarsAnswerResolvesKeysAndGoesWithTheBar() throws {
        let d = Driver()
        searchReady(d)
        let soup = d.open("https://recipes.example/soup")
        d.page(soup, .titleChanged("Chicken noodle soup"))
        let other = d.open("https://news.example/today")
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.queryChanged("something warm to cook")))
        d.system(.meaningResults(d.window, MeaningResults(text: "something warm to cook", scope: .commandBar, hits: [
            MeaningHit(key: "history:https://recipes.example/soup", score: 0.84), MeaningHit(key: "tab:" + soup.rawValue, score: 0.84),
            MeaningHit(key: "history:https://news.example/today", score: 0.8),
            MeaningHit(key: "tab:gone", score: 0.79), MeaningHit(key: "history:https://never.example/", score: 0.78)])))
        guard case .commandBar(let bar)? = d.view.overlay else { return XCTFail("no bar") }
        let found = try XCTUnwrap(bar.meaning)
        XCTAssertEqual(found.text, "something warm to cook")
        XCTAssertEqual(found.rows.map(\.place), [.tab, .history], "keys the state no longer has are skipped")
        XCTAssertEqual(found.rows.first?.tab, soup, "an address open in a tab is the tab, though its history entry came first")
        XCTAssertEqual(found.rows.first?.url.absoluteString, "https://recipes.example/soup")
        XCTAssertEqual(found.rows.last?.url.absoluteString, "https://news.example/today")
        _ = other
        d.user(.commandBar(.dismiss))
        XCTAssertNil(d.state.session.windows[d.window]?.meaning[.commandBar], "closing the bar drops its answer")
        d.system(.meaningResults(d.window, MeaningResults(text: "late", scope: .commandBar, hits: [])))
        XCTAssertNil(d.state.session.windows[d.window]?.meaning[.commandBar], "an answer after the bar closed is dropped")
    }

    func testIndexKeysBecomeTheTabToolsIds() throws {
        let d = Driver()
        let tab = d.open("https://recipes.example/soup")
        let visit = try XCTUnwrap(d.state.doc.history.last { $0.url.absoluteString == "https://recipes.example/soup" })
        XCTAssertEqual(d.state.agentTabID(forIndexKey: "tab:" + tab.rawValue, profile: .default), tab.rawValue)
        XCTAssertEqual(d.state.agentTabID(forIndexKey: "history:https://recipes.example/soup", profile: .default), AgentTabID.historyPrefix + visit.id.rawValue)
        XCTAssertNil(d.state.agentTabID(forIndexKey: "history:https://never.example/", profile: .default))
        XCTAssertNil(d.state.agentTabID(forIndexKey: "tab:" + tab.rawValue, profile: ProfileID("other")), "another profile's tab")
        XCTAssertNil(d.state.agentTabID(forIndexKey: "archive:none", profile: .default))
        XCTAssertNil(d.state.agentTabID(forIndexKey: "nonsense", profile: .default))
    }
}

final class LocalWiringShownTitleTests: XCTestCase {
    /// Found on the real route: a page's title is kept in its window's slot, so the index read every open tab under its
    /// stored title, mostly empty, and all of them looked alike to the model.
    func testTheIndexAndTheDuplicateScopesReadTheTitleTheSidebarShows() throws {
        let d = Driver()
        let soup = d.open("https://recipes.example/soup"), salad = d.open("https://recipes.example/salad")
        d.page(soup, .titleChanged("Chicken noodle soup"))
        d.page(salad, .titleChanged("Greek salad"))
        d.user(.settings(.max(.tidyTabs(true))))
        guard case .ai(let tidy, .tidyToday, _)? = d.user(.assist(.organizeToday)).effects.first(where: { if case .ai = $0 { true } else { false } }) else { return XCTFail("no Tidy") }
        d.system(.aiResult(tidy, .reply(.groups([AIGroupPlan(folder: "Recipes", tabs: [soup.rawValue, salad.rawValue])]))))
        let tabs = (d.state.searchCorpus()[.default] ?? []).filter { $0.kind == .tab }
        XCTAssertEqual(tabs.first { $0.id == soup.rawValue }?.title, "Chicken noodle soup")
        XCTAssertEqual(tabs.first { $0.id == salad.rawValue }?.title, "Greek salad")
        d.user(.settings(.max(.feature(.tabCleanup, true))))
        d.system(.aiKeys([:], localDecisions: true))
        let entries = d.state.duplicateScopes().flatMap(\.entries)
        XCTAssertEqual(entries.first { $0.id == soup }?.title, "Chicken noodle soup")
        let rows = d.state.meaningCandidates(MeaningResults(text: "x", scope: .commandBar, hits: [MeaningHit(key: "tab:" + soup.rawValue, score: 0.9)]), profile: .default)
        XCTAssertEqual(rows.first?.title, "Chicken noodle soup")
        XCTAssertEqual(rows.first?.tab, soup, "a tab inside a group")
    }
}
