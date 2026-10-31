import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The space's tab list: Pinned rows (folders nested), the divider with Today's Clear, the New Tab row,
/// Today rows.
///
/// Not an NSOutlineView (Arc uses `TablistOutlineView`): rows are plain views in a flipped document view inside an
/// NSScrollView, placed at `SidebarFrames.rows` and reused by item id. Layout is data (BrkLayout/TablistLayout), so
/// row geometry, drag hit-testing and pixel tests read one pure function instead of NSOutlineView's internal layout.
/// Rows sit in two section containers (`section-pinned`, `section-today`) so e2e can scope rows to a section.
/// Space switches push the old rows out and the new ones in over Metrics.motion.spaceSwitch.
@MainActor
final class TablistView: NSScrollView {
    private let dispatch: Dispatch
    private let drag: DragController
    private let document = ListDocumentView()
    private let pinnedSection = FlippedView()
    private let todaySection = FlippedView()
    private let divider: DividerRowView
    private let newTab: NewTabRowView
    private let dropLine = NSView()
    private let topEdge = NSView()
    private let bottomEdge = NSView()
    private var rowViews: [ItemID: RowView] = [:]
    /// Cmd+click selection: view state (no command carries it). The hover × on a selected row closes all of them.
    private var multiselection: [ItemID] = []
    private var last: (space: SpaceSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette)?
    private var dropFolder: ItemID?
    private var contentBottom = 0.0

