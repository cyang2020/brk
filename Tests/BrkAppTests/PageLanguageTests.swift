@testable import BrkApp
import XCTest

/// A page that declares no language: what its text says, and silence when it does not say clearly.
final class PageLanguageTests: XCTestCase {
    func testRecognizesFrenchAndEnglishRunningText() {
        XCTAssertEqual(PageLanguage.recognize("La bibliothèque du quartier ouvre ses portes tous les matins à neuf heures. Les habitants y viennent pour emprunter des livres et lire les journaux."), "fr")
        XCTAssertEqual(PageLanguage.recognize("The neighbourhood library opens its doors every morning at nine o'clock. People come to borrow books and read the newspapers."), "en")
    }

    func testAShortTextOrOneWithoutLettersDoesNotSay() {
        XCTAssertNil(PageLanguage.recognize(""))
        XCTAssertNil(PageLanguage.recognize("Bonjour"))
        XCTAssertNil(PageLanguage.recognize("12 345 678 — 90 + 12 = 34 / 56 789 012 345 678 901 234 567 890 123 456"))
    }
}
