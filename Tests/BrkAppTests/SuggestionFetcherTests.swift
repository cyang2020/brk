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

    private func answers() -> [(WindowID, String, [String])] {
        sent.compactMap { if case .system(.suggestions(let w, let q, let r)) = $0 { (w, q, r) } else { nil } }
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
