import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class BrowserBasicIntegrationTests: XCTestCase {
    func testHandoffQueuesNavigationAfterThePreviousPresentationCloses() throws {
        let d = Driver()
        let first = try XCTUnwrap(d.snapshot.pages.first?.id)
        let source = try XCTUnwrap(d.state.session.live[first]?.browser)
        d.user(.window(.new))
        let second = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != first.window })
        d.user(.tab(.focus(first.item)), in: second)
        let page = PageID(window: second, item: first.item)
        let previous = try XCTUnwrap(d.state.session.live[page]?.browser)
        let closed = reduce(d.state, .system(.page(previous, .closed)), d.ctx)
        XCTAssertNil(closed.state.session.live[page]?.browser)
        let requested = url("http://127.0.0.1:9/requested-while-waiting")
        let pending = reduce(closed.state, .user(second, .page(.navigate(.focused, requested))), d.ctx)
        XCTAssertFalse(pending.effects.contains(.page(page, .navigate(requested))))
        XCTAssertEqual(pending.state.session.live[page]?.requestedURL, requested)
        let token = BrowserToken(page: page, generation: (pending.state.session.generations[page] ?? 0) + 1)
        let document = DocumentToken(browser: token, sequence: 1)
        let created = reduce(pending.state, .system(.page(token, .browserCreated(.profile(.default), .ready(document)))), d.ctx)
        let restored = reduce(created.state, .system(.page(token, .locationRestored(from: source, url: start))), d.ctx)
        XCTAssertEqual(restored.effects.filter { $0 == .page(page, .navigate(requested)) }.count, 1)
        XCTAssertEqual(restored.state.session.live[page]?.requestedURL, requested)
        XCTAssertEqual(restored.state.doc.windows[second]?.slots[first.item]?.committedURL, start)
        let committed = reduce(restored.state, .system(.page(token, .committed(requested))), d.ctx)
        XCTAssertNil(committed.state.session.live[page]?.requestedURL)
        XCTAssertEqual(committed.state.doc.windows[second]?.slots[first.item]?.committedURL, requested)
    }

    func testHandoffRestoresTheAddressWithoutDuplicatingTheHistoryVisit() throws {
        let d = Driver()
        let first = try XCTUnwrap(d.snapshot.pages.first?.id)
        let source = try XCTUnwrap(d.state.session.live[first]?.browser)
        let document = DocumentToken(browser: source, sequence: 1)
        d.page(first.item, .documentChanged(.loading(document)))
        d.page(first.item, .committed(start))
        d.page(first.item, .documentChanged(.ready(document)))
        let visit = try XCTUnwrap(d.state.session.live[first]?.recordedVisitID)
        let count = d.state.doc.history.count
        d.user(.window(.new))
        let second = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != first.window })
        d.user(.tab(.focus(first.item)), in: second)
        let page = PageID(window: second, item: first.item)
        let token = BrowserToken(page: page, generation: (d.state.session.generations[page] ?? 0) + 1)
        let ready = DocumentToken(browser: token, sequence: document.sequence)
        let unavailable = reduce(d.state, .system(.page(source, .documentChanged(.unavailable))), d.ctx)
        let closed = reduce(unavailable.state, .system(.page(source, .closed)), d.ctx)
        let created = reduce(closed.state, .system(.page(token, .browserCreated(.profile(.default), .ready(ready)))), d.ctx)
        let restored = reduce(created.state, .system(.page(token, .locationRestored(from: source, url: start))), d.ctx)
        let titled = reduce(restored.state, .system(.page(token, .titleChanged("Moved document"))), d.ctx)
        XCTAssertEqual(titled.state.doc.history.count, count)
        XCTAssertEqual(titled.state.session.live[page]?.recordedVisitID, visit)
        XCTAssertEqual(titled.state.doc.windows[second]?.slots[first.item]?.committedURL, start)
        XCTAssertEqual(titled.state.doc.history.first { $0.id == visit }?.title, "Moved document")
    }

    func testBackgroundStartupSyncKeepsTheEmptyWindowCommandBar() {
        let d = Driver(startURL: nil)
        let overlay = d.view.overlay
        d.system(.sidebarData(.syncPoll))
        XCTAssertEqual(d.view.overlay, overlay)
        if case .commandBar? = d.view.overlay {} else { XCTFail("The new empty window lost its command bar") }
        XCTAssertTrue(d.snapshot.pages.isEmpty)
    }

}
