import BrkBase
import CoreGraphics
import Foundation

// Owner: F3. Window kinds and external links: a second standard window, incognito and Little Arc windows through
// the scratch-container seam (`ContainerScope.window`, `Session.scratch`, `SectionRole.scratch`), "Open in <space>",
// and links from other apps routed by Air Traffic Control (anatomy-m 1.8, 1.10, 4.2; visual-and-copy.md "Little
// Arc", "Air Traffic Control").
//
// Little Arc (Arc: `LittleBrowser`, hosted by BrkApp/LittleWindowController.swift in an NSPanel): one tab in the
// window's own container, no sidebar, Arc's default size until a frame is saved (Metrics.littleArc), the next one
// cascading by Metrics.littleArc.cascade from the last. Its entry points (`LittleBrowserEntryPoint`): the File menu
// (Opt+Cmd+N, `newLittle(nil)`: the command bar opens on an empty window), an external link (`externalURL` with
// "Links from other apps open in Little Arc" or a `.littleArc` route), an Opt+Cmd+click on a page link
// (`Rules/Peek.swift` `specialOpen` -> `newLittle(url)`). A Little Arc goes when its tab is moved out ("Open in"),
// closed (Shift+Cmd+W archives it; Cmd+W archives the tab and normalize closes the emptied window), or idle past
// the Links threshold (`Rules/Archive.swift`).

