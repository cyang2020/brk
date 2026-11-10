import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class BrowserBasicIntegrationTests: XCTestCase {
    func testBackgroundStartupSyncKeepsTheEmptyWindowCommandBar() {
        let d = Driver(startURL: nil)
        let overlay = d.view.overlay
        d.system(.sidebarData(.syncPoll))
        XCTAssertEqual(d.view.overlay, overlay)
        if case .commandBar? = d.view.overlay {} else { XCTFail("The new empty window lost its command bar") }
        XCTAssertTrue(d.snapshot.pages.isEmpty)
    }

}