    init(dispatch: @escaping Dispatch, drag: DragController) {
        self.dispatch = dispatch
        self.drag = drag
        divider = DividerRowView(dispatch: dispatch)
        newTab = NewTabRowView(dispatch: dispatch)
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .allowed
        horizontalScrollElasticity = .none
        contentView.wantsLayer = true
        documentView = document
        pinnedSection.identify(.section(.pinned))
        todaySection.identify(.section(.today))
        for view in [pinnedSection, todaySection, dropLine] { document.addSubview(view) }
        todaySection.addSubview(divider)
        todaySection.addSubview(newTab)
        dropLine.wantsLayer = true
        dropLine.isHidden = true
        for edge in [topEdge, bottomEdge] {
            edge.wantsLayer = true
            edge.isHidden = true
            addSubview(edge)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// A rename field of some row is being edited.
    var isRenaming: Bool { rowViews.values.contains { $0.isEditingName } }

    /// The rename field of `item` becomes first responder; false when it is not showing.
    func focusRenameField(_ item: ItemID) -> Bool {
        guard let row = rowViews[item], let window else { return false }
        return row.focusRenameField(in: window)
    }

    func focusList() -> Bool {
        guard let window else { return false }
        return window.makeFirstResponder(document)
    }

    func render(_ space: SpaceSnapshot, renaming: ItemID?, frames f: SidebarFrames, dockOrder: [SpaceID], palette: Palette) {
        if let last, last.space == space, last.renaming == renaming, last.frames == f, last.palette == palette { return }
        let previousSpace = last?.space.id
        last = (space, renaming, f, palette)
        if let previousSpace, previousSpace != space.id { pushTransition(from: previousSpace, to: space.id, order: dockOrder) }

        var rows: [ItemID: (row: Row, section: SectionKind)] = [:]
        func index(_ list: [Row], _ section: SectionKind) {
            for row in list {
                rows[row.id] = (row, section)
                if case .folder(let folder) = row { index(folder.children, section) }
            }
        }
        index(space.pinned.rows, .pinned)
        index(space.today.rows, space.today.kind)
        todaySection.identify(.section(space.today.kind))

        // Section containers enclose their rows (Today: the divider, New Tab and its rows).
        let width = f.tablistViewport.width
        var pinnedRect: CGRect?, todayRect: CGRect?, spacer = CGRect.zero
        for frame in f.rows {
            switch frame.kind {
            case .topSpacer: spacer = frame.rect
            case .item(let id) where rows[id]?.section == .pinned: pinnedRect = pinnedRect?.union(frame.rect) ?? frame.rect
            case .item, .divider, .newTab: todayRect = todayRect?.union(frame.rect) ?? frame.rect
            }
        }
        pinnedSection.frame = pinnedRect ?? CGRect(x: 0, y: spacer.maxY, width: width, height: 0)
        todaySection.frame = todayRect ?? CGRect(x: 0, y: spacer.maxY, width: width, height: 0)
        contentBottom = Double(f.rows.last?.rect.maxY ?? 0)
        document.frame = CGRect(x: 0, y: 0, width: width, height: max(contentBottom, f.tablistViewport.height))

        multiselection.removeAll { rows[$0] == nil }
        var seen: Set<ItemID> = []
        for frame in f.rows {
            switch frame.kind {
            case .item(let id):
                guard let (row, section) = rows[id] else { continue }
                seen.insert(id)
                let container = section == .pinned ? pinnedSection : todaySection
                let view = rowViews[id] ?? makeRow(id)
                if view.superview !== container { container.addSubview(view) }
                view.frame = frame.rect.offsetBy(dx: -container.frame.minX, dy: -container.frame.minY)
                view.render(row, section: section, depth: frame.depth, renaming: renaming == id, multiselected: multiselection.contains(id), palette: palette)
            case .divider:
                divider.frame = frame.rect.offsetBy(dx: -todaySection.frame.minX, dy: -todaySection.frame.minY)
                divider.render(canClear: space.today.kind == .today && !space.today.rows.isEmpty, palette: palette)
            case .newTab:
                newTab.frame = frame.rect.offsetBy(dx: -todaySection.frame.minX, dy: -todaySection.frame.minY)
                newTab.render(palette: palette)
            case .topSpacer:
                break
            }
        }
        for (id, view) in rowViews where !seen.contains(id) {
            view.retire()
            view.removeFromSuperview()
            rowViews[id] = nil
        }
        dropLine.layer?.backgroundColor = palette.color(palette.tokens.dragHintStrong).cgColor
        for edge in [topEdge, bottomEdge] { edge.layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor }
        updateEdges()
    }

    private func makeRow(_ id: ItemID) -> RowView {
        let view = RowView(dispatch: dispatch, drag: drag)
        view.onToggleMultiselect = { [weak self] id in self?.toggleMultiselect(id) }
        view.onClearMultiselect = { [weak self] in self?.clearMultiselect() }
        view.closeTargets = { [weak self] id in
            guard let self, self.multiselection.contains(id) else { return [id] }
            return self.multiselection
        }
        rowViews[id] = view
        return view
    }

    private func toggleMultiselect(_ id: ItemID) {
        if let i = multiselection.firstIndex(of: id) { multiselection.remove(at: i) } else { multiselection.append(id) }
        for (rowID, view) in rowViews { view.multiselected = multiselection.contains(rowID) }
    }

    private func clearMultiselect() {
        guard !multiselection.isEmpty else { return }
        multiselection = []
        for view in rowViews.values { view.multiselected = false }
    }

    /// Arc slides the space pages sideways (`SidebarPagingContainerViewController`): forward in dock order pushes
    /// from the right.
    private func pushTransition(from old: SpaceID, to new: SpaceID, order: [SpaceID]) {
        guard window != nil, let a = order.firstIndex(of: old), let b = order.firstIndex(of: new) else { return }
        let push = CATransition()
        push.type = .push
        push.subtype = b > a ? .fromRight : .fromLeft
        push.duration = Metrics.motion.spaceSwitch.value
        push.timingFunction = CAMediaTimingFunction(name: .easeOut)
        contentView.layer?.add(push, forKey: "spaceSwitch")
    }

    // MARK: Scroll edges: 1 pt hairlines while rows are hidden above or below (cra L748).

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateEdges()
    }

    private func updateEdges() {
        let visible = contentView.documentVisibleRect
        let line = Draw.hairline.value
        let top = isFlipped ? 0 : bounds.height - line, bottom = isFlipped ? bounds.height - line : 0
        topEdge.frame = CGRect(x: 0, y: top, width: bounds.width, height: line)
        bottomEdge.frame = CGRect(x: 0, y: bottom, width: bounds.width, height: line)
        topEdge.isHidden = visible.minY <= 0
        bottomEdge.isHidden = visible.maxY >= contentBottom
    }

    // MARK: Drag feedback (DragController)

    /// A point in the window's content view (top-left origin) in the list's document coordinates.
    func documentPoint(fromRoot point: CGPoint, frames f: SidebarFrames) -> CGPoint {
        let scroll = contentView.bounds.origin
        return CGPoint(x: point.x - f.tablistViewport.minX + scroll.x, y: point.y - f.tablistViewport.minY + scroll.y)
    }

    /// Scrolls when a drag holds near the top or bottom edge of the visible list.
    func autoScroll(at point: CGPoint, frames f: SidebarFrames) {
        let zone = Metrics.tablist.rowHeight.value / 2
        var origin = contentView.bounds.origin
        if point.y < f.tablistViewport.minY + zone { origin.y -= Draw.autoScrollStep.value }
        else if point.y > f.tablistViewport.maxY - zone { origin.y += Draw.autoScrollStep.value }
        else { return }
        origin.y = min(max(0, origin.y), max(0, document.frame.height - contentView.bounds.height))
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }

    /// Draws where `destination` lands: a line between rows, or the target folder row highlighted. Nil clears it.
    func showDrop(_ destination: Destination?, dragging: ItemID?, at point: CGPoint?, frames f: SidebarFrames, space: SpaceSnapshot) {
        setDropFolder(nil)
        dropLine.isHidden = true
        guard case .into(let parent, let index)? = destination, let dragging else { return }
        let rect = { (id: ItemID) in f.rows.first { $0.kind == .item(id) } }
        let t = Metrics.tablist
        let half = t.rowSpacing.value / 2
        let children: [Row]
        var depth = 0
        if parent == space.pinned.root { children = space.pinned.rows }
        else if parent == space.today.root { children = space.today.rows }
        else if case .folder(let folder)? = Self.find(parent, in: space.pinned.rows + space.today.rows), let folderRow = rect(parent) {
            children = folder.children
            depth = folderRow.depth + 1
            let overFolder = point.map { folderRow.rect.contains($0) } ?? false
            if overFolder || folder.collapsed || folder.children.allSatisfy({ $0.id == dragging }) {
                setDropFolder(parent)
                return
            }
        } else { return }
        let others = children.filter { $0.id != dragging }
        let y: Double
        if index < others.count, let target = rect(others[index].id) {
            y = target.rect.minY - half
        } else if let lastChild = others.last, let end = Self.lastVisible(lastChild).flatMap(rect) {
            y = end.rect.maxY + half
        } else if parent == space.pinned.root, let spacer = f.rows.first(where: { $0.kind == .topSpacer }) {
            y = spacer.rect.maxY + half
        } else if parent == space.today.root, let newTabRow = f.rows.first(where: { $0.kind == .newTab }) {
            y = newTabRow.rect.maxY + half
        } else { return }
        let indent = t.selectionInset.value + Double(depth) * t.folderIndent.value
        let line = Draw.dropLineWidth.value
        dropLine.frame = CGRect(x: indent, y: y - line / 2, width: max(0, document.bounds.width - indent - t.selectionInset.value), height: line)
        dropLine.layer?.cornerRadius = line / 2
        dropLine.isHidden = false
    }

    private func setDropFolder(_ id: ItemID?) {
        guard id != dropFolder else { return }
        if let old = dropFolder { rowViews[old]?.dropInto = false }
        dropFolder = id
        if let id { rowViews[id]?.dropInto = true }
    }

    func rowView(_ id: ItemID) -> RowView? { rowViews[id] }

    static func find(_ id: ItemID, in rows: [Row]) -> Row? {
        for row in rows {
            if row.id == id { return row }
            if case .folder(let folder) = row, let hit = find(id, in: folder.children) { return hit }
        }
        return nil
    }

    /// The last row drawn for `row`'s subtree: itself, or the last visible descendant of an expanded folder.
    static func lastVisible(_ row: Row) -> ItemID? {
        if case .folder(let folder) = row, !folder.collapsed, let child = folder.children.last { return lastVisible(child) }
        return row.id
    }
}

/// The list's document view. Takes keyboard focus for `FocusTarget.sidebar` but handles no keys itself: app
/// shortcuts go through the menu and the key router, never through sidebar views.
@MainActor
final class ListDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

/// Geometry inside one 40 pt row: the 36 pt selection inset 8 (and indented by depth), the 16 pt icon centred 26
/// from the sidebar edge, the title from x 45, the 24 pt hover button at the right.
struct RowGeometry {
    let selection: CGRect
    let icon: CGRect
    let titleX: Double
    let button: CGRect

