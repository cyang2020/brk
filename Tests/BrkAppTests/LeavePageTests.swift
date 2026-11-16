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

    /// Review of #11: Quit asked its pages after it had torn Brk down (input dropped, keys swallowed), so Stay left Brk unusable.
    /// Every way of quitting now asks first; Stay leaves Brk working, and a quit asked for while a question is open waits for it.
    func testStayOnQuitLeavesBrkWorking() throws {
        let h = LeaveHarness(), quits = QuitCounter()
        defer { h.close(); quits.restore() }
        h.engine.beforeUnloadPages = [h.page]
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(h.engine.leaveQuestions.map(\.page), [h.page], "Quit asks the page on screen")
        XCTAssertFalse(h.store.isTerminating, "nothing is torn down while the page is asked")
        XCTAssertEqual(quits.count, 0)
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(h.engine.leaveQuestions.count, 1, "a second quit waits for the same answer")
        h.engine.answerLeaving(false)
        XCTAssertEqual(quits.count, 0, "Stay keeps Brk running")
        XCTAssertFalse(h.store.isTerminating)
        XCTAssertFalse(Quit.confirmed)
        h.store.dispatch(.user(h.window, .commandBar(.submit("https://example.test/after-stay"))))
        XCTAssertEqual(h.store.snapshot.pages.count, 2, "a person's command still works after Stay")

        // SIGTERM, Restart and the rest (`Quit.request`) ask before the teardown too.
        var terminated = 0, declined = 0
        h.store.dispatch(.user(h.window, .tab(.focus(h.page.item))))
        h.store.quitAfterAskingPages(terminate: { terminated += 1 }, declined: { declined += 1 })
        XCTAssertFalse(h.store.isTerminating)
        h.engine.answerLeaving(false)
        XCTAssertEqual([terminated, declined], [0, 1])
        XCTAssertFalse(h.store.isTerminating)

        // A quit asked for while a tab's question is open is asked once that one is answered.
        h.store.dispatch(.user(h.window, .tab(.close(.focused))))
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(h.engine.leaveQuestions.count, 1)
        h.engine.answerLeaving(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(h.engine.leaveQuestions.map(\.page), [h.page], "then the quit asks")
        h.engine.answerLeaving(true)
        XCTAssertEqual(quits.count, 1, "Leave goes on to quit")
    }

    /// Review of #11: Leave applied Cmd+W's command again to whatever was focused by then, closing another tab and keeping the
    /// asked one. It now goes on only if it ends the same pages; while asked, no other page takes the asked one's place.
    func testLeaveDoesNotCloseAnotherPageWhenFocusMoved() throws {
        let h = LeaveHarness()
        defer { h.close() }
        h.engine.beforeUnloadPages = [h.page]
        h.store.dispatch(.user(h.window, .settings(.links(.externalLinksInLittleArc(false)))))
        h.store.dispatch(.user(h.window, .commandBar(.submit("https://example.test/second"))))
        let second = try XCTUnwrap(h.store.snapshot.pages.map(\.id).first { $0 != h.page })
        h.store.dispatch(.user(h.window, .tab(.focus(h.page.item))))
        h.store.dispatch(.user(h.window, .tab(.close(.focused))))
        XCTAssertEqual(h.engine.leaveQuestions.map(\.page), [h.page])
        h.store.dispatch(.user(h.window, .tab(.focus(second.item))))
        XCTAssertEqual(h.store.state.shownLoadedPages(in: h.window), [h.page], "a shortcut to another tab waits while asked")
        h.store.dispatch(.system(.externalURL(URL(string: "https://example.test/from-another-app")!)))
        let third = try XCTUnwrap(h.store.snapshot.pages.map(\.id).first { $0 != h.page && $0 != second })
        XCTAssertEqual(h.store.state.shownLoadedPages(in: h.window), [third], "a link from another app moved focus")
        h.engine.answerLeaving(true)
        XCTAssertNotNil(h.engine.surface(for: third), "Leave does not close the page focused since")
        XCTAssertNotNil(h.engine.surface(for: h.page))
        XCTAssertNotNil(tabRow(h), "the asked tab stays; closing it again asks again")
        XCTAssertTrue(h.engine.leaveQuestions.isEmpty)
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
