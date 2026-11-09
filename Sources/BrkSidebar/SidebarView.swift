import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The sidebar column: title row (traffic lights are AppKit's own buttons, placed by the window controller
/// at `SidebarFrames.trafficLightsOrigin`; the sidebar toggle and back/forward/reload are here), URL pill, favorites,
/// the space header, the space's tab list, the dock, and the two edge views (resize handle, reveal strip).
/// Translucent tokens over the themed background; while peeking, the same view is re-framed over the content with
/// its own backdrop.
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`, `focusRenameField`, `focusList`.
/// Everything else in BrkSidebar is internal to W3.
@MainActor
public final class SidebarView: NSView {
    /// Content owns its hit zones. Sidebar supplies only the dragged tab and a root-coordinate pointer.
    public var contentDrop: ((ItemID, CGPoint) -> Command?)?
    /// A drop on the Max panel beside the page (Brk's own): any row, tab, split or folder, becomes this command.
    public var panelDrop: ((ItemID, ItemKind, CGPoint) -> Command?)?
    /// A Space's dock icon dragged onto the Max panel; `panelDropEnded` when such a drag is over.
    public var panelSpaceDrop: ((SpaceID, CGPoint) -> Command?)?
    public var panelDropEnded: (() -> Void)?
    /// The drag card's size for what the page shows now.
    public var contentDropCardSize: (() -> CGSize)?
    public var beginContentDrop: ((ItemID) -> Void)?
    public var endContentDrop: (() -> Void)?
    @discardableResult
    public func cancelDrag() -> Bool {
        let dockCancelled = dock.cancelReorder()
        guard drag.isActive else { return dockCancelled }
        drag.cancel()
        return true
    }
    let dispatch: Dispatch
    let drag: DragController
    private let backdrop = FloatingBackdropView()
    let header: TitleRowView
    let urlPill: URLPillView
    let favorites: FavoritesView
    let spaceHeader: SpaceHeaderView
    let tablist: TablistView
    let dock: DockView
    /// Arc's mini players, between the list and the dock.
    let miniPlayers: MiniPlayerStackView
    /// The edge views straddle or sit outside the column, so they live beside it in the root (installed when this
    /// view moves into a superview) and are framed from `WindowFrames`.
    let resizeHandle: ResizeHandleView
    let revealStrip: RevealStripView
    private var last: Slice?
    /// The last render's input: a drag's grid layout renders the column again from it.
    private var lastRender: (snapshot: WindowSnapshot, frames: WindowFrames, palette: Palette)?
    /// The grid's layout while a drag holds one (DragController). Not in the document.
    private(set) var favoritesDrag: FavoritesDrag?
    private var floatingWatch: FloatingSidebarTracking?
    /// The two-finger swipe (`PageSwipeGesture`, which the AI panel's swipe shares).
    private let gesture = PageSwipeGesture()
    private var canSwipe = false
    /// Where the column stands in the row of pages (`SpacePager`). The header and the rows sit in `strip`, which moves;
    /// `pagesClip` cuts it at the sidebar's edges, and the Favorites sit in it too, moving only at the edge of their group.
    private let pager = SpacePager()
    private let pagesClip = PagesContainerView()
    private let strip = PagesContainerView()
    private lazy var previousPage = SpaceSidePageView(frame: .zero)
    private lazy var nextPage = SpaceSidePageView(frame: .zero)
    private let edgeFeedback = SpaceEdgeFeedbackView(frame: .zero)
    /// The ring is full, since when: lifting 0.1 s after that opens Create a Space.
    private var edgeArmedAt: CFTimeInterval?
    /// The page left by a Space switch, until the move ends; `jumpFrom` says on which side it stands when it is not the
    /// new Space's neighbour in the dock.
    private var outgoing: SpacePage?
    private var jumpFrom: SidebarPage?
    /// A swipe holds the Library: it opened it on its way there or began with it open, and may still come back. The Library
    /// closes when the column settles on a Space.
    private var swipeHoldsLibrary = false
    private var closingLibrary = false
    /// The window's background follows the position: two themes and how far between them; nil when the move is over.
    public var onThemeBlend: ((ResolvedTheme, ResolvedTheme, Double) -> Void)?
    public var onThemeBlendEnded: (() -> Void)?
    /// How far the Library has come in while the column moves toward it, 0...1 (Arc: `LayoutState.transitioning`); nil at rest.
    public var onLibraryProgress: ((Double?) -> Void)?
    private var libraryProgress: Double?
    private var themeBlending = false
    /// The column moves, so the root's crossfade and the Library's own layout wait.
    public var isPaging: Bool { pager.isActive }
    public var isPagingLibrary: Bool { libraryProgress != nil }
    /// The pointer is over the column: Arc then shows the pill's accessories and Today's Clear.
    private var hoverTracking: NSTrackingArea?
    private var pointerInside = false {
        didSet {
            guard pointerInside != oldValue else { return }
            applyColumnHover()
        }
    }
    /// The + popover takes the hover: Arc's column shows neither the accessories nor Clear under it (Q11-a).
    private var plusMenuOpen = false { didSet { applyColumnHover() } }
    private func applyColumnHover() {
        urlPill.sidebarHovered = pointerInside && !plusMenuOpen
        tablist.sidebarHovered = pointerInside && !plusMenuOpen
    }

    /// Everything `render` reads. Equal slices change nothing, so render returns before touching a view.
    struct Slice: Equatable {
        var tools: TabToolsSnapshot
        var sidebar: SidebarSnapshot
        var urlPill: URLPillSnapshot
        var favorites: FavoritesSnapshot
        var space: SpaceSnapshot
        var dock: [DockItem]
        var plusMenu: [[PlusMenuRow]]
        var renaming: ItemID?
        var theme: ResolvedTheme
        var frames: SidebarFrames?
        var floats: Bool
        var resizeHandle: CGRect?
        var revealStrip: CGRect?
        var palette: Palette
        /// The New Tab row looks like the current tab (a blank window with nothing open, or Cmd+T's bar is open).
        var newTabCurrent: Bool
        /// Create a Space is open: its flow takes the column's place.
        var creatingSpace: Bool
        var favoritesDrag: FavoritesDrag?
        var miniPlayers: [MiniPlayerSnapshot]
        var miniPlayerHover: MiniPlayerHover?
        var aiToggle: AIToggleSnapshot?
    }

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        drag = DragController(dispatch: dispatch)
        header = TitleRowView(dispatch: dispatch)
        urlPill = URLPillView(dispatch: dispatch)
        favorites = FavoritesView(dispatch: dispatch, drag: drag)
        spaceHeader = SpaceHeaderView(dispatch: dispatch)
        tablist = TablistView(dispatch: dispatch, drag: drag)
        dock = DockView(dispatch: dispatch)
        miniPlayers = MiniPlayerStackView(dispatch: dispatch)
        resizeHandle = ResizeHandleView(dispatch: dispatch)
        revealStrip = RevealStripView(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [backdrop, header, urlPill, pagesClip, dock, miniPlayers, edgeFeedback] as [NSView] { addSubview(view) }
        pagesClip.clipsToBounds = true
        pagesClip.addSubview(strip)
        pagesClip.addSubview(favorites)
        strip.addSubview(spaceHeader)
        strip.addSubview(tablist)
        pager.host = self
        pager.onMove = { [weak self] in self?.pagerMoved() }
        pager.onSelect = { [weak self] page in self?.pagerSelected(page) }
        pager.onLift = { [weak self] in self?.pagerLifted() }
        pager.onDetent = { [weak self] in
            guard self?.last?.sidebar.hapticsEnabled == true else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        pager.onSettled = { [weak self] in self?.pagerSettled() }
        miniPlayers.onHoverChange = { [weak self] _ in self?.renderAfterDrag() }
        dock.plusMenuChanged = { [weak self] open in self?.plusMenuOpen = open }
        dock.spaceDrop = { [weak self] space, point in self?.panelSpaceDrop?(space, point) }
        dock.spaceDropEnded = { [weak self] in self?.panelDropEnded?() }
        drag.sidebar = self
        identify(.sidebar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { drag.cancel() }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        placeEdgeViews()
    }

    /// The root's view the edge views (resize handle, reveal strip) go above. The content card reaches the sidebar's
    /// edge, so the handle, which straddles that edge, must be over the cards or half of it would be under the page.
    public weak var edgeViewsAbove: NSView? { didSet { placeEdgeViews() } }

    private func placeEdgeViews() {
        guard let superview else { return }
        let anchor = edgeViewsAbove.flatMap { $0.superview === superview ? $0 : nil } ?? self
        superview.addSubview(revealStrip, positioned: .above, relativeTo: anchor)
        superview.addSubview(resizeHandle, positioned: .above, relativeTo: anchor)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFloatingWatch()
            resetSwipe()
            pointerInside = false
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTracking == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    public override func mouseEntered(with event: NSEvent) { pointerInside = true }
    public override func mouseExited(with event: NSEvent) { pointerInside = false }

    public override func viewDidHide() {
        super.viewDidHide()
        pointerInside = false
    }

    /// The root hides this view while the sidebar is hidden; the resize handle beside it goes with it.
    public override var isHidden: Bool {
        didSet { resizeHandle.sidebarHidden = isHidden }
    }

    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, palette: Palette) {
        defer {
            if pager.isActive { renderSidePages() }
            applyPagePosition()
        }
        let before = lastRender?.snapshot
        lastRender = (snapshot, frames, palette)
        syncPager(snapshot, frames: frames, before: before)
        canSwipe = snapshot.kind == .standard && (snapshot.overlay == nil || libraryOpen(snapshot)) && snapshot.dialog == nil && snapshot.pendingSpaceDeletion == nil
        let space = SidebarLayout.space(in: snapshot)
        // A blank or incognito window: no favorites, no space dots, "This Window" or "Incognito Tabs" over its own tabs.
        let thisWindow = SidebarLayout.listsOwnTabs(snapshot.kind)
        let dockItems = thisWindow ? [] : snapshot.dock
        // The New Tab row looks like the current tab in a blank window with nothing open, and while the command bar
        // opens a new tab (Q01-a).
        let creating: Bool = if case .commandBar(let bar)? = snapshot.overlay { bar.createsTab } else { false }
        let newTabCurrent = (thisWindow && snapshot.content.panes.isEmpty) || creating
        let slice = Slice(tools: snapshot.tabTools, sidebar: snapshot.sidebar, urlPill: snapshot.urlPill, favorites: snapshot.favorites, space: space,
                          dock: dockItems, plusMenu: snapshot.plusMenu, renaming: snapshot.renaming, theme: snapshot.theme, frames: frames.sidebar,
                          floats: frames.sidebarFloats, resizeHandle: frames.resizeHandle, revealStrip: frames.revealStrip, palette: palette,
                          newTabCurrent: newTabCurrent, creatingSpace: snapshot.dialog == .newSpace, favoritesDrag: favoritesDrag,
                          miniPlayers: snapshot.miniPlayers, miniPlayerHover: miniPlayers.hover, aiToggle: snapshot.aiToggle)
        guard slice != last else { return }
        let previous = last
        // While a drag changes the grid, and as it ends, the tiles and everything under them slide.
        let sliding = previous != nil && previous?.favoritesDrag != favoritesDrag
        last = slice
        resizeHandle.hapticsEnabled = snapshot.sidebar.hapticsEnabled
        resizeHandle.render(frames.resizeHandle, width: snapshot.sidebar.width, palette: palette)
        revealStrip.render(frames.revealStrip)
        guard let rest = frames.sidebar else {
            isHidden = true
            stopFloatingWatch()
            drag.cancel()
            return
        }
        var f = FavoritesGrid.applying(favoritesDrag, to: rest, favorites: snapshot.favorites)
        if let hover = miniPlayers.hover { f = MiniPlayerLayout.applying(snapshot.miniPlayers.map(\.tab), hover: hover, to: f) }
        isHidden = false
        identify(frames.sidebarFloats ? .floatingSidebar : .sidebar)
        place(f.frame, slideIn: previous != nil && previous?.frames == nil && !pager.isActive)
        pagesClip.frame = bounds
        strip.frame.size = bounds.size
        edgeFeedback.frame = bounds
        backdrop.isHidden = !frames.sidebarFloats
        if frames.sidebarFloats { backdrop.render(snapshot.theme, palette: palette) }
        backdrop.frame = bounds
        let local = { (r: CGRect) in r.offsetBy(dx: -f.frame.minX, dy: -f.frame.minY) }
        header.frame = local(f.titleRow)
        // In a split each pane has its own back, forward and reload (Arc moves them off the title row).
        header.render(snapshot.urlPill, frames: f, toolbar: snapshot.sidebar.toolbarVisible, palette: palette, navigation: snapshot.content.split == nil,
                      ai: snapshot.aiToggle)
        urlPill.frame = local(f.urlPill)
        urlPill.isHidden = f.urlPill.height == 0
        // Any window with no page reads as a search field, a new space's as well (Arc, P24 e).
        urlPill.render(snapshot.urlPill, palette: palette, searchField: true)
        favorites.isHidden = thisWindow
        favorites.frame = local(f.favoritesTray)
        favorites.render(snapshot.favorites, renaming: snapshot.renaming, frames: f, palette: palette, now: snapshot.now, sliding: sliding,
                         lit: snapshot.sidebar.lit)
        spaceHeader.isHidden = !snapshot.sidebar.spaceHeaderVisible
        Slide.place(spaceHeader, at: local(f.spaceHeader), sliding: sliding)
        spaceHeader.render(space, palette: palette, interactive: !thisWindow)
        Slide.place(tablist, at: local(f.tablistViewport), sliding: sliding)
        tablist.render(space, renaming: snapshot.renaming, frames: f, palette: palette, tools: snapshot.tabTools,
                       newTabCurrent: newTabCurrent, now: snapshot.now, lit: snapshot.sidebar.lit)
        miniPlayers.frame = bounds
        miniPlayers.isHidden = slice.creatingSpace || snapshot.miniPlayers.isEmpty
        miniPlayers.render(snapshot.miniPlayers, frames: f.miniPlayers, origin: f.frame.origin, palette: palette,
                           animated: previous != nil && previous?.miniPlayerHover != miniPlayers.hover)
        dock.frame = local(f.dock)
        dock.hapticsEnabled = snapshot.sidebar.hapticsEnabled
        dock.render(dockItems, frames: f, palette: palette, creating: slice.creatingSpace, plusMenu: slice.plusMenu)
        // Arc's Create a Space flow takes the column's place between the title row and the dock (P24 a).
        if slice.creatingSpace { for view in [urlPill, favorites, tablist, spaceHeader] as [NSView] { view.isHidden = true } }
        else { tablist.isHidden = false }
        drag.context = DragController.Context(space: space, favorites: snapshot.favorites, frames: f, shown: snapshot.content.panes.first(where: \.focused)?.tab,
                                              spaceHeaderDrops: !thisWindow)
        drag.hapticsEnabled = snapshot.sidebar.hapticsEnabled
        if frames.sidebarFloats { watchFloatingExit() } else { stopFloatingWatch() }
    }

    public func handleScrollWheel(_ event: NSEvent) -> Bool {
        // The native window's callback already scopes this invocation. CG-backed in-process events have no window.
        let ownsEvent = event.window == nil || event.window === window
        let library = lastRender.map { libraryOpen($0.snapshot) } ?? false
        guard ownsEvent, canSwipe, library || !isHiddenOrHasHiddenAncestor, window?.isVisible == true, window?.attachedSheet == nil else {
            resetSwipe(); return false
        }
        // With the Library open the gesture is the column's anywhere in the window (bin:0x100215694).
        let starts = library || bounds.contains(convert(event.locationInWindow, from: nil))
        return gesture.handle(event, starts: starts, pager: pager, window: window) { wheel in
            renderSidePages()
            if !wheel { swipeHoldsLibrary = library }
        }
    }

    private func resetSwipe() { gesture.reset(pager) }

    private func libraryOpen(_ snapshot: WindowSnapshot) -> Bool {
        if case .library? = snapshot.overlay { true } else { false }
    }

    // MARK: The pages

    /// The row of pages from the snapshot, and the selected page when something other than the fingers changed it.
    private func syncPager(_ snapshot: WindowSnapshot, frames: WindowFrames, before: WindowSnapshot?) {
        guard snapshot.kind == .standard else { return }
        let width = snapshot.sidebar.width
        var libraryWidth = LibraryLayout.panelWidth(windowWidth: frames.contentSize.width, sidebarWidth: width)
        if case .library(let library)? = snapshot.overlay {
            libraryWidth = LibraryLayout.panelWidth(windowWidth: frames.contentSize.width, sidebarWidth: width, page: library.page, spaces: library.spaces.count)
        }
        let spaces = snapshot.dock.map { SidebarPage.space($0.id) }
        pager.update(pages: [.library] + spaces, widths: [libraryWidth] + spaces.map { _ in width })
        let open = libraryOpen(snapshot)
        if !open { closingLibrary = false }
        let current = SidebarPage.space(snapshot.space.id)
        guard let selected = pager.selectedPage else { return }
        // A swipe holds the Library open while it decides, whichever page it is on.
        let shown: SidebarPage
        if !open || closingLibrary { shown = current }
        else if swipeHoldsLibrary { shown = selected == .library ? .library : current }
        else { shown = .library }
        if let before, before.space.id != snapshot.space.id {
            outgoing = SpacePage(space: before.space, favorites: before.favorites, theme: before.theme)
        }
        guard shown != selected else { return }
        if shown == .library || selected == .library { return pager.select(shown, animated: false) }
        let adjacent = abs((pager.pages.firstIndex(of: shown) ?? 0) - pager.selected) <= 1
        jumpFrom = adjacent ? nil : selected
        pager.select(shown, animated: before != nil)
    }

    /// The neighbouring page on one side of the current Space, and which page it stands for.
    private func sidePage(previous: Bool, snapshot: WindowSnapshot) -> SpacePage? {
        if let outgoing, case .space(let from)? = jumpFrom, let here = pager.pages.firstIndex(of: .space(snapshot.space.id)),
           let there = pager.pages.firstIndex(of: .space(from)), (there < here) == previous {
            return outgoing
        }
        return previous ? snapshot.neighbors.previous : snapshot.neighbors.next
    }

    /// Draws the neighbouring pages, for as long as the column moves.
    private func renderSidePages() {
        guard let lastRender, let f = lastRender.frames.sidebar ?? last?.frames else { return }
        let snapshot = lastRender.snapshot
        for (view, previous) in [(previousPage, true), (nextPage, false)] {
            guard let page = sidePage(previous: previous, snapshot: snapshot) else {
                view.removeFromSuperview()
                continue
            }
            if view.superview !== strip { strip.addSubview(view, positioned: .below, relativeTo: nil) }
            let width = f.frame.width
            view.frame = CGRect(x: previous ? -width : width, y: 0, width: width, height: f.frame.height)
            view.render(page, sharesFavorites: page.favorites.root == snapshot.favorites.root, column: f.frame, snapshot: snapshot, now: snapshot.now)
        }
    }

    private func pagerMoved() {
        applyPagePosition()
        // Toward the Library: it opens as soon as the column leaves the first Space, and closes again if the swipe comes back.
        if pager.isTracking, (libraryProgress ?? 0) > 0, let lastRender, !libraryOpen(lastRender.snapshot) {
            swipeHoldsLibrary = true
            dispatch(.library(.open(nil)))
        }
    }

    private func pagerSelected(_ page: SidebarPage) {
        guard let lastRender else { return }
        switch page {
        case .library:
            swipeHoldsLibrary = true
            if !libraryOpen(lastRender.snapshot) { dispatch(.library(.open(nil))) }
        case .space(let id):
            // Out of the Library the Space changes when the column stands on it (`pagerSettled`).
            if !libraryOpen(lastRender.snapshot) { dispatch(.space(.focus(id))) }
        }
    }

    /// The fingers lifted: a full ring past the last Space opens Create a Space (bin:0x10021ca38).
    private func pagerLifted() {
        if let armed = edgeArmedAt, CACurrentMediaTime() - armed > Metrics.pageSwipe.edgeHold.value {
            dispatch(.sidebar(.openDialog(.newSpace)))
        }
        edgeArmedAt = nil
    }

    private func pagerSettled() {
        jumpFrom = nil
        outgoing = nil
        let held = swipeHoldsLibrary
        swipeHoldsLibrary = false
        guard let lastRender else { return }
        if held, libraryOpen(lastRender.snapshot), case .space(let id)? = pager.selectedPage {
            closingLibrary = true
            dispatch(.library(.close))
            if id != lastRender.snapshot.space.id { dispatch(.space(.focus(id))) }
        }
    }

    /// Puts everything that follows the position where it belongs; at rest, back in its place.
    private func applyPagePosition() {
        guard let lastRender, lastRender.snapshot.kind == .standard, let here = pager.pages.firstIndex(of: .space(lastRender.snapshot.space.id)),
              pager.origins.count > 1 else { return }
        guard pager.isActive else { return restPages() }
        let snapshot = lastRender.snapshot, origins = pager.origins, position = pager.position
        let firstSpace = origins[1]
        // Toward the Library the pages stand still: the whole column goes (`onLibraryProgress`).
        let along = max(position, firstSpace)
        strip.setFrameOrigin(CGPoint(x: origins[here] - along, y: 0))
        if previousPage.superview == nil, nextPage.superview == nil { renderSidePages() }
        // The Favorites stand still over the pages of their profile, and move past the edge of that group (bin:0x10010b144).
        let sharesPrevious = here > 1 && snapshot.neighbors.previous?.favorites.root == snapshot.favorites.root
        let sharesNext = snapshot.neighbors.next?.favorites.root == snapshot.favorites.root
        let low = origins[sharesPrevious ? here - 1 : here], high = origins[sharesNext ? here + 1 : here]
        let tray = last?.frames.map { $0.favoritesTray.offsetBy(dx: -$0.frame.minX, dy: -$0.frame.minY) } ?? favorites.frame
        favorites.setFrameOrigin(CGPoint(x: tray.minX - (along - min(max(along, low), high)), y: tray.minY))
        // The colors between the two pages, the dots in the dock likewise (bin:0x10021dcf4).
        if let pair = PageSwipeRule.pair(at: along, origins: origins) {
            let theme = { (index: Int) -> ResolvedTheme in
                if index == here - 1, let page = self.sidePage(previous: true, snapshot: snapshot) { return page.theme }
                if index == here + 1, let page = self.sidePage(previous: false, snapshot: snapshot) { return page.theme }
                return snapshot.theme
            }
            themeBlending = true
            onThemeBlend?(theme(pair.floor), theme(pair.ceil), pair.progress)
            var factors: [SpaceID: Double] = [:]
            if case .space(let id) = pager.pages[pair.floor] { factors[id] = 1 - pair.progress }
            if case .space(let id) = pager.pages[pair.ceil], pair.ceil != pair.floor { factors[id] = pair.progress }
            dock.showSelection(factors)
        }
        // Past the last Space.
        let pressed = position - (origins.last ?? 0)
        if here == origins.count - 1, pressed > 0, let palette = last?.palette {
            let feedback = PageSwipeRule.edgeFeedback(pressed: pressed)
            edgeFeedback.render(fade: feedback.fade, progress: feedback.progress, palette: palette)
            if pager.isTracking {
                let full = feedback.progress >= 1
                if full != (edgeArmedAt != nil), last?.sidebar.hapticsEnabled == true {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                edgeArmedAt = full ? (edgeArmedAt ?? CACurrentMediaTime()) : nil
            }
        } else {
            edgeFeedback.isHidden = true
        }
        setLibraryProgress(position < firstSpace || libraryOpen(snapshot) ? min(max((firstSpace - position) / firstSpace, 0), 1) : nil)
    }

    private func restPages() {
        strip.setFrameOrigin(.zero)
        previousPage.removeFromSuperview()
        nextPage.removeFromSuperview()
        edgeFeedback.isHidden = true
        edgeArmedAt = nil
        if let tray = last?.frames.map({ $0.favoritesTray.offsetBy(dx: -$0.frame.minX, dy: -$0.frame.minY) }) { favorites.setFrameOrigin(tray.origin) }
        dock.showSelection(nil)
        if themeBlending {
            themeBlending = false
            onThemeBlendEnded?()
        }
        setLibraryProgress(nil)
    }

    private func setLibraryProgress(_ progress: Double?) {
        guard progress != libraryProgress else { return }
        libraryProgress = progress
        onLibraryProgress?(progress)
    }

    /// A drag's grid layout: the column takes it at once.
    func setFavoritesDrag(_ drag: FavoritesDrag?) {
        favoritesDrag = drag
        renderAfterDrag()
    }

    /// The drag is over: nothing renders until `renderAfterDrag`, so its command reaches the grid first.
    func clearFavoritesDrag() { favoritesDrag = nil }

    func renderAfterDrag() {
        if let lastRender { render(lastRender.snapshot, frames: lastRender.frames, palette: lastRender.palette) }
    }

    /// The palette of the last render (the drag preview's card color).
    var currentPalette: Palette? { last?.palette }

    /// Makes the rename field of `item` (a row or a favorite tile) first responder. False when it is not on screen or
    /// not renaming.
    public func focusRenameField(_ item: ItemID) -> Bool {
        tablist.focusRenameField(item) || favorites.focusRenameField(item)
    }

    /// Keyboard focus into the tab list itself (FocusTarget.sidebar). False when the list is not in a window.
    public func focusList() -> Bool {
        tablist.focusList()
    }

    // MARK: Brk's AI panel (docs/design/ai-right-panel.md)

    /// The Space whose dot in the dock is under `point` (window coordinates): where an AI list row dragged out of the panel
    /// would move its conversation. Nil while the sidebar is hidden or the point is over no dot.
    public func dockSpace(atWindowPoint point: CGPoint) -> SpaceID? {
        guard !isHidden, let frames = drag.context?.frames else { return nil }
        let root = rootPoint(fromWindow: point)
        return frames.dockSpaces.first { $0.value.contains(root) }?.key
    }

    /// The dot under such a drag shows the drop target, as under a dragged tab.
    public func showDockDrop(_ space: SpaceID?) { dock.showDrop(space: space) }

    /// What a dragged row stands for: the whole Cmd+click selection it belongs to, else the row itself.
    public func dragGroup(for item: ItemID) -> [ItemID] { tablist.selectionGroup(containing: item) }

    /// Coming back from hidden, the column slides in from its parked position (x = -(width + 10)) over Arc's
    /// show/hide duration and curve. Otherwise frames apply at once.
    private func place(_ target: CGRect, slideIn: Bool) {
        guard slideIn, window != nil else {
            frame = target
            return
        }
        frame = target.offsetBy(dx: -(target.maxX + Metrics.sidebar.floatingParkedGap.value), dy: 0)
        let curve = Metrics.motion.sidebarCurve.value.map(Float.init)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.motion.sidebarToggle.value
            context.timingFunction = CAMediaTimingFunction(controlPoints: curve[0], curve[1], curve[2], curve[3])
            animator().frame = target
        }
    }

    private func watchFloatingExit() {
        guard floatingWatch == nil, let root = superview else { return }
        floatingWatch = FloatingSidebarTracking(root: root, staysOpen: { [weak self] in
            guard let self else { return false }
            return self.drag.isActive || self.tablist.isRenaming || self.favorites.isRenaming || self.window?.attachedSheet != nil
        }, boundary: { [weak self] in
            (self?.last?.frames?.frame.maxX ?? 0) + Metrics.sidebar.floatingStayOpenSlack.value
        }, dismiss: { [weak self] in self?.dispatch(.sidebar(.peek(false))) })
    }

    private func stopFloatingWatch() {
        floatingWatch?.stop()
        floatingWatch = nil
    }

}

/// The title row: sidebar toggle after the traffic lights, then back, forward and reload (stop while loading)
/// right-aligned, 32 pt buttons 2 pt apart ending 6 pt from the edge (cra L1215). A window drag region.
/// When the toggle and the three buttons do not fit (Arc at 164) the row keeps back and forward and folds the toggle
/// and reload into a "…" menu, on 28 pt buttons without gaps. With the toolbar shown only the toggle stays: the
/// navigation buttons are in the toolbar.
///
/// Brk's own (docs/design/ai-right-panel.md): while the window can open the AI panel a chat button ends the row, the
/// panel's switch as the toggle is the sidebar's. It keeps its hover fill while the panel is open and carries the count of
/// what waits for the user. Narrower, reload goes into "…" first (with the toggle, as Arc folds them), then the chat
/// button, whose "…" item carries the count. Without it the row is Arc's, unchanged.
@MainActor
final class TitleRowView: NSView {
    private let toggle = GlyphButton()
    private let back = GlyphButton()
    private let forward = GlyphButton()
    private let reload = GlyphButton()
    private let more = GlyphButton()
    private let ai = GlyphButton()
    private let aiBadge = AIToggleBadge()
    private let dispatch: Dispatch
    private var loading = false
    private var aiFolded = false
    /// The sidebar toggle is in "…" (Arc's compact row).
    private var foldsToggle = false
    private var last: (URLPillSnapshot, SidebarFrames, Bool, Palette, Bool, AIToggleSnapshot?)?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        toggle.action = { _ in dispatch(.sidebar(.toggle)) }
        back.action = { _ in dispatch(.page(.back(.focused))) }
        forward.action = { _ in dispatch(.page(.forward(.focused))) }
        reload.action = { [weak self] modifiers in self?.reloadOrStop(modifiers) }
        more.action = { [weak self] _ in self?.showMore() }
        toggle.toolTip = SidebarCopy.showHideSidebar
        back.toolTip = SidebarCopy.goBack
        forward.toolTip = SidebarCopy.goForward
        more.identify(.tabTool("title-more"))
        ai.action = { _ in dispatch(.assist(.togglePanel)) }
        ai.identify(.aiControl("toggle"))
        aiBadge.identify(.aiControl("toggle-badge"))
        for button in [toggle, back, forward, reload, more, ai] { addSubview(button) }
        addSubview(aiBadge)
        identify(.titleRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    /// The title row moves the window (spike unknown 6); its buttons do not.
    override var mouseDownCanMoveWindow: Bool { true }

    /// `navigation` false hides back, forward and reload (a split shows them in each pane's header); with the
    /// toolbar shown they are in the toolbar.
    /// `ai`: the chat button's state while the window can open the AI panel; nil leaves Arc's row as it is.
    func render(_ pill: URLPillSnapshot, frames f: SidebarFrames, toolbar: Bool, palette: Palette, navigation: Bool = true, ai toggleState: AIToggleSnapshot? = nil) {
        if let last, last.0 == pill, last.1 == f, last.2 == toolbar, last.3 == palette, last.4 == navigation, last.5 == toggleState { return }
        last = (pill, f, toolbar, palette, navigation, toggleState)
        loading = pill.loading
        let w = Metrics.window, size = Draw.navButton.value, gap = Draw.navGap.value
        let y = (f.titleRow.height - size) / 2
        let lightsEnd = f.trafficLightsOrigin.x - f.titleRow.minX + 3 * w.trafficLightSize.value + 2 * w.trafficLightSpacing.value
        toggle.frame = CGRect(x: lightsEnd + Draw.toggleGap.value, y: y, width: size, height: size)
        var right = f.titleRow.width - Metrics.sidebar.titleRowRightInset.value
        // With the toolbar shown the chat button is the toolbar's; a split's row keeps it at the end.
        let chat = toggleState != nil && !toolbar
        let offRow = toolbar || !navigation
        let compact = Draw.navButtonCompact.value, cy = (f.titleRow.height - compact) / 2
        aiFolded = false
        foldsToggle = false
        ai.isHidden = !chat
        if chat, !offRow, right - 4 * size - 3 * gap < toggle.frame.maxX + gap {
            // Too narrow for all five. First reload goes into "…" and the toggle stays: the chat button, "…", forward and
            // back on Arc's 28 pt compact buttons. Narrower still, Arc's own compact row with the chat button in "…" too.
            reload.isHidden = true
            more.isHidden = false
            if right - 4 * compact >= toggle.frame.maxX {
                toggle.isHidden = false
                for (i, button) in [ai, more, forward, back].enumerated() {
                    button.frame = CGRect(x: right - Double(i + 1) * compact, y: cy, width: compact, height: compact)
                    button.isHidden = false
                }
            } else {
                ai.isHidden = true
                aiFolded = true
                foldsToggle = true
                toggle.isHidden = true
                for (i, button) in [more, forward, back].enumerated() {
                    button.frame = CGRect(x: right - Double(i + 1) * compact, y: cy, width: compact, height: compact)
                    button.isHidden = button.frame.minX < lightsEnd
                }
            }
        } else {
            if chat {
                ai.frame = CGRect(x: right - size, y: y, width: size, height: size)
                if !offRow { right -= size + gap }
            }
            let fits = right - 3 * size - 2 * gap >= toggle.frame.maxX + gap
            more.isHidden = offRow || fits
            toggle.isHidden = !offRow && !fits
            foldsToggle = toggle.isHidden
            if fits || offRow {
                var x = right
                for button in [reload, forward, back] {
                    x -= size
                    button.frame = CGRect(x: x, y: y, width: size, height: size)
                    button.isHidden = offRow
                    x -= gap
                }
            } else {
                reload.isHidden = true
                for (i, button) in [more, forward, back].enumerated() {
                    button.frame = CGRect(x: right - Double(i + 1) * compact, y: cy, width: compact, height: compact)
                    button.isHidden = button.frame.minX < lightsEnd
                }
            }
        }
        back.isEnabled = pill.canGoBack
        forward.isEnabled = pill.canGoForward
        reload.isEnabled = pill.text != nil
        reload.toolTip = pill.loading ? SidebarCopy.stop : SidebarCopy.reload
        let glyph = Draw.navGlyph.value, radius = Draw.navButtonRadius.value, fill = palette.tokens.itemHover
        toggle.render(.sidebarToggle, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        back.render(.back, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        forward.render(.forward, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        reload.render(pill.loading ? .stop : .reload, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        more.render(.more, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        if let toggleState {
            ai.renderSymbol(AIToggleBadge.symbol, size: glyph, palette: palette, radius: radius, hoverFill: fill)
            ai.latchedFill = toggleState.open ? fill : nil
            ai.toolTip = AIThreadWords.toggleTip(toggleState.language)
            ai.setAccessibilityLabel(AIThreadWords.toggleName(toggleState.language))
            ai.setAccessibilityValue(toggleState.open ? "open" : "closed")
        }
        aiBadge.show(ai.isHidden ? 0 : toggleState?.waiting ?? 0, on: ai.frame, palette: palette)
    }

    private func reloadOrStop(_ modifiers: NSEvent.ModifierFlags) {
        if loading { dispatch(.page(.stop(.focused))) }
        else { dispatch(.page(.reload(.focused, ignoringCache: modifiers.contains(.option)))) }
    }

    /// The narrow row's "…": the buttons that did not fit.
    private func showMore() {
        let menu = NSMenu()
        let reloadItem = NSMenuItem(title: loading ? SidebarCopy.stop : SidebarCopy.reload, action: #selector(menuReload), keyEquivalent: "")
        reloadItem.target = self
        reloadItem.isEnabled = last?.0.text != nil
        let toggleItem = NSMenuItem(title: SidebarCopy.showHideSidebar, action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self
        menu.autoenablesItems = false
        // What did not fit: reload, the toggle when it is folded too (Arc's compact row).
        menu.items = foldsToggle ? [reloadItem, toggleItem] : [reloadItem]
        // The chat button folded in: its item, with the count of what waits for the user.
        if aiFolded, let state = last?.5 {
            let item = NSMenuItem(title: AIThreadWords.toggleName(state.language), action: #selector(menuAI), keyEquivalent: "")
            item.target = self
            if state.waiting > 0 { item.badge = NSMenuItemBadge(count: state.waiting) }
            item.state = state.open ? .on : .off
            menu.items.append(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: more.frame.minX, y: more.frame.maxY), in: self)
    }

    @objc private func menuReload() { reloadOrStop([]) }
    @objc private func menuToggle() { dispatch(.sidebar(.toggle)) }
    @objc private func menuAI() { dispatch(.assist(.togglePanel)) }
}

/// The count on the title row's chat button (and the toolbar's): what waits for the user in the profile, in the Space's
/// color, at the button's top right, as on the panel's list icon.
@MainActor
final class AIToggleBadge: NSView {
    /// The chat bubbles: the same icon as the command bar's "AI Conversations" row and the panel's list icon.
    static let symbol = "bubble.left.and.bubble.right"
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: Metrics.ai.toggleBadgeFont.value, weight: .semibold)
        label.alignment = .center
        label.isSelectable = false
        addSubview(label)
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ count: Int, on button: CGRect, palette: Palette) {
        isHidden = count == 0
        guard count > 0 else { return }
        label.stringValue = count > 99 ? "99+" : "\(count)"
        label.textColor = palette.scheme == .light ? .white : NSColor(srgbRed: 0x1F / 255, green: 0x1E / 255, blue: 0x24 / 255, alpha: 1)
        layer?.backgroundColor = palette.focusColor.cgColor
        let height = Metrics.ai.toggleBadgeHeight.value, width = max(height, ceil(label.intrinsicContentSize.width) + 6)
        frame = CGRect(x: button.maxX - width + 4, y: button.minY - 2, width: width, height: height)
        layer?.cornerRadius = height / 2
        let lh = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: 0, y: ((height - lh) / 2).rounded(), width: width, height: lh)
        setAccessibilityLabel(label.stringValue)
    }
}

/// The URL pill (Arc: `CommandBarPlaceholderView`): the focused tab's host or "Search or Enter URL…". While the pointer
/// is over the sidebar two accessories show at its right end: copy link and the site controls. A click opens the
/// command bar to edit the current tab. The profile badge (F2) sits at the trailing end while the space's profile is
/// not the default, or the window is incognito; an incognito pill has Arc's CommandBarPlaceholderIncognitoBackground.
/// While the focused card shows an Easel the pill is its Share button (Q09 a): a grey lock, "Share", a thin edge; a
/// click shares the board (a PNG file).
@MainActor
final class URLPillView: HoverView {
    private let label = NSTextField(labelWithString: "")
    private let lock = NSImageView()
    private let badge = ProfileBadgeView()
    private let copyLink = GlyphButton()
    private let siteInfo = GlyphButton()
    /// Arc's second line: Translation Available / Translated (P01-a, P50-b).
    private let translationLine: PillTranslationLine
    private var pill: URLPillSnapshot?
    private var palette: Palette?
    private let dispatch: Dispatch
    /// Set by the sidebar while the pointer is anywhere over it.
    var sidebarHovered = false { didSet { if sidebarHovered != oldValue { stateChanged() } } }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        translationLine = PillTranslationLine(dispatch: dispatch)
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.urlPill.cornerRadius.value
        layer?.masksToBounds = true
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: Draw.urlFont.value)
        label.isSelectable = false
        siteInfo.action = { _ in dispatch(.site(.controls)) }
        siteInfo.toolTip = "Website controls and privacy"
        siteInfo.identify(.siteInfo)
        addSubview(label)
        addSubview(badge)
        lock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Share")?
            .withSymbolConfiguration(.init(pointSize: Draw.shareLockGlyph.value[1], weight: .medium))
        lock.imageScaling = .scaleProportionallyUpOrDown
        lock.contentTintColor = NSColor(srgbRed: 0x9B / 255.0, green: 0x9A / 255.0, blue: 0x9A / 255.0, alpha: 1)   // Q09 a: #9B9A9A
        lock.isHidden = true
        addSubview(lock)
        copyLink.action = { _ in dispatch(.page(.copyURL(.plain))) }
        copyLink.toolTip = SidebarCopy.copyLink
        addSubview(copyLink)
        addSubview(siteInfo)
        addSubview(translationLine)
        identify(.urlPill)
    }

    /// A blank or incognito window's pill reads as a search field while it has no page (Arc: a magnifier before
    /// "Search or Enter URL…").
    private var searchField = false

    func render(_ pill: URLPillSnapshot, palette: Palette, searchField: Bool = false) {
        let search = searchField && pill.text == nil
        if pill == self.pill, palette == self.palette, search == self.searchField { needsLayout = true; return }
        self.pill = pill
        self.palette = palette
        self.searchField = search
        let text = pill.host ?? pill.text
        // No tip: Arc shows none over its pill (Q23, the pointer held on it for 3.5 s).
        label.stringValue = (text ?? Copy.urlPlaceholder) + (pill.zoomPercent == 100 ? "" : "  \(pill.zoomPercent)%")
        label.textColor = text == nil ? palette.ink.placeholder : palette.ink.secondary
        // Arc's placeholder is a weight heavier than an address: 134 pt wide in Q02-b, SF 13 medium; "wikipedia.org" in
        // Q13-c is 79 pt, SF 13 regular.
        label.font = .systemFont(ofSize: Draw.urlFont.value, weight: text == nil ? .medium : .regular)
        let radius = Metrics.urlPill.accessoryRadius.value
        copyLink.render(.copyLink, size: Draw.pillAccessoryGlyph.value, palette: palette, radius: radius, hoverFill: palette.tokens.itemHover)
        if search {
            siteInfo.render(.search, size: Draw.pillSearchGlyph.value, palette: palette, tint: palette.ink.searchGlyph, radius: radius, hoverFill: palette.tokens.itemHover)
        } else {
            siteInfo.render(.siteControls, size: Draw.pillAccessoryGlyph.value, palette: palette, radius: radius, hoverFill: palette.tokens.itemHover)
        }
        siteInfo.isEnabled = !search
        // Arc's incognito pill keeps its own background but shows no badge (the 2026-11-03 capture Q03).
        badge.render(pill.profile?.incognito == true ? nil : pill.profile, palette: palette)
        lock.isHidden = pill.share == nil
        layer?.borderWidth = pill.share == nil ? 0 : Draw.shareEdge.value
        layer?.borderColor = NSColor.black.withAlphaComponent(0.13).cgColor
        if pill.share != nil { label.textColor = palette.ink.secondary }
        translationLine.render(search || pill.share != nil ? nil : pill.translation, shareQuote: !search && pill.share == nil && pill.shareQuote, palette: palette)
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = Metrics.urlPill.accessorySize.value, inset = Draw.pillAccessoryInset.value
        // A search-field pill keeps its magnifier before the placeholder; otherwise the site controls sit at the right
        // end with copy link before them.
        siteInfo.frame = searchField ? CGRect(x: inset, y: (bounds.height - size) / 2, width: size, height: size)
            : CGRect(x: bounds.width - inset - size, y: (bounds.height - size) / 2, width: size, height: size)
        copyLink.frame = CGRect(x: bounds.width - inset - size, y: (bounds.height - size) / 2, width: size, height: size)
            .offsetBy(dx: searchField ? 0 : -(size + Draw.pillAccessoryGap.value), dy: 0)
        var leading = searchField ? inset + size + Draw.pillSearchTextLeading.value : Draw.pillTextLeading.value
        if !lock.isHidden {
            let glyph = Draw.shareLockGlyph.value
            lock.frame = CGRect(x: glyph[2], y: (bounds.height - glyph[1]) / 2, width: glyph[0], height: glyph[1])
            leading = Draw.shareTextLeading.value
        }
        var trailing = accessoriesShown ? copyLink.frame.minX : bounds.width - leading
        if !badge.isHidden {
            if !accessoriesShown { trailing = bounds.width - inset }
            let width = min(badge.fittingWidth, max(0, (trailing - leading) / 2))
            badge.frame = CGRect(x: trailing - width, y: (bounds.height - BadgeDraw.height.value) / 2, width: width, height: BadgeDraw.height.value)
            trailing = badge.frame.minX - BadgeDraw.gap.value
        }
        let text = label.intrinsicContentSize.height
        if translationLine.isHidden {
            // One line: the line's own box in the pill's middle. A label draws at the top of its frame, so a taller frame
            // (it was Arc's 20 pt text area) put the line 2 pt high. Arc, 2x px from the pill's top: the capitals of
            // "Search or Enter URL…" span 26 to 46 of 72 (P24-e), "wikipedia.org" 26 to 50 with its p (Q13-c).
            label.frame = CGRect(x: leading, y: (bounds.height - text) / 2, width: max(0, trailing - leading), height: text)
        } else {
            // Two lines: the host higher, the translation line under it (P45-a).
            label.frame = CGRect(x: leading, y: Draw.pillHostCenter.value - text / 2, width: max(0, trailing - leading), height: text)
            let line = ceil(NSFont.systemFont(ofSize: Draw.pillSubtitleFont.value).boundingRectForFont.height)
            translationLine.frame = CGRect(x: leading, y: Draw.pillSubtitleCenter.value - line / 2,
                                           width: min(max(0, trailing - leading), translationLine.textWidth + 4), height: line)
        }
    }

    /// Copy link and the site controls, shown while the pointer is over the sidebar and the tab has an address.
    private var accessoriesShown: Bool { (sidebarHovered || isHovered) && pill?.text != nil && pill?.share == nil }

    override func stateChanged() {
        guard let palette else { return }
        let fill = isPressed ? palette.tokens.tabPressed : isHovered ? palette.tokens.itemHover : palette.tokens.itemBackground
        layer?.backgroundColor = pill?.profile?.incognito == true && !isPressed && !isHovered
            ? ProfileBadgeView.incognitoPillBackground.cgColor : palette.color(fill).cgColor
        copyLink.alphaValue = accessoriesShown ? 1 : 0
        siteInfo.alphaValue = searchField || accessoriesShown ? 1 : 0
        needsLayout = true
    }

    override func rightMouseDown(with event: NSEvent) { dispatch(.site(.controls)) }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        guard bounds.contains(local(event)) else { return }
        if let easel = pill?.share { dispatch(.easel(.share(easel))) } else { dispatch(.commandBar(.open(.editCurrent))) }
    }
}

/// Arc's `ProfileIndicatorView` in the URL pill: the profile's icon (Arc's person glyph when it has none) and name, or
/// "Incognito", on ProfileIndicatorBackgroundColor (#181B1F @ 0.07 light, #FFFFFF @ 0.12 dark; visual-and-copy.md,
/// ARC_AdBlocking). Hidden for the default profile. Owner: F2.
@MainActor
final class ProfileBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let glyph = NSImageView()
    private var badge: ProfileBadge?
    private var palette: Palette?

    /// CommandBarPlaceholderIncognitoBackground #FFFFFF @ 0.15 (P3; visual-and-copy.md, ARC_URLInputter).
    static let incognitoPillBackground = NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.15)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = BadgeDraw.height.value / 2
        label.font = .systemFont(ofSize: BadgeDraw.font.value, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(glyph)
        addSubview(label)
        isHidden = true
        identify(.profileBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shown only with a badge; the same badge and palette change nothing.
    func render(_ badge: ProfileBadge?, palette: Palette) {
        guard badge != self.badge || palette != self.palette else { return }
        self.badge = badge
        self.palette = palette
        isHidden = badge == nil
        guard let badge else { return }
        label.stringValue = badge.name
        label.textColor = palette.ink.secondary
        glyph.image = symbolImage(Self.symbol(badge), size: BadgeDraw.glyph.value)
        glyph.contentTintColor = palette.ink.secondary
        if case .emoji(let emoji)? = badge.icon {
            glyph.image = nil
            label.stringValue = "\(emoji) \(badge.name)"
        }
        layer?.backgroundColor = (palette.scheme == .light ? NSColor(srgbRed: 0x18 / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 0.07)
                                                             : NSColor(white: 1, alpha: 0.12)).cgColor
        toolTip = badge.name
        setAccessibilityLabel(badge.name)
        needsLayout = true
    }

    /// The SF Symbol for the badge's icon: the named icon or symbol, Arc's person glyph without one, glasses for
    /// incognito (Arc's incognito glyph was not recovered).
    static func symbol(_ badge: ProfileBadge) -> String {
        if badge.incognito { return "eyeglasses" }
        switch badge.icon {
        case .named(let name)?: return name.symbol
        case .symbol(let symbol)?: return symbol
        case .emoji?, nil: return "person.crop.circle"
        }
    }

    /// Padding, glyph, gap and the name at its natural width (the label cell's own size, which includes its
    /// inset, rounded up so the name is not truncated by a fraction of a point).
    var fittingWidth: CGFloat {
        let p = BadgeDraw.padding.value
        let glyphWidth = glyph.image == nil ? 0 : BadgeDraw.glyph.value + BadgeDraw.gap.value
        let text = ceil(label.cell?.cellSize.width ?? label.intrinsicContentSize.width) + 1
        return min(BadgeDraw.maxWidth.value, p + glyphWidth + text + p)
    }

    /// The pill sizes the badge in its own layout; the name follows every size change.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let p = BadgeDraw.padding.value, side = BadgeDraw.glyph.value
        var x = p
        if glyph.image != nil {
            glyph.frame = CGRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
            x = glyph.frame.maxX + BadgeDraw.gap.value
        } else {
            glyph.frame = .zero
        }
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: x, y: (bounds.height - height) / 2, width: max(0, bounds.width - x - p), height: height)
    }
}

/// The badge's drawing numbers. Arc's `ProfileIndicatorView` was not measured, so all are guesses sized to sit inside
/// the 36 pt pill next to its 28 pt accessory (layout-constants.md "URL pill").
let BadgeDraw = ProfileBadgeMetrics()

struct ProfileBadgeMetrics: MetricGroup {
    let height = Metric(20.0, .guess("badge height: the pill's text area minimum height (URL pill text area minimum height 20)"))
    let padding = Metric(7.0, .guess("horizontal padding inside the badge"))
    let gap = Metric(4.0, .guess("between the glyph and the name, and between the badge and the URL"))
    let font = Metric(11.0, .guess("badge name size, Arc's secondary line size (cra L115: 11 pt)"))
    let glyph = Metric(11.0, .guess("badge glyph size, the same as its text"))
    let maxWidth = Metric(110.0, .guess("a long profile name truncates so the URL keeps most of the pill"))
}

/// The floating sidebar's own background (Arc: `FloatingSidebarBackgroundView`): the space's gradient and wash over
/// a blur of the page, the sidebar border, rounded like the content card, with the popover shadow.
@MainActor
final class FloatingBackdropView: NSView {
    private let clip = NSView()
    private let blur = NSVisualEffectView()
    private let paint = ThemePaintView()
    private var last: (ResolvedTheme, Palette)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerCurve = .continuous
        blur.blendingMode = .withinWindow
        blur.material = .sidebar
        blur.state = .active
        clip.addSubview(blur)
        clip.addSubview(paint)
        addSubview(clip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Never takes clicks: the rows above it do.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ theme: ResolvedTheme, palette: Palette) {
        if let last, last.0 == theme, last.1 == palette { return }
        last = (theme, palette)
        paint.render(theme)
        clip.layer?.borderColor = palette.color(palette.tokens.border).cgColor
        clip.layer?.borderWidth = Draw.hairline.value
        layer?.shadowColor = palette.ink.shadow.cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = Draw.floatingShadowRadius.value
        layer?.shadowOffset = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let radius = Metrics.content.cornerRadius.value
        clip.frame = bounds
        clip.layer?.cornerRadius = radius
        blur.frame = clip.bounds
        paint.frame = clip.bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

/// The theme's gradient, top to bottom, with its wash on top: the look the window background gives the anchored
/// sidebar, repeated under the floating one.
@MainActor
final class ThemePaintView: NSView {
    private let gradient = CAGradientLayer()
    private let wash = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        gradient.addSublayer(wash)
        return gradient
    }

    func render(_ theme: ResolvedTheme) {
        let color = { (c: RGBA) in NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha).cgColor }
        gradient.colors = theme.gradient.map(color)
        gradient.opacity = Float(Draw.floatingGradientAlpha.value)
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        wash.backgroundColor = color(theme.wash)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = bounds
        CATransaction.commit()
    }
}

/// The sidebar edge (Arc: `SidebarResizeRegionView`): 8 pt centred on the edge. Dragging runs `SidebarResizeDrag`
/// (snap to 228 with a haptic, hide below 82) and dispatches every width; double-click resets to 228. A 3 pt
/// rounded indicator shows while dragging.
@MainActor
final class ResizeHandleView: NSView {
    private let dispatch: Dispatch
    private let indicator = NSView()
    private var drag: SidebarResizeDrag?
    var hapticsEnabled = true
    private var startX = 0.0
    private var lastSample: (x: Double, time: TimeInterval) = (0, 0)
    private var width = Metrics.sidebar.defaultWidth.value
    private var rect: CGRect?
    var sidebarHidden = false { didSet { syncHidden() } }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        indicator.wantsLayer = true
        indicator.isHidden = true
        addSubview(indicator)
        identify(.resizeHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func render(_ rect: CGRect?, width: Double, palette: Palette) {
        self.width = width
        if rect != self.rect {
            self.rect = rect
            frame = rect ?? .zero
            window?.invalidateCursorRects(for: self)
        }
        syncHidden()
        let m = Metrics.sidebar
        indicator.frame = CGRect(x: (bounds.width - m.resizeIndicatorWidth.value) / 2, y: m.resizeIndicatorTrim.value / 2,
                                 width: m.resizeIndicatorWidth.value, height: max(0, bounds.height - m.resizeIndicatorTrim.value))
        indicator.layer?.cornerRadius = m.resizeIndicatorWidth.value / 2
        indicator.layer?.backgroundColor = palette.color(palette.tokens.dragHint).cgColor
    }

    /// Hidden with the sidebar, except mid-drag: dragging below 82 hides the sidebar and dragging back shows it.
    private func syncHidden() {
        isHidden = drag == nil && (rect == nil || sidebarHidden)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            dispatch(.sidebar(.resize(width: SidebarResizeDrag.resetWidth)))
            return
        }
        drag = SidebarResizeDrag(startWidth: width)
        startX = event.locationInWindow.x
        lastSample = (startX, event.timestamp)
        indicator.isHidden = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        let x = event.locationInWindow.x
        let elapsed = event.timestamp - lastSample.time
        let velocity = elapsed > 0 ? (x - lastSample.x) / elapsed : 0
        lastSample = (x, event.timestamp)
        let wasSnapped = drag.snappedAt != nil
        let next = drag.update(translation: x - startX, velocity: velocity, time: event.timestamp)
        if hapticsEnabled, !wasSnapped, drag.snappedAt != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        self.drag = drag
        dispatch(.sidebar(.resize(width: next)))
    }

    override func mouseUp(with event: NSEvent) {
        if hapticsEnabled, drag?.snappedAt != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        drag = nil
        indicator.isHidden = true
        syncHidden()
    }
}

/// The left-edge strip that reveals a hidden sidebar: the pointer entering it peeks the floating sidebar. It only
/// watches the pointer; clicks pass through to whatever is under it.
@MainActor
final class RevealStripView: NSView {
    private let dispatch: Dispatch
    private var tracking: NSTrackingArea?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        clipsToBounds = true
        identify(.revealStrip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ rect: CGRect?) {
        frame = rect ?? .zero
        isHidden = rect == nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if tracking == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHidden, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dispatch(.sidebar(.peek(true)))
    }
}

/// Moves a view to its new frame, over `Draw.favoritesReflow` when the grid is reflowing for a drag.
@MainActor
enum Slide {
    static func place(_ view: NSView, at rect: CGRect, sliding: Bool) {
        let curve = Draw.favoritesReflowCurve.value.map(Float.init)
        // A zero-length group also stops a slide still under way; setting `frame` alone would not.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = sliding ? Draw.favoritesReflow.value : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: curve[0], curve[1], curve[2], curve[3])
            view.animator().frame = rect
        }
    }
}

/// The sidebar's row of pages: the Library first, then the Spaces in dock order (Arc: `WindowLayoutPage`).
enum SidebarPage: Hashable { case library, space(SpaceID) }
typealias SpacePager = PagePager<SidebarPage>
