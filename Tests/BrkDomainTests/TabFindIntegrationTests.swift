import BrkBase
import XCTest
@testable import BrkDomain

final class TabFindIntegrationTests: XCTestCase {
    func testExplicitRevealAndFindTransferFocusWithoutLeavingACompetingSession() {
        let d = Driver()
        d.user(.find(.open(replace: false)))
        XCTAssertNotNil(d.view.find)
        d.user(.tabTools(.reveal))
        XCTAssertNil(d.view.find)
        XCTAssertEqual(d.view.focus, .sidebar)
        d.user(.find(.open(replace: false)))
        XCTAssertNotNil(d.view.find)
        XCTAssertEqual(d.view.focus, .findInput)
        XCTAssertFalse(d.state.session.windows[d.window]!.sidebarFocused)
    }
}
