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
    private let education: ArchiveEducationView
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
    /// The split preview over a row (DragController) and the row it covers.
    private var splitJoin: SplitJoinPreview?
    private var splitJoinTarget: ItemID?
    private var contentBottom = 0.0
    /// The pointer is over the sidebar: Today's Clear shows (Arc).
    var sidebarHovered = false { didSet { divider.sidebarHovered = sidebarHovered } }
    private lazy var folderPreview = FolderPreview(dispatch: dispatch)
    /// Open Live Folders without rows: their one-line note, by folder.
    private var livePlaceholders: [ItemID: LivePlaceholderView] = [:]
    private var now = Instant(milliseconds: 0)

    init(dispatch: @escaping Dispatch, drag: DragController) {
        self.dispatch = dispatch
        self.drag = drag
        divider = DividerRowView(dispatch: dispatch)
        education = ArchiveEducationView(dispatch: dispatch)
        newTab = NewTabRowView(dispatch: dispatch)
        super.init(frame: .zero)
        document.onKey = { [weak self] command in self?.dispatch(.tabTools(command)) }
        document.onRightClick = { [weak self] event in self?.spaceMenu(event) }
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
        addSubview(education)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Arc opens the space's menu for a right-click on the list's empty area too (P12-g).
    override func rightMouseDown(with event: NSEvent) { spaceMenu(event) }

    private func spaceMenu(_ event: NSEvent) {
        guard let space = last?.space, space.today.kind != .scratch else { return }
        dispatch(.sidebar(.popupMenu(.spaceControls(space.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }

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
        // While New Tab is the current row the tab on screen draws like any other (Arc, Q01-a: one white card).
        let space = newTabCurrent ? space.idlingCurrent : space
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
            case .livePlaceholder(let id) where rows[id]?.section == .pinned: pinnedRect = pinnedRect?.union(frame.rect) ?? frame.rect
            case .item, .divider, .newTab, .livePlaceholder: todayRect = todayRect?.union(frame.rect) ?? frame.rect
            }
        }
        pinnedSection.frame = pinnedRect ?? CGRect(x: 0, y: spacer.maxY, width: width, height: 0)
        todaySection.frame = todayRect ?? CGRect(x: 0, y: spacer.maxY, width: width, height: 0)
        contentBottom = Double(f.rows.last?.rect.maxY ?? 0)
        education.isHidden = tools.archiveEducation == nil
        education.render(tools.archiveEducation, palette: palette)
        // Arc's banners are cards at the bottom of the sidebar, under the list, not in it: the rows scroll clear of it.
        if tools.archiveEducation != nil {
            let margin = Draw.educationMargin.value, cardWidth = max(0, width - 2 * margin)
            let height = education.height(forWidth: cardWidth)
            education.frame = NSRect(x: margin, y: isFlipped ? f.tablistViewport.height - margin - height : margin, width: cardWidth, height: height)
            contentBottom += height + 2 * margin
        }
        document.frame = CGRect(x: 0, y: 0, width: width, height: max(contentBottom, f.tablistViewport.height))

        multiselection.removeAll { rows[$0] == nil }
        divider.isHidden = !f.rows.contains { $0.kind == .divider }
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
                divider.render(canClear: space.today.kind == .today && !space.today.rows.isEmpty, canTidy: space.today.canTidy,
                               tidying: space.today.tidying, palette: palette)
            case .newTab:
                newTab.frame = frame.rect.offsetBy(dx: -todaySection.frame.minX, dy: -todaySection.frame.minY)
                newTab.render(palette: palette, current: newTabCurrent)
            case .livePlaceholder(let id):
                guard case .folder(let folder)? = rows[id]?.row, let live = folder.live else { continue }
                seen.insert(LivePlaceholderView.key(id))
                let container = rows[id]?.section == .pinned ? pinnedSection : todaySection
                let view = livePlaceholders[id] ?? {
                    let made = LivePlaceholderView(dispatch: dispatch)
                    livePlaceholders[id] = made
                    return made
                }()
                if view.superview !== container { container.addSubview(view) }
                view.frame = frame.rect.offsetBy(dx: -container.frame.minX, dy: -container.frame.minY)
                view.render(folder: id, live: live, depth: frame.depth, palette: palette)
            case .topSpacer:
                break
            }
        }
        for (id, view) in livePlaceholders where !seen.contains(LivePlaceholderView.key(id)) {
            view.removeFromSuperview()
            livePlaceholders[id] = nil
        }
        folderPreview.validate { id in
            switch rows[id]?.row {
            case .folder(let folder)?: folder.collapsed
            case .tab(let tab)?: tab.hoverCard != nil
            default: false
            }
        }
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

    /// Arc Previews: a collapsed folder shows its pages beside the sidebar, a supported Pinned tab its site's card
    /// (a calendar's meetings, Linear, Notion or Figma's recent pages); other tabs and open folders show nothing.
    private func rowHovered(_ view: RowView, _ hovered: Bool) {
        guard hovered, tools?.hoverPreviews == true, !view.isEditingName, let palette = last?.palette else {
            folderPreview.pointerLeft(view)
            return
        }
        switch view.row {
        case .folder(let folder)? where folder.collapsed: folderPreview.hover(folder, over: view, now: now, palette: palette)
        case .tab(let tab)?: if let card = tab.hoverCard { folderPreview.hover(tab: tab, card: card, over: view, now: now) } else { folderPreview.pointerLeft(view) }
        default: folderPreview.pointerLeft(view)
        }
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

    /// Arc's split preview in place of `target`'s row while `dragged` is held on its middle (P23-e); the row under it
    /// is hidden meanwhile. Nil clears it. The capsule follows the pointer sideways by `shift` (Arc's sits 7 pt right
    /// of the row in P23-e), as far as the list's side insets, so it never leaves the list.
    func showSplitJoin(_ target: ItemID?, dragged: TabRow?, shift: Double = 0, frames f: SidebarFrames, space: SpaceSnapshot, palette: Palette?) {
        if splitJoinTarget != target, let old = splitJoinTarget { rowViews[old]?.alphaValue = 1 }
        splitJoinTarget = nil
        guard let target, let dragged, let palette, let frame = f.rows.first(where: { $0.kind == .item(target) }),
              case .tab(let row)? = Self.find(target, in: space.pinned.rows + space.today.rows) else {
            splitJoin?.isHidden = true
            return
        }
        let preview = splitJoin ?? {
            let made = SplitJoinPreview(frame: .zero)
            document.addSubview(made)
            splitJoin = made
            return made
        }()
        let inset = Metrics.tablist.selectionInset.value
        preview.frame = frame.rect.offsetBy(dx: min(inset, max(-inset, shift)).rounded(), dy: 0)
        preview.render(dragged: dragged, onto: row, depth: frame.depth, palette: palette)
        preview.layoutSubtreeIfNeeded()
        preview.isHidden = false
        splitJoinTarget = target
        rowViews[target]?.alphaValue = 0
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
    /// Focused only on request (Reveal, `focusList`). As a key view AppKit made it the first responder of a window
    /// that became key before its page existed (a restart into a Space whose profile loads first), and the page
    /// that arrived later never took focus from it.
    override var canBecomeKeyView: Bool { false }
    var onKey: ((TabToolsCommand) -> Void)?
    /// A right-click that no row took (the sections' gaps and the space below the last row).
    var onRightClick: ((NSEvent) -> Void)?
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
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
    /// A Live Folder refreshing: a small spinner where the hover button goes.
    private let spinner = NSProgressIndicator()
    /// A Live Folder whose last refresh failed: a warning mark (its tooltip says why).
    private let liveMark = NSImageView()
    private var renameField: RenameField?
    /// A split row with a custom icon starts its panes after the icon; without one they start in the icon slot.
    private var splitIcon = false
    var multiselected = false { didSet { if multiselected != oldValue { stateChanged() } } }
    var dropInto = false { didSet { if dropInto != oldValue { stateChanged() } } }
    var dragSource = false { didSet { alphaValue = dragSource ? Draw.dragSourceAlpha.value : 1 } }
    /// The row a tab drag left while the pointer is over the content: Arc keeps it in place on the selected-row card
    /// with its × showing (P23-d), and the white drag card follows the pointer instead.
    var dragLifted = false { didSet { if dragLifted != oldValue { stateChanged() } } }
    /// Whether this row has a hover × at all (Today tabs, loaded Pinned tabs).
    private var hasButton = false
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
        for view in [background, icon, title, audio, media, button, peekMarker, spinner, liveMark] as [NSView] { addSubview(view) }
        peekMarker.isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        liveMark.isHidden = true
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
        renderLive(row, palette: palette)
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
        case .folder(let folder) where folder.group:
            // Arc's `TabGroupHeaderCellView`: the group's title over its tabs, no folder glyph, and a × that closes
            // the group while the pointer is on the header.
            title.stringValue = folder.title
            title.font = .systemFont(ofSize: Draw.groupTitleFont.value, weight: .semibold)
            icon.render(.none, tint: palette.ink.secondary)
            hasButton = true
            button.isHidden = false
            button.toolTip = SidebarCopy.closeTabGroup
            button.render(.archiveTab, size: Draw.smallFont.value, palette: palette,
                          radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
            setSegments([], palette: palette)
            peekMarker.isHidden = true
        case .folder(let folder):
            title.stringValue = folder.title
            title.font = .systemFont(ofSize: Draw.rowTitleFont.value, weight: .semibold)
            icon.render(folder.icon.map(IconContent.custom) ?? .folder(open: !folder.collapsed), tint: palette.ink.secondary, palette: palette)
            // A Live Folder's hover button refreshes it (none while it is already refreshing).
            hasButton = folder.live != nil && folder.live?.state != .loading
            button.isHidden = !hasButton
            if folder.live != nil {
                button.toolTip = SidebarCopy.refreshLiveFolder
                button.render(.reload, size: Draw.smallFont.value, palette: palette,
                              radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
            }
            setSegments([], palette: palette)
            peekMarker.isHidden = true
        case .split(let split):
            title.stringValue = ""
            icon.render(split.icon.map(IconContent.custom) ?? .none, tint: palette.ink.secondary)
            splitIcon = split.icon != nil
            hasButton = false
            button.isHidden = true
            setSegments(split.panes, palette: palette)
            peekMarker.isHidden = true
        }
        if case .folder(let folder) = row, folder.group { title.textColor = palette.ink.secondary } else { title.textColor = palette.ink.text }
        for view in [icon, title] as [NSView] { view.alphaValue = dimmed ? Draw.unloadedAlpha.value : 1 }
        if renaming, row.kind != .split { showRenameField(palette: palette) } else { retire() }
        stateChanged()
        needsLayout = true
    }

    private func renderLive(_ row: Row, palette: Palette) {
        let live: LiveFolderSnapshot? = if case .folder(let folder) = row { folder.live } else { nil }
        let id = row.id.rawValue
        spinner.identifier = NSUserInterfaceItemIdentifier("live-folder-spinner-" + id)
        spinner.setAccessibilityIdentifier("live-folder-spinner-" + id)
        liveMark.identifier = NSUserInterfaceItemIdentifier("live-folder-failed-" + id)
        liveMark.setAccessibilityIdentifier("live-folder-failed-" + id)
        if live?.state == .loading { spinner.isHidden = false; spinner.startAnimation(nil) } else { spinner.stopAnimation(nil); spinner.isHidden = true }
        if case .failed(let message)? = live?.state {
            liveMark.isHidden = false
            liveMark.image = Glyph.warning.image(size: Draw.smallFont.value)
            liveMark.contentTintColor = NSColor.systemOrange
            liveMark.toolTip = message
            liveMark.setAccessibilityLabel(message)
        } else { liveMark.isHidden = true }
        toolTip = live.map { SidebarCopy.liveFolderTip($0) }
    }

    private func configureButton(tab: TabRow, palette: Palette) {
        // A window's own tabs (blank and incognito windows) archive like Today's.
        let today = section == .today || section == .scratch
        hasButton = today || tab.loaded
        button.isHidden = !hasButton && !dragLifted
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
        spinner.frame = g.button.insetBy(dx: (g.button.width - 16) / 2, dy: (g.button.height - 16) / 2)
        liveMark.frame = (button.alphaValue > 0 && !button.isHidden ? g.button.offsetBy(dx: -g.button.width, dy: 0) : g.button)
        // The hover button takes room from the title only while it shows (Arc truncates at the selection's end).
        let buttonShown = !button.isHidden && button.alphaValue > 0
        let trailing = !spinner.isHidden ? spinner.frame.minX : !liveMark.isHidden ? liveMark.frame.minX
            : !peekMarker.isHidden ? g.button.minX : !media.isHidden ? media.frame.minX : !audio.isHidden ? audio.frame.minX
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
        else if dragLifted || status == .current { fill = tokens.tabCurrent }
        else if status == .visible { fill = tokens.tabVisible }
        else if isPressed { fill = tokens.tabPressed }
        else if multiselected || isHovered { fill = tokens.itemHover }
        else { fill = nil }
        let layer = background.layer
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
        layer?.borderColor = palette.color(tokens.dragHintStrong).cgColor
        layer?.borderWidth = dropInto ? Draw.hairline.value : 0
        // AppKit owns a layer-backed view's shadow (`NSView.shadow`); its offset is not flipped, so negative is down.
        // A lifted row keeps the current tab's shadow (Arc's lifted Inbox, P23-e); a lifted other row has none (P23-d).
        if status == .current && !dropInto {
            let shadow = NSShadow()
            shadow.shadowColor = palette.color(tokens.tabShadow)
            shadow.shadowBlurRadius = Draw.selectedShadowRadius.value
            shadow.shadowOffset = CGSize(width: 0, height: -Draw.selectedShadowOffset.value)
            background.shadow = shadow
        } else {
            background.shadow = nil
        }
        if case .tab = row { button.isHidden = !hasButton && !dragLifted }
        let shown = (isHovered || dragLifted) && !isEditingName
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
        if reportedHover { reportedHover = false; onHover?(self, false) }   // a menu closes the folder preview
        let targets = closeTargets?(row.id) ?? [row.id]
        dispatch(.sidebar(.popupMenu(targets.count > 1 ? .selection(targets) : .item(row.id), at: rootPoint(fromWindow: event.locationInWindow))))
    }

    @objc private func toggleMute() { if let row { dispatch(.tabTools(.mute(.item(row.id)))) } }

    private func closeTapped() {
        guard let row else { return }
        if case .folder(let folder) = row, folder.group { dispatch(.tabTools(.closeGroup(folder.id))); return }
        if case .folder(let folder) = row, folder.live != nil { dispatch(.tabTools(.site(.refreshFolder(folder.id)))); return }
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
    /// Max's Tidy Tabs (P46-b): 🧹 Tidy left of Clear while the pointer is on the divider and Today has more than six
    /// tabs, a bar between them.
    private let tidy: TidyButton
    private let tidyBar = NSView()
    private var palette: Palette?
    private var canClear = false
    private var canTidy = false, tidying = false
    /// Arc shows Clear whenever the pointer is over the sidebar, not only over the divider.
    var sidebarHovered = false { didSet { if sidebarHovered != oldValue { stateChanged() } } }

    init(dispatch: @escaping Dispatch) {
        clear = ClearButton { dispatch(.tab(.clearToday)) }
        tidy = TidyButton { dispatch(.assist(.organizeToday)) }
        super.init(frame: .zero)
        line.wantsLayer = true
        tidyBar.wantsLayer = true
        addSubview(line)
        addSubview(clear)
        addSubview(tidyBar)
        addSubview(tidy)
        clear.identify(.todayClear)
        tidy.identify(.todayTidy)
    }

    func render(canClear: Bool, canTidy: Bool = false, tidying: Bool = false, palette: Palette) {
        self.palette = palette
        self.canClear = canClear
        self.canTidy = canTidy
        self.tidying = tidying
        line.layer?.backgroundColor = palette.color(palette.tokens.separator).cgColor
        tidyBar.layer?.backgroundColor = palette.color(palette.tokens.separator).cgColor
        clear.render(palette: palette)
        tidy.render(palette: palette, busy: tidying)
        clear.isHidden = !canClear
        tidy.isHidden = !canTidy
        stateChanged()
    }

    override func layout() {
        super.layout()
        let inset = Draw.dividerInset.value
        let size = clear.fittingSize
        // The word ends `clearTrailing` before the sidebar's edge; the label's cell draws it 2 in from the frame.
        let textStart = ((bounds.width - Draw.clearTrailing.value - clear.textWidth) * 2).rounded() / 2
        clear.frame = CGRect(x: textStart - ClearButton.cellInset, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        var end = clear.alphaValue > 0 && !clear.isHidden ? textStart - Draw.clearGap.value : bounds.width - inset
        // Tidy keeps its place while it is invisible too, so the pointer finds it where it appears.
        let gaps = Draw.tidyGaps.value, hairline = Draw.hairline.value, barHeight = Draw.tidySeparatorHeight.value
        let right = clear.isHidden ? bounds.width - Draw.clearTrailing.value : textStart - gaps[3]
        tidyBar.frame = CGRect(x: right - hairline, y: (bounds.height - barHeight) / 2, width: hairline, height: barHeight)
        let tidySize = tidy.fittingSize
        tidy.frame = CGRect(x: (clear.isHidden ? right : tidyBar.frame.minX - gaps[2]) - tidySize.width, y: (bounds.height - tidySize.height) / 2,
                            width: tidySize.width, height: tidySize.height)
        let tidyShown = tidy.alphaValue > 0 && !tidy.isHidden
        tidyBar.isHidden = !tidyShown || clear.isHidden
        if tidyShown { end = tidy.frame.minX - gaps[0] }
        line.frame = CGRect(x: inset, y: (bounds.height - hairline) / 2, width: max(0, end - inset), height: hairline)
    }

    override func stateChanged() {
        clear.alphaValue = canClear && (sidebarHovered || isHovered || clear.isHovered || tidy.isHovered) ? 1 : 0
        tidy.alphaValue = canTidy && (isHovered || clear.isHovered || tidy.isHovered || tidying) ? 1 : 0
        needsLayout = true
    }
}

/// "🧹 Tidy" (Arc's SidebarTidyButton): the broom and the word in Clear's colours, the tooltip "Organize Today Tabs".
/// While Max makes the plan it dims and takes no click.
@MainActor
final class TidyButton: HoverView {
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: AICopy.tidy)
    private let action: () -> Void
    private var palette: Palette?
    private var busy = false

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.captionFont.value, weight: .semibold)
        label.isSelectable = false
        glyph.imageScaling = .scaleProportionallyUpOrDown
        addSubview(glyph)
        addSubview(label)
        toolTip = AICopy.tidyTooltip
    }

    override var fittingSize: NSSize {
        let g = Draw.tidyGlyph.value, text = label.intrinsicContentSize
        return NSSize(width: g[1] + Draw.tidyGaps.value[1] - (g[1] - g[0]) / 2 + text.width, height: max(g[1], text.height))
    }

    func render(palette: Palette, busy: Bool) {
        self.palette = palette
        self.busy = busy
        stateChanged()
    }

    override func layout() {
        super.layout()
        let g = Draw.tidyGlyph.value, text = label.intrinsicContentSize
        // The broom is drawn in a square; its strokes take the middle 7 of its 11.5 points.
        glyph.frame = CGRect(x: -(g[1] - g[0]) / 2, y: (bounds.height - g[1]) / 2, width: g[1], height: g[1])
        label.frame = CGRect(x: bounds.width - text.width, y: (bounds.height - text.height) / 2, width: text.width, height: text.height)
    }

    override func stateChanged() {
        guard let palette else { return }
        let color = palette.color(isHovered && !busy ? palette.tokens.foregroundStrong : palette.tokens.foreground)
        label.textColor = color
        glyph.image = ArcGlyphs.broom(size: Draw.tidyGlyph.value[1])
        glyph.contentTintColor = color
        for view in [glyph, label] as [NSView] { view.alphaValue = busy ? Draw.unloadedAlpha.value : 1 }
        (superview as? HoverView)?.stateChanged()
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if !busy, bounds.contains(local(event)) { action() }
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
        label.font = .systemFont(ofSize: Draw.clearFont.value, weight: .semibold)
        label.isSelectable = false
        addSubview(label)
    }

    /// The label's cell, not its intrinsic size, which cut the last letter (P02-clear-user-brk.png).
    override var fittingSize: NSSize { NSSize(width: label.cellWidth, height: label.intrinsicContentSize.height) }

    static let cellInset = 2.0
    var textWidth: Double { label.attributedStringValue.size().width }

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
        label.lineBreakMode = .byTruncatingTail
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
        label.font = .systemFont(ofSize: Draw.spaceHeaderFont.value, weight: .semibold)
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

/// The note inside an open Live Folder that has no rows (A092): "Loading pull requests…", "No open pull requests",
/// the failure with Try Again, or a not-yet-refreshed folder's Refresh. A click refreshes, except while loading.
@MainActor
final class LivePlaceholderView: HoverView {
    private let dispatch: Dispatch
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var folder: ItemID?
    private var live: LiveFolderSnapshot?
    private var depth = 0
    private var palette: Palette?

    static func key(_ folder: ItemID) -> ItemID { ItemID("live-placeholder-" + folder.rawValue) }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        label.font = .systemFont(ofSize: Draw.smallFont.value)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        for view in [label, spinner] as [NSView] { addSubview(view) }
    }

    func render(folder: ItemID, live: LiveFolderSnapshot, depth: Int, palette: Palette) {
        self.folder = folder
        self.live = live
        self.depth = depth
        self.palette = palette
        identifier = NSUserInterfaceItemIdentifier("live-folder-note-" + folder.rawValue)
        setAccessibilityIdentifier("live-folder-note-" + folder.rawValue)
        label.stringValue = SidebarCopy.liveFolderNote(live.state)
        label.textColor = palette.ink.secondary
        setAccessibilityLabel(label.stringValue)
        if live.state == .loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: depth)
        spinner.frame = g.icon.insetBy(dx: (g.icon.width - 14) / 2, dy: (g.icon.height - 14) / 2)
        let height = label.intrinsicContentSize.height
        label.frame = g.title(height: height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: bounds)
    }

    override func stateChanged() {
        guard let palette else { return }
        let clickable = live?.state != .loading
        layer?.backgroundColor = isHovered && clickable ? palette.color(palette.tokens.itemHover).cgColor : nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let folder, live?.state != .loading, bounds.contains(local(event)) else { return }
        dispatch(.tabTools(.site(.refreshFolder(folder))))
    }
}

