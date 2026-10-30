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
/// Everything else in BrkSidebar is internal to W3. First-pass bodies by the integrator: W3 owns the drawing.
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
        wantsLayer = true
        for view in [header, urlPill, favorites, tablist, dock, resizeHandle] as [NSView] { addSubview(view) }
        identify(.sidebar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, palette: Palette) {
        guard let f = frames.sidebar else { return }
        frame = f.frame
        identify(frames.sidebarFloats ? .floatingSidebar : .sidebar)
        // TODO(W3): Arc's floating background (inset 5, its own radius; not recovered) while floating.
        layer?.backgroundColor = frames.sidebarFloats ? palette.color(palette.tokens.itemBackground).cgColor : nil
        let local = { (r: CGRect) in r.offsetBy(dx: -f.frame.minX, dy: -f.frame.minY) }
        header.frame = local(f.titleRow)
        header.render(snapshot.urlPill, palette: palette)
        urlPill.frame = local(f.urlPill)
        urlPill.render(snapshot.urlPill, frame: urlPill.frame, palette: palette)
        favorites.frame = local(f.favoritesTray)
        favorites.render(snapshot.favorites, frames: f, palette: palette)
        tablist.frame = local(f.tablistViewport)
        tablist.render(snapshot.space, renaming: snapshot.renaming, frames: f, palette: palette)
        dock.frame = local(f.dock)
        dock.render(snapshot.dock, frames: f, palette: palette)
        if let handle = frames.resizeHandle {
            resizeHandle.isHidden = false
            resizeHandle.frame = local(handle)
            resizeHandle.currentWidth = snapshot.sidebar.width
        } else {
            resizeHandle.isHidden = true
        }
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
    private let back = NSButton(title: "‹", target: nil, action: nil)
    private let forward = NSButton(title: "›", target: nil, action: nil)
    private let reload = NSButton(title: "↻", target: nil, action: nil)

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.titleRow)
        for (button, command) in [(back, Command.page(.back(.focused))), (forward, .page(.forward(.focused))), (reload, .page(.reload(.focused, ignoringCache: false)))] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.target = self
            button.action = #selector(fire(_:))
            button.tag = [back, forward, reload].firstIndex(of: button)!
            _ = command
            addSubview(button)
        }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    /// The title row is a window drag region (spike unknown 6: dragging the title row moves the window).
    override var mouseDownCanMoveWindow: Bool { true }

    func render(_ pill: URLPillSnapshot, palette: Palette) {
        back.isEnabled = pill.canGoBack
        forward.isEnabled = pill.canGoForward
        // TODO(W3): Arc's icon glyphs and the title row's exact button positions (right inset 6).
        let size = Metrics.urlPill.accessorySize.value
        let y = (bounds.height - size) / 2
        var x = bounds.width - Metrics.sidebar.titleRowRightInset.value
        for button in [reload, forward, back] {
            x -= size
            button.frame = CGRect(x: x, y: y, width: size, height: size)
            button.contentTintColor = palette.color(palette.tokens.foregroundStrong)
        }
    }

    @objc private func fire(_ sender: NSButton) {
        switch sender.tag {
        case 0: dispatch(.page(.back(.focused)))
        case 1: dispatch(.page(.forward(.focused)))
        default: dispatch(.page(.reload(.focused, ignoringCache: false)))
        }
    }
}

/// The URL pill: display URL or "Search or Enter URL…"; a click dispatches `.commandBar(.open(.editCurrent))`.
@MainActor
final class URLPillView: NSView {
    let dispatch: Dispatch
    private let label = NSTextField(labelWithString: "")

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.urlPill.cornerRadius.value
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(label)
        identify(.urlPill)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ pill: URLPillSnapshot, frame: CGRect, palette: Palette) {
        layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
        label.stringValue = pill.text ?? Copy.urlPlaceholder
        label.textColor = palette.color(pill.text == nil ? palette.tokens.foreground : palette.tokens.foregroundStrong)
        let inset = Metrics.urlPill.sideInset.value, icon = Metrics.urlPill.leadingIcon.value
        label.frame = CGRect(x: inset + icon, y: (bounds.height - Metrics.urlPill.textMinHeight.value) / 2,
                             width: max(0, bounds.width - 2 * inset - icon), height: Metrics.urlPill.textMinHeight.value)
        // TODO(W3): leading favicon (22) and the accessory buttons (28, radius 9); loading indicator.
    }

    override func mouseUp(with event: NSEvent) { dispatch(.commandBar(.open(.editCurrent))) }
}

