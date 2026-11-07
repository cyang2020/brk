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

    func testTheFolderFinderLeavesOutWhatTheRealSearchLeavesOut() async throws {
        for path in ["Documents/budget.txt", "budget-top.txt", "Documents/other.txt", ".hidden/budget.txt", "Documents/.budget.txt", "Library/budget.txt",
                     "Applications/Budget.app/Contents/budget.plist"] { try touch(path) }
        let found = await FolderFinder(home: root).find("budget")
        XCTAssertEqual(Set(found.map(\.name)), ["budget.txt", "budget-top.txt"])
        XCTAssertEqual(found.first { $0.name == "budget.txt" }?.path.hasSuffix("/Documents/budget.txt"), true)
    }

    /// The real folder, which macOS does not guard.
    func testTheRealApplicationsFolderIsRead() {
        XCTAssertTrue(LocalSearch.apps(named: "safari", in: [URL(fileURLWithPath: "/Applications", isDirectory: true)]).contains { $0.path == "/Applications/Safari.app" })
    }

    func testAppsByNameFromTheirFolders() throws {
        for path in ["Applications/Budget Tool.app/Contents/Info.plist", "Applications/Suite/Budget Helper.app/Contents/Info.plist", "Applications/Other.app/Contents/Info.plist",
                     "Applications/a/b/Too Deep Budget.app/Contents/Info.plist", "Applications/.Budget Hidden.app/Contents/Info.plist"] { try touch(path) }
        let hits = LocalSearch.apps(named: "budget", in: [root.appendingPathComponent("Applications"), root.appendingPathComponent("Missing")])
        XCTAssertEqual(hits.map(\.name), ["Budget Helper", "Budget Tool"])
        XCTAssertTrue(hits[0].path.hasSuffix("/Applications/Suite/Budget Helper.app"))
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

    func testTheDebounceAsksOnceForAQuickRunOfKeys() async {
        let finder = SlowFinder(), window = WindowID("w")
        let search = LocalSearch(send: { [unowned self] in self.sent.append($0) }, finder: finder, applicationRoots: [], debounce: .milliseconds(50))
        for text in ["bud", "budg", "budge", "budget"] { search.search(window, LocalSearchRequest(query: text, name: text, scope: .files)) }
        await wait { !answers().isEmpty }
        XCTAssertEqual(finder.asked, ["budget"])
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

    func testCancellingLeavesNoAnswer() async {
        let finder = SlowFinder(), window = WindowID("w")
        let search = LocalSearch(send: { [unowned self] in self.sent.append($0) }, finder: finder, applicationRoots: [], debounce: .milliseconds(1))
        search.search(window, LocalSearchRequest(query: "first", name: "first", scope: .files))
        await wait { finder.asked == ["first"] }
        search.cancel(window)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(answers(), [])
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

    func testUnderTheControlSocketWithNoFixtureNothingIsFound() async {
        let search = LocalSearch.live(send: { [unowned self] in self.sent.append($0) }, options: LaunchOptions(environment: ["BRK_CONTROL_SOCKET": "/tmp/x.sock"]))
        // A file name that exists in no fixture: the point is that no answer comes at all.
        search.search(WindowID("w"), LocalSearchRequest(query: "safari", name: "safari"))
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(answers(), [])
    }

    // MARK: Spotlight's question

    func testTheSpotlightQuestionIsAboutTheFileNameOnly() {
        let format = SpotlightFinder.predicate(for: "my re*port?").predicateFormat
        XCTAssertTrue(format.contains("kMDItemFSName"), format)
        XCTAssertFalse(format.lowercased().contains("kmdtextcontent"), format)
        XCTAssertTrue(format.contains("*my*"), format)
        XCTAssertTrue(format.contains(#"*re\\*port\\?*"#), format)
    }

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

    func testAStoppedRunEndsEmptyHanded() async {
        let run = SpotlightRun(predicate: SpotlightFinder.predicate(for: "safari"), scopes: [URL(fileURLWithPath: "/Applications", isDirectory: true)], timeout: .seconds(10))
        run.stop()
        let hits = await run.results()
        XCTAssertEqual(hits, [])
    }

    // MARK: The dictionary

    func testTheOfflineDictionaryAnswersAWordAndNothingForNonsense() throws {
        XCTAssertNil(BarLookups.definition(of: "zzzqqqxyz"))
        let found = try XCTUnwrap(BarLookups.definition(of: "apple"), "the system dictionary has no English on this Mac?")
        XCTAssertTrue(found.lowercased().contains("apple"), found)
        XCTAssertLessThanOrEqual(found.count, 400)
        XCTAssertFalse(found.contains("\n"))
    }

    func testALookupWaitsAndANewerOneCancels() async {
        let lookups = BarLookups(send: { [unowned self] in self.sent.append($0) })
        let window = WindowID("w")
        for word in ["app", "appl", "apple"] { lookups.define(window, word: word) }
        let answers = { self.sent.compactMap { input -> BarDefinition? in if case .system(.definition(_, let found)) = input { found } else { nil } } }
        await wait { !answers().isEmpty }
        XCTAssertEqual(answers().map(\.word), ["apple"])
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

    func testAfterADayItFetchesAgainAndShowsTheOldFileMeanwhile() async throws {
        let file = root.appendingPathComponent("rates.xml"), calls = Calls(), clock = FixedClock(T)
        let first = store(file, clock, fetch: { calls.add(); return Self.ecb("2026-11-06", usd: 1.1) })
        first.need()
        await wait { !self.rates().isEmpty }
        sent = []
        let next = store(file, FixedClock(T.advanced(by: .seconds(25 * 3600))), fetch: { calls.add(); return Self.ecb("2026-11-07", usd: 1.2) })
        next.need()
        XCTAssertEqual(self.rates().map(\.date), ["2026-11-06"], "the old file at once")
        await wait { self.rates().count == 2 }
        XCTAssertEqual(self.rates().map(\.date), ["2026-11-06", "2026-11-07"])
        XCTAssertEqual(calls.count, 2)
    }

    func testNoNetworkAndNoFileMeansNoRatesAndNoHammering() async {
        let file = root.appendingPathComponent("rates.xml"), calls = Calls(), clock = FixedClock(T)
        let rates = store(file, clock, fetch: { calls.add(); throw URLError(.notConnectedToInternet) })
        rates.need()
        await wait { calls.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        for _ in 0..<5 { rates.need() }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls.count, 1, "a failure waits an hour")
        XCTAssertEqual(self.rates(), [])
        clock.time = T.advanced(by: .seconds(3601))
        rates.need()
        await wait { calls.count == 2 }
        XCTAssertEqual(calls.count, 2)
    }

    func testAFailedFetchKeepsAnOldFile() async throws {
        let file = root.appendingPathComponent("rates.xml"), clock = FixedClock(T)
        try Self.ecb("2026-11-01", usd: 1.0).write(to: file)
        let stale = Date(timeIntervalSince1970: Double(T.advanced(by: .seconds(-5 * 24 * 3600)).milliseconds) / 1000)
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: file.path)
        store(file, clock, fetch: { throw URLError(.notConnectedToInternet) }).need()
        XCTAssertEqual(self.rates().map(\.date), ["2026-11-01"])
    }

    func testAGarbledAnswerIsNotKept() async throws {
        let file = root.appendingPathComponent("rates.xml"), clock = FixedClock(T), calls = Calls()
        store(file, clock, fetch: { calls.add(); return Data("<html>maintenance</html>".utf8) }).need()
        await wait { calls.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(self.rates(), [])
    }

    func testTestInstancesUseTheFixtureFileAndNeverTheNetwork() throws {
        let fixture = root.appendingPathComponent("fixture.xml")
        try Self.ecb("2026-11-06", usd: 1.1).write(to: fixture)
        let with = CurrencyRatesStore.live(dataDirectory: root, clock: FixedClock(T), send: { [unowned self] in self.sent.append($0) },
                                           options: LaunchOptions(environment: ["BRK_CONTROL_SOCKET": "/tmp/x.sock", "BRK_CURRENCY_RATES_FILE": fixture.path]))
        with.need()
        XCTAssertEqual(rates().map(\.date), ["2026-11-06"])

        sent = []
        let without = CurrencyRatesStore.live(dataDirectory: root, clock: FixedClock(T), send: { [unowned self] in self.sent.append($0) },
                                              options: LaunchOptions(environment: ["BRK_CONTROL_SOCKET": "/tmp/x.sock"]))
        without.need()
        XCTAssertEqual(rates(), [])
    }
}
