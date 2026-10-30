import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// Owner: W3. The space's tab list: Pinned rows, the divider with Today's Clear, the New Tab row, Today rows.
///
/// Not an NSOutlineView (Arc uses `TablistOutlineView`): rows are plain views in a flipped document view inside an
/// NSScrollView, placed at `SidebarFrames.rows` and reused by item id. Layout is data (BrkLayout/TablistLayout), so
/// row geometry, drag hit-testing and pixel tests read one pure function instead of NSOutlineView's internal layout.
/// Space switches slide the old rows out and the new ones in over Metrics.motion.spaceSwitch.
@MainActor
final class TablistView: NSScrollView {
    let dispatch: Dispatch
    private var rowViews: [ItemID: RowView] = [:]

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func render(_ space: SpaceSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette) {
        // TODO(W3): document view height = last row maxY; for each RowFrame: .item(id) -> reuse or make a RowView,
        // set frame, render the Row; remove views whose ids are gone; .divider -> separator + Clear button
        // (identify(.todayClear), dispatch .tab(.clearToday)); .newTab -> identify(.todayNewTab), dispatch
        // .commandBar(.open(.newTab)). Section containers get identify(.section(kind)) for e2e scoping.
        fatalError("not implemented")
    }
}

/// One row: tab, folder header, or split. Background by status (TabCellBackgroundCurrent / ContentVisible /
/// hover), selection 36 tall inset 8 radius 12, hover close button (archive) on tabs.
/// Click -> `.tab(.focus(id))`; double-click -> `.item(.beginRename(.item(id)))`; folder click -> `.item(.toggleFolder)`;
/// right-click -> `.sidebar(.popupMenu(.item(id), at:))`; drag -> `TablistLayout.dropTarget` -> `.item(.move)`.
@MainActor
final class RowView: NSView {
    let dispatch: Dispatch
    private(set) var row: Row?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ row: Row, renaming: Bool, palette: Palette) {
        guard row != self.row else { return }
        identify(.row(row.id))
        // TODO(W3): title (SF Pro 13), favicon 16, loading indicator, dim when !loaded; rename field identify(.renameField)
        // committing .item(.rename(id, title:)) on Return and cancelling (nil) on Esc.
        self.row = row
        fatalError("not implemented")
    }
}
