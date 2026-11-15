import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. Dragging rows and favorites with plain pointer events (no NSDraggingSession: nothing leaves the
/// window). A press becomes a drag after `Draw.dragThreshold`; the item's image follows the pointer; the target under the
/// pointer shows where it lands; release dispatches one move or split command. The press itself has already opened the
/// item (`SidebarPress`, Arc: Q13-press-*), so the dragged tab is the current one, except over the page: there Arc shows
/// what the window showed before the press again, because that is the tab the drop would split with (P23-d, Q13-e).
/// Released on the Favorites grid, the image glides on into its cell and the tile shows when it gets there (`land`).
///
/// Targets, in the order they are tested:
/// - the page: a slot or a frame (`PageDropRule`);
/// - the favorites tray: the cell under the pointer in the grid laid out with the item in it (`FavoritesGrid.dropTarget`);
/// - the Space name strip: the top of Pinned (Q13-g/h);
/// - a dock space cell: `.space(id)`;
/// - the tab list: first `TablistLayout.splitTarget`, the middle band of another tab or split row, where a tab joins it
///   in a split (the half under the pointer on a tab, the whole row on a split, Q15; the release sends
///   `.split(.joinRow)`); else
///   `TablistLayout.dropTarget` (the same `Placement.canPlace` the reducer applies). It sees row frames, not which
///   item is dragged, so its index counts the attached list; the dragged item's own slot is removed here
///   (`Destination` counts children after the item is detached), and drops into the item itself or its own subtree
///   are refused.
///
/// While a drag is over the grid or a favorite is on the move the grid shows a `FavoritesDrag`: SidebarView lays the
/// column out with it (`FavoritesGrid.applying`), and the hit tests read those same frames.
///
/// A press on a row of a Cmd/Shift-click selection of several rows carries them all (`SidebarPress.carried`; Arc 1.170,
/// probed 2026-11-15, ~/brk-evidence/multi-drag/README.md). The image is a stack of their rows with a count badge
/// (`DragStack`); the rows stay where they are; the same targets take the drop, each by one command: a list slot, a
/// folder, the Favorites grid (one empty cell opens) and the Space name strip move them all there in sidebar order
/// (`BulkTabAction.move`); a dock space moves them to that space; the middle of another tab row makes one split
/// (`SplitCommand.joinRows`), tabs only and while the panes fit. The page takes none (Arc shows no slot); a drop nothing
/// took ends the selection.
@MainActor
final class DragController {
    struct Item: Equatable {
        let id: ItemID
        let kind: ItemKind
        let section: SectionKind
    }

    /// What hit testing reads, refreshed on every render.
    struct Context {
        var space: SpaceSnapshot
        var favorites: FavoritesSnapshot
        /// The column as drawn now, with the grid's drag layout.
        var frames: SidebarFrames
        /// The tab the window shows (the focused pane): what a press remembers.
        var shown: ItemID?
        /// The strip takes drops only over a space's own Pinned (not a blank or incognito window's list).
        var spaceHeaderDrops: Bool
    }

    private enum Target: Equatable {
        case favorites(index: Int)
        case list(Destination, point: CGPoint)
        case dock(SpaceID)
        case content(Command)
        /// Makes or grows a split with this row.
        case split(SplitJoin)
        case spaceHeader

        var destination: Destination? {
            switch self {
            case .favorites, .content, .split, .spaceHeader: nil
            case .list(let destination, _): destination
            case .dock(let space): .space(space)
            }
        }
    }

    private struct Press {
        let item: Item
        /// Everything the drag carries when the press was on a row of a selection of several rows, in the selection's
        /// order; empty for a drag of `item` alone.
        let group: [Item]
        let source: NSView
        /// Where the press was, in window coordinates.
        let start: CGPoint
        /// What the window showed before this press opened the item.
        let shownBefore: ItemID?
    }

    private final class Session {
        let press: Press
        let preview: any DragFollowing
        /// Arc's drag card over the content (P23-d, Q13-e); nil for anything but a tab.
        let card: ContentDragCard?
        /// The pointer's place in the card, as fractions: a drag keeps it when its image changes size. A row counts the
        /// sidebar's whole width (Arc's row spans it: pressed at 86 of 228 the card's left is 64 of 169 and 43 of 113 back from
        /// the pointer, Q17-zone-straight-x1100, Q17-split-hold), a tile its own.
        let cardGrab: CGPoint
        var target: Target?
        var overContent = false
        var item: Item { press.item }
        var group: [Item]? { press.group.count > 1 ? press.group : nil }

        init(press: Press, preview: any DragFollowing, card: ContentDragCard?, cardGrab: CGPoint) {
            self.press = press
            self.preview = preview
            self.card = card
            self.cardGrab = cardGrab
        }
    }

    private let dispatch: Dispatch
    weak var sidebar: SidebarView?
    var context: Context?
    /// Advanced > "Haptic feedback when reordering tabs": a tick each time the drop slot under the pointer changes.
    var hapticsEnabled = true
    var haptic: @MainActor () -> Void = { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    private var pressed: Press?
    private var session: Session?
    private var escapeMonitor: Any?
    private var cancelledPress = false
    /// The image of the last drop on the grid, still gliding to its cell.
    private var landing: DragImage?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
    }

    var isActive: Bool { session != nil }
    /// The item pressed or being dragged: its row keeps its view while the list scrolls (TablistView places only rows near view).
    var heldItem: ItemID? { session?.press.item.id ?? pressed?.item.id }

    /// Mouse down on a row or tile: remember it; it becomes a drag once the pointer travels far enough. Called before
    /// the press opens the item, so `shownBefore` is still the tab it replaces. `group`: every item the drag carries
    /// (`item` among them) when it is a selection of several rows.
    func press(_ item: Item, group: [Item] = [], source: NSView, event: NSEvent) {
        endLanding()
        cancelledPress = false
        pressed = Press(item: item, group: group.count > 1 ? group : [], source: source, start: event.locationInWindow, shownBefore: context?.shown)
        session = nil
    }

    /// Mouse dragged. True once the press has become a drag (the caller drops its pressed look and its click).
    @discardableResult
    func drag(_ event: NSEvent) -> Bool {
        if session == nil {
            guard let pressed, hypot(event.locationInWindow.x - pressed.start.x, event.locationInWindow.y - pressed.start.y) >= Draw.dragThreshold.value
            else { return false }
            begin(pressed)
        }
        guard let session, let sidebar, let context else { return session != nil }
        let local = session.preview.superview?.convert(event.locationInWindow, from: nil) ?? sidebar.convert(event.locationInWindow, from: nil)
        let root = sidebar.rootPoint(fromWindow: event.locationInWindow)
        if context.frames.tablistViewport.contains(root) { sidebar.tablist.autoScroll(at: root, frames: context.frames) }
        updateShownTab(session, over: root, frames: context.frames)
        guard self.session === session, let current = self.context else { return true }
        let previous = session.target
        session.target = target(at: root, session: session, context: current)
        // The grid's new layout moves what is under the pointer: read the target again from the frames now drawn. A
        // grown tray still holds the pointer and a shrunk one still does not, so this settles at once.
        let grid = gridDrag(session.target, item: session.item, context: current)
        if grid != sidebar.favoritesDrag {
            sidebar.setFavoritesDrag(grid)
            guard self.session === session, let moved = self.context else { return true }
            session.target = target(at: root, session: session, context: moved)
        }
        guard let latest = self.context else { return true }
        // Over the Max panel the row follows the pointer, as over the sidebar: the page's card would hide the input.
        let overPanel = if case .content(.assist(.attach))? = session.target { true } else { false }
        if let card = session.card {
            if session.overContent, let size = sidebar.contentDropCardSize?() { card.fit(size) }
            card.place(at: local, grab: session.cardGrab)
            card.isHidden = !session.overContent || overPanel
        }
        // Over the page the card stands for the drag.
        session.preview.isHidden = session.overContent && !overPanel
        session.preview.place(shape(session.target, item: session.item, context: latest), pointer: local)
        if hapticsEnabled, session.target?.destination != nil, session.target?.destination != previous?.destination { haptic() }
        show(session.target, session: session, context: latest)
        return true
    }

    /// Mouse up. True when a drag ended here (the caller must not treat the release as a click).
    func release(_ event: NSEvent) -> Bool {
        pressed = nil
        if cancelledPress { cancelledPress = false; return true }
        guard let session else { return false }
        if let sidebar, let context {
            session.target = target(at: sidebar.rootPoint(fromWindow: event.locationInWindow), session: session, context: context)
        }
        if let group = session.group {
            releaseGroup(session, group.map(\.id))
            return true
        }
        var lands = false, settles = false
        if case .favorites? = session.target { lands = true }
        if case .list? = session.target, !session.preview.isHidden { settles = true }
        // The grid goes from its drag layout straight to the document's new one, so the command comes before any render.
        finish(session, keepsImage: lands || settles)
        if lands { sidebar?.favorites.arriving = session.item.id }
        switch session.target {
        case .content(let command)?: dispatch(command)
        case .split(let join)?: dispatch(.split(.joinRow(session.item.id, onto: join.target, at: join.paneIndex)))
        case .favorites(let index)?:
            if let root = context?.favorites.root { dispatch(.item(.move(session.item.id, to: .into(parent: root, index: index)))) }
        case .spaceHeader?: dispatch(.item(.dropOnSpaceHeader(session.item.id)))
        case let target?:
            if let destination = target.destination { dispatch(.item(.move(session.item.id, to: destination))) }
        case nil:
            break
        }
        sidebar?.renderAfterDrag()
        if lands, let image = session.preview as? DragImage { land(image, on: session.item.id) }
        if settles, let image = session.preview as? DragImage { settle(image, on: session.item.id) }
        return true
    }

    /// The release of a drag of several rows: one command moves them all, so the change is one step, and the move ends
    /// the selection. A drop on the Max panel or one nothing took ends it too, as Arc's does. The image goes at once.
    private func releaseGroup(_ session: Session, _ ids: [ItemID]) {
        finish(session)
        let bulk = { (destination: Destination) in self.dispatch(.tabTools(.bulk(.items(ids), .move(destination)))) }
        switch session.target {
        case .content(let command)?:
            dispatch(command)
            dispatch(.tabTools(.clearSelection))
        case .split(let join)?: dispatch(.split(.joinRows(ids, onto: join.target, at: join.paneIndex)))
        case .favorites(let index)?:
            if let root = context?.favorites.root { bulk(.into(parent: root, index: index)) }
        case .spaceHeader?:
            if let root = context?.space.pinned.root { bulk(.into(parent: root, index: 0)) }
        case let target?:
            if let destination = target.destination { bulk(destination) }
        case nil:
            dispatch(.tabTools(.clearSelection))
        }
        sidebar?.renderAfterDrag()
    }

    /// A drop in the tab list (Arc's dragging session slides its image to the destination, recorded 2026-11-13): the image
    /// glides from where it was let go onto the row's new place over `Draw.dropLanding`, ease-out, while the other rows
    /// slide aside; the row shows when it arrives.
    private func settle(_ image: DragImage, on id: ItemID) {
        landing = image
        guard let tablist = sidebar?.tablist, let row = tablist.rowView(id), let host = image.superview else { return endLanding() }
        let card = RowGeometry(bounds: row.bounds, depth: row.depth).selection
        let end = host.convert(card, from: row)
        tablist.arriving = id
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Draw.dropLanding.value
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            image.animator().frame = end
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.landing === image { self?.endLanding() } }
        })
    }

    /// A drop on the grid (Arc, Q21): the image glides from where it was let go into the tile's cell over `Draw.dropLanding`,
    /// and only then does the tile show there. A drop the grid did not take has no cell: the image just goes.
    private func land(_ image: DragImage, on id: ItemID) {
        landing = image
        guard let favorites = sidebar?.favorites, let cell = favorites.cell(of: id), let host = image.superview else { return endLanding() }
        let end = host.convert(cell, from: favorites)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Draw.dropLanding.value
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            image.animator().frame = end
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.landing === image { self?.endLanding() } }
        })
    }

    /// The image is in its cell, or something else took over (a new press, the sidebar going away): the tile shows.
    func endLanding() {
        landing?.removeFromSuperview()
        landing = nil
        sidebar?.favorites.arriving = nil
        sidebar?.tablist.arriving = nil
    }

    /// Ends a drag without moving anything (the sidebar went away under it).
    func cancel() {
        endLanding()
        if pressed != nil || session != nil { cancelledPress = true }
        pressed = nil
        if let session {
            finish(session)
            sidebar?.renderAfterDrag()
        }
    }

    // MARK: Session

    private func begin(_ press: Press) {
        guard let sidebar, let palette = sidebar.currentPalette else { return }
        if press.group.count > 1 { return beginGroup(press, sidebar: sidebar, palette: palette) }
        let source = press.source, item = press.item
        sidebar.beginContentDrop?(item.id)
        // The image is the item at rest: no pressed fill.
        (source as? HoverView)?.setHovered(false)
        (source as? HoverView)?.isPressed = false
        let row = source as? RowView
        // A tab or split stays in its place on the selected card with its × (Q13-a, Q13-g, P23-d); the image has the ×
        // too. A folder has no such look in any reference, and keeps the dimmed row.
        if item.kind != .folder { row?.dragLifted = true }
        let tab: TabRow? = if case .tab(let tab)? = row?.row { tab } else { (source as? FavoriteTileView)?.shownRow }
        let host = sidebar.superview ?? sidebar
        let preview = DragImage(source: source, tab: tab, listWidth: context.map { Double($0.frames.frame.width) } ?? Metrics.sidebar.resetWidth.value, palette: palette)
        host.addSubview(preview)
        let cardRect = row.map { RowGeometry(bounds: $0.bounds, depth: $0.depth).selection } ?? source.bounds
        let at = source.convert(press.start, from: nil)
        preview.grab = CGPoint(x: (at.x - cardRect.minX) / max(cardRect.width, 1), y: (at.y - cardRect.minY) / max(cardRect.height, 1))
        var card: ContentDragCard?
        if let tab, item.kind == .tab {
            let made = ContentDragCard(tab: tab, palette: palette)
            made.isHidden = true
            host.addSubview(made)
            card = made
        }
        let cardGrab = row == nil ? preview.grab : CGPoint(x: sidebar.convert(press.start, from: nil).x / max(sidebar.bounds.width, 1), y: preview.grab.y)
        session = Session(press: press, preview: preview, card: card, cardGrab: cardGrab)
        if item.kind == .folder { row?.dragSource = true }
        // A favorite's own cell is empty for the whole drag (Q13-c, Q13-d).
        if row == nil { source.alphaValue = 0 }
        watchEscape()
    }

    /// A drag of several rows: the rows stay as they are (Arc keeps them in place, still selected); the stack follows the
    /// pointer with the tab that was current when the selection began on top (the selection's first), the others behind
    /// it in sidebar order.
    private func beginGroup(_ press: Press, sidebar: SidebarView, palette: Palette) {
        let order = Self.sidebarOrder(context?.space)
        let top = press.group.first { $0.id == context?.shown } ?? press.group[0]
        let rest = press.group.filter { $0.id != top.id }.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        let shown = context?.shown
        let all = (context?.space.pinned.rows ?? []) + (context?.space.today.rows ?? [])
        let cards = ([top] + rest).prefix(Draw.dragStackCards.value).map { item -> DragStack.Card in
            // A row scrolled out of view has no view to picture: a tab's is drawn from its row, as a Favorite's is.
            if let view = sidebar.tablist.rowView(item.id) {
                return DragStack.Card(image: view.dragImage(), rowSize: view.bounds.size, current: item.id == shown)
            }
            let size = press.source.bounds.size
            guard case .tab(let tab)? = TablistView.find(item.id, in: all) else { return DragStack.Card(image: nil, rowSize: nil, current: item.id == shown) }
            return DragStack.Card(image: DragRowImage.make(tab: tab, size: size, in: press.source, palette: palette), rowSize: size, current: item.id == shown)
        }
        let listWidth = context.map { Double($0.frames.frame.width) } ?? Metrics.sidebar.resetWidth.value
        let stack = DragStack(cards: Array(cards), count: press.group.count, listWidth: listWidth, palette: palette)
        (sidebar.superview ?? sidebar).addSubview(stack)
        session = Session(press: press, preview: stack, card: nil, cardGrab: .zero)
        watchEscape()
    }

    private func watchEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Key.escape.code, self?.isActive == true else { return event }
            self?.cancel()
            return nil
        }
    }

    /// Each row's place in the sidebar, top to bottom (folders' rows after their folder).
    private static func sidebarOrder(_ space: SpaceSnapshot?) -> [ItemID: Int] {
        var order: [ItemID: Int] = [:]
        func walk(_ rows: [Row]) {
            for row in rows {
                order[row.id] = order.count
                if case .folder(let folder) = row { walk(folder.children) }
            }
        }
        walk(space?.pinned.rows ?? [])
        walk(space?.today.rows ?? [])
        return order
    }

    /// Clears everything the drag drew, but for the image when it goes on to a cell (`land`). The grid's drag layout goes
    /// too, but nothing is rendered yet: the caller sends its command first and then `SidebarView.renderAfterDrag`.
    private func finish(_ session: Session, keepsImage: Bool = false) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        sidebar?.endContentDrop?()
        if !keepsImage { session.preview.removeFromSuperview() }
        session.card?.removeFromSuperview()
        let source = session.press.source
        (source as? RowView)?.dragSource = false
        (source as? RowView)?.dragLifted = false
        source.alphaValue = 1
        sidebar?.clearFavoritesDrag()
        if let context { show(nil, session: session, context: context) }
        self.session = nil
    }

    /// Past the sidebar the window shows again what it showed before the press, with the row lifted in place (P23-d, Q13-e);
    /// back in the sidebar the dragged tab is the current one again.
    private func updateShownTab(_ session: Session, over root: CGPoint, frames: SidebarFrames) {
        guard session.card != nil else { return }
        let over = !frames.frame.contains(root)
        guard over != session.overContent else { return }
        session.overContent = over
        if let before = session.press.shownBefore, before != session.item.id { dispatch(.tab(.focus(over ? before : session.item.id))) }
    }

    // MARK: Targets

    private func target(at root: CGPoint, session: Session, context: Context) -> Target? {
        if let group = session.group { return groupTarget(at: root, pressed: session.item, group: group, context: context) }
        let item = session.item
        guard let sidebar else { return nil }
        // The Max panel lies over the page; nothing of Arc's drop rules changes where it is not.
        if let command = sidebar.panelDrop?(item.id, item.kind, root) { return .content(command) }
        if item.kind == .tab, let command = sidebar.contentDrop?(item.id, root) { return .content(command) }
        let f = context.frames
        // The strip above an empty, hint-less tray is the way in (`FavoritesGrid.emptyDropZone`), in a space's own window only.
        let wayIn = context.spaceHeaderDrops && FavoritesGrid.emptyDropZone(frames: f, favorites: context.favorites)?.contains(root) == true
        if f.favoritesTray.contains(root) || wayIn {
            guard case .into(_, let index)? = FavoritesGrid.dropTarget(at: root, frames: f, favorites: context.favorites, dragging: item.kind, item: item.id) else { return nil }
            return .favorites(index: index)
        }
        if f.spaceHeader.contains(root) {
            return context.spaceHeaderDrops && Placement.canPlace(item.kind, inSection: .pinned, parentKind: .section) ? .spaceHeader : nil
        }
        if let space = f.dockSpaces.first(where: { $0.value.contains(root) })?.key { return .dock(space) }
        guard f.tablistViewport.contains(root) else { return nil }
        let point = sidebar.tablist.documentPoint(fromRoot: root, frames: f)
        if let join = TablistLayout.splitTarget(at: point, rows: f.rows, space: context.space, dragging: item.kind, from: item.section, item: item.id) {
            return .split(join)
        }
        guard let raw = TablistLayout.dropTarget(at: point, rows: f.rows, space: context.space, dragging: item.kind),
              let destination = Self.detached(raw, dragging: item.id, in: context.space) else { return nil }
        return .list(destination, point: point)
    }

    /// Where a drag of several rows lands (Arc 1.170, 2026-11-15): the targets of a single row, each taking all of them
    /// or none. The page takes none: Arc shows no slot there and the drop changes nothing.
    private func groupTarget(at root: CGPoint, pressed: Item, group: [Item], context: Context) -> Target? {
        guard let sidebar else { return nil }
        // The Max panel takes the whole selection (WindowRootView reads it through `SidebarView.dragGroup`).
        if let command = sidebar.panelDrop?(pressed.id, pressed.kind, root) { return .content(command) }
        let f = context.frames
        let kinds = Set(group.map(\.kind))
        let wayIn = context.spaceHeaderDrops && FavoritesGrid.emptyDropZone(frames: f, favorites: context.favorites)?.contains(root) == true
        if f.favoritesTray.contains(root) || wayIn {
            guard kinds.allSatisfy({ Placement.canPlace($0, inSection: .favorites, parentKind: .section) }),
                  case .into(_, let index)? = FavoritesGrid.dropTarget(at: root, frames: f, favorites: context.favorites, dragging: .tab, item: pressed.id) else { return nil }
            return .favorites(index: index)
        }
        if f.spaceHeader.contains(root) {
            return context.spaceHeaderDrops && kinds.allSatisfy({ Placement.canPlace($0, inSection: .pinned, parentKind: .section) }) ? .spaceHeader : nil
        }
        if let space = f.dockSpaces.first(where: { $0.value.contains(root) })?.key { return .dock(space) }
        guard f.tablistViewport.contains(root) else { return nil }
        let point = sidebar.tablist.documentPoint(fromRoot: root, frames: f)
        let ids = Set(group.map(\.id))
        if kinds == [.tab], let join = Self.groupSplitTarget(at: point, rows: f.rows, space: context.space, pressed: pressed.id, group: group, ids: ids) {
            return .split(join)
        }
        var raw: Destination?
        for kind in kinds {
            guard let place = TablistLayout.dropTarget(at: point, rows: f.rows, space: context.space, dragging: kind), raw == nil || raw == place else { return nil }
            raw = place
        }
        guard let raw, let destination = Self.detached(raw, dragging: ids, in: context.space) else { return nil }
        return .list(destination, point: point)
    }

    /// The middle of another tab or split row takes several tabs when each could join it alone and the panes fit.
    private static func groupSplitTarget(at point: CGPoint, rows: [RowFrame], space: SpaceSnapshot, pressed: ItemID, group: [Item], ids: Set<ItemID>) -> SplitJoin? {
        var found: SplitJoin?
        for section in Set(group.map(\.section)) {
            guard let join = TablistLayout.splitTarget(at: point, rows: rows, space: space, dragging: .tab, from: section, item: pressed),
                  found == nil || found == join else { return nil }
            found = join
        }
        guard let join = found, !ids.contains(join.target) else { return nil }
        let panes: Int
        switch join {
        case .tab: panes = 1
        case .split(let id, _):
            guard case .split(let split)? = TablistView.find(id, in: space.pinned.rows + space.today.rows) else { return nil }
            panes = split.panes.count
        }
        return panes + group.count <= Metrics.content.maxPanes.value ? join : nil
    }

    /// `TablistLayout.dropTarget`'s index counts the list as drawn, with the dragged item still in it; `Destination`
    /// counts after the item is detached. Nil for a drop into the dragged item or anything inside it.
    static func detached(_ destination: Destination, dragging id: ItemID, in space: SpaceSnapshot) -> Destination? {
        detached(destination, dragging: [id], in: space)
    }

    /// The same for several rows: the index counts the parent's rows that are not dragged (`BulkTabAction.move` takes
    /// them out first). Nil for a drop into any dragged row or anything inside one.
    static func detached(_ destination: Destination, dragging ids: Set<ItemID>, in space: SpaceSnapshot) -> Destination? {
        guard case .into(let parent, var index) = destination else { return destination }
        guard let path = path(to: parent, in: space), !path.contains(where: ids.contains) else { return nil }
        let siblings: [Row]? = if parent == space.pinned.root { space.pinned.rows }
            else if parent == space.today.root { space.today.rows }
            else if case .folder(let folder)? = TablistView.find(parent, in: space.pinned.rows + space.today.rows) { folder.children }
            else { nil }
        if let siblings { index -= siblings.prefix(max(0, index)).filter { ids.contains($0.id) }.count }
        return .into(parent: parent, index: index)
    }

    /// `parent` and the folders it sits in, innermost first; a section root alone. Nil when it is not in the space.
    private static func path(to parent: ItemID, in space: SpaceSnapshot) -> [ItemID]? {
        if parent == space.pinned.root || parent == space.today.root { return [parent] }
        func search(_ rows: [Row], _ above: [ItemID]) -> [ItemID]? {
            for row in rows {
                guard case .folder(let folder) = row else { continue }
                if folder.id == parent { return [parent] + above }
                if let hit = search(folder.children, [folder.id] + above) { return hit }
            }
            return nil
        }
        return search(space.pinned.rows + space.today.rows, [])
    }

    /// What the grid shows for a drag at `target`: a new tile's or a reorder's empty cell over the tray; outside it a
    /// favorite's own cell stays empty and a tab from the list changes nothing.
    private func gridDrag(_ target: Target?, item: Item, context: Context) -> FavoritesDrag? {
        let favorite = context.favorites.tiles.contains { $0.id == item.id }
        if case .favorites(let index)? = target { return favorite ? .reordering(item.id, slot: index) : .incoming(slot: index) }
        return favorite ? .leaving(item.id) : nil
    }

    /// The image for a drag at `target`: over the grid a tile of the grid's size for the new count; elsewhere a row, a little
    /// smaller on the Space name strip (Q13-g: 186 x 31 for the 212 x 36 row).
    private func shape(_ target: Target?, item: Item, context: Context) -> DragImage.Shape {
        switch target {
        case .favorites?:
            let count = context.favorites.tiles.count + (context.favorites.tiles.contains { $0.id == item.id } ? 0 : 1)
            return .tile(FavoritesGrid.tileSize(count: count, width: context.frames.favoritesTray.width))
        case .spaceHeader?: return .row(scale: Draw.dragRowOverHeaderScale.value)
        default: return .row(scale: 1)
        }
    }

    private func show(_ target: Target?, session: Session, context: Context) {
        guard let sidebar else { return }
        let f = context.frames
        if case .favorites? = target { sidebar.favorites.showEmptyDrop(true) } else { sidebar.favorites.showEmptyDrop(false) }
        sidebar.spaceHeader.dropHighlighted = target == .spaceHeader
        if case .list(let destination, let point)? = target {
            let dragging = Set((session.group ?? [session.item]).map(\.id))
            sidebar.tablist.showDrop(destination, dragging: dragging, at: point, frames: f, space: context.space)
        } else {
            sidebar.tablist.showDrop(nil, dragging: [], at: nil, frames: f, space: context.space)
        }
        if case .dock(let space)? = target { sidebar.dock.showDrop(space: space) } else { sidebar.dock.showDrop(space: nil) }
        if case .split(let join)? = target { sidebar.tablist.showSplitJoin(join, frames: f) } else { sidebar.tablist.showSplitJoin(nil, frames: f) }
    }
}

