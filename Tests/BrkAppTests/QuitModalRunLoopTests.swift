import AppKit
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class QuitModalRunLoopTests: XCTestCase {
    func testQuitRequestCanRunWhileANativeConfirmationOwnsTheModalMode() {
        var invoked = false
        Quit.enqueue { invoked = true }
        let deadline = Date().addingTimeInterval(0.25)
        while !invoked && Date() < deadline {
            _ = RunLoop.main.run(mode: .modalPanel, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(invoked, "Quit must reach ordered shutdown while a native modal confirmation is pending")
    }
}
