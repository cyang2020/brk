import BrkBase
@testable import BrkDomain
import XCTest

final class LocalModelsDomainTests: XCTestCase {
    func testTheCardsActionsBecomeEffectsAndItsStateReachesTheMaxSnapshot() {
        let d = Driver()
        for action: LocalModelAction in [.download(.search), .cancel(.decision), .remove(.search), .choose(.decision, file: "jevk5-4b-v0.3-q8")] {
            XCTAssertEqual(d.user(.settings(.max(.localModel(action)))).effects, [.localModel(action)])
        }
        let row = LocalModelRow(kind: .search, title: "EmbeddingGemma 2", purpose: "Finds tabs by meaning.", bytes: 309_855_456,
                                license: "Apache 2.0", languages: "100+ languages", residentMB: 500,
                                stage: .downloading(received: 1_000, total: 309_855_456), runtimeFound: true)
        let snapshot = LocalModelsSnapshot(rows: [row], indexed: nil)
        d.system(.localModels(snapshot))
        XCTAssertEqual(d.snapshot.settings.max.localModels, snapshot)
        XCTAssertEqual(d.snapshot.settings.max.localModels?.row(.search)?.stage, .downloading(received: 1_000, total: 309_855_456))
    }

    /// The index holds what this lists and nothing else, so clearing history must empty its history part.
    func testSearchCorpusListsWebTabsAndHistoryAndDropsClearedHistory() throws {
        let d = Driver()
        d.user(.library(.clearHistory))
        let tab = d.open("https://www.zhihu.com/question/583920114")
        d.page(tab, .titleChanged("Redis 持久化：RDB 和 AOF 到底怎么选？ - 知乎"))
        let browser = try XCTUnwrap(d.state.session.live[PageID(window: d.window, item: tab)]?.browser)
        for (sequence, address) in ["https://www.zhihu.com/question/583920114", "https://juejin.cn/post/7301928374650183"].enumerated() {
            let document = DocumentToken(browser: browser, sequence: UInt64(sequence + 10))
            d.page(tab, .documentChanged(.loading(document)))
            d.page(tab, .committed(url(address)))
            d.page(tab, .documentChanged(.ready(document)))
        }
        let corpus = try XCTUnwrap(d.state.searchCorpus()[.default])
        XCTAssertTrue(corpus.contains { $0.kind == .tab && $0.id == tab.rawValue })
        let history = corpus.filter { $0.kind == .history }
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(Set(history.map(\.id)).count, history.count, "one entry per address")
        XCTAssertTrue(corpus.allSatisfy { $0.url.hasPrefix("http") })

        d.user(.library(.clearHistory))
        XCTAssertEqual(d.state.searchCorpus()[.default]?.filter { $0.kind == .history }, [])
    }
}