    init(bounds: CGRect, depth: Int) {
        let t = Metrics.tablist
        let indent = Double(depth) * t.folderIndent.value
        selection = CGRect(x: t.selectionInset.value + indent, y: (bounds.height - t.selectionHeight.value) / 2,
                           width: max(0, bounds.width - 2 * t.selectionInset.value - indent), height: t.selectionHeight.value)
        icon = CGRect(x: selection.minX + Draw.faviconLeading.value, y: bounds.midY - t.favicon.value / 2, width: t.favicon.value, height: t.favicon.value)
        titleX = selection.minX + Draw.titleLeading.value
        let size = 2 * t.hoverButtonRadius.value
        button = CGRect(x: selection.maxX - Draw.closeTrailing.value - size, y: bounds.midY - size / 2, width: size, height: size)
    }

    /// The title's frame for a label of `height`, ending before `trailing`.
    func title(height: Double, trailing: Double, in bounds: CGRect) -> CGRect {
        CGRect(x: titleX, y: (bounds.height - height) / 2, width: max(0, trailing - titleX), height: height)
    }
}

/// One row (Arc: `TabCellView`, `SplitViewCellView`, a folder's cell): background by status and pointer state,
/// icon, title, and the hover button. Tabs: × archives a Today tab ("Archive this tab"), − unloads a loaded Pinned
/// tab ("Close and Keep Pinned"). Folders: open or closed folder glyph; a click toggles. Splits: the panes side by
/// side in one row, separated by a slash, each with its own × on hover. Double-click renames a tab or folder in place.
@MainActor
final class RowView: HoverView {
    private let dispatch: Dispatch
    private let drag: DragController
    private(set) var row: Row?
    private var section: SectionKind = .today
    private var depth = 0
    private var palette: Palette?
    private let background = NSView()
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private let button = GlyphButton()
    private var segments: [SplitSegmentView] = []
    private var slashes: [CAShapeLayer] = []
    private var renameField: RenameField?
    /// A split row with a custom icon starts its panes after the icon; without one they start in the icon slot.
    private var splitIcon = false
    var multiselected = false { didSet { if multiselected != oldValue { stateChanged() } } }
    var dropInto = false { didSet { if dropInto != oldValue { stateChanged() } } }
    var dragSource = false { didSet { alphaValue = dragSource ? Draw.dragSourceAlpha.value : 1 } }
    var onToggleMultiselect: ((ItemID) -> Void)?
    var onClearMultiselect: (() -> Void)?
    /// The tabs the hover × closes: this row, or the whole Cmd+click selection it belongs to.
    var closeTargets: ((ItemID) -> [ItemID])?

