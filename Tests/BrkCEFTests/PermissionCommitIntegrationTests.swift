import BrkBase
import Foundation
import XCTest
@testable import BrkCEF
@testable import BrkDomain

final class PermissionCommitIntegrationTests: XCTestCase {
    func testActualCommitWhileLoadingCanRememberButProvisionalAndReplacedDocumentsCannot() throws {
        let first = URL(string: "https://loading.example/document")!
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        let projection = ProjectionContext(now: ctx.now, calendar: .current)
        let seed = RestoreSeed(startURL: first, contentSize: CGSize(width: 1280, height: 776))
        var state = StateCodec.restore(nil, seed: seed, ctx: ctx).state
        let page = try XCTUnwrap(project(state, projection).pages.first?.id)
        let browser = BrowserToken(page: page, generation: 1)
        state = reduce(state, .system(.page(browser, .browserCreated(.profile(.default), .unavailable))), ctx).state
        var native = MainDocumentState(browser: browser)
        func emit(_ events: [PageEvent]) { for event in events { state = reduce(state, .system(.page(browser, event)), ctx).state } }
        emit(native.allowed(first, redirect: false))
        emit(native.started(first))
        emit(native.addressChanged(first, loading: true))
        guard case .loading(let token) = native.availability else { return XCTFail("The document should still be loading") }
        let origin = try XCTUnwrap(SiteOrigin(first))
        let target = SiteTarget(document: token, context: .profile(.default), origin: origin)
        XCTAssertNil(state.siteTarget(in: page.window), "Clear-data still requires a ready document")
        XCTAssertTrue(state.validSiteTarget(target, allowLoading: true))
        state = reduce(state, .user(page.window, .site(.permission(target, origin, [.notifications], .deny))), ctx).state
        XCTAssertEqual(state.sitePreferences(.profile(.default)).permissions(for: origin, embeddedIn: origin)[.notifications], .deny)
        let saved = StateCodec.encode(state)
        let restored = StateCodec.restore(saved, seed: seed, ctx: ctx).state
        XCTAssertEqual(restored.sitePreferences(.profile(.default)).permissions(for: origin, embeddedIn: origin)[.notifications], .deny)

        let replacement = URL(string: "https://replacement.example/document")!
        emit(native.allowed(replacement, redirect: false))
        XCTAssertFalse(state.validSiteTarget(target, allowLoading: true), "Pending navigation must fence the old grant")
        emit(native.started(replacement))
        XCTAssertFalse(state.validSiteTarget(target, allowLoading: true), "A replacement document must reject the old token")
        state = reduce(state, .user(page.window, .site(.permission(target, origin, [.notifications], .allow))), ctx).state
        XCTAssertEqual(state.sitePreferences(.profile(.default)).permissions(for: origin, embeddedIn: origin)[.notifications], .deny)
    }
}