/// Arc's auto-archive banner (`AutoArchiveEducationView`, its numbers in `SidebarDraw`): a card with a band ("We cleaned
/// up!" after the archive box), "Arc archives tabs that you haven’t used in the past 12 hours. You can adjust this in
/// Settings." (`bin:0x103a0cc20`) with Settings a link, and the filled "Got it". Both dismiss it for good (Arc's dismiss
/// reasons `settingsLearnMore`, `manual`); Settings also opens Settings → Profiles, where Archive tabs after lives.
@MainActor
final class ArchiveEducationView: NSView {
    private let card = FlippedView()
    private let band = FlippedView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: SidebarCopy.archiveEducationTitle)
    private let text = NSTextView()
    private let link = LinkHotspot()
    private let dismiss = EducationButton()
    private var shown: String?
    private var ink: NSColor?
    private var focus: NSColor?

    init(dispatch: @escaping Dispatch) {
        super.init(frame: .zero)
        wantsLayer = true
        // bin:0x10256cab0: a black shadow at 20%, radius 1, one point up (bin:0x1036baf68 holds 1, 0, -1).
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 1
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.cornerRadius = Draw.educationCorner.value
        card.layer?.masksToBounds = true
        band.wantsLayer = true
        icon.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: Draw.educationTitleFont.value, weight: .medium)
        title.font = .systemFont(ofSize: Draw.educationTitleFont.value, weight: .medium)
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = false
        addSubview(card)
        card.addSubview(band)
        band.addSubview(icon)
        band.addSubview(title)
        card.addSubview(text)
        card.addSubview(link)
        card.addSubview(dismiss)
        identify(.tabTool("education"))
        link.identify(.tabTool("education-settings"))
        dismiss.identify(.tabTool("education-dismiss"))
        dismiss.action = { dispatch(.tabTools(.dismissArchiveEducation)) }
        link.action = {
            dispatch(.tabTools(.dismissArchiveEducation))
            dispatch(.settings(.openPane(.profiles)))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ threshold: String?, palette: Palette) {
        let light = palette.scheme == .light
        // `backgroundExtra`, `focus` are Arc's palette fields (bin:0x10256ca3c, 0x10256e3e8): the card has no capture,
        // so the white card of the sidebar's current tab stands for the first; the second is the theme's dark shade.
        card.layer?.backgroundColor = palette.color(palette.tokens.tabCurrent).cgColor
        band.layer?.backgroundColor = NSColor(white: light ? 0 : 1, alpha: light ? 0.08 : 0.05).cgColor
        let titleInk = NSColor(white: light ? 0 : 1, alpha: 0.8)
        title.textColor = titleInk
        icon.contentTintColor = titleInk
        let fill = palette.focusColor
        dismiss.render(fill: fill)
        guard let threshold else { shown = nil; return }
        let sentence = Copy.archiveEducation(threshold)
        let message = NSColor(white: light ? 0 : 1, alpha: 0.5)
        guard sentence != shown || ink != message || focus != fill else { return }
        shown = sentence
        ink = message
        focus = fill
        let body = NSMutableAttributedString(string: sentence, attributes: [.font: NSFont.systemFont(ofSize: Draw.educationMessageFont.value), .foregroundColor: message])
        let range = (sentence as NSString).range(of: Copy.archiveEducationLink, options: .backwards)
        // bin:0x10256eb4c: the link's run is medium; bin:0x10256ec0c: white when dark, else the palette's focus.
        body.addAttributes([.font: NSFont.systemFont(ofSize: Draw.educationMessageFont.value, weight: .medium), .foregroundColor: light ? fill : NSColor.white], range: range)
        text.textStorage?.setAttributedString(body)
        needsLayout = true
    }

    private var bandHeight: CGFloat { 2 * Draw.educationPadding.value + ceil(title.intrinsicContentSize.height) }
    private func messageHeight(forWidth width: CGFloat) -> CGFloat {
        guard let manager = text.layoutManager, let container = text.textContainer else { return 0 }
        container.containerSize = CGSize(width: max(0, width - 2 * Draw.educationPadding.value), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    /// The band, the message under 12 pt, the button with 12 pt around it.
    func height(forWidth width: CGFloat) -> CGFloat {
        bandHeight + Draw.educationPadding.value + messageHeight(forWidth: width) + 2 * Draw.educationPadding.value + dismiss.height
    }

    override func layout() {
        super.layout()
        let padding = Draw.educationPadding.value, width = bounds.width
        card.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Draw.educationCorner.value, cornerHeight: Draw.educationCorner.value, transform: nil)
        band.frame = CGRect(x: 0, y: 0, width: width, height: bandHeight)
        let titleSize = title.intrinsicContentSize, iconSize = icon.intrinsicContentSize
        icon.frame = CGRect(x: padding, y: ((bandHeight - iconSize.height) / 2).rounded(), width: iconSize.width, height: iconSize.height)
        title.frame = CGRect(x: icon.frame.maxX + Draw.educationIconGap.value, y: ((bandHeight - titleSize.height) / 2).rounded(), width: max(0, width - icon.frame.maxX - Draw.educationIconGap.value - padding), height: titleSize.height)
        let height = messageHeight(forWidth: width)
        text.frame = CGRect(x: padding, y: band.frame.maxY + padding, width: max(0, width - 2 * padding), height: height)
        dismiss.frame = CGRect(x: padding, y: text.frame.maxY + padding, width: max(0, width - 2 * padding), height: dismiss.height)
        guard let manager = text.layoutManager, let container = text.textContainer, let sentence = shown else { return }
        let glyphs = manager.glyphRange(forCharacterRange: (sentence as NSString).range(of: Copy.archiveEducationLink, options: .backwards), actualCharacterRange: nil)
        link.frame = manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: text.frame.minX, dy: text.frame.minY)
    }
}