    init(dispatch: @escaping Dispatch, drag: DragController) {
        self.dispatch = dispatch
        self.drag = drag
        super.init(frame: .zero)
        background.wantsLayer = true
        background.layer?.cornerCurve = .continuous
        background.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
        title.isSelectable = false
        for view in [background, icon, title, button] as [NSView] { addSubview(view) }
        button.action = { [weak self] _ in self?.closeTapped() }
    }

    var isEditingName: Bool { renameField.map { !$0.finished } ?? false }

    func render(_ row: Row, section: SectionKind, depth: Int, renaming: Bool, multiselected: Bool, palette: Palette) {
        self.row = row
        self.section = section
        self.depth = depth
        self.palette = palette
        self.multiselected = multiselected
        identify(.row(row.id))
        button.identify(.rowClose(row.id))
        var dimmed = false
        switch row {
        case .tab(let tab):
            title.stringValue = tab.title
            toolTip = tab.title
            icon.render(IconContent(tab: tab), tint: palette.ink.secondary, loading: tab.loading)
            dimmed = !tab.loaded && section != .today
            configureButton(tab: tab, palette: palette)
            setSegments([], palette: palette)
        case .folder(let folder):
            title.stringValue = folder.title
            toolTip = folder.title
            icon.render(folder.icon.map(IconContent.custom) ?? .folder(open: !folder.collapsed), tint: palette.ink.secondary)
            button.isHidden = true
            setSegments([], palette: palette)
        case .split(let split):
            title.stringValue = ""
            toolTip = split.panes.map(\.title).joined(separator: " / ")
            icon.render(split.icon.map(IconContent.custom) ?? .none, tint: palette.ink.secondary)
            splitIcon = split.icon != nil
            button.isHidden = true
            setSegments(split.panes, palette: palette)
        }
        title.textColor = palette.ink.text
        for view in [icon, title] as [NSView] { view.alphaValue = dimmed ? Draw.unloadedAlpha.value : 1 }
        if renaming, row.kind != .split { showRenameField(palette: palette) } else { retire() }
        stateChanged()
        needsLayout = true
    }