/// What follows the pointer in the sidebar: the row (Q13-d, Q13-g) or, over the grid, a raised tile of the grid's size
/// (Q13-a, Q13-c). A tile from a row has no ring; a Favorite's own tile keeps the current tile's rim, since the press opened
/// it: the icon's colors, light around Wikipedia's in Q13-c and dark grey around MDN's in Q21. The pointer stays at the same fraction of the image as it was of the item it pressed (Q13-a's tile: 24.5 of 65
/// in from the left, pressed 0.37 along the row; Q13-d's row: centred, pressed in a tile's middle).
@MainActor
final class DragImage: NSView {
    enum Shape: Equatable {
        case row(scale: Double)
        case tile(CGSize)
    }

    /// The pointer's place in the image, as fractions of its width and height.
    var grab = CGPoint(x: 0.5, y: 0.5)
    private let rowImage = NSImageView()
    private let rowCard = NSView()
    private let rowSize: CGSize
    /// The row's own image rect, relative to the image at full size (the row is wider than its card).
    private let rowImageFrame: CGRect
    private let icon = IconView()
    private let ring = CAShapeLayer()
    private let ringed: Bool
    /// The tile's own rim (`FavoriteTileView`): the icon's picture through the ring's line.
    private let rim = CALayer()
    private let rimMask = CAShapeLayer()
    private let rimPicture: CGImage?
    private let trayWidth: Double
    private var shape: Shape?
    /// A tile fills this view; a row fills `rowCard`, which also casts the row's shadow line.
    private let fill: CGColor

