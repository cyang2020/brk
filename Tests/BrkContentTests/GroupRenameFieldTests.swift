import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
@testable import BrkSidebar
import XCTest

/// Double-clicking a Tidy group's header renames it in place. The user saw "Men" next to a field reading "Men's Bags"
/// (2026-11-14): a redraw while renaming showed the old title again, and the field sat one icon column to its right.
@MainActor
final class GroupRenameFieldTests: XCTestCase {
    func testAGroupHeaderBeingRenamedShowsOnlyTheFieldWhereItsTitleWas() throws {
        let palette = Palette(resolveTheme(SpaceTheme(colors: [RGBA(hex: "#F2EAE4")], texture: .grain, intensity: 0.25, appearance: .auto)))
        let row = RowView(dispatch: { _ in }, drag: DragController(dispatch: { _ in }))
        row.frame = CGRect(x: 0, y: 0, width: 228, height: 36)
        let group = Row.folder(FolderRow(group: true, id: ItemID("g"), section: .today, title: "Men's Bags", collapsed: false, icon: nil, children: []))
        row.render(group, section: .today, depth: 0, renaming: false, multiselected: false, palette: palette)
        row.layoutSubtreeIfNeeded()
        let title = try XCTUnwrap(row.subviews.first { ($0 as? NSTextField)?.stringValue == "Men's Bags" && !($0 is RenameField) })
        let titleX = title.frame.minX
        for _ in 0..<2 {  // the second render is the redraw that brought the old title back
            row.render(group, section: .today, depth: 0, renaming: true, multiselected: false, palette: palette)
            row.layoutSubtreeIfNeeded()
        }
        let field = try XCTUnwrap(row.subviews.compactMap { $0 as? RenameField }.first)
        XCTAssertTrue(title.isHidden)
        XCTAssertEqual(field.frame.minX, titleX, accuracy: 0.5)
        row.render(group, section: .today, depth: 0, renaming: false, multiselected: false, palette: palette)
        XCTAssertFalse(title.isHidden)
    }
}
