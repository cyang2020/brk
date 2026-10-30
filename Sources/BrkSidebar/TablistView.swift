import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

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
    private let document = FlippedView()
    private let divider = DividerRowView()
    private let newTab = NewTabRowView()

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false
        documentView = document
        document.addSubview(divider)
        document.addSubview(newTab)
        divider.clear.target = self
        divider.clear.action = #selector(clearToday)
        divider.clear.identify(.todayClear)
        newTab.identify(.todayNewTab)
        newTab.onClick = { [dispatch] in dispatch(.commandBar(.open(.newTab))) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The rename field of `item` becomes first responder; false when it is not showing.
    func focusRenameField(_ item: ItemID) -> Bool {
        guard let row = rowViews[item], let window else { return false }
        return row.focusRenameField(in: window)
    }

    func render(_ space: SpaceSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette) {
        let height = frames.rows.last.map { $0.rect.maxY } ?? 0
        document.frame = CGRect(x: 0, y: 0, width: frames.tablistViewport.width, height: max(height, frames.tablistViewport.height))
        var rowsByID: [ItemID: Row] = [:]
        func index(_ rows: [Row]) { for row in rows { rowsByID[row.id] = row; if case .folder(let f) = row { index(f.children) } } }
        index(space.pinned.rows)
        index(space.today.rows)
        var seen: Set<ItemID> = []
        for frame in frames.rows {
            switch frame.kind {
            case .item(let id):
                guard let row = rowsByID[id] else { continue }
                seen.insert(id)
                let view = rowViews[id] ?? {
                    let v = RowView(dispatch: dispatch)
                    rowViews[id] = v
                    document.addSubview(v)
                    return v
                }()
                view.frame = frame.rect
                view.depth = frame.depth
                view.render(row, renaming: renaming == id, palette: palette)
            case .divider:
                divider.frame = frame.rect
                divider.render(palette: palette)
            case .newTab:
                newTab.frame = frame.rect
                newTab.render(palette: palette)
            case .topSpacer:
                break
            }
        }
        for (id, view) in rowViews where !seen.contains(id) { view.removeFromSuperview(); rowViews[id] = nil }
        // TODO(W3): section containers identify(.section(kind)) for e2e scoping; the space-switch slide animation.
    }

    @objc private func clearToday() { dispatch(.tab(.clearToday)) }
}

@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The Pinned/Today divider with Today's Clear button.
@MainActor
final class DividerRowView: NSView {
    let line = NSView()
    let clear = NSButton(title: Copy.clearToday, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        line.wantsLayer = true
        clear.isBordered = false
        clear.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addSubview(line)
        addSubview(clear)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(palette: Palette) {
        let inset = Metrics.tablist.selectionInset.value
        clear.sizeToFit()
        clear.frame.origin = CGPoint(x: bounds.width - inset - clear.frame.width, y: (bounds.height - clear.frame.height) / 2)
        clear.contentTintColor = palette.color(palette.tokens.foreground)
        line.frame = CGRect(x: inset, y: bounds.midY, width: max(0, clear.frame.minX - 2 * inset), height: 1)
        line.layer?.backgroundColor = palette.color(palette.tokens.separator).cgColor
    }
}

/// Today's "New Tab" row (Arc: `newTabButton`).
@MainActor
final class NewTabRowView: NSView {
    private let label = NSTextField(labelWithString: "+  " + Copy.newTab)
    var onClick: (() -> Void)?

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(label)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(palette: Palette) {
        label.textColor = palette.color(palette.tokens.foreground)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: Metrics.tablist.selectionInset.value * 2, y: (bounds.height - label.frame.height) / 2)
    }

    override func mouseUp(with event: NSEvent) { onClick?() }
}

/// One row: tab, folder header, or split. Background by status (TabCellBackgroundCurrent / ContentVisible /
/// hover), selection 36 tall inset 8 radius 12, hover close button (archive) on tabs.
/// Click -> `.tab(.focus(id))`; double-click -> `.item(.beginRename(.item(id)))`; folder click -> `.item(.toggleFolder)`;
/// right-click -> `.sidebar(.popupMenu(.item(id), at:))`; drag -> `TablistLayout.dropTarget` -> `.item(.move)`.
@MainActor
final class RowView: NSView {
    let dispatch: Dispatch
    private(set) var row: Row?
    var depth = 0
    private let selection = NSView()
    private let title = NSTextField(labelWithString: "")

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        selection.wantsLayer = true
        selection.layer?.cornerCurve = .continuous
        selection.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(selection)
        addSubview(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// False until the rename field exists (W3 creates it on `render(renaming: true)`).
    func focusRenameField(in window: NSWindow) -> Bool {
        // TODO(W3): guard let field = renameField else { return false }; return window.makeFirstResponder(field)
        false
    }

    func render(_ row: Row, renaming: Bool, palette: Palette) {
        self.row = row
        identify(.row(row.id))
        let t = Metrics.tablist
        let indent = Double(depth) * t.folderIndent.value
        selection.frame = CGRect(x: t.selectionInset.value + indent, y: (bounds.height - t.selectionHeight.value) / 2,
                                 width: max(0, bounds.width - 2 * t.selectionInset.value - indent), height: t.selectionHeight.value)
        let text: String
        var background: RGBA?
        var dim = false
        switch row {
        case .tab(let tab):
            text = tab.title
            dim = !tab.loaded
            switch tab.status {
            case .current: background = palette.tokens.tabCurrent
            case .visible: background = palette.tokens.tabVisible
            case .idle: background = nil
            }
        case .folder(let folder):
            text = (folder.collapsed ? "▸ " : "▾ ") + folder.title
        case .split(let split):
            text = split.panes.map(\.title).joined(separator: " | ")
            background = split.status == .current ? palette.tokens.tabCurrent : nil
        }
        selection.layer?.backgroundColor = background.map { palette.color($0).cgColor }
        title.stringValue = text
        title.textColor = palette.color(dim ? palette.tokens.foreground : palette.tokens.foregroundStrong)
        title.frame = CGRect(x: selection.frame.minX + t.selectionInset.value + t.favicon.value + t.selectionInset.value / 2,
                             y: (bounds.height - 18) / 2, width: max(0, selection.frame.width - 3 * t.selectionInset.value - t.favicon.value), height: 18)
        // TODO(W3): favicon or CustomIcon (16), loading indicator, hover close button (identify(.rowClose(id)),
        // dispatch .tab(.close(.item(id)))), the rename field identify(.renameField) committing .item(.rename(id, title:))
        // on Return and cancelling (nil) on Esc, drag and drop through TablistLayout.dropTarget.
        _ = renaming
    }

    override func mouseUp(with event: NSEvent) {
        guard let row else { return }
        if event.clickCount == 2 { dispatch(.item(.beginRename(.item(row.id)))); return }
        switch row {
        case .folder: dispatch(.item(.toggleFolder(row.id)))
        case .tab, .split: dispatch(.tab(.focus(row.id)))
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let row else { return }
        dispatch(.sidebar(.popupMenu(.item(row.id), at: event.locationInWindow)))
    }
}
