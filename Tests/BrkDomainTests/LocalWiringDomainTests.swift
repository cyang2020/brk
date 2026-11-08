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
            MeaningHit(key: "tab:" + soup.rawValue, score: 0.84), MeaningHit(key: "history:https://news.example/today", score: 0.8),
            MeaningHit(key: "tab:gone", score: 0.79), MeaningHit(key: "history:https://never.example/", score: 0.78)])))
        guard case .commandBar(let bar)? = d.view.overlay else { return XCTFail("no bar") }
        let found = try XCTUnwrap(bar.meaning)
        XCTAssertEqual(found.text, "something warm to cook")
        XCTAssertEqual(found.rows.map(\.place), [.tab, .history], "keys the state no longer has are skipped")
        XCTAssertEqual(found.rows.first?.tab, soup)
        XCTAssertEqual(found.rows.first?.url.absoluteString, "https://recipes.example/soup")
        XCTAssertEqual(found.rows.last?.url.absoluteString, "https://news.example/today")
        _ = other
        d.user(.commandBar(.dismiss))
        XCTAssertNil(d.state.session.windows[d.window]?.meaning[.commandBar], "closing the bar drops its answer")
        d.system(.meaningResults(d.window, MeaningResults(text: "late", scope: .commandBar, hits: [])))
        XCTAssertNil(d.state.session.windows[d.window]?.meaning[.commandBar], "an answer after the bar closed is dropped")
    }

    func testTheHistoryPageAsksByMeaningAndShowsVisitsForItsText() throws {
        let d = Driver()
        let tab = d.open("https://juejin.cn/post/1")
        d.page(tab, .titleChanged("MySQL 索引优化实战 - 掘金"))
        d.user(.library(.openHistory))
        XCTAssertEqual(meaning(d.user(.library(.historySearch("讲数据库的")))), [], "no search model")
        searchReady(d)
        XCTAssertEqual(meaning(d.user(.library(.historySearch(" 讲数据库的 ")))), [MeaningQuery(text: "讲数据库的", scope: .history, profile: .default)])
        d.system(.meaningResults(d.window, MeaningResults(text: "讲数据库的", scope: .history, hits: [MeaningHit(key: "history:https://juejin.cn/post/1", score: 0.81)])))
        let shown = try XCTUnwrap(d.view.historyMeaning)
        XCTAssertEqual(shown.text, "讲数据库的")
        XCTAssertEqual(shown.rows.map(\.url.absoluteString), ["https://juejin.cn/post/1"])
        XCTAssertNotNil(shown.rows.first?.id, "a visit, so the page can select and remove it")
        XCTAssertEqual(meaning(d.user(.library(.historySearch("讲数据库的")))), [], "already answered")
        d.user(.library(.historySearch("")))
        XCTAssertNil(d.view.historyMeaning, "an empty search drops it")
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

    func testPlaceNewTabsTellsJevK5EachGroupsTabs() throws {
        let d = Driver()
        d.user(.settings(.max(.feature(.tabPlacement, true))))
        let soup = d.open("https://recipes.example/soup"), salad = d.open("https://recipes.example/salad")
        d.user(.settings(.max(.tidyTabs(true))))
        guard case .ai(let tidy, .tidyToday, _)? = d.user(.assist(.organizeToday)).effects.first(where: { if case .ai = $0 { true } else { false } }) else { return XCTFail("no Tidy") }
        d.system(.aiResult(tidy, .reply(.groups([AIGroupPlan(folder: "Recipes", tabs: [soup.rawValue, salad.rawValue])]))))
        let pie = d.open("https://recipes.example/pie")
        let page = PageID(window: d.window, item: pie)
        let browser = d.state.session.live[page]?.browser ?? BrowserToken(page: page, generation: 1)
        let document = DocumentToken(browser: browser, sequence: (d.state.session.live[page]?.documentSequence ?? 0) + 1)
        let effects = [d.page(pie, .documentChanged(.loading(document))), d.page(pie, .titleChanged("Apple pie")), d.page(pie, .documentChanged(.ready(document))),
                       d.page(pie, .loadingChanged(isLoading: false, canGoBack: false, canGoForward: false))].flatMap(\.effects)
        let task = try XCTUnwrap(effects.compactMap { if case .ai(_, let task, _) = $0 { task } else { nil } }.first)
        guard case .decide(let request, .tabPlacement, .placement(let key, let subject, let members, let profile)?) = task else { return XCTFail("\(task)") }
        XCTAssertEqual(key, "group")
        XCTAssertNotNil(request.questions["group"])
        XCTAssertEqual(subject.id, pie)
        XCTAssertEqual(subject.title, "Apple pie")
        XCTAssertEqual(profile, .default)
        XCTAssertEqual(Set(members["Recipes"]?.map(\.id) ?? []), [soup, salad])
    }
}