/// The favorites grid. Tile click -> `.tab(.focus(id))`; drag between tiles and to/from the tab list.
@MainActor
final class FavoritesView: NSView {
    let dispatch: Dispatch
    private var tiles: [ItemID: FavoriteTileView] = [:]
    private let empty = NSTextField(wrappingLabelWithString: Copy.favoritesEmptyTitle)

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        empty.alignment = .center
        empty.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addSubview(empty)
        identify(.favoritesTray)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ favorites: FavoritesSnapshot, frames: SidebarFrames, palette: Palette) {
        let shown = Set(favorites.tiles.map(\.id))
        for (id, tile) in tiles where !shown.contains(id) { tile.removeFromSuperview(); tiles[id] = nil }
        for row in favorites.tiles {
            let tile = tiles[row.id] ?? {
                let t = FavoriteTileView(dispatch: dispatch, id: row.id)
                tiles[row.id] = t
                addSubview(t)
                return t
            }()
            if let rect = frames.favoriteTiles[row.id] { tile.frame = rect.offsetBy(dx: -frames.favoritesTray.minX, dy: -frames.favoritesTray.minY) }
            tile.render(row, palette: palette)
        }
        empty.isHidden = !favorites.tiles.isEmpty
        empty.textColor = palette.color(palette.tokens.foreground)
        empty.frame = bounds.insetBy(dx: Metrics.favorites.inset.value, dy: Metrics.favorites.inset.value)
        // TODO(W3): drag and drop between tiles and the tab list; the empty-state subtitle.
    }
}

@MainActor
final class FavoriteTileView: NSView {
    let dispatch: Dispatch
    let id: ItemID
    private let label = NSTextField(labelWithString: "")

    init(dispatch: @escaping Dispatch, id: ItemID) {
        self.dispatch = dispatch
        self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.favorites.tileRadius.value
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        identify(.favorite(id))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ row: TabRow, palette: Palette) {
        layer?.backgroundColor = palette.color(row.status == .current ? palette.tokens.tabCurrent : palette.tokens.itemBackground).cgColor
        label.stringValue = String(row.title.prefix(1))   // TODO(W3): favicon or CustomIcon; the selected ring (inset 1, radius 11)
        label.textColor = palette.color(palette.tokens.foregroundStrong)
        label.frame = bounds
    }

    override func mouseUp(with event: NSEvent) { dispatch(.tab(.focus(id))) }
}