    private func configureButton(tab: TabRow, palette: Palette) {
        let today = section == .today
        button.isHidden = !today && !tab.loaded
        button.toolTip = today ? Copy.archiveTabTooltip : SidebarCopy.closeKeepPinned
        button.render(today ? .archiveTab : .closeKeepPinned, size: Draw.smallFont.value, palette: palette,
                      radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
    }

    private func setSegments(_ panes: [TabRow], palette: Palette) {
        while segments.count < panes.count {
            let segment = SplitSegmentView(dispatch: dispatch)
            segments.append(segment)
            addSubview(segment)
        }
        while segments.count > panes.count { segments.removeLast().removeFromSuperview() }
        while slashes.count < max(0, panes.count - 1) {
            let slash = CAShapeLayer()
            slash.lineCap = .round
            layer?.addSublayer(slash)
            slashes.append(slash)
        }
        while slashes.count > max(0, panes.count - 1) { slashes.removeLast().removeFromSuperlayer() }
        for (segment, pane) in zip(segments, panes) { segment.render(pane, palette: palette) }
        for slash in slashes {
            slash.strokeColor = palette.ink.slash.cgColor
            slash.lineWidth = Draw.hairline.value
        }
        title.isHidden = !panes.isEmpty
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: depth)
        background.frame = g.selection
        icon.frame = g.icon
        button.frame = g.button
        let height = title.intrinsicContentSize.height
        let trailing = button.isHidden ? g.selection.maxX - Draw.titleTrailing.value : g.button.minX
        title.frame = g.title(height: height, trailing: trailing, in: bounds)
        renameField?.frame = g.title(height: height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: bounds)
        layoutSegments(g)
    }

    /// Panes share the row from the icon slot (or after a custom split icon) to the selection's end, a slash between.
    private func layoutSegments(_ g: RowGeometry) {
        guard !segments.isEmpty else { return }
        let start = splitIcon ? g.icon.maxX : g.icon.minX - Draw.faviconLeading.value / 2
        let end = g.selection.maxX - Draw.closeTrailing.value / 2
        let gap = Draw.splitSlashSlant.value * 2
        let width = (end - start - gap * Double(segments.count - 1)) / Double(segments.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, segment) in segments.enumerated() {
            let x = start + Double(i) * (width + gap)
            segment.frame = CGRect(x: x, y: g.selection.minY, width: max(0, width), height: g.selection.height)
            if i < slashes.count {
                let mid = x + width + gap / 2, h = Draw.splitSlashHeight.value / 2, s = Draw.splitSlashSlant.value / 2
                let path = CGMutablePath()
                path.move(to: CGPoint(x: mid - s, y: bounds.midY + h))
                path.addLine(to: CGPoint(x: mid + s, y: bounds.midY - h))
                slashes[i].path = path
            }
        }
        CATransaction.commit()
    }