extension Work {
    mutating func windows(_ command: WindowCommand, in window: WindowID) {
        switch command {
        case .place(let placement):
            effects.append(.window(window, .place(placement)))
        case .toggleStayOnTop:
            state.doc.windows[window]?.stayOnTop.toggle()
        case .newBlank:
            guard let doc = state.doc.windows[window] else { return }
            let id = newWindow(kind: .blank, space: doc.space, sidebar: (true, doc.sidebarWidth), cascadingFrom: cascadeOrigin(doc))
            openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: id)
        case .new:
            // Cmd+N: a standard window on the dispatching window's space, sharing the global sidebar. It opens with
            // the command bar and an empty card, like Arc's new window (normalize fills nothing; `focus` would).
            // While the last standard window is closed (Brk kept running), Cmd+N brings that one back with the bar
            // instead, so the next launch does not restore a second window the user never asked to keep.
            if let closed = reopenClosedWindow() {
                openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: closed)
                return
            }
            guard let doc = state.doc.windows[window] else { return }
            let id = newWindow(kind: .standard, space: doc.space, sidebar: (doc.sidebarVisible || doc.kind == .little, doc.sidebarWidth), cascadingFrom: cascadeOrigin(doc))
            state.doc.windows[id]?.aiPanelWidth = doc.aiPanelWidth
            openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: id)
        case .newIncognito:
            // Shift+Cmd+N: a session-only window; its tabs live in its scratch tree and its pages browse in
            // `BrowsingContext.incognito` (F2 owns the context and badge; the projection gives it dark chrome).
            guard let doc = state.doc.windows[window] else { return }
            if state.session.privateSession == nil { state.session.privateSession = PrivateSessionID(ctx.newID()) }
            let id = newWindow(kind: .incognito, space: doc.space, sidebar: (true, doc.sidebarWidth), cascadingFrom: cascadeOrigin(doc))
            openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: id)
        case .newLittle(let url):
            // Opt+Cmd+N, an external link or an Opt+Cmd+click: one tab in the window's own container, no sidebar.
            // With a url the tab is shown at once; without one the command bar opens, and a Little Arc that is left
            // without a tab and without its bar closes (normalize).
            guard let doc = state.doc.windows[window] else { return }
            let id = newWindow(kind: .little, space: doc.space, sidebar: (false, doc.sidebarWidth))
            if let url {
                openScratchTab(url, in: id, focus: true)
            } else {
                openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: id)
            }
        case .close:
            // Shift+Cmd+W. An ephemeral window goes with its tree (a Little Arc's tab is archived with reason manual
            // so Restore Last Closed Tab brings it back; incognito tabs leave no trace). A standard window is removed
            // unless it is the last one (then AppKit's close-and-quit path takes over through `WindowEffect.close`).
            guard let doc = state.doc.windows[window], window != state.session.closedWindow else { return }
            switch doc.kind {
            case .little, .blank:
                if let tree = state.session.scratch[window], let root = tree.root(for: .scratch(window)) {
                    archiveTabs(tree[root]?.children ?? [], reason: .manual, in: window)
                }
                removeWindow(window)
            case .incognito:
                for tab in state.session.scratch[window]?.allTabs() ?? [] { unload(tab) }
                removeWindow(window)
                if !state.doc.windows.values.contains(where: { $0.kind == .incognito }), let epoch = state.session.privateSession {
                    state.session.privateSession = nil
                    effects.append(.disposeContext(ContextDisposal(id: DisposalID(ctx.newID()), context: .incognito(epoch))))
                }
            case .standard:
                let others = state.doc.windows.values.filter { $0.kind == .standard && $0.id != window && $0.id != state.session.closedWindow }
                if others.isEmpty { effects.append(.window(window, .close)) } else { removeWindow(window) }
            }
        case .openIn(let ref):
            let target: SpaceID? = switch ref {
            case .current: mostRecentStandardWindow().flatMap { state.doc.windows[$0]?.space } ?? state.doc.windows[window]?.space
            case .space(let id): id
            }
            guard let target, let today = state.doc.spaces[target]?.todayRoot else { return }
            promoteHeld(in: window, targetSpace: target, position: .into(parent: today, index: 0))
        case .openInFolder(let folder):
            guard case .folder? = state.doc.tree[folder]?.body,
                  case .pinned(let space)? = state.doc.tree.role(of: folder) else { return }
            promoteHeld(in: window, targetSpace: space, position: .into(parent: folder, index: Int.max))
        }
    }

    /// Open In explicitly opens the committed address in a new destination context. Form/session history resets;
    /// accepted downloads keep their original browser under the transfer owner's lease.
    private mutating func promoteHeld(in window: WindowID, targetSpace: SpaceID, position: TreePosition) {
        guard let doc = state.doc.windows[window], let held = heldTab(in: window),
              var tab = state.displayedTab(held, in: window, for: .savedDocument), state.doc.spaces[targetSpace] != nil else { return }
        let address = state.address(of: held, in: window, for: .visible)
        tab.url = state.address(of: held, in: window, for: .savedDocument)
        let id = ItemID(ctx.newID())
        do { try state.doc.tree.insert(id, .tab(tab), at: position, createdAt: ctx.now) } catch { return }
        _ = removeItem(held)
        let standard = mostRecentStandardWindow() ?? reopenClosedWindow() ?? newWindow(kind: .standard, space: targetSpace, sidebar: (true, doc.sidebarWidth))
        if case .peek? = state.session.windows[window]?.overlay { state.session.windows[window]?.overlay = nil }
        if doc.kind == .little {
            // Links it opened are tabs of its own: archived as closing it does, not dropped with the window.
            if let tree = state.session.scratch[window], let root = tree.root(for: .scratch(window)) {
                archiveTabs(tree[root]?.children ?? [], reason: .manual, in: window)
            }
            removeWindow(window)
        }
        focus(id, in: standard)
        if let address, address != tab.url { request(address, for: PageID(window: standard, item: id)) }
    }

    /// Links from other apps (Apple Event GetURL). The first matching route wins (Air Traffic Control, in the
    /// user's order); else Air Traffic Control's Default (`LinkSettings.externalDefault`: a chosen space, else "Links
    /// from other apps open in Little Arc", else the most recent standard window's current space). A url the bar
    /// may not open is ignored.
    mutating func externalURL(_ url: URL) {
        guard isAllowedURL(url) else { return }
        open(url, at: state.doc.linkRoutes.first { $0.matches(url) }?.destination ?? state.doc.settings.links.externalDefault)
    }

    /// Opens `url` where a route says. A route naming a space that is gone falls back to the most recent space.
    mutating func open(_ url: URL, at destination: LinkDestination) {
        let recent = mostRecentStandardWindow()
        switch destination {
        case .littleArc:
            // The window it is asked from only lends its space and sidebar width: the closed window will do.
            guard let from = recent ?? state.doc.windows.keys.sorted().first else { return }
            windows(.newLittle(url), in: from)
        case .space(let space) where state.doc.spaces[space] != nil:
            let window = recent ?? reopenClosedWindow() ?? newWindow(kind: .standard, space: space, sidebar: (true, Metrics.sidebar.defaultWidth.value))
            openTab(url, inSpace: space, window: window, focus: true)
        case .space, .mostRecentSpace:
            // With the last standard window closed while Brk keeps running, the link brings it back.
            guard let window = recent ?? reopenClosedWindow()
                    ?? state.doc.spaceOrder.first.map({ newWindow(kind: .standard, space: $0, sidebar: (true, Metrics.sidebar.defaultWidth.value)) }),
                  let space = state.doc.windows[window]?.space else { return }
            openTab(url, inSpace: space, window: window, focus: true)
        }
    }

    // MARK: Helpers

    /// A new `WindowDoc` (and its session and scratch tree) on `space`. A new window appears down and right of the
    /// one it was asked from (`cascadingFrom`, the dispatching window's frame), so Cmd+N visibly adds a window
    /// instead of covering the old one exactly; a Little Arc cascades from the last Little Arc that has reported a
    /// frame (Arc: "new windows cascade by 30"). The step is Little Arc's measured 30 for every kind until Arc's
    /// standard-window cascade is measured. Without a frame to cascade from the host centers the window at the
    /// kind's default size. Returns its id.
    @discardableResult
    mutating func newWindow(kind: WindowKind, space: SpaceID, sidebar: (visible: Bool, width: Double), cascadingFrom origin: CGRect? = nil) -> WindowID {
        // A new standard window (a Little Arc page's window.open) takes the closed one's place for the next launch.
        if kind == .standard, let closed = state.session.closedWindow { removeWindow(closed) }
        let id = WindowID(ctx.newID())
        let step = Metrics.littleArc.cascade.value
        var bounds = origin.map { $0.offsetBy(dx: step, dy: -step) }
        if kind == .little, let last = state.doc.windows.values.filter({ $0.kind == .little }).compactMap(\.bounds).max(by: { $0.minX < $1.minX }) {
            bounds = last.offsetBy(dx: step, dy: -step)
        }
        state.doc.windows[id] = WindowDoc(id: id, kind: kind, bounds: bounds, space: space, activeBySpace: [:],
                                          stayOnTop: kind == .little, sidebarVisible: sidebar.visible, sidebarWidth: sidebar.width)
        ensureSession(id)
        return id
    }

    /// The frame a new window cascades from. A Little Arc's small panel (its sidebar always hidden) is no model for a
    /// full window: one asked from it opens at its kind's default size.
    func cascadeOrigin(_ doc: WindowDoc) -> CGRect? { doc.kind == .little ? nil : doc.bounds }

    /// The last standard window's close button or Shift+Cmd+W (`Session.closedWindow`): its pages unload (their
    /// addresses stay in its slots and move into the tabs) and its session starts over, so nothing it showed plays or
    /// waits out of sight; its `WindowDoc` stays for the next launch and for the commands that still need a window.
    mutating func closeKeepingForNextLaunch(_ id: WindowID) {
        for page in state.session.loaded.filter({ $0.window == id }).sorted() { unload(page) }
        let size = state.session.windows[id]?.contentSize ?? Metrics.window.defaultSize.value
        state.session.windows[id] = .fresh(contentSize: size)
        state.session.closedWindow = id
    }

    /// Brings the closed standard window back (its host opens again, at its saved frame, showing what it showed; normalize
    /// loads its page). Nil when no window is closed.
    mutating func reopenClosedWindow() -> WindowID? {
        guard let id = state.session.closedWindow else { return nil }
        state.session.closedWindow = nil
        guard state.doc.windows[id] != nil else { return nil }
        ensureSession(id)
        return id
    }

    /// Drops a window and everything only it held (session, scratch tree, loaded pages of its scratch tabs).
    mutating func removeWindow(_ id: WindowID) {
        for page in state.session.loaded.filter({ $0.window == id }).sorted() { unload(page) }
        state.doc.windows[id] = nil
        state.session.windows[id] = nil
        state.session.scratch[id] = nil
        if state.session.closedWindow == id { state.session.closedWindow = nil }
    }

    /// The session and scratch tree a window needs before the rules can use it (normalize repairs the same). The
    /// session starts at the kind's default content size, so layout is right before AppKit reports a frame.
    mutating func ensureSession(_ id: WindowID) {
        if state.session.windows[id] == nil {
            let size = state.doc.windows[id]?.kind == .little ? Metrics.littleArc.defaultSize.value : Metrics.window.defaultSize.value
            state.session.windows[id] = .fresh(contentSize: size)
        }
        if state.session.scratch[id] == nil {
            var tree = SidebarTree(scope: .window(id))
            tree.makeRoot(ItemID(ctx.newID()), .scratch(id), createdAt: ctx.now)
            state.session.scratch[id] = tree
        }
    }

    /// A tab in the window's scratch tree (a Little Arc's page, a Peek's page), loaded, shown when `focus`.
    @discardableResult
    mutating func openScratchTab(_ url: URL, in window: WindowID, focus focusIt: Bool) -> ItemID? {
        ensureSession(window)
        guard let root = state.session.scratch[window]?.root(for: .scratch(window)) else { return nil }
        let id = ItemID(ctx.newID())
        var inserted = false
        state.withTree(.window(window)) { tree in
            do {
                try tree.insert(id, .tab(Tab(url: nil, title: "", lastActiveAt: ctx.now)), at: .into(parent: root, index: 0), createdAt: ctx.now)
                inserted = true
            } catch {}
        }
        guard inserted else { return nil }
        request(url, for: PageID(window: window, item: id))
        if focusIt { focus(id, in: window) }
        return id
    }

    /// The tab "Open in" moves: the window's peeked tab, else a Little Arc's shown tab.
    func heldTab(in window: WindowID) -> ItemID? { state.heldTab(in: window) }

    func mostRecentStandardWindow() -> WindowID? { state.mostRecentStandardWindow() }
}

