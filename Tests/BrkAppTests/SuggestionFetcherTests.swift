import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// Owner: F4. The fetcher as the store drives it: `Effect.fetchSuggestions` per keystroke in, one
/// `SystemEvent.suggestions` per settled query out. The network is a URLProtocol stub that answers like the
/// e2e fixture (`["q", ["q-a", "q-b"]]`) and records what was asked.
@MainActor
final class SuggestionFetcherTests: XCTestCase {
    private var sent: [Input] = []

    private func fetcher(override: URL? = nil) -> SuggestionFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubSuggest.self]
        return SuggestionFetcher(send: { [unowned self] in self.sent.append($0) }, session: URLSession(configuration: configuration), override: override)
    }

    private func answers() -> [(WindowID, String, [EngineSuggestion])] {
        sent.compactMap { if case .system(.suggestions(let w, let q, let r, _)) = $0 { (w, q, r) } else { nil } }
    }

    private func waitForAnswers(_ count: Int) async {
        let deadline = Date().addingTimeInterval(5)
        while answers().count < count, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    override func setUp() {
        StubSuggest.reset()
    }

    /// typing "s", "sw", "swi" quickly asks once, for "swi", and answers with the engine's list for that query
    func test_aBurstOfKeystrokesAsksOnceForTheLastQuery() async {
        let f = fetcher()
        let w = WindowID("w")
        for q in ["s", "sw", "swi"] { f.fetch(w, query: q, url: URL(string: "https://suggest.test/?q=\(q)")!) }
        await waitForAnswers(1)
        try? await Task.sleep(for: .seconds(Metrics.commandBar.suggestionDebounce.value * 2))
        XCTAssertEqual(StubSuggest.asked, ["swi"])
        XCTAssertEqual(answers().map(\.1), ["swi"])
        XCTAssertEqual(answers().first?.2, ["swi-a", "swi-b"])
        XCTAssertEqual(answers().first?.0, w)
    }

    /// Google's answer in Chromium's form: searches and a site with their relevances, the search as typed's relevance, an
    /// entity shown by its name (field 7 of its entity info), a calculator row left out, the `)]}'` line skipped; the
    /// OpenSearch form still reads as plain searches
    func test_parsesGooglesChromiumForm() throws {
        let entity = Data([0x0a, 0x02, 0x2f, 0x67, 0x3a, 0x06] + Array("GitHub".utf8)).base64EncodedString()
        let json: [Any] = ["githu", ["github", "github", "https://github.com/", "= 4"], ["", "", "GitHub page", ""], [],
                           ["google:suggesttype": ["QUERY", "ENTITY", "NAVIGATION", "CALCULATOR"], "google:suggestrelevance": [1251, 1250, 1249, 1200],
                            "google:verbatimrelevance": 851, "google:suggestdetail": [[:], ["google:entityinfo": entity], [:], [:]]]]
        let body = Data(")]}'\n".utf8) + (try JSONSerialization.data(withJSONObject: json))
        let answer = SuggestionFetcher.parse(body)
        XCTAssertEqual(answer.verbatimRelevance, 851)
        XCTAssertEqual(answer.rows, [EngineSuggestion("github", relevance: 1251), EngineSuggestion("github", relevance: 1250, title: "GitHub"),
                                     EngineSuggestion("https://github.com/", kind: .navigation, relevance: 1249, title: "GitHub page")])
        XCTAssertEqual(SuggestionFetcher.parse(try JSONSerialization.data(withJSONObject: ["q", ["q-a"]])).rows, ["q-a"])
    }
}

/// Answers `["q", ["q-a", "q-b"]]` for any URL with a `q` (or `query`) item; "fail" is a network error.
final class StubSuggest: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var log: [URL] = []
    private static let lock = NSLock()
    static var urls: [URL] { lock.withLock { log } }
    static var asked: [String] { urls.compactMap(query) }
    static func reset() { lock.withLock { log = [] } }

    private static func query(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" || $0.name == "query" }?.value
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock { Self.log.append(url) }
        let q = Self.query(url) ?? ""
        if q == "fail" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let body = try! JSONSerialization.data(withJSONObject: [q, ["\(q)-a", "\(q)-b"]])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