    override func stateChanged() {
        guard let palette, let row else { return }
        let tokens = palette.tokens
        let status: RowStatus? = switch row {
        case .tab(let tab): tab.status
        case .split(let split): split.status
        case .folder: nil
        }
        let fill: RGBA?
        if dropInto { fill = tokens.itemHover }
        else if status == .current { fill = tokens.tabCurrent }
        else if status == .visible { fill = tokens.tabVisible }
        else if isPressed { fill = tokens.tabPressed }
        else if multiselected || isHovered { fill = tokens.itemHover }
        else { fill = nil }
        let layer = background.layer
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
        layer?.borderColor = palette.color(tokens.dragHintStrong).cgColor
        layer?.borderWidth = dropInto ? Draw.hairline.value : 0
        let shadow = status == .current && !dropInto
        layer?.shadowColor = palette.color(tokens.tabShadow).cgColor
        layer?.shadowOpacity = shadow ? 1 : 0
        layer?.shadowRadius = Draw.selectedShadowRadius.value
        layer?.shadowOffset = CGSize(width: 0, height: -Draw.selectedShadowOffset.value)
        button.alphaValue = isHovered && !isEditingName ? 1 : 0
    }

    // MARK: Pointer

    override func mouseDown(with event: NSEvent) {
        guard let row else { return }
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        if event.modifierFlags.contains(.command), row.kind == .tab {
            onToggleMultiselect?(row.id)
            return
        }
        isPressed = true
        drag.press(.init(id: row.id, kind: row.kind, section: section), source: self, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if drag.drag(event) { isPressed = false }
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if drag.release(event) { return }
        guard let row, !event.modifierFlags.contains(.command), bounds.contains(local(event)) else { return }
        onClearMultiselect?()
        if event.clickCount == 2, row.kind != .split {
            dispatch(.item(.beginRename(.item(row.id))))
            return
        }
        switch row {
        case .folder: dispatch(.item(.toggleFolder(row.id)))
        case .tab: dispatch(.tab(.focus(row.id)))
        case .split:
            let point = local(event)
            let pane = segments.first { $0.frame.contains(point) }?.pane?.id
            dispatch(.tab(.focus(pane ?? row.id)))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let row else { return }
        dispatch(.sidebar(.popupMenu(.item(row.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }

    private func closeTapped() {
        guard let row else { return }
        for id in closeTargets?(row.id) ?? [row.id] { dispatch(.tab(.close(.item(id)))) }
        onClearMultiselect?()
    }

    // MARK: Rename field: Return commits, Escape cancels, losing focus commits.

    private func showRenameField(palette: Palette) {
        guard renameField == nil, let row else { return }
        let text = switch row {
        case .tab(let tab): tab.title
        case .folder(let folder): folder.title
        case .split: ""
        }
        let field = RenameField(text: text, font: title.font, color: palette.ink.text) { [weak self] title in
            guard let self, let row = self.row else { return }
            self.dispatch(.item(.rename(row.id, title: title)))
        }
        addSubview(field)
        renameField = field
        title.isHidden = true
        needsLayout = true
    }

    func focusRenameField(in window: NSWindow) -> Bool {
        layoutSubtreeIfNeeded()
        return renameField?.focus(in: window) ?? false
    }

    /// Drops the field without committing (the rename ended elsewhere: Esc through the menu, or the row left).
    func retire() {
        guard let field = renameField else { return }
        field.retire()
        renameField = nil
        title.isHidden = !segments.isEmpty
    }
}

/// One pane inside a split row: favicon and title; hovering shows its own × (Arc: per-child close).
/// Clicks go to the row (the pane under the pointer gets focus).
@MainActor
final class SplitSegmentView: HoverView {
    private let dispatch: Dispatch
    private(set) var pane: TabRow?
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private let close = GlyphButton()
    private var palette: Palette?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.tablist.hoverButtonRadius.value
        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
        title.isSelectable = false
        for view in [icon, title, close] as [NSView] { addSubview(view) }
        close.action = { [weak self] _ in
            guard let id = self?.pane?.id else { return }
            dispatch(.split(.closePaneAt(id)))
        }
        close.toolTip = Copy.archiveTabTooltip
    }

    func render(_ pane: TabRow, palette: Palette) {
        self.pane = pane
        identify(.splitSegment(pane.id))
        toolTip = pane.title
        self.palette = palette
        title.stringValue = pane.title
        title.textColor = palette.ink.text
        icon.render(IconContent(tab: pane), tint: palette.ink.secondary, loading: pane.loading)
        close.render(.archiveTab, size: Draw.smallFont.value, palette: palette, radius: Metrics.tablist.hoverButtonRadius.value,
                     hoverFill: palette.tokens.itemHover)
        close.identify(.rowClose(pane.id))
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let t = Metrics.tablist
        let side = t.favicon.value, size = min(2 * t.hoverButtonRadius.value, bounds.width / 3)
        icon.frame = CGRect(x: Draw.faviconLeading.value / 2, y: (bounds.height - side) / 2, width: side, height: side)
        close.frame = CGRect(x: bounds.width - size, y: (bounds.height - size) / 2, width: size, height: size)
        let height = title.intrinsicContentSize.height
        let start = icon.frame.maxX + Draw.faviconLeading.value / 2
        let end = close.alphaValue > 0 ? close.frame.minX : bounds.width - Draw.faviconLeading.value / 2
        title.frame = CGRect(x: start, y: (bounds.height - height) / 2, width: max(0, end - start), height: height)
    }

    override func stateChanged() {
        guard let palette else { return }
        layer?.backgroundColor = (isHovered || pane?.status == .current) ? palette.color(palette.tokens.tabChild).cgColor : nil
        close.alphaValue = isHovered ? 1 : 0
        needsLayout = true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let pane else { return }
        dispatch(.sidebar(.popupMenu(.item(pane.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }
}

/// The Pinned/Today divider (Arc: `exploreSectionDivider` with `SidebarClearButton`): a separator hairline; hovering
/// it shows "↓ Clear", which archives Today's tabs that are not on screen.
@MainActor
final class DividerRowView: HoverView {
    private let line = NSView()
    private let clear: ClearButton
    private var palette: Palette?
    private var canClear = false

    init(dispatch: @escaping Dispatch) {
        clear = ClearButton { dispatch(.tab(.clearToday)) }
        super.init(frame: .zero)
        line.wantsLayer = true
        addSubview(line)
        addSubview(clear)
        clear.identify(.todayClear)
    }

    func render(canClear: Bool, palette: Palette) {
        self.palette = palette
        self.canClear = canClear
        line.layer?.backgroundColor = palette.color(palette.tokens.separator).cgColor
        clear.render(palette: palette)
        clear.isHidden = !canClear
        stateChanged()
    }

    override func layout() {
        super.layout()
        let inset = Metrics.tablist.selectionInset.value
        let size = clear.fittingSize
        clear.frame = CGRect(x: bounds.width - inset - size.width, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        let end = clear.alphaValue > 0 && !clear.isHidden ? clear.frame.minX - inset / 2 : bounds.width - inset
        let hairline = Draw.hairline.value
        line.frame = CGRect(x: inset, y: (bounds.height - hairline) / 2, width: max(0, end - inset), height: hairline)
    }

    override func stateChanged() {
        clear.alphaValue = canClear && (isHovered || clear.isHovered) ? 1 : 0
        needsLayout = true
    }
}

/// "↓ Clear": the down arrow and the word, in the sidebar foreground; stronger on hover.
@MainActor
final class ClearButton: HoverView {
    private let arrow = NSImageView()
    private let label = NSTextField(labelWithString: Copy.clearToday)
    private let action: () -> Void
    private var palette: Palette?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.smallFont.value, weight: .medium)
        label.isSelectable = false
        addSubview(arrow)
        addSubview(label)
    }

    override var fittingSize: NSSize {
        let text = label.intrinsicContentSize
        let glyph = Draw.smallFont.value
        return NSSize(width: glyph + Draw.navGap.value * 2 + text.width, height: max(text.height, glyph))
    }

    func render(palette: Palette) {
        self.palette = palette
        arrow.image = Glyph.clearDown.image(size: Draw.captionFont.value, weight: .semibold)
        stateChanged()
    }

    override func layout() {
        super.layout()
        let glyph = Draw.smallFont.value
        arrow.frame = CGRect(x: 0, y: (bounds.height - glyph) / 2, width: glyph, height: glyph)
        let text = label.intrinsicContentSize
        label.frame = CGRect(x: glyph + Draw.navGap.value * 2, y: (bounds.height - text.height) / 2, width: text.width, height: text.height)
    }

    override func stateChanged() {
        guard let palette else { return }
        let color = palette.color(isHovered ? palette.tokens.foregroundStrong : palette.tokens.foreground)
        arrow.contentTintColor = color
        label.textColor = color
        (superview as? HoverView)?.stateChanged()
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { action() }
    }
}

/// Today's "New Tab" row (Arc: `NewTabCellView`): a plus in the icon slot and "New Tab"; opens the command bar.
@MainActor
final class NewTabRowView: HoverView {
    private let dispatch: Dispatch
    private let background = NSView()
    private let icon = IconView()
    private let label = NSTextField(labelWithString: Copy.newTab)
    private var palette: Palette?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        background.wantsLayer = true
        background.layer?.cornerCurve = .continuous
        background.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        label.font = .systemFont(ofSize: Draw.rowTitleFont.value)
        label.isSelectable = false
        for view in [background, icon, label] as [NSView] { addSubview(view) }
        identify(.todayNewTab)
    }

    func render(palette: Palette) {
        guard palette != self.palette else { return }
        self.palette = palette
        let color = palette.color(palette.tokens.foregroundStrong)
        label.textColor = color
        icon.render(.glyph(.plus), tint: color)
        stateChanged()
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: 0)
        background.frame = g.selection
        icon.frame = g.icon
        label.frame = g.title(height: label.intrinsicContentSize.height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: bounds)
    }

    override func stateChanged() {
        guard let palette else { return }
        let fill = isPressed ? palette.tokens.tabPressed : isHovered ? palette.tokens.itemHover : nil
        background.layer?.backgroundColor = fill.map { palette.color($0).cgColor }
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { dispatch(.commandBar(.open(.newTab))) }
    }
}

/// The space header above the list (Arc: `pinnedTabsHeader`): the space's icon and name, 14 pt medium in the
/// secondary color. A click collapses or expands Pinned (a chevron says which on hover); right-click is the space's
/// menu.
@MainActor
final class SpaceHeaderView: HoverView {
    private let dispatch: Dispatch
    private let icon = IconView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var space: SpaceSnapshot?
    private var palette: Palette?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.spaceHeaderFont.value, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        for view in [icon, label, chevron] as [NSView] { addSubview(view) }
    }

    func render(_ space: SpaceSnapshot, palette: Palette) {
        if space == self.space, palette == self.palette { return }
        self.space = space
        self.palette = palette
        let color = palette.color(palette.tokens.foregroundStrong)
        label.stringValue = space.title
        label.textColor = color
        icon.isHidden = space.icon == .none
        icon.render(IconContent(space: space.icon, color: RGBA(0, 0, 0, 0)), tint: color)
        chevron.image = (space.pinned.collapsed ? Glyph.chevronRight : Glyph.chevronDown).image(size: Draw.captionFont.value, weight: .semibold)
        chevron.contentTintColor = color
        toolTip = space.pinned.collapsed ? SidebarCopy.expandPinned : SidebarCopy.collapsePinned
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: 0)
        icon.frame = g.icon
        let size = Draw.smallFont.value
        chevron.frame = CGRect(x: g.selection.maxX - Draw.closeTrailing.value - size, y: (bounds.height - size) / 2, width: size, height: size)
        let start = icon.isHidden ? g.icon.minX : g.titleX
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: start, y: (bounds.height - height) / 2, width: max(0, chevron.frame.minX - start), height: height)
    }

    override func stateChanged() { chevron.alphaValue = isHovered ? 1 : 0 }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(local(event)) { dispatch(.space(.togglePinnedSection(.current))) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let space else { return }
        dispatch(.sidebar(.popupMenu(.space(space.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }
}