extension AppState {
    /// The standard window the user used last: the one that became key most recently, then the one whose shown tab is
    /// most recent, ties by id.
    func mostRecentStandardWindow() -> WindowID? {
        doc.windows.values.filter { $0.kind == .standard && $0.id != session.closedWindow }
            .sorted { a, b in
                let (x, y) = (session.windows[a.id]?.activationOrder ?? 0,
                              session.windows[b.id]?.activationOrder ?? 0)
                if x != y { return x > y }
                let ta = a.activeBySpace[a.space].map(lastActiveOf) ?? Instant(milliseconds: 0)
                let tb = b.activeBySpace[b.space].map(lastActiveOf) ?? Instant(milliseconds: 0)
                return ta != tb ? ta > tb : a.id < b.id
            }
            .first?.id
    }
}

extension Command {
    /// Whether this command, sent to the closed window (`Session.closedWindow`: the menus, the Dock and the Settings
    /// window send there while no browser window is open), brings that window back first. The Settings window's own
    /// commands and the app-wide ones run without it; the window-making ones decide for themselves (Cmd+N brings it
    /// back, a new incognito, blank or Little window only takes its space); everything else shows something in it.
    var reopensClosedWindow: Bool {
        switch self {
        case .settings, .profile, .sidebarData, .site: false
        case .tabTools(.preferences), .page(.copyURL): false
        case .later(.aiCommandBar), .app(.help(.open)): true
        case .later, .app: false
        case .window(.place), .window(.toggleStayOnTop), .window(.openIn), .window(.openInFolder): true
        case .window(.new), .window(.newIncognito), .window(.newBlank), .window(.newLittle), .window(.close): false
        default: true
        }
    }
}

