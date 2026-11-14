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
///
/// Only rows within one viewport above and below the visible part have views, as NSOutlineView keeps only the rows it
/// shows: a sidebar imported from Arc has hundreds of rows per Space, and every row view costs in each layout, tracking-area
/// and layer pass of the window, in a Space swipe (both neighbours render) and in a Space switch. Scrolling half a
/// viewport places the next rows.
@MainActor
final class TablistView: NSScrollView {
    /// Every scroll event of the list goes through the window, one at a time. With AppKit's responsive scrolling the
    /// scroll view tracks a whole gesture by itself and takes the next gestures before the window sees their first
    /// event (measured 2026-11-05), so the sidebar could never tell a Space swipe from a list scroll.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    private let dispatch: Dispatch
    private let drag: DragController
    private let document = ListDocumentView()
    private let pinnedSection = FlippedView()
    private let todaySection = FlippedView()
    private let divider: DividerRowView
    private let education: ArchiveEducationView
    private let newTab: NewTabRowView
    private let dropLine = DropLineView()
    private let topEdge = NSView()
    private let bottomEdge = NSView()
    /// The round button at the list's edge while the current row is scrolled out of view (Arc, Q18-media-q, -r).
    private let currentArrow = CurrentRowArrowView()
    private var currentRow: (id: ItemID, title: String)?
    private var rowViews: [ItemID: RowView] = [:]
    /// The last render's rows, what they draw and what lights them, for placing rows as the list scrolls.
    private var renderedRows: [ItemID: (row: Row, section: SectionKind)] = [:]
    private var renderedLit: Set<ItemID> = []
    /// Where the visible part of the list was when rows were last placed (document coordinates).
    private var placedAt: CGRect?
    private var splitJoinLeading: Bool?
    /// A render cache of the domain selection. Pointer gestures dispatch typed selection and bulk commands.
    private var multiselection: [ItemID] = []
    private var last: (space: SpaceSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette)?
    private var tools: TabToolsSnapshot?
    private var lastReveal: UInt64?
    private var dropFolder: ItemID?
    /// The row a held tab would join (DragController), and the band across it when it is a split.
    private var splitJoinTarget: ItemID?
    private let joinBand = NSView()
    private var contentBottom = 0.0
    /// The pointer is over the sidebar: Today's Clear shows (Arc).
    var sidebarHovered = false { didSet { divider.sidebarHovered = sidebarHovered } }
    private lazy var folderPreview = FolderPreview(dispatch: dispatch)
    /// Open Live Folders without rows: their one-line note, by folder.
    private var livePlaceholders: [ItemID: LivePlaceholderView] = [:]
    private var now = Instant(milliseconds: 0)
    /// Arc's row motions (`TablistMotion`, `TablistAnimator`): rows on their way out, by item, with their top in document
    /// points, so a row that comes back half-way keeps its view and its motion.
    private let animator = TablistAnimator()
    private var departing: [ItemID: (view: DepartingRowView, top: Double)] = [:]

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
        for view in [joinBand, pinnedSection, todaySection, dropLine] { document.addSubview(view) }
        joinBand.wantsLayer = true
        joinBand.isHidden = true
        joinBand.identify(.tabTool("split-join-band"))
        todaySection.addSubview(divider)
        todaySection.addSubview(newTab)
        dropLine.isHidden = true
        for edge in [topEdge, bottomEdge] {
            edge.wantsLayer = true
            edge.isHidden = true
            addSubview(edge)
        }
        addSubview(education)
        addSubview(currentArrow)
        currentArrow.isHidden = true
        currentArrow.action = { [weak self] in self?.scrollToCurrentRow() }
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

    /// The pointer is on a row's hover card.
    var hoverCardHasPointer: Bool { folderPreview.hasPointer }

    /// Escape while a hover card's search field has the keyboard closes the card.
    func takeEscape() -> Bool { folderPreview.takeEscape() }

    /// The rename field of `item` becomes first responder; false when it is not showing.
    func focusRenameField(_ item: ItemID) -> Bool {
        if rowViews[item] == nil, let rect = last?.frames.rows.first(where: { $0.kind == .item(item) })?.rect {
            document.scrollToVisible(rect)
            placeRows(refresh: false)
        }
        guard let row = rowViews[item], let window else { return false }
        return row.focusRenameField(in: window)
    }

    func focusList() -> Bool {
        guard let window else { return false }
        return window.makeFirstResponder(document)
    }

    /// The Cmd+click selection `id` belongs to, in its order, else `id` alone.
    func selectionGroup(containing id: ItemID) -> [ItemID] { multiselection.contains(id) ? multiselection : [id] }

