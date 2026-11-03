import BrkBase
import BrkDomain
import XCTest
@testable import BrkSettings

/// R3-6 (A085): the Links pane says when the system-wide Little Arc shortcut could not be taken.
final class GlobalShortcutNoteTests: XCTestCase {
    func testTheNoteAppearsOnlyWhenTheShortcutIsNotSystemWide() {
        let chord = KeyChord([.option, .command], .n)
        XCTAssertNil(SettingsCopy.globalShortcutNote(nil))
        XCTAssertNil(SettingsCopy.globalShortcutNote(.off))
        XCTAssertNil(SettingsCopy.globalShortcutNote(.registered(chord)))
        let taken = SettingsCopy.globalShortcutNote(.unavailable(chord, code: -9878))
        XCTAssertTrue(taken?.contains("used by another app") == true, taken ?? "nil")
        XCTAssertTrue(taken?.hasPrefix("⌥⌘N") == true, taken ?? "nil")
        XCTAssertTrue(SettingsCopy.globalShortcutNote(.needsModifier(KeyChord([], .n)))?.contains("no modifier") == true)
    }
}
