import BrkBase
import XCTest

/// Chord parsing and formatting, as saved shortcut overrides use them.
final class KeyTests: XCTestCase {
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