    /// `newTabCurrent`: the New Tab row draws as the current row (a blank window showing nothing, as Arc's does).
    /// `lit`: the rows an AI list row or chip under the pointer lights (docs/design/ai-right-panel.md).
    func render(_ space: SpaceSnapshot, renaming: ItemID?, frames f: SidebarFrames, palette: Palette, tools: TabToolsSnapshot,
                newTabCurrent: Bool = false, now: Instant = Instant(milliseconds: 0), lit: Set<ItemID> = []) {
        // While New Tab is the current row the tab on screen draws like any other (Arc, Q01-a: one white card).
        let space = newTabCurrent ? space.idlingCurrent : space
        self.tools = tools
        self.now = now
        multiselection = tools.selected
        let previous = last
        last = (space, renaming, f, palette)

        var rows: [ItemID: (row: Row, section: SectionKind)] = [:]
        currentRow = nil
        func index(_ list: [Row], _ section: SectionKind) {
            for row in list {
                rows[row.id] = (row, section)
                if case .folder(let folder) = row { index(folder.children, section) }
                if case .tab(let tab) = row, tab.status == .current { currentRow = (row.id, tab.title) }
                if case .split(let split) = row, split.status == .current { currentRow = (row.id, split.panes.first { $0.status == .current }?.title ?? "") }
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
        let dividerWasHidden = divider.isHidden
        divider.isHidden = !f.rows.contains { $0.kind == .divider }
        renderedRows = rows
        renderedLit = lit
        // Rows still on their way out stay where they are on screen while their section's frame moves.
        for (id, entry) in departing {
            guard let container = entry.view.superview else { departing[id] = nil; continue }
            entry.view.frame.origin.y = entry.top - container.frame.minY
        }
        let moment = CACurrentMediaTime()
        let plan = motionPlan(from: previous, to: space, frames: f)
        if let plan { animator.begin(plan, at: moment) }
        placeRows(refresh: true, plan: plan, before: previous?.frames, now: moment)
        var seen: Set<ItemID> = []
        for frame in f.rows {
            switch frame.kind {
            case .item:
                break
            case .divider:
                divider.frame = frame.rect.offsetBy(dx: -todaySection.frame.minX, dy: -todaySection.frame.minY)
                divider.render(canClear: space.today.kind == .today && !space.today.rows.isEmpty, clearAction: space.today.clearAction,
                               canTidy: space.today.canTidy, tidying: space.today.tidying, cleanup: space.today.cleanup, space: space.id, palette: palette)
                move(divider, .divider, plan: plan, fresh: dividerWasHidden, now: moment)
            case .newTab:
                newTab.frame = frame.rect.offsetBy(dx: -todaySection.frame.minX, dy: -todaySection.frame.minY)
                newTab.render(palette: palette, current: newTabCurrent)
                move(newTab, .newTab, plan: plan, fresh: false, now: moment)
            case .livePlaceholder(let id):
                guard case .folder(let folder)? = rows[id]?.row, let live = folder.live else { continue }
                seen.insert(LivePlaceholderView.key(id))
                let container = rows[id]?.section == .pinned ? pinnedSection : todaySection
                var made = false
                let view = livePlaceholders[id] ?? {
                    let created = LivePlaceholderView(dispatch: dispatch)
                    livePlaceholders[id] = created
                    made = true
                    return created
                }()
                if view.superview !== container { container.addSubview(view) }
                view.frame = frame.rect.offsetBy(dx: -container.frame.minX, dy: -container.frame.minY)
                view.render(folder: id, live: live, depth: frame.depth, palette: palette)
                move(view, frame.kind, plan: plan, fresh: made, now: moment)
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
        dropLine.ink = palette.focusColor
        for edge in [topEdge, bottomEdge] { edge.layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor }
        if let reveal = tools.reveal, tools.revealGeneration != lastReveal, let row = f.rows.first(where: { $0.kind == .item(reveal) }) {
            document.scrollToVisible(row.rect)
            lastReveal = tools.revealGeneration
        }
        updateEdges()
    }

    /// Gives a view to each row within one viewport of the visible part of the list (and to the rows that must keep theirs:
    /// one being renamed, pressed or dragged, a drop or join target) and retires the others. `refresh`: a render, so rows that
    /// keep their views draw the new snapshot too; a scroll only draws the rows it adds.
    /// `plan`: the render's motion from the layout `before` (`TablistMotion`), started at `now`.
    private func placeRows(refresh: Bool, plan: TablistMotionPlan? = nil, before: SidebarFrames? = nil, now: CFTimeInterval = CACurrentMediaTime()) {
        guard let last else { return }
        let f = last.frames
        let visible = contentView.documentVisibleRect
        placedAt = visible
        let reach = max(visible.height, f.tablistViewport.height)
        let near = CGRect(x: 0, y: visible.minY - reach, width: max(visible.width, f.tablistViewport.width), height: visible.height + 2 * reach)
        var keep = Set([last.renaming, drag.heldItem, splitJoinTarget, dropFolder].compactMap { $0 })
        for (id, view) in rowViews where view.isEditingName { keep.insert(id) }
        var placed: Set<ItemID> = []
        var shown: [(id: ItemID, view: RowView, made: Bool, back: (top: Double, opacity: Float)?, rect: CGRect)] = []
        for frame in f.rows {
            guard case .item(let id) = frame.kind, let (row, section) = renderedRows[id] else { continue }
            guard keep.contains(id) || (frame.rect.maxY >= near.minY && frame.rect.minY <= near.maxY) else { continue }
            placed.insert(id)
            let container = section == .pinned ? pinnedSection : todaySection
            let existing = rowViews[id]
            // A row back while its picture is still on the way out (a folder opened again half-way) starts where the
            // picture is drawn.
            var back: (top: Double, opacity: Float)?
            if existing == nil, let entry = departing.removeValue(forKey: id), entry.view.superview != nil {
                back = (entry.top + animator.presentedOffset(entry.view), entry.view.layer?.presentation()?.opacity ?? 1)
                animator.forget(entry.view)
                entry.view.removeFromSuperview()
            }
            let view = existing ?? makeRow(id)
            if view.superview !== container { container.addSubview(view) }
            view.frame = frame.rect.offsetBy(dx: -container.frame.minX, dy: -container.frame.minY)
            if refresh || existing == nil {
                view.render(row, section: section, depth: frame.depth, renaming: last.renaming == id, multiselected: multiselection.contains(id), palette: last.palette,
                            animated: plan?.toggled[id] != nil)
                view.lit = renderedLit.contains(id)
                view.dropInto = dropFolder == id
                view.joinLeading = splitJoinTarget == id ? splitJoinLeading : nil
            }
            shown.append((id, view, existing == nil, back, frame.rect))
        }
        let oldRects = plan.map { plan in plan.departures.isEmpty ? [:] : Dictionary((before?.rows ?? []).map { ($0.kind, $0.rect) }, uniquingKeysWith: { a, _ in a }) } ?? [:]
        for (id, view) in rowViews where !placed.contains(id) {
            view.retire()
            rowViews[id] = nil
            defer { view.removeFromSuperview() }
            guard let departure = plan?.departures[.item(id)], let old = oldRects[.item(id)], let container = view.superview else { continue }
            // Arc's way out, drawn from the old place under the rows that move over it. The row itself goes now, with
            // whatever hangs on it (a popover, the pointer's hover); a picture of it makes the way out, as the table views
            // Arc's list is built on animate pictures of the rows they remove.
            var top = Double(old.minY), clipLine: Double?
            if case .slideUp(let by, let clip, _, _) = departure {
                top -= by
                clipLine = clip - top
            }
            let picture = DepartingRowView(picture: view.departurePicture(titles: clipLine == nil),
                                           frame: CGRect(x: old.minX - container.frame.minX, y: top - container.frame.minY, width: old.width, height: old.height))
            container.addSubview(picture, positioned: .below, relativeTo: nil)
            departing[id] = (picture, top)
            animator.depart(picture, departure: departure, clipLine: clipLine, now: now)
        }
        for entry in shown {
            let kind = RowFrame.Kind.item(entry.id)
            // A row back from its way out moves from where its picture was drawn: the plan's slides, plus what is missing.
            let missing = entry.back.map { $0.top - entry.rect.minY - (plan?.slides[kind] ?? []).reduce(0) { $0 + $1.dy } } ?? 0
            switch plan?.arrivals[kind] {
            case .fade?:
                if entry.made { animator.fadeIn(entry.view, from: entry.back?.opacity ?? 0, now: now) }
                animator.slide(entry.view, kind: kind, fresh: false, now: now)
                if abs(missing) > 0.5 { animator.extraSlide(entry.view, kind: kind, dy: missing, timing: .list, now: now) }
            case .underFolder(let clip)?:
                animator.slide(entry.view, kind: kind, fresh: false, now: now)
                if abs(missing) > 0.5 { animator.extraSlide(entry.view, kind: kind, dy: missing, timing: .folderOpen, now: now) }
                let opening = (plan?.slides[kind]?.first { $0.timing == .folderOpen }?.dy ?? 0) + missing
                animator.clip(entry.view, below: clip - entry.rect.minY, slide: opening, timing: .folderOpen, now: now)
            case nil:
                animator.slide(entry.view, kind: kind, fresh: entry.made && entry.back == nil, now: now)
                if abs(missing) > 0.5 { animator.extraSlide(entry.view, kind: kind, dy: missing, timing: .list, now: now) }
            }
            if plan?.moved.contains(kind) == true { animator.raise(entry.view, now: now) }
        }
        if let plan, !plan.moved.isEmpty {
            // A row moving into another section passes over the rows of the one it leaves.
            let into = Set(plan.moved.compactMap { kind -> SectionKind? in
                guard case .item(let id) = kind else { return nil }
                return renderedRows[id]?.section
            })
            if into.count == 1, let section = into.first {
                animator.raise(section == .pinned ? pinnedSection : todaySection, now: now)
            }
        }
    }

    /// The motion of the divider, New Tab and a Live Folder's note: they slide like rows, and fade in when they appear.
    private func move(_ view: NSView, _ kind: RowFrame.Kind, plan: TablistMotionPlan?, fresh: Bool, now: CFTimeInterval) {
        if plan?.arrivals[kind] != nil { animator.fadeIn(view, now: now) }
        animator.slide(view, kind: kind, fresh: fresh, now: now)
    }

    /// Arc moves the rows only within one Space at one width, and not under a drag (rows hold still until the drop).
    private func motionPlan(from previous: (space: SpaceSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette)?, to space: SpaceSnapshot,
                            frames f: SidebarFrames) -> TablistMotionPlan? {
        guard let previous, previous.frames.rows != f.rows else { return nil }
        guard previous.space.id == space.id, abs(previous.frames.tablistViewport.width - f.tablistViewport.width) < 0.5, window != nil,
              !isHiddenOrHasHiddenAncestor, !drag.isActive else {
            stopMotion()
            return nil
        }
        let plan = TablistMotion.plan(from: previous.frames.rows, previous.space, to: f.rows, space)
        return plan.isEmpty ? nil : plan
    }

    private func stopMotion() {
        animator.stopAll()
        departing.removeAll()
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

    // MARK: Scroll edges: 1 pt hairlines while rows are hidden above or below (cra L748).

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        // Half a viewport moved since rows were placed: the next ones get their views, the far ones go.
        let visible = contentView.documentVisibleRect
        if let placedAt, abs(visible.minY - placedAt.minY) > max(visible.height, 1) / 2 || abs(visible.height - placedAt.height) > 1 {
            placeRows(refresh: false)
        }
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
        updateCurrentArrow(visible: visible)
    }

    private func updateCurrentArrow(visible: CGRect) {
        guard let last, let palette = Optional(last.palette) else { return }
        let row = currentRow.flatMap { current in last.frames.rows.first { $0.kind == .item(current.id) }?.rect }
        guard let arrow = TablistLayout.currentRowArrow(row: row, visible: visible) else {
            currentArrow.isHidden = true
            return
        }
        currentArrow.isHidden = false
        var frame = TablistLayout.currentRowArrowFrame(arrow, in: bounds.size)
        if !isFlipped { frame.origin.y = bounds.height - frame.maxY }
        currentArrow.frame = frame
        currentArrow.render(arrow, tip: currentRow?.title, palette: palette)
    }

    private func scrollToCurrentRow() {
        guard let last, let current = currentRow, let row = last.frames.rows.first(where: { $0.kind == .item(current.id) }) else { return }
        document.scrollToVisible(row.rect)
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
        let indent = Draw.dropRingLeading.value + Double(depth) * t.folderIndent.value
        let ring = Draw.dropRingSide.value
        dropLine.frame = CGRect(x: indent, y: y - ring / 2, width: max(ring, document.bounds.width - indent - Draw.dropLineTrailing.value), height: ring)
        dropLine.isHidden = false
    }

    /// Where a held tab would join (Arc, Q15): a slot in the half of a tab's row under the pointer, the row's own icon and
    /// title moved to the other half; or one band across a split row, the whole sidebar wide. Nil clears it.
    func showSplitJoin(_ join: SplitJoin?, frames f: SidebarFrames) {
        if let old = splitJoinTarget, old != join?.target { rowViews[old]?.joinLeading = nil }
        splitJoinTarget = join?.target
        splitJoinLeading = nil
        joinBand.isHidden = true
        switch join {
        case .tab(let id, let leading)?:
            splitJoinLeading = leading
            rowViews[id]?.joinLeading = leading
        case .split(let id, _)?:
            guard let palette = last?.palette, let row = f.rows.first(where: { $0.kind == .item(id) }) else { return }
            joinBand.layer?.backgroundColor = palette.focusColor.withAlphaComponent(Draw.dropHintAlpha.value).cgColor
            joinBand.frame = CGRect(x: 0, y: row.rect.minY, width: row.rect.width, height: row.rect.height + Metrics.tablist.rowSpacing.value)
            joinBand.isHidden = false
        case nil:
            break
        }
    }

    private func setDropFolder(_ id: ItemID?) {
        guard id != dropFolder else { return }
        if let old = dropFolder { rowViews[old]?.dropInto = false }
        dropFolder = id
        if let id { rowViews[id]?.dropInto = true }
    }

    func rowView(_ id: ItemID) -> RowView? { rowViews[id] }

    /// The row a dropped image is gliding onto (`DragController.settle`): hidden until the image arrives.
    var arriving: ItemID? {
        didSet {
            guard arriving != oldValue else { return }
            if let oldValue { rowViews[oldValue]?.alphaValue = 1 }
            if let arriving { rowViews[arriving]?.alphaValue = 0 }
        }
    }

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

/// Arc's round button at the list's edge: an arrow towards the current row, its title as the tooltip; a click scrolls the
/// row back into view. It has nothing to do with media; a taller mini player is just one way to lose the row (Q18-media-e).
@MainActor
final class CurrentRowArrowView: NSView {
    private let button = GlyphButton()
    var action: (() -> Void)? { didSet { button.action = { [weak self] _ in self?.action?() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(button)
        identify(.tabTool("current-row-arrow"))
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: Draw.currentArrowShadow.value)
        shadow.shadowBlurRadius = Draw.currentArrowShadowBlur.value
        shadow.shadowOffset = CGSize(width: 0, height: -Draw.currentArrowShadowOffset.value)
        self.shadow = shadow
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func layout() { super.layout(); button.frame = bounds }

    func render(_ arrow: CurrentRowArrow, tip: String?, palette: Palette) {
        let light = palette.scheme == .light
        button.latchedFill = light ? Draw.currentArrowFillLight.value : Draw.currentArrowFillDark.value
        button.tip = tip
        button.render(arrow == .up ? .currentRowUp : .currentRowDown, size: Draw.currentArrowGlyph.value, palette: palette,
                      tint: NSColor(white: light ? 0 : 1, alpha: Draw.currentArrowInkLight.value), radius: Metrics.tablist.currentArrowSide.value / 2,
                      hoverFill: nil)
    }
}

/// Where a dragged row lands in the list (Arc, Q13-d): a line ending in a small ring at its left.
@MainActor
final class DropLineView: NSView {
    var ink = NSColor.gray { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let width = Draw.dropLineWidth.value, side = bounds.height
        ink.setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: width / 2, dy: width / 2))
        ring.lineWidth = width
        ring.stroke()
        ink.setFill()
        NSBezierPath(roundedRect: CGRect(x: side - width / 2, y: (side - width) / 2, width: max(0, bounds.width - side + width / 2), height: width), xRadius: width / 2, yRadius: width / 2).fill()
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
    /// The speaker button, between the icon and the title.
    let speaker: CGRect

    init(bounds: CGRect, depth: Int, speaker hasSpeaker: Bool = false) {
        let t = Metrics.tablist
        let indent = Double(depth) * t.folderIndent.value
        selection = CGRect(x: t.selectionInset.value + indent, y: (bounds.height - t.selectionHeight.value) / 2,
                           width: max(0, bounds.width - 2 * t.selectionInset.value - indent), height: t.selectionHeight.value)
        icon = CGRect(x: selection.minX + Draw.faviconLeading.value, y: bounds.midY - t.favicon.value / 2, width: t.favicon.value, height: t.favicon.value)
        titleX = selection.minX + TablistLayout.titleStart(leading: Draw.titleLeading.value, speaker: hasSpeaker)
        speaker = TablistLayout.speakerButton(selection: selection)
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
    /// Brk's own: the outline and tint in the Space's color while the AI conversation under the pointer used this row's tab.
    private let litMark = NSView()
    private let icon = IconView()
    /// A folder's glyph: Arc's drawn folder that opens and closes in 3D (`FolderIconView`).
    private let folderIcon = FolderIconView()
    private let title = NSTextField(labelWithString: "")
    /// "Double-click to rename" under the title, on a tab just dropped on the Space name strip (Q13-h).
    private let renameHint = NSTextField(labelWithString: SidebarCopy.renameHint)
    /// Place New Tabs' suggestion under the title ("Move to Recipes"): a click makes the move, its × drops it.
    private let suggestion = SuggestionLine()
    /// The half of this row a held tab would take (Q15).
    private let joinSlot = NSView()
    /// Arc's `_audibilityButton`: the speaker between the icon and the title of a tab that makes sound or is muted.
    private let audio = GlyphButton()
    /// Arc's drawn speaker inside the speaker button, whose own glyph stays clear (the button keeps the hover and the click).
    private let speakerGlyph = SpeakerGlyphView()
    private let button = GlyphButton()
    /// Arc's × / − inside the tab row's hover button, likewise.
    private let crossOrHyphen = CrossOrHyphenView()
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
    /// The AI list row or chip under the pointer used this row's tab (docs/design/ai-right-panel.md, 悬停高亮).
    var lit = false { didSet { if lit != oldValue { showLit() } } }
    var dropInto = false { didSet { if dropInto != oldValue { stateChanged() } } }
    var dragSource = false { didSet { alphaValue = dragSource ? Draw.dragSourceAlpha.value : 1 } }
    /// The row a tab drag left while the pointer is over the content: Arc keeps it in place on the selected-row card
    /// with its × showing (P23-d), and the white drag card follows the pointer instead.
    var dragLifted = false { didSet { if dragLifted != oldValue { stateChanged() } } }
    /// A tab held over this row's middle would take its left half (true) or right half (false); nil when none is (Q15).
    var joinLeading: Bool? {
        didSet {
            guard joinLeading != oldValue else { return }
            joinSlot.isHidden = joinLeading == nil
            if let palette { joinSlot.layer?.backgroundColor = palette.focusColor.withAlphaComponent(Draw.dropHintAlpha.value).cgColor }
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }
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
        renameHint.font = .systemFont(ofSize: Draw.renameHintFont.value)
        renameHint.isSelectable = false
        renameHint.lineBreakMode = .byTruncatingTail
        renameHint.isHidden = true
        joinSlot.wantsLayer = true
        joinSlot.layer?.cornerCurve = .continuous
        joinSlot.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        joinSlot.isHidden = true
        litMark.wantsLayer = true
        litMark.layer?.cornerCurve = .continuous
        litMark.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        litMark.isHidden = true
        for view in [background, litMark, joinSlot, icon, folderIcon, title, renameHint, suggestion, audio, button, peekMarker, spinner, liveMark] as [NSView] { addSubview(view) }
        // Inside their buttons: they show, fade and hide with them.
        audio.addSubview(speakerGlyph)
        button.addSubview(crossOrHyphen)
        folderIcon.isHidden = true
        speakerGlyph.isHidden = true
        crossOrHyphen.isHidden = true
        suggestion.isHidden = true
        suggestion.accept = { [weak self] in if let id = self?.row?.id { self?.dispatch(.assist(.acceptSuggestion(id))) } }
        suggestion.dismiss = { [weak self] in if let id = self?.row?.id { self?.dispatch(.assist(.dismissSuggestion(id))) } }
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

    /// `animated`: the folder just opened or closed, so its glyph turns (Arc's FolderIconView).
    func render(_ row: Row, section: SectionKind, depth: Int, renaming: Bool, multiselected: Bool, palette: Palette, animated: Bool = false) {
        // A row that changed under the pointer (a folder just collapsed) reports its hover anew below, so its card is
        // decided again. An unchanged one does not: that restarted the card's wait at every redraw, and a loading page
        // redraws the sidebar several times a second, so the card never opened.
        let changed = row != self.row
        // The same row changing state (muted, become the current pinned tab) moves its glyphs; a reused or new one does not.
        let sameRow = self.row?.id == row.id
        let speakerShown = !speakerGlyph.isHidden
        self.row = row
        self.section = section
        self.depth = depth
        self.palette = palette
        self.multiselected = multiselected
        identify(.row(row.id))
        button.identify(.rowClose(row.id))
        joinSlot.identify(.tabTool("split-join-slot-" + row.id.rawValue))
        audio.isHidden = true
        speakerGlyph.isHidden = true
        crossOrHyphen.isHidden = true
        renameHint.isHidden = true
        suggestion.isHidden = true
        folderIcon.isHidden = true
        renderLive(row, palette: palette)
        switch row {
        case .tab(let tab):
            audio.isHidden = tab.speaker == nil
            speakerGlyph.isHidden = tab.speaker == nil
            let speakerInk = NSColor(white: palette.scheme == .light ? 0 : 1, alpha: Draw.rowSpeakerInk.value)
            renderSpeakerButton(muted: tab.muted, ink: .clear, palette: palette)
            speakerGlyph.render(muted: tab.muted, tint: speakerInk, animated: sameRow && speakerShown && !speakerGlyph.isHidden)
            audio.tip = tab.muted ? SidebarCopy.unmuteThisTab : SidebarCopy.muteThisTab
            audio.identify(.tabTool("audio-" + tab.id.rawValue))
            title.stringValue = tab.title
            renameHint.isHidden = !tab.renameHint || renaming
            renameHint.textColor = palette.ink.text.withAlphaComponent(Draw.renameHintInk.value)
            if let label = tab.aiSuggestion, !renaming, !tab.renameHint {
                suggestion.isHidden = false
                suggestion.render(label, id: tab.id, palette: palette)
            }
            icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette)
            if tab.awaitingFirstDocument { title.stringValue = SidebarCopy.untitled }
            title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
            configureButton(tab: tab, palette: palette, animated: sameRow)
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
            if let custom = folder.icon {
                icon.render(.custom(custom), tint: palette.ink.secondary, palette: palette)
            } else {
                icon.render(.none, tint: palette.ink.secondary)
                folderIcon.isHidden = false
                folderIcon.render(folder.collapsed ? .collapsed : .expanded, ink: HueInk(palette), light: palette.scheme == .light, animated: animated)
                folderIcon.identify(.tabTool("folder-glyph-" + (folder.collapsed ? "closed-" : "open-") + folder.id.rawValue))
            }
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
        if case .folder(let folder) = row, folder.group { title.textColor = palette.color(palette.tokens.foreground) } else { title.textColor = palette.ink.text }
        if renaming, row.kind != .split { showRenameField(palette: palette) } else { dropRenameField() }
        if changed, reportedHover { reportedHover = false; onHover?(self, false) }
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
        // A kept AI page (Brk's own): a dot in the Space's colour for data that changed since the user looked, the
        // warning sign for a refresh that was stopped or failed; its schedule and last refresh are the tooltip.
        guard case .tab(let tab) = row, AIPageTab.shows(tab.url) else { return }
        liveMark.identifier = NSUserInterfaceItemIdentifier("live-page-mark-" + id)
        liveMark.setAccessibilityIdentifier("live-page-mark-" + id)
        toolTip = tab.sourceStatus
        switch tab.liveMark {
        case .changed?:
            liveMark.isHidden = false
            liveMark.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: Draw.livePageDot.value, weight: .regular))
            liveMark.contentTintColor = palette.focusColor
            liveMark.toolTip = tab.sourceStatus
            liveMark.setAccessibilityLabel(SidebarCopy.livePageChanged)
        case .attention?:
            liveMark.isHidden = false
            liveMark.image = Glyph.warning.image(size: Draw.smallFont.value)
            liveMark.contentTintColor = NSColor.systemOrange
            liveMark.toolTip = tab.sourceStatus
            liveMark.setAccessibilityLabel(SidebarCopy.livePageStopped)
        case nil: break
        }
    }

    /// The speaker button's own symbol: clear under the drawn speaker, inked for a picture of the row.
    private func renderSpeakerButton(muted: Bool, ink: NSColor, palette: Palette) {
        if muted {
            audio.render(.rowSpeakerMuted, size: Draw.rowSpeakerMutedGlyph.value, weight: .regular, palette: palette, tint: ink,
                         radius: Draw.rowSpeakerRadius.value, hoverFill: palette.tokens.itemHover)
        } else {
            audio.render(.rowSpeaker, size: Draw.rowSpeakerGlyph.value, weight: .medium, palette: palette, tint: ink,
                         radius: Draw.rowSpeakerRadius.value, hoverFill: palette.tokens.itemHover)
        }
    }

    private func configureButton(tab: TabRow, palette: Palette, animated: Bool) {
        // A window's own tabs (blank and incognito windows) archive like Today's.
        // Arc (Q18-rowbutton-*): the current Pinned row has a minus that closes the page and keeps the row; every
        // other row, Pinned ones too, loaded or not, has the × that archives it.
        let keeps = keepsPinned(tab)
        hasButton = true
        button.isHidden = !hasButton && !dragLifted
        button.toolTip = keeps ? SidebarCopy.closeKeepPinned : Copy.archiveTabTooltip
        button.render(keeps ? .closeKeepPinned : .archiveTab, size: Draw.rowCloseGlyph.value, weight: .semibold, palette: palette, tint: .clear,
                      radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
        crossOrHyphen.isHidden = false
        crossOrHyphen.render(hyphen: keeps, tint: palette.ink.secondary, animated: animated)
    }

    /// The current tab of the Pinned section: its button closes the page and keeps the row.
    private func keepsPinned(_ tab: TabRow) -> Bool { section != .today && section != .scratch && tab.status == .current }

    private func setSegments(_ panes: [TabRow], palette: Palette) {
        while segments.count < panes.count {
            let segment = SplitSegmentView(dispatch: dispatch)
            segments.append(segment)
            addSubview(segment)
        }
        while segments.count > panes.count { segments.removeLast().removeFromSuperview() }
        for (segment, pane) in zip(segments, panes) { segment.render(pane, palette: palette) }
        title.isHidden = !panes.isEmpty || renameField != nil
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: depth, speaker: !audio.isHidden)
        background.frame = g.selection
        litMark.frame = g.selection
        icon.frame = g.icon
        crossOrHyphen.frame = CGRect(origin: .zero, size: g.button.size)
        speakerGlyph.frame = CGRect(origin: .zero, size: g.speaker.size)
        let side = Draw.folderIconSide.value
        folderIcon.frame = CGRect(x: g.icon.midX - side / 2, y: g.icon.midY - side / 2, width: side, height: side)
        button.frame = g.button
        audio.frame = g.speaker
        let height = title.intrinsicContentSize.height
        peekMarker.frame = g.button
        spinner.frame = g.button.insetBy(dx: (g.button.width - 16) / 2, dy: (g.button.height - 16) / 2)
        liveMark.frame = (button.alphaValue > 0 && !button.isHidden ? g.button.offsetBy(dx: -g.button.width, dy: 0) : g.button)
        // The hover button takes room from the title only while it shows (Arc truncates at the selection's end).
        let buttonShown = !button.isHidden && button.alphaValue > 0
        let trailing = !spinner.isHidden ? spinner.frame.minX : !liveMark.isHidden ? liveMark.frame.minX
            : !peekMarker.isHidden ? g.button.minX
            : buttonShown ? g.selection.maxX - Draw.rowTitleOverButton.value : g.selection.maxX - Draw.titleTrailing.value
        title.frame = g.title(height: height, trailing: trailing, in: bounds)
        if let leading = joinLeading {
            // The slot takes one half, the row's own icon and title the other, cut off at its end (Q15-a, Q15-b).
            let half = g.selection.width / 2, inset = Draw.splitJoinSlotInset.value
            joinSlot.frame = CGRect(x: (leading ? g.selection.minX : g.selection.midX) + inset, y: g.selection.minY, width: half - inset, height: g.selection.height)
            if leading { icon.frame.origin.x += half }
            let start = g.titleX + (leading ? half : 0), end = (leading ? g.selection.maxX : g.selection.midX) - Draw.splitJoinTitleTrailing.value
            title.frame = CGRect(x: start, y: title.frame.minY, width: max(0, end - start), height: title.frame.height)
        }
        if !renameHint.isHidden {
            title.frame.origin.y += Draw.renameHintTitleShift.value
            renameHint.frame = CGRect(x: title.frame.minX, y: Draw.renameHintTop.value, width: title.frame.width, height: renameHint.intrinsicContentSize.height)
        }
        if !suggestion.isHidden {
            // The same two lines as "Double-click to rename" (Q13-h): the title moves up, the suggestion goes under it.
            title.frame.origin.y += Draw.renameHintTitleShift.value
            suggestion.frame = CGRect(x: title.frame.minX, y: Draw.renameHintTop.value - 2, width: max(0, g.selection.maxX - Draw.titleTrailing.value - title.frame.minX), height: suggestion.fittingSize.height)
        }
        // Arc's group header starts its title where a tab's favicon starts (no icon column); its rename field too.
        var field = g.title(height: height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: bounds)
        if case .folder(let folder)? = row, folder.group {
            let start = g.selection.minX + Draw.groupTitleLeading.value
            title.frame = CGRect(x: start, y: title.frame.minY, width: max(0, trailing - start), height: height)
            field = CGRect(x: start, y: field.minY, width: max(0, field.maxX - start), height: field.height)
        }
        renameField?.frame = field
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

    /// The lit look: the Space's own color as a thin outline and a light tint over whatever fill the row has.
    private func showLit() {
        litMark.isHidden = !lit
        litMark.identify(.tabTool("ai-lit-" + (row?.id.rawValue ?? "")))
        guard lit, let palette else { return }
        litMark.layer?.borderWidth = Metrics.ai.litBorderWidth.value
        litMark.layer?.borderColor = palette.focusColor.cgColor
        litMark.layer?.backgroundColor = palette.focusColor.withAlphaComponent(Metrics.ai.litTint.value).cgColor
    }

    override func stateChanged() {
        guard let palette, let row else { return }
        if lit { showLit() }
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
        // Q18-navy-row-hover-arc.png: a hovered row reads white 0.11 over a dark theme (the 0.15 of the other hovers is too much).
        else if multiselected || isHovered { fill = !multiselected && palette.scheme == .dark ? tokens.tabPreviousHover : tokens.itemHover }
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

    /// For a picture of the row (a drag, its way out of the list): the glyphs drawn on layers, which a view's cached image
    /// leaves out, give way to their symbols. The row is drawn as before afterwards when `restore` runs.
    private func pictureGlyphs() -> () -> Void {
        guard let palette else { return {} }
        var undo: [() -> Void] = []
        if !folderIcon.isHidden {
            folderIcon.isHidden = true
            icon.render(.folder(open: folderIcon.state == .expanded), tint: palette.ink.secondary, palette: palette)
            undo.append { [self] in folderIcon.isHidden = false; icon.render(.none, tint: palette.ink.secondary) }
        }
        if !speakerGlyph.isHidden {
            speakerGlyph.isHidden = true
            let ink = NSColor(white: palette.scheme == .light ? 0 : 1, alpha: Draw.rowSpeakerInk.value)
            renderSpeakerButton(muted: speakerGlyph.muted, ink: ink, palette: palette)
            undo.append { [self] in speakerGlyph.isHidden = false; renderSpeakerButton(muted: speakerGlyph.muted, ink: .clear, palette: palette) }
        }
        if !crossOrHyphen.isHidden, case .tab(let tab)? = row {
            crossOrHyphen.isHidden = true
            button.render(keepsPinned(tab) ? .closeKeepPinned : .archiveTab, size: Draw.rowCloseGlyph.value, weight: .semibold, palette: palette,
                          radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
            undo.append { [self] in crossOrHyphen.isHidden = false; configureButton(tab: tab, palette: palette, animated: false) }
        }
        return { undo.forEach { $0() } }
    }

    /// The row as it looks, for its way out of the list (`DepartingRowView`): without its hover button, and without its
    /// titles when it slides up (Arc's sliding rows keep only their icons). The row is not shown again afterwards.
    func departurePicture(titles: Bool) -> NSImage? {
        button.alphaValue = 0
        if !titles {
            for label in [title, renameHint] as [NSView] { label.isHidden = true }
            suggestion.isHidden = true
            for segment in segments { segment.showsTitle = false }
        }
        _ = pictureGlyphs()
        layoutSubtreeIfNeeded()
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The row's icon, title and button for the drag image: no card and no shadow, the image has its own.
    func dragImage() -> NSImage? {
        let restore = pictureGlyphs()
        layoutSubtreeIfNeeded()
        let shadow = background.shadow, fill = background.layer?.backgroundColor
        background.shadow = nil
        background.layer?.backgroundColor = nil
        defer {
            background.shadow = shadow
            background.layer?.backgroundColor = fill
            restore()
        }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
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
        // The press opens a tab or a split's pane right away (Arc, Q13-press-row); `press` first, it notes what the window shows.
        drag.press(.init(id: row.id, kind: row.kind, section: section), source: self, event: event)
        let point = local(event)
        SidebarPress.commands(for: row, pane: segments.first { $0.frame.contains(point) }?.pane?.id, command: false, shift: false).forEach(dispatch)
    }

    override func mouseDragged(with event: NSEvent) {
        if drag.drag(event) { isPressed = false }
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if drag.release(event) { return }
        guard let row, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), bounds.contains(local(event)) else { return }
        if case .folder = row { onSelect?(row.id) }
        if event.clickCount == 2, row.kind != .split {
            dispatch(.item(.beginRename(.item(row.id))))
            return
        }
        if case .folder = row { dispatch(.item(.toggleFolder(row.id))) }
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
        dispatch(.tabTools(.bulk(.items(closeTargets?(row.id) ?? [row.id]), closeAction(row))))
        onClearMultiselect?()
    }

    /// A Pinned row that is not the current tab is archived, like a Today row (Arc, Q18-rowbutton-pinned-x-removed-the-row).
    private func closeAction(_ row: Row) -> BulkTabAction {
        if case .tab(let tab) = row, section != .today, section != .scratch, !keepsPinned(tab) { return .archive }
        return .close
    }

    // MARK: Middle-click: a tab row goes as its × sends it, this row alone (Arc 1.170 archives a middle-clicked tab,
    // docs/design/input-rules.md). The press is claimed so the list does not take it for anything else.

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, case .tab? = row else { super.otherMouseDown(with: event); return }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let row, case .tab = row else { super.otherMouseUp(with: event); return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dispatch(.tabTools(.bulk(.items([row.id]), closeAction(row))))
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

    /// The row left the list: the pointer is off it, and its rename field goes without committing.
    func retire() {
        if reportedHover { reportedHover = false; onHover?(self, false) }
        dropRenameField()
    }

    /// Drops the field without committing (the rename ended elsewhere: Esc through the menu, or the row left).
    private func dropRenameField() {
        guard let field = renameField else { return }
        field.retire()
        renameField = nil
        title.isHidden = !segments.isEmpty
    }
}

/// A row that left the list, drawn as a picture for its way out (`TablistAnimator.depart`). It takes no pointer and has
/// no identifier: for the harness and accessibility the row is gone.
@MainActor
final class DepartingRowView: NSView {
    init(picture: NSImage?, frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = picture
        layer?.contentsGravity = .resize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
        self.palette = palette
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
        let height = title.intrinsicContentSize.height
        let start = Draw.splitSegmentTitleLeading.value
        let end = close.alphaValue > 0 ? close.frame.minX : bounds.width - Draw.faviconLeading.value / 2
        title.frame = CGRect(x: start, y: (bounds.height - height) / 2, width: max(0, end - start), height: height)
    }

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

/// Place New Tabs' suggestion on a row: "→ Move to" and the destination's name in the accent colour, a small × after
/// them. Each is one line; when the row is narrow the name is cut short with "…", never the action. Every part is a
/// `HoverView`, so it takes the click before the row does.
@MainActor
final class SuggestionLine: NSView {
    let action = SuggestionPart()
    let name = SuggestionPart()
    let close = SuggestionPart()
    var accept: (() -> Void)? { didSet { action.action = accept; name.action = accept } }
    var dismiss: (() -> Void)? { didSet { close.action = dismiss } }
    static let closeWidth: CGFloat = 14
    static let gap: CGFloat = 3
    /// The labels draw their text 2 points in from each side; this makes the space after "Move to" a word space.
    static let wordGap: CGFloat = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        for part in [action, name, close] { addSubview(part) }
        close.toolTip = "Dismiss suggestion"
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ label: AISuggestionLabel, id: ItemID, palette: Palette) {
        action.text("→ " + label.action, color: palette.focusColor)
        name.text(label.name, color: palette.focusColor)
        toolTip = label.text
        close.glyph.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss suggestion")?
            .withSymbolConfiguration(.init(pointSize: Draw.renameHintFont.value - 2, weight: .semibold))
        close.glyph.contentTintColor = palette.ink.secondary
        identify(.tabTool("ai-suggestion-line-" + id.rawValue))
        action.identify(.tabTool("ai-suggestion-" + id.rawValue))
        name.identify(.tabTool("ai-suggestion-name-" + id.rawValue))
        close.identify(.tabTool("ai-suggestion-dismiss-" + id.rawValue))
        action.setAccessibilityLabel(label.text)
        name.setAccessibilityLabel(label.text)
        close.setAccessibilityLabel("Dismiss suggestion")
        needsLayout = true
    }

    override var fittingSize: NSSize {
        NSSize(width: action.natural.width + Self.wordGap + name.natural.width + Self.gap + Self.closeWidth, height: max(action.natural.height, 14))
    }

    override func layout() {
        super.layout()
        let actionWidth = min(action.natural.width, bounds.width - Self.closeWidth - Self.gap)
        action.frame = CGRect(x: 0, y: 0, width: max(0, actionWidth), height: bounds.height)
        let room = bounds.width - action.frame.maxX - Self.wordGap - Self.gap - Self.closeWidth
        name.frame = CGRect(x: action.frame.maxX + Self.wordGap, y: 0, width: max(0, min(name.natural.width, room)), height: bounds.height)
        close.frame = CGRect(x: name.frame.maxX + Self.gap, y: 0, width: Self.closeWidth, height: bounds.height)
    }
}

/// One clickable part of a suggestion: a one-line label or a glyph, acting on mouse up inside it.
@MainActor
final class SuggestionPart: HoverView {
    let label = NSTextField(labelWithString: "")
    let glyph = NSImageView()
    var action: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.isSelectable = false
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        addSubview(glyph)
        setAccessibilityRole(.button)
    }

    /// The text on one line, cut with "…" at its end when the part is narrower than it.
    func text(_ value: String, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        label.attributedStringValue = NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: Draw.renameHintFont.value, weight: .medium),
                                                                                     .foregroundColor: color, .paragraphStyle: style])
        needsLayout = true
    }

    /// The width and height the text takes on one line.
    var natural: CGSize {
        let size = label.attributedStringValue.size()
        return CGSize(width: ceil(size.width) + 4, height: ceil(size.height))
    }

    /// The text does not fit and ends in "…".
    var isTruncated: Bool { bounds.width < natural.width }

    override func layout() {
        super.layout()
        label.frame = bounds
        glyph.frame = bounds
    }

    override func stateChanged() { alphaValue = isPressed ? 0.6 : 1 }
    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { action?() }
    }
    override func accessibilityPerformPress() -> Bool { action?(); return true }
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
    /// While Tidy works the hairline gives way to Arc's moving wave.
    private let wave = TidyWaveView()
    private let clear: ClearButton
    /// Max's Tidy Tabs (P46-b): 🧹 Tidy left of Clear while the pointer is on the divider and Today has more than six
    /// tabs, a bar between them.
    private let tidy: TidyButton
    private let tidyBar = NSView()
    /// Brk's Suggest Tabs to Close: the duplicate and long-unvisited Today tabs, listed in a menu, left of Tidy.
    private let cleanup: CleanupButton
    private var space: SpaceID?
    private var cleanupCount = 0
    private var palette: Palette?
    private var canClear = false
    private var canTidy = false, tidying = false
    /// Arc shows Clear whenever the pointer is over the sidebar, not only over the divider.
    var sidebarHovered = false { didSet { if sidebarHovered != oldValue { stateChanged() } } }

    init(dispatch: @escaping Dispatch) {
        clear = ClearButton { dispatch(.tab(.clearToday)) }
        tidy = TidyButton { dispatch(.assist(.organizeToday)) }
        weak var owner: DividerRowView?
        cleanup = CleanupButton { point in
            guard let space = owner?.space else { return }
            dispatch(.sidebar(.popupMenu(.todayCleanup(space), at: point)))
        }
        super.init(frame: .zero)
        owner = self
        line.wantsLayer = true
        tidyBar.wantsLayer = true
        addSubview(line)
        addSubview(wave)
        wave.isHidden = true
        wave.onShownChange = { [weak self] in self?.needsLayout = true }
        addSubview(clear)
        addSubview(tidyBar)
        addSubview(tidy)
        addSubview(cleanup)
        clear.identify(.todayClear)
        tidy.identify(.todayTidy)
        cleanup.identify(.tabTool("today-cleanup"))
    }

    func render(canClear: Bool, clearAction: TodayClearAction = .clearOthers, canTidy: Bool = false, tidying: Bool = false, cleanup count: Int = 0, space: SpaceID? = nil, palette: Palette) {
        self.palette = palette
        self.canClear = canClear
        self.canTidy = canTidy
        self.tidying = tidying
        self.space = space
        cleanupCount = count
        cleanup.render(count: count, palette: palette)
        cleanup.isHidden = count == 0
        line.layer?.backgroundColor = palette.color(palette.tokens.separator).cgColor
        // Arc strokes the wave in SidebarSeparator, the hairline's colour.
        wave.color = palette.color(palette.tokens.separator).cgColor
        wave.restWidth = Draw.hairline.value
        wave.setLoading(tidying)
        tidyBar.layer?.backgroundColor = palette.color(palette.tokens.separator).cgColor
        clear.render(clearAction, palette: palette)
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
        let wordStart = ((bounds.width - Draw.clearTrailing.value - clear.textWidth) * 2).rounded() / 2
        // The ↓ goes left of the word, which stays where it is; everything further left moves over by it.
        let textStart = wordStart - clear.arrowRoom
        clear.frame = CGRect(x: textStart - ClearButton.cellInset, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        // With the ↓ the hairline ends 20 before the word (Q18-clear-pinned-current-resting-arc.png), without it 10.
        let clearGap = clear.arrowRoom > 0 ? Draw.clearGap.value - Draw.clearArrowGap.value : Draw.clearGap.value
        var end = clear.alphaValue > 0 && !clear.isHidden ? textStart - clearGap : bounds.width - inset
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
        let cleanupSize = cleanup.fittingSize
        let cleanupRight = tidy.isHidden ? (clear.isHidden ? right : tidyBar.frame.minX - gaps[2]) : tidy.frame.minX - gaps[0]
        cleanup.frame = CGRect(x: cleanupRight - cleanupSize.width, y: (bounds.height - cleanupSize.height) / 2, width: cleanupSize.width, height: cleanupSize.height)
        if cleanup.alphaValue > 0 && !cleanup.isHidden { end = cleanup.frame.minX - gaps[0] }
        line.frame = CGRect(x: inset, y: (bounds.height - hairline) / 2, width: max(0, end - inset), height: hairline)
        // The wave is centred on the hairline over the same length, tall enough for its crests and the thick line.
        let waveHeight = Draw.tidyWaveHeight.value + Draw.tidyWaveLineWidth.value
        wave.frame = CGRect(x: line.frame.minX, y: line.frame.midY - waveHeight / 2, width: line.frame.width, height: waveHeight)
        wave.isHidden = !wave.isShown
        line.isHidden = wave.isShown
    }

    override func stateChanged() {
        let hovering = isHovered || clear.isHovered || tidy.isHovered || cleanup.isHovered
        let shown: [(NSView, CGFloat)] = [(clear, canClear && (sidebarHovered || hovering) ? 1 : 0), (tidy, canTidy && (hovering || tidying) ? 1 : 0),
                                          (cleanup, cleanupCount > 0 && hovering ? 1 : 0)]
        // Arc fades the divider's buttons in and out (bin:0x1001ac9c0); a window not on screen yet takes them at once.
        let curve = Draw.dividerFadeCurve.value.map(Float.init)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = window == nil ? 0 : Draw.dividerFade.value
            context.timingFunction = CAMediaTimingFunction(controlPoints: curve[0], curve[1], curve[2], curve[3])
            for (view, alpha) in shown where view.alphaValue != alpha { view.animator().alphaValue = alpha }
        }
        needsLayout = true
    }
}

/// Brk's cleanup list beside Tidy: a stack glyph and how many Today tabs it lists, in Clear's colours; a click opens the
/// list as a menu under it.
@MainActor
final class CleanupButton: HoverView {
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let action: (CGPoint) -> Void
    private var palette: Palette?

    init(action: @escaping (CGPoint) -> Void) {
        self.action = action
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.captionFont.value, weight: .semibold)
        label.isSelectable = false
        glyph.imageScaling = .scaleProportionallyUpOrDown
        addSubview(glyph)
        addSubview(label)
        toolTip = AICopy.cleanupTooltip
        setAccessibilityLabel(AICopy.cleanupTooltip)
        setAccessibilityRole(.button)
    }

    override var fittingSize: NSSize {
        let g = Draw.tidyGlyph.value[1], text = label.intrinsicContentSize
        return NSSize(width: g + Draw.tidyGaps.value[1] + label.cellWidth, height: max(g, text.height))
    }

    func render(count: Int, palette: Palette) {
        self.palette = palette
        label.stringValue = "\(count)"
        stateChanged()
    }

    override func layout() {
        super.layout()
        let g = Draw.tidyGlyph.value[1], text = label.intrinsicContentSize
        glyph.frame = CGRect(x: 0, y: (bounds.height - g) / 2, width: g, height: g)
        label.frame = CGRect(x: bounds.width - label.cellWidth, y: (bounds.height - text.height) / 2, width: label.cellWidth, height: text.height)
    }

    override func stateChanged() {
        guard let palette else { return }
        let color = isHovered ? palette.color(palette.tokens.foregroundStrong) : palette.clearInk
        label.textColor = color
        glyph.image = NSImage(systemSymbolName: "rectangle.stack.badge.minus", accessibilityDescription: AICopy.cleanupTooltip)
        glyph.contentTintColor = color
        (superview as? HoverView)?.stateChanged()
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        guard bounds.contains(local(event)) else { return }
        // The menu opens under the button, as a pop-up button's does.
        action(rootPoint(of: CGPoint(x: bounds.minX, y: isFlipped ? bounds.maxY : bounds.minY)))
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
        // The label's cell, not its intrinsic size, which cut the last letter; the cell draws the word 2 in from each side.
        return NSSize(width: g[0] + Draw.tidyGaps.value[1] + label.cellWidth, height: max(g[1], text.height))
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
        label.frame = CGRect(x: bounds.width - label.cellWidth, y: (bounds.height - text.height) / 2, width: label.cellWidth, height: text.height)
    }

    override func stateChanged() {
        guard let palette else { return }
        let color = isHovered && !busy ? palette.color(palette.tokens.foregroundStrong) : palette.clearInk
        label.textColor = color
        glyph.image = ArcGlyphs.broom(size: Draw.tidyGlyph.value[1])
        glyph.contentTintColor = color
        for view in [glyph, label] as [NSView] { view.alphaValue = busy ? Draw.busyAlpha.value : 1 }
        (superview as? HoverView)?.stateChanged()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        if !busy { swingBroom() }
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if !busy, bounds.contains(local(event)) { action() }
    }

    private var swingEnd: DispatchWorkItem?

    /// Arc's press: the broom hangs from its top edge and springs 25° clockwise, then back 0.4 s later. Its bristles swing
    /// past the button's left edge, so the button stops clipping until the swing has settled.
    private func swingBroom() {
        guard let layer = glyph.layer, let superlayer = layer.superlayer else { return }
        // In a flipped parent the layer's top edge is y 0 and a clockwise turn is a positive angle.
        let flipped = superlayer.contentsAreFlipped()
        let anchor = CGPoint(x: Draw.tidyBroomPivot.value, y: flipped ? 0 : 1), old = layer.anchorPoint, size = layer.bounds.size
        if anchor != old {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.anchorPoint = anchor
            layer.position = CGPoint(x: layer.position.x + (anchor.x - old.x) * size.width, y: layer.position.y + (anchor.y - old.y) * size.height)
            CATransaction.commit()
        }
        layer.add(Self.swing(to: Draw.tidyBroomSwing.value * (flipped ? 1 : -1)), forKey: "rotationAnimation")
        clipsToBounds = false
        swingEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in
            guard let self, let layer = self.glyph.layer else { return }
            let back = Self.swing(to: 0)
            layer.add(back, forKey: "rotationAnimationBack")
            let settle = DispatchWorkItem { [weak self] in self?.endSwing() }
            self.swingEnd = settle
            DispatchQueue.main.asyncAfter(deadline: .now() + back.duration, execute: settle)
        }
        swingEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Draw.tidyBroomHold.value, execute: end)
    }

    /// Clipping back on; the pointer may have left while the button reached past its edge.
    private func endSwing() {
        clipsToBounds = true
        guard let window else { return }
        setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private static func swing(to angle: CGFloat) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: "transform.rotation.z")
        spring.toValue = angle
        let p = Draw.tidyBroomSpring.value
        spring.mass = p[0]
        spring.stiffness = p[1]
        spring.damping = p[2]
        spring.initialVelocity = p[3]
        spring.duration = spring.settlingDuration
        spring.fillMode = .forwards
        return spring
    }
}

/// "Clear", with a ↓ before the word while the current tab is outside Today (Arc's `SidebarClearButton`: `clearAll`,
/// Q18-clear-pinned-current-arc.png): both in the sidebar foreground, stronger on hover.
@MainActor
final class ClearButton: HoverView {
    private let arrow = NSImageView()
    private let label = NSTextField(labelWithString: Copy.clearToday)
    private let action: () -> Void
    private var palette: Palette?
    /// What the button says now: "↓ Clear" or "Clear" (accessibility, and how e2e reads it).
    private(set) var clearAction = TodayClearAction.clearOthers

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.clearFont.value, weight: .semibold)
        label.isSelectable = false
        arrow.imageScaling = .scaleNone
        arrow.isHidden = true
        addSubview(label)
        addSubview(arrow)
    }

    /// The label's cell, not its intrinsic size, which cut the last letter (P02-clear-user-brk.png).
    override var fittingSize: NSSize { NSSize(width: arrowRoom + label.cellWidth, height: label.intrinsicContentSize.height) }

    static let cellInset = 2.0
    var textWidth: Double { label.attributedStringValue.size().width }
    /// How far the ↓ pushes the button's left edge out from the word.
    var arrowRoom: Double { clearAction == .clearAll ? Draw.clearArrowWidth.value + Draw.clearArrowGap.value : 0 }

    func render(_ action: TodayClearAction, palette: Palette) {
        self.palette = palette
        clearAction = action
        arrow.isHidden = action != .clearAll
        toolTip = action == .clearAll ? Copy.clearTodayAll : Copy.clearTodayOthers
        setAccessibilityLabel(action == .clearAll ? "↓ " + Copy.clearToday : Copy.clearToday)
        stateChanged()
        needsLayout = true
    }

    /// Arc's press: the ↓ sinks `Draw.clearArrowPress` while the button is held (bin:0x10030f714, back at bin:0x10030f8d4).
    private var arrowSunk = false

    override func layout() {
        super.layout()
        arrow.frame = arrowFrame
        label.frame = CGRect(x: arrowRoom, y: 0, width: bounds.width - arrowRoom, height: bounds.height)
    }

    private var arrowFrame: CGRect {
        CGRect(x: Self.cellInset, y: arrowSunk ? Draw.clearArrowPress.value : 0, width: Draw.clearArrowWidth.value, height: bounds.height)
    }

    private func sinkArrow(_ sunk: Bool) {
        guard sunk != arrowSunk else { return }
        arrowSunk = sunk
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Draw.clearArrowPressDuration.value
            context.allowsImplicitAnimation = true
            arrow.animator().frame = arrowFrame
        }
    }

    override func stateChanged() {
        guard let palette else { return }
        // The pointer on the label writes it in the rows' ink (Q18-clear-pinned-current-on-label-arc.png: #2A2C2E).
        let ink = isHovered ? palette.ink.text : palette.clearInk
        label.textColor = ink
        arrow.image = Glyph.clearDown.image(size: Draw.clearArrowGlyph.value, weight: .semibold)
        arrow.contentTintColor = ink
        (superview as? HoverView)?.stateChanged()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        sinkArrow(true)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        sinkArrow(false)
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
    /// Arc's chevron turns between down (Pinned open) and right (closed) rather than changing picture
    /// (`SidebarSectionHeaderView`'s chevron, bin:0x1001cace0): one glyph on its own layer, turned 90°.
    private let chevron = CALayer()
    private var chevronTint: NSColor?
    private let more = GlyphButton()
    private var space: SpaceSnapshot?
    private var palette: Palette?
    /// What the strip showed last, so a change of it moves instead of jumping.
    private var shownExpanded: Bool?, shownPill: Bool?, shownCollapsed: Bool?
    /// A drag is over the strip: the whole of it turns dark grey (Arc, Q13-g).
    var dropHighlighted = false {
        didSet {
            guard dropHighlighted != oldValue, let palette else { return }
            layer?.backgroundColor = dropHighlighted ? palette.focusColor.withAlphaComponent(Draw.dropHintAlpha.value).cgColor : nil
        }
    }

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
        for view in [background, icon, label, more] as [NSView] { addSubview(view) }
        chevron.opacity = 0
        layer?.addSublayer(chevron)
    }

    /// False for a blank window's "This Window" header: no Pinned to collapse, no space menu.
    private var interactive = true

    func render(_ space: SpaceSnapshot, palette: Palette, interactive: Bool = true) {
        if space == self.space, palette == self.palette, interactive == self.interactive { return }
        // Another Space's strip (the column switched Spaces): Arc's belongs to its page, so nothing of it moves.
        if space.id != self.space?.id { shownExpanded = nil; shownPill = nil; shownCollapsed = nil }
        self.space = space
        self.palette = palette
        self.interactive = interactive
        // The default Space stays light on a Mac in Dark; its darker surface made the 45% name read below 3:1.
        let color = palette.color(palette.tokens.foregroundStrong).withAlphaComponent(0.5)
        label.stringValue = space.title
        label.textColor = color
        icon.render(IconContent(space: space.icon, color: RGBA(0, 0, 0, 0)), tint: color)
        paintChevron(palette.ink.secondary)
        turnChevron(collapsed: space.pinned.collapsed)
        more.render(.more, size: Draw.navGlyph.value, palette: palette, radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
        toolTip = space.pinned.collapsed ? SidebarCopy.expandPinned : SidebarCopy.collapsePinned
        stateChanged()
        needsLayout = true
    }

    /// The chevron shows, and the name starts after it, while hovered and while Pinned is collapsed; the pill and
    /// "…" only while hovered (Arc, Q18-collapse-b and -c). Never on a blank window's header.
    private var expanded: Bool { interactive && (isHovered || space?.pinned.collapsed == true) }
    private var pillShown: Bool { interactive && isHovered }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: 0)
        background.frame = CGRect(x: g.selection.minX, y: 0, width: g.selection.width, height: bounds.height)
        icon.frame = g.icon
        let size = Draw.spaceChevron.value + 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chevron.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        chevron.position = CGPoint(x: g.icon.midX, y: bounds.midY)
        chevron.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        more.frame = g.button
        let hasIcon = space?.icon != SpaceIcon.none
        let start = expanded || hasIcon ? g.titleX : g.selection.minX + Draw.spaceHeaderLeading.value
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: start, y: (bounds.height - height) / 2, width: max(0, (pillShown ? more.frame.minX : g.selection.maxX) - start), height: height)
    }

    override func stateChanged() {
        guard let palette else { return }
        let shown = expanded, pill = pillShown
        background.layer?.backgroundColor = palette.color(isPressed ? palette.tokens.tabPressed : palette.tokens.itemBackground).cgColor
        let live = window != nil
        // Arc (bin:0x1001c66c4, 0x1001c7910): the chevron fades in as its slot opens and pushes the name over, 0.1 s
        // ease-out; the pill and "…" fade over 0.07 s.
        let ease = CAMediaTimingFunction(name: .easeOut)
        if shown != shownExpanded {
            let animate = live && shownExpanded != nil
            shownExpanded = shown
            fade(chevron, to: shown ? 1 : 0, over: animate ? Draw.spaceHeaderSlide.value : 0)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? Draw.spaceHeaderSlide.value : 0
                context.timingFunction = ease
                context.allowsImplicitAnimation = animate
                icon.animator().alphaValue = shown || space?.icon == SpaceIcon.none ? 0 : 1
                needsLayout = true
                layoutSubtreeIfNeeded()
            }
        }
        if pill != shownPill {
            let animate = live && shownPill != nil
            shownPill = pill
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? Draw.spaceHeaderPillFade.value : 0
                context.timingFunction = ease
                background.animator().alphaValue = pill ? 1 : 0
                more.animator().alphaValue = pill ? 1 : 0
            }
        }
        needsLayout = true
    }

    private func fade(_ target: CALayer, to opacity: Float, over duration: Double) {
        let from = (target.presentation() ?? target).opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.opacity = opacity
        CATransaction.commit()
        guard duration > 0 else { target.removeAnimation(forKey: "brk.fade"); return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        target.add(animation, forKey: "brk.fade")
    }

    private func paintChevron(_ tint: NSColor) {
        guard tint != chevronTint, let glyph = Glyph.chevronDown.image(size: Draw.spaceChevron.value, weight: .semibold) else { return }
        chevronTint = tint
        let size = Draw.spaceChevron.value + 2
        let painted = NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            let box = CGRect(x: (rect.width - glyph.size.width) / 2, y: (rect.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: box)
            tint.set()
            box.fill(using: .sourceAtop)
            return true
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chevron.contents = painted
        CATransaction.commit()
    }

    /// Down while Pinned is open, turned a quarter to the right while it is closed; a change turns it over
    /// `Draw.spaceHeaderSlide`, ease-out, from wherever it is.
    private func turnChevron(collapsed: Bool) {
        guard collapsed != shownCollapsed else { return }
        let animate = window != nil && shownCollapsed != nil
        shownCollapsed = collapsed
        // A quarter turn counterclockwise on screen: in a flipped layer that is a negative angle.
        let flipped = chevron.superlayer?.contentsAreFlipped() ?? true
        let angle = collapsed ? (flipped ? -1.0 : 1.0) * .pi / 2 : 0
        let from = (chevron.presentation() ?? chevron).value(forKeyPath: "transform")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chevron.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
        guard animate else { chevron.removeAnimation(forKey: "brk.turn"); return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = from
        animation.toValue = chevron.transform
        animation.duration = Draw.spaceHeaderSlide.value
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        chevron.add(animation, forKey: "brk.turn")
    }

    /// Control-click is the right-click, as on the rows.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        if interactive { isPressed = true }
    }

    override func mouseUp(with event: NSEvent) {
        let pressed = isPressed
        isPressed = false
        if pressed, interactive, bounds.contains(local(event)) { dispatch(.space(.togglePinnedSection(.current))) }
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
