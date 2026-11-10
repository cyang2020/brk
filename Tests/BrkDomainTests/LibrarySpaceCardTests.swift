import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F5. The … menu of a card on the Library's Spaces page, as Arc 1.170 shows it (verify/visual-pairs/run-20261103
/// P30-c): every row a command that does something to the card's space while the Library stays open.
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
