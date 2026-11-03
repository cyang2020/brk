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
    private let education: NSButton
    private let newTab: NewTabRowView
    private let dropLine = NSView()
    private let topEdge = NSView()
    private let bottomEdge = NSView()
    private var rowViews: [ItemID: RowView] = [:]
    /// A render cache of the domain selection. Pointer gestures dispatch typed selection and bulk commands.
    private var multiselection: [ItemID] = []
    private var last: (space: SpaceSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette)?
    private var tools: TabToolsSnapshot?
    private var lastReveal: UInt64?
    private var dropFolder: ItemID?
    private var contentBottom = 0.0
    /// The pointer is over the sidebar: Today's Clear shows (Arc).
    var sidebarHovered = false { didSet { divider.sidebarHovered = sidebarHovered } }
    private lazy var folderPreview = FolderPreview(dispatch: dispatch)
    private var now = Instant(milliseconds: 0)

    init(dispatch: @escaping Dispatch, drag: DragController) {
        self.dispatch = dispatch
        self.drag = drag
        divider = DividerRowView(dispatch: dispatch)
        education = NSButton(title: "", target: nil, action: nil)
        newTab = NewTabRowView(dispatch: dispatch)
        super.init(frame: .zero)
        document.onKey = { [weak self] command in self?.dispatch(.tabTools(command)) }
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
        document.addSubview(education)
        education.target = self
        education.action = #selector(dismissEducation)
        education.bezelStyle = .regularSquare
        education.cell?.wraps = true
        education.cell?.usesSingleLineMode = false
        education.cell?.lineBreakMode = .byWordWrapping
        education.font = .systemFont(ofSize: 11)
        education.identify(.tabTool("education"))
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

    /// `newTabCurrent`: the New Tab row draws as the current row (a blank window showing nothing, as Arc's does).
    func render(_ space: SpaceSnapshot, renaming: ItemID?, frames f: SidebarFrames, dockOrder: [SpaceID], palette: Palette, tools: TabToolsSnapshot,
                newTabCurrent: Bool = false, now: Instant = Instant(milliseconds: 0)) {
        self.tools = tools
        self.now = now
        multiselection = tools.selected
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
        education.isHidden = tools.archiveEducation == nil
        education.title = tools.archiveEducation.map { $0 + "  ×" } ?? ""
        education.frame = NSRect(x: 8, y: contentBottom + 10, width: max(0, width - 16), height: 68)
        if tools.archiveEducation != nil { contentBottom += 88 }
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
                newTab.render(palette: palette, current: newTabCurrent)
            case .topSpacer:
                break
            }
        }
        folderPreview.validate { id in if case .folder(let folder)? = rows[id]?.row { folder.collapsed } else { false } }
        for (id, view) in rowViews where !seen.contains(id) {
            view.retire()
            view.removeFromSuperview()
            rowViews[id] = nil
        }
        dropLine.layer?.backgroundColor = palette.color(palette.tokens.dragHintStrong).cgColor
        for edge in [topEdge, bottomEdge] { edge.layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor }
        if let reveal = tools.reveal, tools.revealGeneration != lastReveal, let row = rowViews[reveal] {
            document.scrollToVisible(document.convert(row.bounds, from: row))
            lastReveal = tools.revealGeneration
        }
        updateEdges()
    }

    @objc private func dismissEducation() { dispatch(.tabTools(.dismissArchiveEducation)) }

    private func makeRow(_ id: ItemID) -> RowView {
        let view = RowView(dispatch: dispatch, drag: drag)
        view.onRangeSelect = { [weak self] id in self?.dispatch(.tabTools(.select(id, .range))) }
        view.onSelect = { [weak self] id in self?.dispatch(.tabTools(.select(id, .replace))) }
        view.onToggleMultiselect = { [weak self] id in self?.toggleMultiselect(id) }
        view.onClearMultiselect = { [weak self] in self?.clearMultiselect() }
        view.onHover = { [weak self] row, hovered in self?.rowHovered(row, hovered) }
        view.closeTargets = { [weak self] id in
            guard let self, self.multiselection.contains(id) else { return [id] }
            return self.multiselection
        }
        rowViews[id] = view
        return view
    }

    /// Arc Previews: a collapsed folder shows its pages beside the sidebar; tabs and open folders show nothing.
    private func rowHovered(_ view: RowView, _ hovered: Bool) {
        guard hovered, tools?.hoverPreviews == true, case .folder(let folder)? = view.row, folder.collapsed, !view.isEditingName,
              let palette = last?.palette else {
            folderPreview.pointerLeft(view)
            return
        }
        folderPreview.hover(folder, over: view, now: now, palette: palette)
    }

    private func toggleMultiselect(_ id: ItemID) { dispatch(.tabTools(.select(id, .toggle))) }
    private func clearMultiselect() {}

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