    /// `listWidth`: the width of the list's rows, for a Favorite's row image.
    init(source: NSView, tab: TabRow?, listWidth: Double, palette: Palette) {
        let row = source as? RowView
        let bounds = row?.bounds ?? CGRect(x: 0, y: 0, width: listWidth, height: Metrics.tablist.rowHeight.value)
        // An indented row (inside a folder or group) lifts as the card it draws, its own selection.
        let card = RowGeometry(bounds: bounds, depth: row?.depth ?? 0).selection
        rowSize = card.size
        rowImageFrame = bounds.offsetBy(dx: -card.minX, dy: -card.minY)
        let tile = source as? FavoriteTileView
        ringed = tile?.hasIcon == true && tab?.status == .current
        rimPicture = tile?.rimPicture
        trayWidth = tile?.trayWidth ?? 0
        fill = palette.color(palette.tokens.tabCurrent).cgColor
        super.init(frame: CGRect(origin: .zero, size: rowSize))
        wantsLayer = true
        alphaValue = Draw.dragPreviewAlpha.value
        if let layer {
            layer.cornerCurve = .continuous
            layer.cornerRadius = Metrics.tablist.selectionRadius.value
        }
        // AppKit owns a layer-backed view's shadow: set on the layer it never shows. The offset is not flipped, so negative is down.
        let soft = NSShadow()
        soft.shadowColor = NSColor.black.withAlphaComponent(Draw.dragPreviewShadowOpacity.value)
        soft.shadowBlurRadius = Draw.dragPreviewShadow.value
        soft.shadowOffset = CGSize(width: 0, height: -Draw.dragPreviewShadowOffset.value)
        shadow = soft
        // A row image keeps the selected row's own shadow line under it (Q15-a: darkest right under the row); a tile has none.
        rowCard.wantsLayer = true
        rowCard.layer?.backgroundColor = palette.color(palette.tokens.tabCurrent).cgColor
        rowCard.layer?.cornerCurve = .continuous
        rowCard.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        let line = NSShadow()
        line.shadowColor = palette.color(palette.tokens.tabShadow)
        line.shadowBlurRadius = Draw.selectedShadowRadius.value
        line.shadowOffset = CGSize(width: 0, height: -Draw.selectedShadowOffset.value)
        rowCard.shadow = line
        addSubview(rowCard)
        rowImage.imageScaling = .scaleAxesIndependently
        rowImage.image = row?.dragImage() ?? tab.flatMap { DragRowImage.make(tab: $0, size: rowImageFrame.size, in: source, palette: palette) }
        addSubview(rowImage)
        if let tab { icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette) }
        icon.hidesEmptyFavicon = true
        addSubview(icon)
        ring.fillColor = nil
        ring.strokeColor = palette.color(palette.tokens.separator).cgColor
        ring.lineWidth = Draw.tileRingWidth.value
        ring.opacity = Float(Draw.dragTileRingOpacity.value)
        layer?.addSublayer(ring)
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = Draw.tileRingWidth.value
        rim.mask = rimMask
        rim.contents = rimPicture
        rim.isHidden = true
        layer?.addSublayer(rim)
        identify(.tabTool("drag-image"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Takes `shape` with the pointer at `pointer` (the superview's coordinates).
    func place(_ shape: Shape, pointer: CGPoint) {
        let size: CGSize
        switch shape {
        case .row(let scale): size = CGSize(width: rowSize.width * scale, height: rowSize.height * scale)
        case .tile(let tile): size = tile
        }
        setFrameSize(size)
        setFrameOrigin(CGPoint(x: pointer.x - grab.x * size.width, y: pointer.y - grab.y * size.height))
        guard shape != self.shape else { return }
        self.shape = shape
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch shape {
        case .row(let scale):
            rowImage.isHidden = false
            rowCard.isHidden = false
            rowCard.frame = bounds
            layer?.backgroundColor = nil
            icon.isHidden = true
            ring.isHidden = true
            rim.isHidden = true
            rowImage.frame = CGRect(x: rowImageFrame.minX * scale, y: rowImageFrame.minY * scale, width: rowImageFrame.width * scale, height: rowImageFrame.height * scale)
        case .tile:
            rowImage.isHidden = true
            rowCard.isHidden = true
            layer?.backgroundColor = fill
            icon.isHidden = false
            let side = Draw.tileFavicon.value
            icon.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let m = Metrics.favorites
            ring.frame = bounds
            ring.path = CGPath(roundedRect: bounds.insetBy(dx: m.ringInset.value, dy: m.ringInset.value), cornerWidth: m.ringRadius.value, cornerHeight: m.ringRadius.value, transform: nil)
            ring.isHidden = !ringed || rimPicture != nil
            rim.frame = bounds
            rimMask.frame = bounds
            rimMask.path = ring.path
            rim.contentsRect = FaviconWash.window(tile: size, trayWidth: trayWidth)
            rim.isHidden = !ringed || rimPicture == nil
        }
        CATransaction.commit()
    }
}

/// What follows the pointer: `DragImage` for one item, `DragStack` for several.
@MainActor
protocol DragFollowing: NSView {
    /// Takes `shape` with the pointer at `pointer` (the superview's coordinates).
    func place(_ shape: DragImage.Shape, pointer: CGPoint)
}

extension DragImage: DragFollowing {}

/// What follows the pointer in a drag of several rows (Arc 1.170, 2026-11-15, ~/brk-evidence/multi-drag/README.md): the
/// first rows stacked, the first on top, each next one `Draw.dragStackStep` lower and further right, and a red badge with
/// the count at the stack's top left. The stack hangs below and right of the pointer wherever the row was pressed. The top
/// card is the current tab's white one; the others keep their selected rows' grey. Over the Favorites grid the cards are
/// blank tiles of the grid's size; over the Space name strip, smaller rows.
@MainActor
final class DragStack: NSView, DragFollowing {
    struct Card {
        let image: NSImage?
        /// The row the image was taken from; nil for a card with no image.
        let rowSize: CGSize?
        let current: Bool
    }

    private let cards: [Card]
    private var views: [(card: NSView, shade: NSView, image: NSImageView)] = []
    private let badge = NSView()
    private let label = NSTextField(labelWithString: "")
    private let rowCard: CGSize
    private var shape: DragImage.Shape?

    init(cards: [Card], count: Int, listWidth: Double, palette: Palette) {
        self.cards = cards
        rowCard = RowGeometry(bounds: CGRect(x: 0, y: 0, width: listWidth, height: Metrics.tablist.rowHeight.value), depth: 0).selection.size
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = Draw.dragPreviewAlpha.value
        // The last card first, so the first is drawn over the others.
        for card in cards.reversed() {
            let view = NSView(), shade = NSView(), image = NSImageView()
            view.wantsLayer = true
            // The theme's row fills are see-through (a dark theme's very much so): on an opaque card the rows behind do
            // not show through the one in front.
            view.layer?.backgroundColor = palette.dragCardBase.cgColor
            view.layer?.cornerCurve = .continuous
            view.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
            let soft = NSShadow()
            soft.shadowColor = NSColor.black.withAlphaComponent(Draw.dragPreviewShadowOpacity.value)
            soft.shadowBlurRadius = Draw.dragPreviewShadow.value / 2
            soft.shadowOffset = CGSize(width: 0, height: -Draw.dragPreviewShadowOffset.value)
            view.shadow = soft
            shade.wantsLayer = true
            shade.layer?.backgroundColor = palette.color(card.current ? palette.tokens.tabCurrent : palette.tokens.itemHover).cgColor
            shade.layer?.cornerCurve = .continuous
            shade.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
            image.imageScaling = .scaleAxesIndependently
            image.image = card.image
            view.addSubview(shade)
            view.addSubview(image)
            addSubview(view)
            views.insert((view, shade, image), at: 0)
        }
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        label.stringValue = String(count)
        label.font = .systemFont(ofSize: Draw.dragStackBadge.value[0] * 0.65, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        badge.addSubview(label)
        addSubview(badge)
        identify(.tabTool("drag-stack"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func place(_ shape: DragImage.Shape, pointer: CGPoint) {
        let b = Draw.dragStackBadge.value, top = Draw.dragStackCard.value, step = Draw.dragStackStep.value
        let size: CGSize
        switch shape {
        case .row(let scale): size = CGSize(width: rowCard.width * scale, height: rowCard.height * scale)
        case .tile(let tile): size = tile
        }
        let behind = Double(max(cards.count - 1, 0))
        let cardTop = top[1] - b[2]
        setFrameSize(CGSize(width: top[0] + behind * step[0] + size.width, height: max(b[0], cardTop + behind * step[1] + size.height)))
        setFrameOrigin(CGPoint(x: pointer.x + b[1], y: pointer.y + b[2]))
        guard shape != self.shape else { return }
        self.shape = shape
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (k, view) in views.enumerated() {
            view.card.frame = CGRect(x: top[0] + Double(k) * step[0], y: cardTop + Double(k) * step[1], width: size.width, height: size.height)
            view.shade.frame = view.card.bounds
            let card = cards[k]
            if case .row(let scale) = shape, let row = card.rowSize {
                // The row's image keeps its place in the row, which is wider than its card.
                let selection = RowGeometry(bounds: CGRect(origin: .zero, size: row), depth: 0).selection
                view.image.frame = CGRect(x: -selection.minX * scale, y: -selection.minY * scale, width: row.width * scale, height: row.height * scale)
                view.image.isHidden = false
            } else {
                view.image.isHidden = true
            }
        }
        let text = label.intrinsicContentSize
        let width = max(b[0], text.width + b[0] / 2)
        badge.frame = CGRect(x: 0, y: 0, width: width, height: b[0])
        badge.layer?.cornerRadius = b[0] / 2
        label.frame = CGRect(x: 0, y: (b[0] - text.height) / 2, width: width, height: text.height)
        CATransaction.commit()
    }
}

/// A Favorite's row image (Q13-d): the row a tab would draw, its icon and title, with no hover button.
@MainActor
enum DragRowImage {
    static func make(tab: TabRow, size: CGSize, in source: NSView, palette: Palette) -> NSImage? {
        let view = FlippedView(frame: CGRect(origin: .zero, size: size))
        let g = RowGeometry(bounds: view.bounds, depth: 0)
        let icon = IconView(frame: g.icon)
        icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette)
        let title = NSTextField(labelWithString: tab.awaitingFirstDocument ? SidebarCopy.untitled : tab.title)
        title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
        title.textColor = palette.ink.text
        title.lineBreakMode = .byTruncatingTail
        let height = title.intrinsicContentSize.height
        title.frame = g.title(height: height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: view.bounds)
        view.addSubview(icon)
        view.addSubview(title)
        // In the window for a moment, for the window's scale.
        view.alphaValue = 1
        source.superview?.addSubview(view, positioned: .below, relativeTo: source)
        defer { view.removeFromSuperview() }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

extension Palette {
    /// The opaque fill under a drag card: white, or a dark grey in a dark theme.
    var dragCardBase: NSColor { scheme == .dark ? NSColor(white: 0.17, alpha: 1) : .white }
}

/// Arc's drag image while a tab is over the content (P23-d): a white rounded card centred on the pointer, the tab's
/// icon above its title in bold, over a soft shadow (Draw.dragCard*).
@MainActor
final class ContentDragCard: NSView {
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")

    init(tab: TabRow, palette: Palette) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = palette.dragCardBase.cgColor
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Draw.dragCardRadius.value
        let soft = NSShadow()
        soft.shadowColor = NSColor.black.withAlphaComponent(Draw.dragCardShadowOpacity.value)
        soft.shadowBlurRadius = Draw.dragCardShadow.value
        soft.shadowOffset = CGSize(width: 0, height: -3)
        shadow = soft
        icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette)
        title.stringValue = tab.awaitingFirstDocument ? SidebarCopy.untitled : tab.title
        title.font = .systemFont(ofSize: Draw.dragCardTitleFont.value, weight: .bold)
        title.textColor = palette.ink.text
        title.alignment = .center
        title.usesSingleLineMode = false
        title.cell?.wraps = true
        title.cell?.truncatesLastVisibleLine = true
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = Draw.dragCardTitleLines.value
        title.isSelectable = false
        addSubview(icon)
        addSubview(title)
        identify(.tabTool("content-drag-card"))
    }

    /// The card's size follows the panes the page shows (`PageDropRule.cardSize`); the icon and the title stay centred in it.
    func fit(_ size: CGSize) {
        guard size != frame.size else { return }
        setFrameSize(size)
        let side = Draw.dragCardIcon.value, inset = Draw.dragCardInset.value, gap = Draw.dragCardTitleGap.value
        let width = max(size.width - 2 * inset, 0)
        let lines = ceil(title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let top = ((size.height - (side + gap + lines)) / 2).rounded()
        icon.frame = CGRect(x: (size.width - side) / 2, y: top, width: side, height: side)
        title.frame = CGRect(x: inset, y: top + side + gap, width: width, height: lines)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `point` in the superview's coordinates; `grab` is the pointer's place in the card, as fractions.
    func place(at point: CGPoint, grab: CGPoint) {
        setFrameOrigin(CGPoint(x: (point.x - grab.x * bounds.width).rounded(), y: (point.y - grab.y * bounds.height).rounded()))
    }
}