/// The dock: Library (archive in v1), one cell per space, "+". Cell click -> `.space(.focus(id))`; "+" ->
/// `.sidebar(.popupMenu(.plusButton, at:))`; Library -> `.archive(.open)`. Press scale Metrics.dock.pressScale.
@MainActor
final class DockView: NSView {
    let dispatch: Dispatch
    private var cells: [SpaceID: DockCellView] = [:]
    private let library = NSButton(title: "☰", target: nil, action: nil)
    private let plus = NSButton(title: "+", target: nil, action: nil)

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        for button in [library, plus] {
            button.isBordered = false
            button.target = self
            addSubview(button)
        }
        library.action = #selector(openLibrary)
        plus.action = #selector(plusMenu)
        library.identify(.dockLibrary)
        plus.identify(.dockPlus)
        identify(.dock)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ items: [DockItem], frames: SidebarFrames, palette: Palette) {
        let local = { (r: CGRect) in r.offsetBy(dx: -frames.dock.minX, dy: -frames.dock.minY) }
        library.frame = local(frames.libraryButton)
        plus.frame = local(frames.plusButton)
        library.contentTintColor = palette.color(palette.tokens.foregroundStrong)
        plus.contentTintColor = palette.color(palette.tokens.foregroundStrong)
        let shown = Set(items.map(\.id))
        for (id, cell) in cells where !shown.contains(id) { cell.removeFromSuperview(); cells[id] = nil }
        for item in items {
            let cell = cells[item.id] ?? {
                let c = DockCellView(dispatch: dispatch, id: item.id)
                cells[item.id] = c
                addSubview(c)
                return c
            }()
            if let rect = frames.dockSpaces[item.id] { cell.frame = local(rect) }
            cell.render(item, palette: palette)
        }
    }

    @objc private func openLibrary() { dispatch(.archive(.open)) }
    @objc private func plusMenu() {
        let point = convert(CGPoint(x: plus.frame.midX, y: plus.frame.maxY), to: nil)
        dispatch(.sidebar(.popupMenu(.plusButton, at: point)))
    }
}

@MainActor
final class DockCellView: NSView {
    let dispatch: Dispatch
    let id: SpaceID
    private let glyph = NSTextField(labelWithString: "")
    private let dot = NSView()

    init(dispatch: @escaping Dispatch, id: SpaceID) {
        self.dispatch = dispatch
        self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.dock.cellRadius.value
        glyph.alignment = .center
        dot.wantsLayer = true
        addSubview(glyph)
        addSubview(dot)
        identify(.dockSpace(id))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ item: DockItem, palette: Palette) {
        layer?.backgroundColor = item.active ? palette.color(palette.tokens.itemBackground).cgColor : nil
        let compact = bounds.width < Metrics.dock.compactBelow.value
        switch item.icon {
        case .none:
            glyph.isHidden = true
            dot.isHidden = false
            let size = compact ? bounds.width / 2 : Metrics.dock.cellRadius.value * 2
            dot.frame = CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
            dot.layer?.cornerRadius = size / 2
            dot.layer?.backgroundColor = palette.color(item.color).cgColor
        case .custom(let icon):
            dot.isHidden = true
            glyph.isHidden = compact
            glyph.stringValue = Self.text(for: icon)
            glyph.frame = bounds
        }
        toolTip = item.title
    }

    /// TODO(W3): NamedIcon glyphs from an icon font and SF Symbols as images; the first pass shows text.
    static func text(for icon: CustomIcon) -> String {
        switch icon {
        case .emoji(let e): e
        case .named(let n): String(n.rawValue.prefix(1)).uppercased()
        case .symbol(let s): String(s.prefix(1)).uppercased()
        }
    }

    override func mouseUp(with event: NSEvent) { dispatch(.space(.focus(id))) }
    override func rightMouseUp(with event: NSEvent) { dispatch(.sidebar(.popupMenu(.space(id), at: event.locationInWindow))) }
}

/// The sidebar edge: drag resizes through `SidebarResizeDrag` (snap to 228, hide below 82), double-click resets to
/// 228. Dispatches `.sidebar(.resize(width:))` on every drag sample; a 3 pt indicator draws while dragging.
@MainActor
final class ResizeHandleView: NSView {
    let dispatch: Dispatch
    var currentWidth: Double = Metrics.sidebar.defaultWidth.value
    private var drag: SidebarResizeDrag?
    private var dragStartX: Double = 0

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.resizeHandle)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { dispatch(.sidebar(.resize(width: SidebarResizeDrag.resetWidth))); return }
        drag = SidebarResizeDrag(startWidth: currentWidth)
        dragStartX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        // TODO(W3): pointer velocity from successive samples (pt/s) and the haptic on snap.
        let width = drag.update(translation: event.locationInWindow.x - dragStartX, velocity: 0, time: event.timestamp)
        self.drag = drag
        dispatch(.sidebar(.resize(width: width)))
    }

    override func mouseUp(with event: NSEvent) { drag = nil }
}