/// The focused sidebar handles ordinary arrows and Return locally. App shortcuts still use the action table.
@MainActor
final class ListDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var onKey: ((TabToolsCommand) -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: onKey?(.sidebarStep(.next))
        case 126: onKey?(.sidebarStep(.previous))
        case 36, 53: onKey?(.leaveSidebar)
        default: super.keyDown(with: event)
        }
    }
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
    /// Hover changes, for the folder preview (TablistView).
    var onHover: ((RowView, Bool) -> Void)?
    private var reportedHover = false
    private(set) var row: Row?
    private var section: SectionKind = .today
    private var depth = 0
    private var palette: Palette?
    private let background = NSView()
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private lazy var media = MediaRowControls(dispatch: dispatch)
    private let audio = GlyphButton()
    private let button = GlyphButton()
    private var segments: [SplitSegmentView] = []
    /// The peeked page's icon at the row's trailing end while the window's Peek was opened from this tab.
    private let peekMarker = PeekMarkerView()
    private var renameField: RenameField?
    /// A split row with a custom icon starts its panes after the icon; without one they start in the icon slot.
    private var splitIcon = false
    var multiselected = false { didSet { if multiselected != oldValue { stateChanged() } } }
    var dropInto = false { didSet { if dropInto != oldValue { stateChanged() } } }
    var dragSource = false { didSet { alphaValue = dragSource ? Draw.dragSourceAlpha.value : 1 } }
    var onRangeSelect: ((ItemID) -> Void)?
    var onSelect: ((ItemID) -> Void)?
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
        for view in [background, icon, title, audio, media, button, peekMarker] as [NSView] { addSubview(view) }
        peekMarker.isHidden = true
        audio.action = { [weak self] _ in self?.toggleMute() }
        audio.isHidden = true
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
        media.isHidden = true
        switch row {
        case .tab(let tab):
            media.render(tab)
            audio.isHidden = !tab.audible && !tab.muted
            audio.render(tab.muted ? .speakerMuted : .speaker, size: Draw.smallFont.value, palette: palette,
                         radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
            audio.toolTip = tab.muted ? "Unmute Tab" : "Mute Tab"
            audio.identify(.tabTool("audio-" + tab.id.rawValue))
            title.stringValue = tab.title
            icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette)
            if tab.awaitingFirstDocument { title.stringValue = SidebarCopy.untitled }
            title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
            dimmed = !tab.loaded && section != .today && section != .scratch
            configureButton(tab: tab, palette: palette)
            setSegments([], palette: palette)
            peekMarker.isHidden = !tab.peeking
            if tab.peeking { peekMarker.render(favicon: tab.peekFavicon, palette: palette) }
        case .folder(let folder):
            title.stringValue = (folder.group ? "Group · " : "") + folder.title
            title.font = .systemFont(ofSize: Draw.rowTitleFont.value, weight: .semibold)
            icon.render(folder.icon.map(IconContent.custom) ?? .folder(open: !folder.collapsed), tint: palette.ink.secondary, palette: palette)
            button.isHidden = true
            setSegments([], palette: palette)
            peekMarker.isHidden = true
        case .split(let split):
            title.stringValue = ""
            icon.render(split.icon.map(IconContent.custom) ?? .none, tint: palette.ink.secondary)
            splitIcon = split.icon != nil
            button.isHidden = true
            setSegments(split.panes, palette: palette)
            peekMarker.isHidden = true
        }
        title.textColor = palette.ink.text
        for view in [icon, title] as [NSView] { view.alphaValue = dimmed ? Draw.unloadedAlpha.value : 1 }
        if renaming, row.kind != .split { showRenameField(palette: palette) } else { retire() }
        stateChanged()
        needsLayout = true
    }

    private func configureButton(tab: TabRow, palette: Palette) {
        // A window's own tabs (blank and incognito windows) archive like Today's.
        let today = section == .today || section == .scratch
        button.isHidden = !today && !tab.loaded
        button.toolTip = today ? Copy.archiveTabTooltip : SidebarCopy.closeKeepPinned
        // Arc draws × on Pinned rows too; there it unloads the tab and keeps it pinned.
        button.render(.archiveTab, size: Draw.smallFont.value, palette: palette,
                      radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
    }

    private func setSegments(_ panes: [TabRow], palette: Palette) {
        while segments.count < panes.count {
            let segment = SplitSegmentView(dispatch: dispatch)
            segments.append(segment)
            addSubview(segment)
        }
        while segments.count > panes.count { segments.removeLast().removeFromSuperview() }
        for (segment, pane) in zip(segments, panes) { segment.render(pane, palette: palette) }
        title.isHidden = !panes.isEmpty
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: depth)
        background.frame = g.selection
        icon.frame = g.icon
        button.frame = g.button
        audio.frame = g.button.offsetBy(dx: -g.button.width, dy: 0)
        media.frame = audio.frame.offsetBy(dx: -audio.frame.width, dy: 0)
        let height = title.intrinsicContentSize.height
        peekMarker.frame = g.button
        // The hover button takes room from the title only while it shows (Arc truncates at the selection's end).
        let buttonShown = !button.isHidden && button.alphaValue > 0
        let trailing = !peekMarker.isHidden ? g.button.minX : !media.isHidden ? media.frame.minX : !audio.isHidden ? audio.frame.minX
            : buttonShown ? g.button.minX : g.selection.maxX - Draw.titleTrailing.value
        title.frame = g.title(height: height, trailing: trailing, in: bounds)
        renameField?.frame = g.title(height: height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: bounds)
        layoutSegments(g)
    }

    /// Arc's split row: each pane a box inside the row's selection (Draw.splitSegment*), side by side with a gap,
    /// after the custom split icon when there is one. Boxes too narrow for a title show only the icon.
    private func layoutSegments(_ g: RowGeometry) {
        guard !segments.isEmpty else { return }
        let inset = Draw.splitSegmentInset.value, gap = Draw.splitSegmentGap.value
        let start = splitIcon ? g.icon.maxX + inset : g.selection.minX + inset
        let end = g.selection.maxX - inset
        let width = (end - start - gap * Double(segments.count - 1)) / Double(segments.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, segment) in segments.enumerated() {
            segment.frame = CGRect(x: start + Double(i) * (width + gap), y: g.selection.minY + inset,
                                   width: max(0, width), height: max(0, g.selection.height - 2 * inset))
            segment.showsTitle = width >= Draw.splitSegmentTitleMinWidth.value
        }
        CATransaction.commit()
    }

    override func stateChanged() {
        guard let palette, let row else { return }
        let hovered = isHovered && !isEditingName && !isPressed
        if hovered != reportedHover { reportedHover = hovered; onHover?(self, hovered) }
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
        // AppKit owns a layer-backed view's shadow (`NSView.shadow`); its offset is not flipped, so negative is down.
        if status == .current && !dropInto {
            let shadow = NSShadow()
            shadow.shadowColor = palette.color(tokens.tabShadow)
            shadow.shadowBlurRadius = Draw.selectedShadowRadius.value
            shadow.shadowOffset = CGSize(width: 0, height: -Draw.selectedShadowOffset.value)
            background.shadow = shadow
        } else {
            background.shadow = nil
        }
        let shown = isHovered && !isEditingName
        if (button.alphaValue > 0) != shown { needsLayout = true }
        button.alphaValue = shown ? 1 : 0
    }

    // MARK: Pointer

    override func mouseDown(with event: NSEvent) {
        guard let row else { return }
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        if event.modifierFlags.contains(.shift) { onRangeSelect?(row.id); return }
        if event.modifierFlags.contains(.command) {
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
        guard let row, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), bounds.contains(local(event)) else { return }
        onSelect?(row.id)
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
        let targets = closeTargets?(row.id) ?? [row.id]
        dispatch(.sidebar(.popupMenu(targets.count > 1 ? .selection(targets) : .item(row.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }

    @objc private func toggleMute() { if let row { dispatch(.tabTools(.mute(.item(row.id)))) } }

    private func closeTapped() {
        guard let row else { return }
        dispatch(.tabTools(.bulk(.items(closeTargets?(row.id) ?? [row.id]), .close)))
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
        if reportedHover { reportedHover = false; onHover?(self, false) }
        guard let field = renameField else { return }
        field.retire()
        renameField = nil
        title.isHidden = !segments.isEmpty
    }
}

/// One pane inside a split row (Arc 1.170): a TabCellBackgroundChild box with the pane's favicon and title (the
/// icon alone when the box is narrow); hovering shows its own × (Arc: per-child close). Clicks go to the row (the
/// pane under the pointer gets focus).
@MainActor
final class SplitSegmentView: HoverView {
    var showsTitle = true { didSet { if showsTitle != oldValue { title.isHidden = !showsTitle; needsLayout = true } } }
    private let dispatch: Dispatch
    private(set) var pane: TabRow?
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private lazy var media = MediaRowControls(dispatch: dispatch)
    private let audio = GlyphButton()
    private let close = GlyphButton()
    private var palette: Palette?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Draw.splitSegmentRadius.value
        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
        title.isSelectable = false
        audio.action = { [weak self] _ in self?.toggleMute() }
        for view in [icon, title, audio, media, close] as [NSView] { addSubview(view) }
        close.action = { [weak self] _ in
            guard let id = self?.pane?.id else { return }
            dispatch(.split(.closePaneAt(id)))
        }
        close.toolTip = Copy.archiveTabTooltip
    }

    func render(_ pane: TabRow, palette: Palette) {
        self.pane = pane
        media.render(pane)
        identify(.splitSegment(pane.id))
        self.palette = palette
        audio.isHidden = !pane.audible && !pane.muted
        audio.render(pane.muted ? .speakerMuted : .speaker, size: Draw.smallFont.value, palette: palette,
                     radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
        audio.toolTip = pane.muted ? "Unmute Tab" : "Mute Tab"
        audio.identify(.tabTool("audio-" + pane.id.rawValue))
        title.stringValue = pane.title
        title.textColor = palette.ink.text
        icon.render(IconContent(tab: pane), tint: palette.ink.secondary, palette: palette)
        close.render(.archiveTab, size: Draw.smallFont.value, palette: palette, radius: Metrics.tablist.hoverButtonRadius.value,
                     hoverFill: palette.tokens.itemHover)
        close.identify(.rowClose(pane.id))
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let t = Metrics.tablist
        let side = t.favicon.value, size = min(2 * t.hoverButtonRadius.value, bounds.width / 3, bounds.height)
        let iconX = showsTitle ? Draw.splitSegmentIconLeading.value : max(0, min(Draw.splitSegmentIconLeading.value, (bounds.width - side) / 2))
        icon.frame = CGRect(x: iconX, y: (bounds.height - side) / 2, width: side, height: side)
        close.frame = CGRect(x: bounds.width - size, y: (bounds.height - size) / 2, width: size, height: size)
        audio.frame = close.frame.offsetBy(dx: -size, dy: 0)
        media.frame = audio.frame.offsetBy(dx: -audio.frame.width, dy: 0)
        let height = title.intrinsicContentSize.height
        let start = Draw.splitSegmentTitleLeading.value
        let end = !media.isHidden ? media.frame.minX : !audio.isHidden ? audio.frame.minX : close.alphaValue > 0 ? close.frame.minX : bounds.width - Draw.faviconLeading.value / 2
        title.frame = CGRect(x: start, y: (bounds.height - height) / 2, width: max(0, end - start), height: height)
    }

    @objc private func toggleMute() { if let pane { dispatch(.tabTools(.mute(.item(pane.id)))) } }

    override func stateChanged() {
        guard let palette else { return }
        layer?.backgroundColor = palette.color(isHovered ? palette.tokens.itemHover : palette.tokens.tabChild).cgColor
        close.alphaValue = isHovered && showsTitle ? 1 : 0
        needsLayout = true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let pane else { return }
        dispatch(.sidebar(.popupMenu(.item(pane.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }
}

/// Arc's Peek marker at the trailing end of the row a Peek was opened from: the peeked page's icon in a
/// TabCellBackgroundChild box the size of the row's hover button.
@MainActor
final class PeekMarkerView: NSView {
    private let icon = IconView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        addSubview(icon)
        setAccessibilityLabel("Peek")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(favicon: URL?, palette: Palette) {
        layer?.backgroundColor = palette.color(palette.tokens.tabChild).cgColor
        icon.render(.favicon(favicon), tint: palette.ink.secondary)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        let side = Draw.peekMarkerIcon.value
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
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
    /// Arc shows Clear whenever the pointer is over the sidebar, not only over the divider.
    var sidebarHovered = false { didSet { if sidebarHovered != oldValue { stateChanged() } } }

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
        let inset = Draw.dividerInset.value
        let size = clear.fittingSize
        clear.frame = CGRect(x: bounds.width - Draw.clearTrailing.value - size.width, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        let end = clear.alphaValue > 0 && !clear.isHidden ? clear.frame.minX - Draw.clearGap.value : bounds.width - inset
        let hairline = Draw.hairline.value
        line.frame = CGRect(x: inset, y: (bounds.height - hairline) / 2, width: max(0, end - inset), height: hairline)
    }

    override func stateChanged() {
        clear.alphaValue = canClear && (sidebarHovered || isHovered || clear.isHovered) ? 1 : 0
        needsLayout = true
    }
}

/// "Clear": the word in the sidebar foreground, stronger on hover.
@MainActor
final class ClearButton: HoverView {
    private let label = NSTextField(labelWithString: Copy.clearToday)
    private let action: () -> Void
    private var palette: Palette?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.captionFont.value, weight: .semibold)
        label.isSelectable = false
        addSubview(label)
    }

    override var fittingSize: NSSize { label.intrinsicContentSize }

    func render(palette: Palette) {
        self.palette = palette
        stateChanged()
    }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func stateChanged() {
        guard let palette else { return }
        label.textColor = palette.color(isHovered ? palette.tokens.foregroundStrong : palette.tokens.foreground)
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

    private var current = false

    /// `current` draws the row like the current tab (white, shadowed) with the text in the row ink.
    func render(palette: Palette, current: Bool = false) {
        guard palette != self.palette || current != self.current else { return }
        self.palette = palette
        self.current = current
        let color = current ? palette.ink.text : palette.color(palette.tokens.foreground)
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
        let tokens = palette.tokens
        let fill = current ? tokens.tabCurrent : isPressed ? tokens.tabPressed : isHovered ? tokens.itemHover : nil
        background.layer?.backgroundColor = fill.map { palette.color($0).cgColor }
        background.layer?.shadowColor = palette.color(tokens.tabShadow).cgColor
        background.layer?.shadowOpacity = current ? 1 : 0
        background.layer?.shadowRadius = Draw.selectedShadowRadius.value
        background.layer?.shadowOffset = CGSize(width: 0, height: -Draw.selectedShadowOffset.value)
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { dispatch(.commandBar(.open(.newTab))) }
    }
}

/// The space header above the list (Arc: `pinnedTabsHeader`): the space's icon and name, 14 pt medium in the
/// secondary color. Hovered (and while Pinned is collapsed) the row becomes a pill in the URL pill's fill with the
/// collapse chevron in the icon slot (down while expanded, right while collapsed) and a "…" button at the right that
/// opens the space's menu. A click collapses or expands Pinned; right-click is the space's menu.
@MainActor
final class SpaceHeaderView: HoverView {
    private let dispatch: Dispatch
    private let background = NSView()
    private let icon = IconView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let more = GlyphButton()
    private var space: SpaceSnapshot?
    private var palette: Palette?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        background.wantsLayer = true
        background.layer?.cornerCurve = .continuous
        background.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        label.font = .systemFont(ofSize: Draw.spaceHeaderFont.value, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        more.action = { [weak self] _ in self?.showMenu() }
        more.toolTip = SidebarCopy.spaceOptions
        for view in [background, icon, label, chevron, more] as [NSView] { addSubview(view) }
    }

    /// False for a blank window's "This Window" header: no Pinned to collapse, no space menu.
    private var interactive = true

    func render(_ space: SpaceSnapshot, palette: Palette, interactive: Bool = true) {
        if space == self.space, palette == self.palette, interactive == self.interactive { return }
        self.space = space
        self.palette = palette
        self.interactive = interactive
        let color = palette.color(palette.tokens.foregroundStrong)
        label.stringValue = space.title
        label.textColor = color
        icon.render(IconContent(space: space.icon, color: RGBA(0, 0, 0, 0)), tint: color)
        chevron.image = (space.pinned.collapsed ? Glyph.chevronRight : Glyph.chevronDown).image(size: Draw.spaceChevron.value, weight: .semibold)
        chevron.contentTintColor = palette.ink.secondary
        more.render(.more, size: Draw.navGlyph.value, palette: palette, radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
        toolTip = space.pinned.collapsed ? SidebarCopy.expandPinned : SidebarCopy.collapsePinned
        stateChanged()
        needsLayout = true
    }

    /// Pill, chevron and "…" show while hovered and while Pinned is collapsed (never on a blank window's header).
    private var expanded: Bool { interactive && (isHovered || space?.pinned.collapsed == true) }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: 0)
        background.frame = CGRect(x: g.selection.minX, y: 0, width: g.selection.width, height: bounds.height)
        icon.frame = g.icon
        let size = Draw.spaceChevron.value + 2
        chevron.frame = CGRect(x: g.icon.midX - size / 2, y: (bounds.height - size) / 2, width: size, height: size)
        more.frame = g.button
        let hasIcon = space?.icon != SpaceIcon.none
        let start = expanded || hasIcon ? g.titleX : g.selection.minX + Draw.spaceHeaderLeading.value
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: start, y: (bounds.height - height) / 2, width: max(0, (expanded ? more.frame.minX : g.selection.maxX) - start), height: height)
    }

    override func stateChanged() {
        guard let palette else { return }
        let shown = expanded
        background.layer?.backgroundColor = shown ? palette.color(isPressed ? palette.tokens.tabPressed : palette.tokens.itemBackground).cgColor : nil
        chevron.isHidden = !shown
        more.isHidden = !shown
        icon.isHidden = shown || space?.icon == SpaceIcon.none
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) { if interactive { isPressed = true } }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if interactive, bounds.contains(local(event)) { dispatch(.space(.togglePinnedSection(.current))) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard interactive, let space else { return }
        dispatch(.sidebar(.popupMenu(.spaceControls(space.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }

    private func showMenu() {
        guard let space else { return }
        dispatch(.sidebar(.popupMenu(.spaceControls(space.id), at: rootPoint(of: CGPoint(x: more.frame.minX, y: more.frame.maxY)))))
    }
}
