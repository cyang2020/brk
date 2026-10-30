import BrkBase
import XCTest

/// `Key` is its own inventory (CaseIterable), so every case must round-trip by code and by name: no second list.
final class KeyTests: XCTestCase {
    func testEveryKeyRoundTripsByCodeAndName() {
        for key in Key.allCases {
            XCTAssertEqual(Key.byCode(key.code), key, "\(key)")
            XCTAssertEqual(Key.byName(key.name), key, "\(key)")
            XCTAssertFalse(key.menuKeyEquivalent.isEmpty, "\(key)")
        }
        XCTAssertEqual(Set(Key.allCases.map(\.name)).count, Key.allCases.count, "names are unique")
        XCTAssertEqual(Key.t.code, 17)
        XCTAssertEqual(Key.equals.menuKeyEquivalent, "=")
        XCTAssertNil(Key.byCode(255))
    }

    func testChordParsingAndFormatting() throws {
        let t = try XCTUnwrap(KeyChord(parsing: "cmd+t"))
        XCTAssertEqual(t, KeyChord(.command, .t))
        XCTAssertEqual(t.description, "cmd+t")
        XCTAssertEqual(KeyChord(parsing: "Ctrl+Shift+=")?.description, "ctrl+shift+=")
        XCTAssertEqual(KeyChord(parsing: "ctrl+shift++"), KeyChord([.control, .shift], .equals))
        XCTAssertEqual(KeyChord(parsing: "opt+cmd+right"), KeyChord([.option, .command], .rightArrow))
        XCTAssertEqual(KeyChord(parsing: "escape"), KeyChord([], .escape))
        XCTAssertEqual(KeyChord(parsing: "f12"), KeyChord([], .f12))
        XCTAssertEqual(KeyChord(parsing: "ctrl+alt+shift+cmd+t")?.description, "ctrl+alt+shift+cmd+t")
        XCTAssertNil(KeyChord(parsing: "cmd+zz"))
        XCTAssertNil(KeyChord(parsing: "hyper+t"))
        XCTAssertNil(KeyChord(parsing: ""))
    }
}
