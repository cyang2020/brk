import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import XCTest
@testable import BrkApp

/// Issue #11 and the audit's tab-close item: a person's close of a page on screen whose page has a beforeunload handler asks the
/// page first, as Chrome does before it closes a tab. Stay keeps the page; Leave closes it. A page off screen, or one with no
/// handler, closes at once (its handlers still run in Chromium as it closes).
@MainActor
final class LeavePageTests: XCTestCase {
    func testClosingAPageOnScreenThatAsksWaitsForItsAnswer() throws {
        let h = LeaveHarness()
        defer { h.close() }
        h.engine.beforeUnloadPages = [h.page]
        h.store.dispatch(.user(h.window, .tab(.close(.focused))))
        XCTAssertEqual(h.engine.leaveQuestions.map(\.page), [h.page], "the page is asked before it goes")
        XCTAssertNotNil(h.engine.surface(for: h.page), "the page stays while it is asked")
        h.store.dispatch(.user(h.window, .tab(.close(.focused))))
        XCTAssertEqual(h.engine.leaveQuestions.count, 1, "a second close waits for the same answer")
        h.engine.answerLeaving(false)
        XCTAssertNotNil(h.engine.surface(for: h.page), "Stay keeps the page")
        XCTAssertNotNil(tabRow(h), "Stay keeps the tab")
        h.store.dispatch(.user(h.window, .tab(.close(.focused))))
        h.engine.answerLeaving(true)
        XCTAssertNil(h.engine.surface(for: h.page), "Leave closes the page")
        XCTAssertNil(tabRow(h), "Leave closes the tab")
        XCTAssertTrue(h.engine.leaveQuestions.isEmpty)
    }

    func testAPageOffScreenOrWithoutAHandlerClosesWithoutAQuestion() throws {
        let h = LeaveHarness()
        defer { h.close() }
        h.engine.beforeUnloadPages = [h.page]
        h.store.dispatch(.user(h.window, .commandBar(.submit("https://example.test/second"))))
        let second = try XCTUnwrap(h.store.snapshot.pages.map(\.id).first { $0 != h.page })
        h.store.dispatch(.user(h.window, .tab(.close(.item(h.page.item)))))
        XCTAssertTrue(h.engine.leaveQuestions.isEmpty, "a page that is not on screen is not asked")
        XCTAssertNil(h.engine.surface(for: h.page))
        h.store.dispatch(.user(h.window, .tab(.close(.focused))))
        XCTAssertTrue(h.engine.leaveQuestions.isEmpty, "a page without a beforeunload handler is not asked")
        XCTAssertNil(h.engine.surface(for: second))
    }

    private func tabRow(_ h: LeaveHarness) -> Row? {
        guard let window = h.store.snapshot.windows[h.window] else { return nil }
        return (window.space.pinned.rows + window.space.today.rows).first { $0.id == h.page.item }
    }
}

@MainActor
private struct LeaveHarness {
    let engine: StubEngine
    let store: AppStore
    let window: WindowID
    let page: PageID
    let directory: URL
    private let router: KeyRouter

    init() {
        _ = NSApplication.shared
        engine = StubEngine()
        let clock = OffsetClock()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-leave-unit-\(UUID().uuidString)")
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://example.test/"),
                                                                contentSize: Metrics.window.defaultSize.value),
                                          ctx: Context(now: clock.now(), newID: { UUID().uuidString }))
        store = AppStore(restored: restored, clock: clock, engine: engine, stateFile: StateFile(directory: directory))
        router = KeyRouter(store: store)
        engine.delegate = router
        window = store.snapshot.windows.keys.first!
        page = store.snapshot.pages[0].id
        store.start()
    }

    func close() {
        for id in store.snapshot.windows.keys { store.windowController(id)?.window.orderOut(nil) }
        try? FileManager.default.removeItem(at: directory)
    }
}
