import BrkBase
@testable import BrkDomain
import XCTest

final class LocalModelsDomainTests: XCTestCase {
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
