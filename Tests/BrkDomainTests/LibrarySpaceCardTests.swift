import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F5. The … menu of a card on the Library's Spaces page, as Arc 1.170 shows it (verify/visual-pairs/run-20261103
/// P30-c): four groups, nine rows, every row a command that does something to the card's space while the Library
/// stays open.
final class LibrarySpaceCardTests: XCTestCase {
    private func library(_ d: Driver) -> LibrarySnapshot? {
        if case .library(let library)? = d.view.overlay { return library }
        return nil
    }

    /// Two spaces, the window on Work, the Library open on Spaces.
    private func fixture() -> (Driver, first: SpaceID, work: SpaceID) {
        let d = Driver()
        let first = d.view.space.id
        let work = d.newSpace("Work", color: ThemePresets.drab[3])
        d.user(.library(.open(.spaces)))
        return (d, first, work)
    }

    /// Arc's four groups and nine rows, without Manage Spaces… and without Move Left / Move Right (the card's handle
    /// reorders); New Folder and Live Folders act on the card's space even when the window shows another; Delete
    /// Space asks first; Share Space… writes the export file
    func testTheCardMenuIsArcsFourGroupsOfNineRows() throws {
        let (d, first, work) = fixture()
        let t = d.user(.sidebar(.popupMenu(.spaceCard(first), at: CGPoint(x: 620, y: 706))))
        guard case .popupMenu(let window, let menu, let at)? = t.effects.first else { return XCTFail("no popup") }
        XCTAssertEqual(window, d.window)
        XCTAssertEqual(at, CGPoint(x: 620, y: 706))
        XCTAssertNotNil(library(d), "opening the card's menu keeps the Library")
        XCTAssertEqual(layout(menu), ["Change Space Icon…", "Rename Space…", "Edit Theme Color…", "Set Profile ▸", "|",
                                      "New Folder", "Live Folders ▸", "|",
                                      "Share Space…", "Export “Space 1” into Folder ▸", "|",
                                      "Delete Space"])
        XCTAssertEqual(command(menu, "Change Space Icon…"), .sidebar(.openDialog(.icon(.space(first)))))
        XCTAssertEqual(command(menu, "Rename Space…"), .sidebar(.openDialog(.rename(.space(first)))))
        XCTAssertEqual(command(menu, "Edit Theme Color…"), .sidebar(.openDialog(.theme(.space(first)))))
        XCTAssertEqual(command(menu, "New Folder"), .space(.inSpace(first, .newFolder)))
        XCTAssertEqual(isEnabled(menu, "New Folder"), true, "the card's space need not be the window's")
        XCTAssertEqual(titles(try XCTUnwrap(submenu(menu, "Live Folders"))), ["New GitHub Live Folder…", "Connect Calendar File…"])
        XCTAssertEqual(command(menu, "New GitHub Live Folder…"), .space(.inSpace(first, .connectGitHub)))
        XCTAssertEqual(command(menu, "Connect Calendar File…"), .space(.inSpace(first, .connectCalendar)))
        XCTAssertEqual(command(menu, "Share Space…"), .app(.export(.space(.space(first)))))
        XCTAssertEqual(titles(try XCTUnwrap(submenu(menu, "Export “Space 1” into Folder"))), ["Work", "Bookmarks Folder on Disk…"])
        XCTAssertEqual(command(menu, "Work"), .tabTools(.spaceIntoFolder(first, into: work)))
        XCTAssertEqual(command(menu, "Bookmarks Folder on Disk…"), .space(.exportIntoFolder(first)))
        XCTAssertEqual(command(menu, "Delete Space"), .space(.requestDelete(first)))
        XCTAssertEqual(isEnabled(menu, "Delete Space"), true)
        XCTAssertEqual(try XCTUnwrap(submenu(menu, "Set Profile")).entries.first,
                       .choice(title: "Default", command: .profile(.assign(.space(first), to: .default)), on: true))
        XCTAssertFalse(titles(menu).contains { ["Move Left", "Move Right", "Manage Spaces…", "Edit Space…"].contains($0) })
        XCTAssertEqual(d.user(.sidebar(.popupMenu(.spaceCard(SpaceID("ghost")), at: .zero))).effects, [])
    }

