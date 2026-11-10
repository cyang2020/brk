import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// The command bar's file, app and currency sources as the store drives them, against temp folders and fakes.
@MainActor
final class LocalSourcesTests: XCTestCase {
    private var root: URL!
    private var sent: [Input] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-local-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sent = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private func answers() -> [LocalResults] {
        sent.compactMap { if case .system(.localResults(_, let results)) = $0 { results } else { nil } }
    }

    private func rates() -> [CurrencyRates] {
        sent.compactMap { if case .system(.currencyRates(let rates)) = $0 { rates } else { nil } }
    }

    private func wait(until condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: The fixture folder

    /// The real folder, which macOS does not guard.
    func testTheRealApplicationsFolderIsRead() {
        XCTAssertTrue(LocalSearch.apps(named: "safari", in: [URL(fileURLWithPath: "/Applications", isDirectory: true)]).contains { $0.path == "/Applications/Safari.app" })
    }

    // MARK: Search order and stale answers

    @MainActor
    private final class SlowFinder: LocalFileFinder {
        var asked: [String] = []
        func find(_ name: String) async -> [LocalHit] {
            asked.append(name)
            try? await Task.sleep(for: .milliseconds(name == "first" ? 200 : 0))
            return [LocalHit(path: "/d/\(name).txt", name: "\(name).txt")]
        }
    }

    func testANewerRequestCancelsTheOlderOneEvenWhileItIsSearching() async {
        let finder = SlowFinder(), window = WindowID("w")
        let search = LocalSearch(send: { [unowned self] in self.sent.append($0) }, finder: finder, applicationRoots: [], debounce: .milliseconds(1))
        search.search(window, LocalSearchRequest(query: "first", name: "first", scope: .files))
        await wait { finder.asked == ["first"] }
        search.search(window, LocalSearchRequest(query: "second", name: "second", scope: .files))
        await wait { !answers().isEmpty }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(answers().map(\.query), ["second"])
        XCTAssertEqual(answers().first?.files.map(\.name), ["second.txt"])
    }

    /// The real path: ordinary typing finds apps and asks the file index nothing, the `file` prefix does.
    func testWithFilesWhileTypingOffOnlyTheFilePrefixReachesTheIndex() async {
        let finder = SlowFinder(), window = WindowID("w")
        let search = LocalSearch(send: { [unowned self] in self.sent.append($0) }, finder: finder, applicationRoots: [], filesWhileTyping: false, debounce: .milliseconds(1))
        search.search(window, LocalSearchRequest(query: "typed", name: "typed"))
        await wait { !answers().isEmpty }
        XCTAssertEqual(finder.asked, [])
        XCTAssertEqual(answers().first?.files, [])
        search.search(window, LocalSearchRequest(query: "asked", name: "asked", scope: .files))
        await wait { answers().count == 2 }
        XCTAssertEqual(finder.asked, ["asked"])
    }

    // MARK: What a test instance may read

    func testUnderTheControlSocketOnlyTheFixtureFolderIsRead() async throws {
        try touch("Applications/Budget.app/Contents/Info.plist")
        try touch("Documents/budget.txt")
        let socket = LaunchOptions(environment: ["BRK_CONTROL_SOCKET": "/tmp/x.sock", "BRK_LOCAL_SEARCH_FIXTURE": root.path])
        let search = LocalSearch.live(send: { [unowned self] in self.sent.append($0) }, options: socket)
        search.search(WindowID("w"), LocalSearchRequest(query: "budget", name: "budget"))
        await wait { !answers().isEmpty }
        XCTAssertEqual(answers().first?.apps.map(\.name), ["Budget"])
        XCTAssertEqual(answers().first?.files.map(\.name), ["budget.txt"])
        XCTAssertTrue((answers().first?.apps.first?.path ?? "").hasSuffix("/Applications/Budget.app"))
        for hit in (answers().first?.apps ?? []) + (answers().first?.files ?? []) {
            XCTAssertTrue(hit.path.contains(root.lastPathComponent), hit.path)
        }
    }

    // MARK: Spotlight's question

    /// The real index, in a folder every Mac has indexed and nobody's files live in. One word and several: NSMetadataQuery
    /// throws on a predicate it does not like, which no fixture folder walks through.
    func testTheRealIndexTakesTheQuestion() async throws {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        for name in ["safari", "safari app", "saf*ri"] {
            let run = SpotlightRun(predicate: SpotlightFinder.predicate(for: name), scopes: [applications], timeout: .seconds(10))
            let hits = await run.results()
            if name == "saf*ri" { XCTAssertEqual(hits.filter { $0.name == "Safari.app" }, [], "a star means a star"); continue }
            try XCTSkipIf(hits.isEmpty, "Spotlight has not indexed /Applications on this machine")
            XCTAssertTrue(hits.contains { $0.path == "/Applications/Safari.app" }, name + ": \(hits.map(\.path))")
        }
    }

    // MARK: Exchange rates

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func add() { lock.withLock { value += 1 } }
    }

    private final class FixedClock: Clock, @unchecked Sendable {
        var time: Instant
        init(_ time: Instant) { self.time = time }
        func now() -> Instant { time }
    }

    nonisolated private static func ecb(_ date: String, usd: Double) -> Data {
        Data("<e><Cube><Cube time='\(date)'><Cube currency='USD' rate='\(usd)'/></Cube></Cube></e>".utf8)
    }

    private let T = Instant(milliseconds: 1_793_966_400_000)
    private func store(_ file: URL, _ clock: FixedClock, fetch: CurrencyRatesStore.Fetch?) -> CurrencyRatesStore {
        CurrencyRatesStore(file: file, fetch: fetch, clock: clock, send: { [unowned self] in self.sent.append($0) })
    }

    func testRatesAreFetchedOnceAndKeptOnDisk() async throws {
        let file = root.appendingPathComponent("rates.xml"), calls = Calls(), clock = FixedClock(T)
        let rates = store(file, clock, fetch: { calls.add(); return Self.ecb("2026-11-06", usd: 1.1) })
        for _ in 0..<5 { rates.need() }
        await wait { !self.rates().isEmpty }
        for _ in 0..<5 { rates.need() }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls.count, 1, "at most one request a day")
        XCTAssertEqual(self.rates().count, 1)
        XCTAssertEqual(self.rates().first?.date, "2026-11-06")
        XCTAssertEqual(try Data(contentsOf: file), Self.ecb("2026-11-06", usd: 1.1))

        // A new launch within the day reads the file and asks nobody.
        sent = []
        let later = store(file, FixedClock(T.advanced(by: .seconds(23 * 3600))), fetch: { calls.add(); return Data() })
        later.need()
        XCTAssertEqual(self.rates().first?.date, "2026-11-06")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls.count, 1)
    }
}