extension AppState {
    /// The window of any kind the user used last (the one that became key most recently), ties by id: where BrkApp
    /// sends what no key browser window takes, the menu, Settings and About while one of those is in front.
    public func lastUsedWindow() -> WindowID? {
        doc.windows.keys.max { a, b in
            let (x, y) = (session.windows[a]?.activationOrder ?? 0, session.windows[b]?.activationOrder ?? 0)
            return x != y ? x < y : a > b
        }
    }

    /// The tab "Open in" moves: the window's peeked tab, else a Little Arc's shown tab.
    func heldTab(in window: WindowID) -> ItemID? {
        if let peeked = peekedTab(in: window) { return peeked }
        guard doc.windows[window]?.kind == .little else { return nil }
        return focusedPane(in: window)
    }

    /// An Air Traffic Control route as the editor accepts it, with a destination that names an existing space. A
    /// `.matches` pattern is normalized to a host glob (`LinkRoute.normalizedPattern`) and refused when nothing usable
    /// is left; a `.contains` text is trimmed and lowercased and may be empty (New Route adds an empty row, which
    /// matches nothing until the user types). Nil refuses the route.
    func validRoute(_ route: LinkRoute) -> LinkRoute? {
        if case .space(let id) = route.destination, doc.spaces[id] == nil { return nil }
        if route.match == .contains {
            let text = route.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.contains(where: \.isWhitespace) else { return nil }
            return LinkRoute(id: route.id, pattern: text, destination: route.destination, match: .contains)
        }
        guard let pattern = LinkRoute.normalizedPattern(route.pattern) else { return nil }
        return LinkRoute(id: route.id, pattern: pattern, destination: route.destination, match: route.match)
    }
}

