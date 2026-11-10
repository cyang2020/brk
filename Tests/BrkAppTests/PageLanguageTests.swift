@testable import BrkApp
import XCTest

/// A page that declares no language: what its text says, and silence when it does not say clearly.
final class PageLanguageTests: XCTestCase {
    func testAShortTextOrOneWithoutLettersDoesNotSay() {
        XCTAssertNil(PageLanguage.recognize(""))
        XCTAssertNil(PageLanguage.recognize("Bonjour"))
        XCTAssertNil(PageLanguage.recognize("12 345 678 — 90 + 12 = 34 / 56 789 012 345 678 901 234 567 890 123 456"))
    }
}
