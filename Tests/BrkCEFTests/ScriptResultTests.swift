import Foundation
import XCTest
@testable import BrkCEF

/// AppleScript's `execute` answers text: a string as it is, numbers and booleans as JavaScript writes them, objects
/// and arrays as JSON, nothing for undefined and null.
final class ScriptResultTests: XCTestCase {
    func testJavaScriptValuesBecomeAppleScriptText() {
        XCTAssertEqual(CEFEngine.scriptText("Home"), "Home")
        XCTAssertEqual(CEFEngine.scriptText(NSNumber(value: 42)), "42")
        XCTAssertEqual(CEFEngine.scriptText(NSNumber(value: 2.5)), "2.5")
        XCTAssertEqual(CEFEngine.scriptText(NSNumber(value: true)), "true")
        XCTAssertEqual(CEFEngine.scriptText(["b": 1, "a": [1, 2]] as [String: Any]), #"{"a":[1,2],"b":1}"#)
        XCTAssertNil(CEFEngine.scriptText(nil))
        XCTAssertNil(CEFEngine.scriptText(NSNull()))
    }
}