extension LinkRoute {
    /// A pattern as typed ("Open.Spotify.com/", "https://*.spotify.com", " spotify.com. ") reduced to the host glob
    /// `matches` compares: trimmed, lowercased, without a scheme, path, query, port, or trailing dot. Nil when
    /// nothing usable is left (empty text, a bare "*" or "*.", a pattern with spaces inside).
    public static func normalizedPattern(_ text: String) -> String? {
        var pattern = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = pattern.range(of: "://") { pattern = String(pattern[range.upperBound...]) }
        if let cut = pattern.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == ":" }) { pattern = String(pattern[..<cut]) }
        while pattern.hasSuffix(".") { pattern.removeLast() }
        while pattern.hasPrefix(".") { pattern.removeFirst() }
        let host = pattern.hasPrefix("*.") ? String(pattern.dropFirst(2)) : pattern
        guard !host.isEmpty, !host.contains(" "), !host.contains("*") else { return nil }
        return pattern
    }
}

/// Arc's "Open in" menu for a Little Arc or a Peek (`LittleBrowserMoveMenu`): every space in dock order, each
/// moving the held tab to that space (`.window(.openIn(.space(id)))`), then "Open in current Space"
/// (`.window(.openIn(.current))`, the most recently used standard window's space, what Cmd+O does). Pure, so the
/// Peek card and the Little Arc panel build the same menu from the snapshot's dock.
public enum OpenInMenu {
    public static let currentSpaceTitle = "Open in current Space"

    public static func model(spaces: [DockItem], folders: [FolderDestinationCandidate] = []) -> MenuModel {
        var entries: [MenuEntry] = spaces.map { .action(title: $0.title, command: .window(.openIn(.space($0.id))), enabled: true) }
        entries += folders.map { .action(title: "Folder: " + $0.title, command: .window(.openInFolder($0.id)), enabled: true) }
        if !entries.isEmpty { entries.append(.separator) }
        entries.append(.action(title: currentSpaceTitle, command: .window(.openIn(.current)), enabled: true))
        return MenuModel(entries: entries)
    }

    /// The button's label: "Open in <space>" for the space Cmd+O would use.
    public static func buttonTitle(space: String) -> String { "Open in \(space)" }
}

extension WindowSession {
    static func fresh(contentSize: CGSize) -> WindowSession {
        WindowSession(contentSize: contentSize, overlay: nil, overlayOpens: 0, peek: false, renaming: nil, dialog: nil, profileDialog: nil,
                      lastLibraryPage: nil, suggestions: nil, recentCycle: nil, heldModifiers: [], keyRouting: .empty)
    }
}

extension SidebarTree {
    /// The root with this role, if the tree has it.
    func root(for role: SectionRole) -> ItemID? {
        items.values.first { $0.parent == nil && { if case .section(let s) = $0.body { s.role == role } else { false } }($0) }?.id
    }

    /// Every tab in the tree, any depth, by id (so callers archive in a stable order).
    func allTabs() -> [ItemID] {
        items.values.compactMap { if case .tab = $0.body { $0.id } else { nil } }.sorted()
    }
}