    /// every row, chosen from the same state, changes something or asks the app to (a dialog, a panel, an export, a
    /// source request), and the Library is still open afterwards
    func testEveryRowDoesSomethingAndKeepsTheLibrary() throws {
        let (d, first, _) = fixture()
        d.user(.profile(.create(name: "Second", icon: nil)))
        d.user(.library(.open(.spaces)))
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.spaceCard(first), at: .zero)))))
        let rows = menu.actions
        XCTAssertEqual(rows.count, 13, "six plain rows; Set Profile's two profiles and New Profile…; Live Folders' two; Export's other space and folder on disk")
        for row in rows where row.title != "Default" {
            let t = reduce(d.state, .user(d.window, row.command), d.ctx)
            XCTAssertTrue(t.changed || !t.effects.isEmpty, "\(row.title) did nothing")
            let after = project(t.state, ProjectionContext(now: d.now, calendar: Driver.calendar)).windows[d.window]
            if case .library? = after?.overlay {} else if row.title != "New Profile…" { XCTFail("\(row.title) closed the Library") }
        }
    }

    /// New Folder puts "New Folder" at the top of the card's space's Pinned, where the card shows it; the window stays
    /// on its own space, nothing waits for a rename the Library hides, and focus is not taken from the Library
    func testNewFolderLandsInTheCardsSpace() throws {
        let (d, first, work) = fixture()
        d.user(.space(.inSpace(first, .newFolder)))
        XCTAssertEqual(d.view.space.id, work)
        let card = try XCTUnwrap(library(d)?.spaces.first { $0.id == first })
        guard case .folder(let folder)? = card.pinned.first else { return XCTFail("no folder on the card") }
        XCTAssertEqual(folder.title, "New Folder")
        XCTAssertTrue(library(d)?.spaces.first { $0.id == work }?.pinned.isEmpty == true)
        XCTAssertNil(d.view.renaming)
        XCTAssertEqual(d.view.focus, FocusTarget.none)
    }

    /// Live Folders: the source request belongs to the space the window shows, so the window shows the card's space
    /// first; the Library stays
    func testLiveFoldersShowTheCardsSpaceAndAskForTheSource() throws {
        let (d, first, _) = fixture()
        let t = d.user(.space(.inSpace(first, .connectGitHub)))
        XCTAssertEqual(d.view.space.id, first)
        XCTAssertTrue(t.effects.contains { if case .siteRequest = $0 { true } else { false } })
        XCTAssertNotNil(library(d))
        let calendar = d.user(.space(.inSpace(first, .connectCalendar)))
        XCTAssertTrue(calendar.effects.contains { if case .siteRequest = $0 { true } else { false } })
        assertUnchanged(d.state, d.user(.space(.inSpace(SpaceID("ghost"), .newFolder))))
    }

    /// Delete Space asks with Arc's dialog (P27) over the Library; confirming deletes the space and its card goes
    func testDeleteSpaceAsksFirst() throws {
        let (d, first, _) = fixture()
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.spaceCard(first), at: .zero)))))
        d.user(try XCTUnwrap(command(menu, "Delete Space")))
        let pending = try XCTUnwrap(d.view.pendingSpaceDeletion)
        XCTAssertEqual(pending.id, first)
        XCTAssertNotNil(library(d))
        d.user(.space(.confirmDelete(first, token: pending.token, confirmed: true)))
        XCTAssertFalse(d.state.doc.spaceOrder.contains(first))
        XCTAssertEqual(library(d)?.spaces.map(\.id), d.state.doc.spaceOrder)
    }
}