/// The banner's "Got it": white light text in the middle of a filled, rounded rectangle (bin 0x10256e028 to 0x10256e720).
@MainActor
final class EducationButton: HoverView {
    var action: () -> Void = {}
    private let label = NSTextField(labelWithString: SidebarCopy.archiveEducationDismiss)

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Draw.educationButtonCorner.value
        label.font = .systemFont(ofSize: Draw.educationButtonFont.value, weight: .light)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var height: CGFloat { 2 * Draw.educationButtonPadding.value + ceil(label.intrinsicContentSize.height) }
    func render(fill: NSColor) { layer?.backgroundColor = fill.cgColor }

    override func layout() {
        super.layout()
        let line = label.intrinsicContentSize.height
        label.frame = CGRect(x: 0, y: ((bounds.height - line) / 2).rounded(), width: bounds.width, height: line)
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { action() }
    }
}

/// A clickable spot over a word of a text (the banner's Settings): the pointing hand, a click runs `action`.
@MainActor
final class LinkHotspot: HoverView {
    var action: () -> Void = {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { action() }
    }
}

private extension SpaceSnapshot {
    /// The space with its current row, wherever it is, drawn idle.
    var idlingCurrent: SpaceSnapshot {
        var space = self
        space.pinned.rows = space.pinned.rows.map(\.idlingCurrent)
        space.today.rows = space.today.rows.map(\.idlingCurrent)
        return space
    }
}

private extension Row {
    var idlingCurrent: Row {
        switch self {
        case .tab(var tab):
            if tab.status == .current { tab.status = .idle }
            return .tab(tab)
        case .split(var split):
            if split.status == .current { split.status = .idle }
            return .split(split)
        case .folder(var folder):
            folder.children = folder.children.map(\.idlingCurrent)
            return .folder(folder)
        }
    }
}
