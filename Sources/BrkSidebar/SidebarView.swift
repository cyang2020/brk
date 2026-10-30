import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The sidebar column: title row (traffic lights are AppKit's own buttons, positioned by the window
/// controller at `SidebarFrames.trafficLightsOrigin`; back/forward/reload here), URL pill, favorites grid, the
/// space's tab list, the dock, and the edge resize handle. Translucent tokens over the themed background.
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`, `focusRenameField`, `focusList`.
/// Everything else in BrkSidebar is internal to W3.
@MainActor
public final class SidebarView: NSView {
    let dispatch: Dispatch
    let header: SidebarHeaderView
    let urlPill: URLPillView
    let favorites: FavoritesView
    let tablist: TablistView
    let dock: DockView
    let resizeHandle: ResizeHandleView

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        header = SidebarHeaderView(dispatch: dispatch)
        urlPill = URLPillView(dispatch: dispatch)
        favorites = FavoritesView(dispatch: dispatch)
        tablist = TablistView(dispatch: dispatch)
        dock = DockView(dispatch: dispatch)
        resizeHandle = ResizeHandleView(dispatch: dispatch)
        super.init(frame: .zero)
        for view in [header, urlPill, favorites, tablist, dock, resizeHandle] as [NSView] { addSubview(view) }
        identify(.sidebar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, palette: Palette) {
        // TODO(W3): guard let f = frames.sidebar; frame = f.frame; identify(.floatingSidebar) when floating (with
        // Arc's floating background, inset 5); children render their slices at their frames.
        fatalError("not implemented")
    }

    /// Makes the rename field of `item` first responder. False when that row is not on screen or not renaming.
    public func focusRenameField(_ item: ItemID) -> Bool {
        tablist.focusRenameField(item)
    }

    /// Keyboard focus into the tab list itself (FocusTarget.sidebar). False when the list is not in a window.
    public func focusList() -> Bool {
        guard let window else { return false }
        return window.makeFirstResponder(tablist)
    }
}

/// Back, forward, reload in the title row. Clicks dispatch `.page(.back(.focused))` etc.
@MainActor
final class SidebarHeaderView: NSView {
    let dispatch: Dispatch
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.titleRow)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    /// The title row is a window drag region (spike unknown 6: dragging the title row moves the window).
    override var mouseDownCanMoveWindow: Bool { true }
}

/// The URL pill: display URL or "Search or Enter URL…"; a click dispatches `.commandBar(.open(.editCurrent))`.
@MainActor
final class URLPillView: NSView {
    let dispatch: Dispatch
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.urlPill)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ pill: URLPillSnapshot, frame: CGRect, palette: Palette) {
        // TODO(W3): radius Metrics.urlPill.cornerRadius (continuous), itemBackground token, leading icon 22.
        fatalError("not implemented")
    }

    override func mouseUp(with event: NSEvent) { dispatch(.commandBar(.open(.editCurrent))) }
}

/// The favorites grid. Tile click -> `.tab(.focus(id))`; drag between tiles and to/from the tab list.
@MainActor
final class FavoritesView: NSView {
    let dispatch: Dispatch
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.favoritesTray)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ favorites: FavoritesSnapshot, frames: SidebarFrames, palette: Palette) {
        // TODO(W3): one tile view per tile keyed by ItemID (reused across renders), identify(.favorite(id)),
        // radius Metrics.favorites.tileRadius; the current tile gets the ring (inset 1, radius 11); empty state copy.
        fatalError("not implemented")
    }
}

/// The dock: Library (archive in v1), one cell per space, "+". Cell click -> `.space(.focus(id))`; "+" ->
/// `.sidebar(.popupMenu(.plusButton, at:))`; Library -> `.archive(.open)`. Press scale Metrics.dock.pressScale.
@MainActor
final class DockView: NSView {
    let dispatch: Dispatch
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.dock)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ items: [DockItem], frames: SidebarFrames, palette: Palette) {
        // TODO(W3): cells keyed by SpaceID at frames.dockSpaces[id]; identify(.dockSpace(id)); icon: emoji, SF Symbol,
        // or a dot in DockItem.color; active cell background itemBackground; radius Metrics.dock.cellRadius.
        fatalError("not implemented")
    }
}

/// The sidebar edge: drag resizes through `SidebarResizeDrag` (snap to 228, hide below 82), double-click resets to
/// 228. Dispatches `.sidebar(.resize(width:))` on every drag sample; a 3 pt indicator draws while dragging.
@MainActor
final class ResizeHandleView: NSView {
    let dispatch: Dispatch
    private var drag: SidebarResizeDrag?
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.resizeHandle)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
