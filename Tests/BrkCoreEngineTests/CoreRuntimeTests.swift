import BrkBase
import Foundation
import XCTest
@testable import BrkCoreEngine

@MainActor
final class CoreRuntimeTests: XCTestCase {
    func testKeychainModeMatchesTheImportLaunchBoundary() {
        for environment in [[:], ["BRK_CONTROL_SOCKET": ""], ["BRK_CONTROL_SOCKET": "/tmp/test.sock"]] {
            let arguments = BrkCoreRuntime.arguments(userData: URL(fileURLWithPath: "/tmp/brk-profile"),
                                                     debugPort: nil, environment: environment)
            XCTAssertEqual(arguments.contains("--use-mock-keychain"),
                           LaunchOptions(environment: environment).controlSocket != nil)
        }
    }
}
