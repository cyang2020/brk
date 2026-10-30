import BrkBase
import XCTest
@testable import BrkDomain

/// The overlay rule is a table on `Command`, so it is pinned now against the behavioral inventory
/// (ReduceSpecTests "peek and resize keep the archive open", "a resize still keeps an open command bar, while
/// toggling the sidebar closes it").
final class OverlayPolicyTests: XCTestCase {
    func testSidebarPeekAndResizeKeepBothOverlays() {
        for command: Command in [.sidebar(.peek(true)), .sidebar(.peek(false)), .sidebar(.resize(width: 300))] {
            XCTAssertTrue(command.keepsCommandBar, "\(command)")
            XCTAssertTrue(command.keepsLibrary, "\(command)")
        }
    }

    func testOnlyCommandBarCommandsOtherwiseKeepTheBar() {
        XCTAssertTrue(Command.commandBar(.open(.newTab)).keepsCommandBar)
        XCTAssertTrue(Command.commandBar(.submit("x")).keepsCommandBar)
        for command: Command in [.sidebar(.toggle), .library(.open(.archive)), .tab(.togglePin(.focused)), .settings(.autoArchive(.oneHour)), .app(.exit)] {
            XCTAssertFalse(command.keepsCommandBar, "\(command)")
        }
    }

    func testArchiveAndSettingsKeepTheArchivePageAndTheRestClosesIt() {
        XCTAssertTrue(Command.archive(.restore(ArchiveID("a"))).keepsLibrary)
        XCTAssertTrue(Command.settings(.autoArchive(.sevenDays)).keepsLibrary)
        for command: Command in [.sidebar(.toggle), .tab(.focus(ItemID("t"))), .commandBar(.open(.newTab)), .space(.focus(SpaceID("s")))] {
            XCTAssertFalse(command.keepsLibrary, "\(command)")
        }
    }
}
