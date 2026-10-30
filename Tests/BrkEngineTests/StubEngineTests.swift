import AppKit
import BrkBase
import XCTest
@testable import BrkEngine

/// The stub engine is complete, so its contract with AppStore (reconcile, events, surfaces, log, shutdown) is pinned.
@MainActor
final class StubEngineTests: XCTestCase {
    final class Recorder: WebEngineDelegate {
        var events: [(PageID, PageEvent)] = []
        func engine(_ engine: any WebEngine, page: PageID, didEmit event: PageEvent) { events.append((page, event)) }
        func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: PressID) -> Bool { false }
    }

    let a = PageID(ItemID("a")), b = PageID(ItemID("b"))
    let url = URL(string: "https://example.com/x")!

    func testReconcileCreatesSurfacesAndReportsALoad() {
        let engine = StubEngine(), recorder = Recorder()
        engine.delegate = recorder
        engine.reconcile([PageSpec(id: a, initialURL: url, profile: .default), PageSpec(id: b, initialURL: nil, profile: .default)])
        XCTAssertNotNil(engine.surface(for: a))
        XCTAssertNil(engine.surface(for: b), "a pane without a URL gets no page")
        XCTAssertEqual(recorder.events.map(\.1), [
            .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false), .committed(url), .titleChanged("example.com"),
            .loadingChanged(isLoading: false, canGoBack: false, canGoForward: false),
        ])
        XCTAssertEqual(engine.pageLog.map(\.kind), [.created])
        engine.reconcile([PageSpec(id: a, initialURL: url, profile: .default)])
        XCTAssertEqual(recorder.events.count, 4, "reconcile is idempotent")
    }

    func testDroppingASpecClosesThePageAndAReusedIdGetsAFreshSurface() {
        let engine = StubEngine(), recorder = Recorder()
        engine.delegate = recorder
        engine.reconcile([PageSpec(id: a, initialURL: url, profile: .default)])
        let first = engine.surface(for: a)
        engine.reconcile([])
        XCTAssertNil(engine.surface(for: a))
        XCTAssertEqual(recorder.events.last?.1, .closed)
        XCTAssertEqual(engine.pageLog.map(\.kind), [.created, .closeRequested, .closed])
        engine.reconcile([PageSpec(id: a, initialURL: url, profile: .default)])
        XCTAssertNotNil(engine.surface(for: a))
        XCTAssertFalse(engine.surface(for: a) === first)
        XCTAssertEqual(engine.pageLog.last?.generation, 2)
    }

    func testNavigateAndEvaluateReachThePage() {
        let engine = StubEngine(), recorder = Recorder()
        engine.delegate = recorder
        engine.reconcile([PageSpec(id: a, initialURL: url, profile: .default)])
        recorder.events.removeAll()
        let other = URL(string: "http://localhost:9/page2.html")!
        engine.perform(.navigate(other), on: a)
        XCTAssertEqual(recorder.events.map(\.1)[1], .committed(other))
        XCTAssertEqual(recorder.events.map(\.1)[2], .titleChanged("localhost"))
        engine.evaluate("document.title = 'x'", in: a)
        XCTAssertEqual((engine.surface(for: a) as? StubSurface)?.evaluated, ["document.title = 'x'"])
        engine.perform(.goBack, on: b)
        XCTAssertNotNil(engine.facts(for: a))
        XCTAssertNil(engine.facts(for: b))
    }

    func testShutdownIsCleanIdempotentAndClosesEverything() async {
        let engine = StubEngine(), recorder = Recorder()
        engine.delegate = recorder
        engine.reconcile([PageSpec(id: a, initialURL: url, profile: .default)])
        let first = await engine.shutdown()
        XCTAssertEqual(first, .clean)
        let second = await engine.shutdown()
        XCTAssertEqual(second, .clean)
        XCTAssertNil(engine.surface(for: a))
        XCTAssertEqual(engine.pageLog.map(\.kind), [.created, .closeRequested, .closed])
        engine.reconcile([PageSpec(id: b, initialURL: url, profile: .default)])
        XCTAssertNil(engine.surface(for: b), "nothing is created after shutdown")
    }
}
