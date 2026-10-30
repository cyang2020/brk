import BrkBase
import CoreGraphics
import Foundation

// Owner: F3. Window kinds and external links: a second standard window, incognito and Little Arc windows through
// the scratch-container seam (`ContainerScope.window`, `Session.scratch`, `SectionRole.scratch`), "Open in <space>",
// and links from other apps routed by Air Traffic Control. First-pass bodies; F3 fills in Arc's behavior
// (anatomy-m 1.8, 1.10; visual-and-copy.md "Little Arc", "Air Traffic Control").

extension Work {
    mutating func windows(_ command: WindowCommand, in window: WindowID) {
        switch command {
        case .new:
            // Cmd+N: a standard window on the dispatching window's space, sharing the global sidebar. It shows the
            // space's most recent loaded item (normalize fills nothing; `focus` would, so start empty like Arc's
            // new window with the command bar).
            guard let doc = state.doc.windows[window] else { return }
            let id = newWindow(kind: .standard, space: doc.space, sidebar: (doc.sidebarVisible, doc.sidebarWidth))
            openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: id)
        case .newIncognito:
            // Shift+Cmd+N: a session-only window; its tabs live in its scratch tree and its pages browse in
            // `BrowsingContext.incognito`. TODO(F3): Arc's incognito theme (dark, no space theme).
            guard let doc = state.doc.windows[window] else { return }
            let id = newWindow(kind: .incognito, space: doc.space, sidebar: (true, doc.sidebarWidth))
            openOverlay({ .commandBar(openID: $0, target: .newTab) }, in: id)
        case .newLittle(let url):
            // Opt+Cmd+N (or an external link): one tab in the window's own container, no sidebar. With a url the tab
            // is shown at once; without one the command bar opens. TODO(F3): `LittleBrowserEntryPoint`, the
            // auto-archive threshold (`LinkSettings.littleArcAutoArchive`), the "Open in" hint.
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
            guard let doc = state.doc.windows[window] else { return }
            switch doc.kind {
            case .little:
                if let tree = state.session.scratch[window], let root = tree.root(for: .scratch(window)) {
                    archiveTabs(tree[root]?.children ?? [], reason: .manual)
                }
                removeWindow(window)
            case .incognito:
                for tab in state.session.scratch[window]?.allTabs() ?? [] { unload(tab) }
                removeWindow(window)
                if !state.doc.windows.values.contains(where: { $0.kind == .incognito }) { effects.append(.forgetBrowsingData(.incognito)) }
            case .standard:
                let others = state.doc.windows.values.filter { $0.kind == .standard && $0.id != window }
                if others.isEmpty { effects.append(.window(window, .close)) } else { removeWindow(window) }
            }
        case .openIn(let ref):
            // Cmd+O: the held tab (a Little Arc's, or the window's peeked tab) moves to the top of the target
            // space's Today and a standard window on that space shows it; the Little Arc window or the Peek closes.
            guard let doc = state.doc.windows[window], let held = heldTab(in: window) else { return }
            let target: SpaceID? = switch ref {
            case .current: mostRecentStandardWindow().map { state.doc.windows[$0]!.space } ?? doc.space
            case .space(let id): id
            }
            guard let target, let today = state.doc.spaces[target]?.todayRoot else { return }
            let removed = removeItem(held)
            guard let (_, tab) = removed.first else { return }
            let id = ItemID(ctx.newID())
            do { try state.doc.tree.insert(id, .tab(tab), at: .into(parent: today, index: 0), createdAt: ctx.now) } catch { return }
            state.session.loaded.insert(id)
            let standard = mostRecentStandardWindow() ?? newWindow(kind: .standard, space: target, sidebar: (true, doc.sidebarWidth))
            if case .peek? = state.session.windows[window]?.overlay { state.session.windows[window]!.overlay = nil }
            if doc.kind == .little { removeWindow(window) }
            focus(id, in: standard)
        }
    }

    /// Links from other apps (Apple Event GetURL). The first matching route wins; else the Links settings decide:
    /// `defaultRoute`, then "Links from other apps open in Little Arc", else the most recent standard window's
    /// current space. A url the bar may not open is ignored. TODO(F3): Arc's `LinkDestination` copy and the toast.
    mutating func externalURL(_ url: URL) {
        guard isAllowedURL(url) else { return }
        let destination = state.doc.linkRoutes.first { $0.matches(url) }?.destination
            ?? state.doc.settings.links.defaultRoute
            ?? (state.doc.settings.links.externalLinksInLittleArc ? .littleArc : .mostRecentSpace)
        open(url, at: destination)
    }

    /// Opens `url` where a route says.
    mutating func open(_ url: URL, at destination: LinkDestination) {
        let recent = mostRecentStandardWindow()
        switch destination {
        case .littleArc:
            guard let from = recent ?? state.doc.windows.keys.sorted().first else { return }
            windows(.newLittle(url), in: from)
        case .space(let space) where state.doc.spaces[space] != nil:
            let window = recent ?? newWindow(kind: .standard, space: space, sidebar: (true, Metrics.sidebar.defaultWidth.value))
            openTab(url, inSpace: space, window: window, focus: true)
        case .space, .mostRecentSpace:
            guard let window = recent, let space = state.doc.windows[window]?.space else { return }
            openTab(url, inSpace: space, window: window, focus: true)
        }
    }

    // MARK: Helpers

    /// A new `WindowDoc` (and, through normalize, its session and scratch tree) on `space`. Returns its id.
    @discardableResult
    mutating func newWindow(kind: WindowKind, space: SpaceID, sidebar: (visible: Bool, width: Double)) -> WindowID {
        let id = WindowID(ctx.newID())
        state.doc.windows[id] = WindowDoc(id: id, kind: kind, bounds: nil, space: space, activeBySpace: [:],
                                          sidebarVisible: sidebar.visible, sidebarWidth: sidebar.width)
        ensureSession(id)
        return id
    }

    /// Drops a window and everything only it held (session, scratch tree, loaded pages of its scratch tabs).
    mutating func removeWindow(_ id: WindowID) {
        for tab in state.session.scratch[id]?.allTabs() ?? [] { unload(tab) }
        state.doc.windows[id] = nil
        state.session.windows[id] = nil
        state.session.scratch[id] = nil
    }

    /// The session and scratch tree a window needs before the rules can use it (normalize repairs the same).
    mutating func ensureSession(_ id: WindowID) {
        if state.session.windows[id] == nil { state.session.windows[id] = .fresh(contentSize: Metrics.window.defaultSize.value) }
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
                try tree.insert(id, .tab(Tab(url: url, title: "", lastActiveAt: ctx.now)), at: .into(parent: root, index: 0), createdAt: ctx.now)
                inserted = true
            } catch {}
        }
        guard inserted else { return nil }
        state.session.loaded.insert(id)
        if focusIt { focus(id, in: window) }
        return id
    }

    /// The tab "Open in" moves: the window's peeked tab, else a Little Arc's shown tab.
    func heldTab(in window: WindowID) -> ItemID? { state.heldTab(in: window) }

    /// The standard window the user used last: the one whose shown tab is most recent, ties by id.
    /// TODO(F3): track key-window order in the session (`WindowEvent.becameKey`) instead of guessing by recency.
    func mostRecentStandardWindow() -> WindowID? {
        state.doc.windows.values.filter { $0.kind == .standard }
            .sorted { a, b in
                let (x, y) = (a.activeBySpace[a.space].map(state.lastActiveOf) ?? Instant(milliseconds: 0),
                              b.activeBySpace[b.space].map(state.lastActiveOf) ?? Instant(milliseconds: 0))
                return x != y ? x > y : a.id < b.id
            }
            .first?.id
    }
}

extension AppState {
    /// The tab "Open in" moves: the window's peeked tab, else a Little Arc's shown tab.
    func heldTab(in window: WindowID) -> ItemID? {
        if case .peek(_, let tab)? = session.windows[window]?.overlay { return tab }
        guard doc.windows[window]?.kind == .little else { return nil }
        return focusedPane(in: window)
    }
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

    /// Every tab in the tree, any depth.
    func allTabs() -> [ItemID] {
        items.values.compactMap { if case .tab = $0.body { $0.id } else { nil } }
    }
}
