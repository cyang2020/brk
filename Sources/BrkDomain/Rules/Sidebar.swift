import BrkBase
import CoreGraphics
import Foundation

// Owner: W1. Sidebar structure (rename, move, folders), spaces, sidebar chrome, app commands and window events.

extension Work {
    mutating func items(_ command: ItemCommand, in window: WindowID) {
        switch command {
        case .beginRename(let ref):
            // The row becomes a text field: its collapsed ancestors (folders, the Pinned section) expand so the field
            // can show, and a hidden sidebar peeks. `.focused` is the focused tab; an id may also name a folder.
            let id: ItemID?
            switch ref {
            case .focused: id = state.resolveTab(.focused, in: window)
            case .item(let item): id = item
            }
            guard let id, let scope = state.locate(id), let tree = state.tree(scope), let kind = tree[id]?.kind,
                  kind == .tab || kind == .folder else { return }
            var ancestor = tree[id]?.parent
            while let a = ancestor, let node = tree[a] {
                if case .folder(let f) = node.body, f.collapsed { state.withTree(scope) { $0.updateFolder(a) { $0.collapsed = false } } }
                if case .section(let section) = node.body, case .pinned(let space) = section.role, state.doc.spaces[space]?.pinnedCollapsed == true {
                    state.doc.spaces[space]!.pinnedCollapsed = false
                }
                ancestor = node.parent
            }
            if state.session.windows[window]?.renaming != id { state.session.windows[window]!.renaming = id }
            peekIfHidden(window)
        case .rename(let id, let title):
            // Ends a rename. Nil cancels. A tab's custom title is the trimmed text ("" clears it, so the page title
            // shows again); a folder keeps its old title for blank text. At most 500 characters.
            if state.session.windows[window]?.renaming != nil { state.session.windows[window]!.renaming = nil }
            guard let title, let scope = state.locate(id) else { return }
            let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            state.withTree(scope) { tree in
                tree.updateTab(id) { tab in
                    let custom = trimmed.isEmpty ? nil : trimmed
                    if tab.customTitle != custom { tab.customTitle = custom }
                }
                if !trimmed.isEmpty { tree.updateFolder(id) { if $0.title != trimmed { $0.title = trimmed } } }
            }
        case .move(let id, .into(let parent, let index)):
            // Refused (no-op) for roots, cycles and what Placement forbids. A window whose shown item left its space
            // is repaired by normalize; a split the move dissolved is replaced by its pane.
            let wasPinned = state.role(of: id)?.kind == .pinned || state.role(of: id)?.kind == .favorites
            if moveItem(id, to: .into(parent: parent, index: index)), !wasPinned,
               state.role(of: id)?.kind == .pinned || state.role(of: id)?.kind == .favorites {
                setPinnedAddresses(under: id, in: window)
            }
        case .move(let id, .space(let target)):
            // Dropped on a dock space: a Pinned item goes to the end of that space's Pinned, anything else to the top
            // of its Today. The moved tabs count as used now (regression finding 5: a dragged tab is not swept
            // right after the drop).
            guard let space = state.doc.spaces[target], let role = state.role(of: id), state.locate(id) == .global else { return }
            let position: TreePosition = role.kind == .pinned ? .into(parent: space.pinnedRoot, index: Int.max) : .into(parent: space.todayRoot, index: 0)
            guard moveItem(id, to: position) else { return }
            stamp(Set(state.doc.tree.tabs(under: id)))
        case .newFolder:
            // "New Folder" at the top of the current space's Pinned, which expands; the folder is in rename mode.
            guard let space = state.doc.windows[window].flatMap({ state.doc.spaces[$0.space] }) else { return }
            let folder = ItemID(ctx.newID())
            do {
                try state.doc.tree.insert(folder, .folder(Folder(title: "New Folder", collapsed: false)), at: .into(parent: space.pinnedRoot, index: 0), createdAt: ctx.now)
            } catch { return }
            if space.pinnedCollapsed { state.doc.spaces[space.id]!.pinnedCollapsed = false }
            state.session.windows[window]!.renaming = folder
            peekIfHidden(window)
        case .toggleFolder(let id):
            guard let scope = state.locate(id) else { return }
            state.withTree(scope) { $0.updateFolder(id) { $0.collapsed.toggle() } }
        case .deleteFolder(let id):
            // "Deleting this folder will archive the tabs inside it."
            guard let scope = state.locate(id), case .folder? = state.tree(scope)?[id]?.body else { return }
            archiveTabs([id], reason: .containerDeleted, in: window)
        case .setIcon(let id, let icon):
            guard let scope = state.locate(id) else { return }
            state.withTree(scope) { tree in
                tree.updateTab(id) { if $0.icon != icon { $0.icon = icon } }
                tree.updateFolder(id) { if $0.icon != icon { $0.icon = icon } }
                tree.updateSplit(id) { if $0.icon != icon { $0.icon = icon } }
            }
        }
    }

    mutating func spaces(_ command: SpaceCommand, in window: WindowID) {
        switch command {
        case .create(let title, let icon, let theme):
            // Fresh Pinned and Today roots; a blank title is stored "" and shown as "Space N" by dock position. The
            // dispatching window switches to it (nothing shown) and the dialog closes.
            let space = SpaceID(ctx.newID()), pinned = ItemID(ctx.newID()), today = ItemID(ctx.newID())
            guard state.doc.tree.makeRoot(pinned, .pinned(space), createdAt: ctx.now),
                  state.doc.tree.makeRoot(today, .today(space), createdAt: ctx.now) else { return }
            state.doc.spaces[space] = Space(id: space, title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon,
                                            theme: clamped(theme), profile: .default, pinnedRoot: pinned, todayRoot: today, pinnedCollapsed: false)
            state.doc.spaceOrder.append(space)
            showSpace(space, in: window)
            if state.session.windows[window]?.dialog != nil { state.session.windows[window]!.dialog = nil }
        case .update(let id, let title, let icon, let theme):
            // Patches what is given (a blank title keeps the old one) and closes this window's dialog.
            guard var space = state.doc.spaces[id] else { return }
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { space.title = title }
            if let icon { space.icon = icon }
            if let theme { space.theme = clamped(theme) }
            if space != state.doc.spaces[id] { state.doc.spaces[id] = space }
            if state.session.windows[window]?.dialog != nil { state.session.windows[window]!.dialog = nil }
        case .delete(let id):
            // Refused for the last space. Its tabs are archived (reason containerDeleted, in sidebar order), its roots
            // removed, and windows on it move to the next space in dock order, else the previous one.
            guard let space = state.doc.spaces[id], let index = state.doc.spaceOrder.firstIndex(of: id), state.doc.spaceOrder.count > 1 else { return }
            let order = state.doc.spaceOrder
            let neighbour = index + 1 < order.count ? order[index + 1] : order[index - 1]
            for (wid, w) in state.doc.windows where w.space == id { showSpace(neighbour, in: wid) }
            let contents = [space.pinnedRoot, space.todayRoot].flatMap { state.doc.tree[$0]?.children ?? [] }
            archiveTabs(contents, reason: .containerDeleted, in: window)
            for root in [space.pinnedRoot, space.todayRoot] {
                for (tab, _) in state.doc.tree.removeRoot(root) ?? [] { unload(tab) }
            }
            state.doc.spaces[id] = nil
            state.doc.spaceOrder.remove(at: index)
            for (wid, w) in state.doc.windows where w.activeBySpace[id] != nil { state.doc.windows[wid]!.activeBySpace[id] = nil }
        case .move(let id, let index):
            // `index` counts the dock after the space is taken out, clamped.
            guard let from = state.doc.spaceOrder.firstIndex(of: id) else { return }
            let to = min(max(index, 0), state.doc.spaceOrder.count - 1)
            guard to != from else { return }
            state.doc.spaceOrder.remove(at: from)
            state.doc.spaceOrder.insert(id, at: to)
        case .focus(let id):
            // The space's last active item shows again (activeBySpace keeps it per space).
            showSpace(id, in: window)
        case .step(let step):
            guard let current = state.doc.windows[window]?.space, let i = state.doc.spaceOrder.firstIndex(of: current) else { return }
            let j = step == .next ? i + 1 : i - 1
            if state.doc.spaceOrder.indices.contains(j) { showSpace(state.doc.spaceOrder[j], in: window) }
        case .togglePinnedSection(let ref):
            let id: SpaceID? = switch ref {
            case .current: state.doc.windows[window]?.space
            case .space(let s): s
            }
            if let id, state.doc.spaces[id] != nil { state.doc.spaces[id]!.pinnedCollapsed.toggle() }
        }
    }

    mutating func sidebar(_ command: SidebarCommand, in window: WindowID) {
        switch command {
        case .toggle:
            state.doc.windows[window]!.sidebarVisible.toggle()
            if state.session.windows[window]?.peek == true { state.session.windows[window]!.peek = false }
        case .resize(let width):
            // After `SidebarResizeDrag`: 0 (or less) hides the sidebar and keeps the stored width; anything else shows
            // it at the width rounded to whole points and clamped to Metrics.sidebar.minWidth...maxWidth.
            guard width.isFinite else { return }
            if width <= 0 {
                if state.doc.windows[window]!.sidebarVisible { state.doc.windows[window]!.sidebarVisible = false }
                return
            }
            let clamped = min(max(width.rounded(), Metrics.sidebar.minWidth.value), Metrics.sidebar.maxWidth.value)
            if state.doc.windows[window]!.sidebarWidth != clamped { state.doc.windows[window]!.sidebarWidth = clamped }
            if !state.doc.windows[window]!.sidebarVisible { state.doc.windows[window]!.sidebarVisible = true }
            if state.session.windows[window]?.peek == true { state.session.windows[window]!.peek = false }
        case .peek(let open):
            // Only a hidden sidebar floats.
            let peek = open && !state.doc.windows[window]!.sidebarVisible
            if state.session.windows[window]?.peek != peek { state.session.windows[window]!.peek = peek }
        case .openDialog(let request):
            // Nil closes; an unknown space is ignored. A hidden sidebar peeks so the dialog shows; focus derives to it.
            let dialog: SpaceDialog?
            switch request {
            case nil: dialog = nil
            case .newSpace?: dialog = .newSpace
            case .editSpace(.current)?: dialog = .editSpace(state.doc.windows[window]!.space)
            case .editSpace(.space(let id))?:
                guard state.doc.spaces[id] != nil else { return }
                dialog = .editSpace(id)
            }
            if state.session.windows[window]?.dialog != dialog { state.session.windows[window]!.dialog = dialog }
            if dialog != nil { peekIfHidden(window) }
        case .popupMenu(let request, let at):
            // A native menu built from state; each entry carries the real command it dispatches. A menu with no
            // entries (unknown item or space) emits nothing.
            let menu = menuModel(for: request, in: window)
            if !menu.entries.isEmpty { effects.append(.popupMenu(window, menu, at: at)) }
        }
    }

    /// The popup menus (Electron `menuFor`, labels from the action table and Arc's copy):
    /// - plus button: New Tab, New Folder, New Space;
    /// - space: Rename Space, Change Space Icon…, Edit Theme Color… (each opens the space dialog), Delete Space
    ///   (disabled for the last space);
    /// - folder: Rename Current Item, Collapse or Expand Folder, Delete Folder;
    /// - split: Pin/Unpin Tab, then "Move to Pinned in X" / "Move to Today in X" for every other space;
    /// - tab: Pin/Unpin Tab, Rename Current Item, Reset Tab to Original URL (when it drifted), the moves, then
    ///   Today: Archive Tab (`.tab(.close)`); Pinned or Favorites: Close and Keep Pinned (`.tab(.close)`) and Archive
    ///   Tab (`.tab(.archive)`).
    func menuModel(for request: PopupMenuRequest, in window: WindowID) -> MenuModel {
        func entry(_ title: String, _ command: Command, enabled: Bool = true) -> MenuEntry {
            .action(title: title, command: command, enabled: enabled)
        }
        switch request {
        case .selection(let ids):
            let publicIDs = ids.filter { state.locate($0) == .global }
            return MenuModel(entries: publicIDs.isEmpty ? [] : [entry("Export Selected Tabs…", .app(.export(.items(publicIDs))))])
        case .plusButton:
            return MenuModel(entries: [
                entry("New Tab", .commandBar(.open(.newTab))),
                entry("New Folder", .item(.newFolder)),
                entry("New Space", .sidebar(.openDialog(.newSpace))),
            ])
        case .space(let id):
            guard state.doc.spaces[id] != nil else { return MenuModel(entries: []) }
            let edit = Command.sidebar(.openDialog(.editSpace(.space(id))))
            return MenuModel(entries: [
                entry("Rename Space", edit), entry("Change Space Icon…", edit), entry("Edit Theme Color…", edit), .separator,
                entry("Export Space…", .app(.export(.space(.space(id))))),
                entry("Delete Space", .space(.delete(id)), enabled: state.doc.spaceOrder.count > 1),
            ])
        case .item(let id):
            guard let scope = state.locate(id), let tree = state.tree(scope), let node = tree[id], let role = tree.role(of: id) else {
                return MenuModel(entries: [])
            }
            switch node.body {
            case .section:
                return MenuModel(entries: [])
            case .folder(let f):
                return MenuModel(entries: [
                    entry(ActionID.rename.spec.title, .item(.beginRename(.item(id)))),
                    entry(f.collapsed ? "Expand Folder" : "Collapse Folder", .item(.toggleFolder(id))), .separator,
                    entry("Export Folder…", .app(.export(.items([id]))), enabled: scope == .global),
                    entry("Delete Folder", .item(.deleteFolder(id))),
                ])
            case .tab, .split:
                let unit = tree.splitContaining(id) ?? id
                let unitRole = tree.role(of: unit) ?? role
                let home = unitRole.space ?? state.doc.windows[window]?.space
                let prefix = unitRole.kind == .pinned ? "Move to Pinned in " : "Move to Today in "
                let moves = state.doc.spaceOrder.filter { $0 != home && state.doc.spaces[$0] != nil }.map {
                    entry(prefix + state.displayTitle(of: $0), .item(.move(unit, to: .space($0))))
                }
                let pinTarget: ItemID
                if case .split(let s) = node.body { pinTarget = s.panes.ids[0] } else { pinTarget = id }
                var entries = [entry(ActionID.pinTab.spec.title, .tab(.togglePin(.item(pinTarget)))),
                               entry("Export…", .app(.export(.items([id]))), enabled: scope == .global)]
                guard case .tab(let tab) = node.body else {
                    return MenuModel(entries: moves.isEmpty ? entries : entries + [.separator] + moves)
                }
                entries.append(entry(ActionID.rename.spec.title, .item(.beginRename(.item(id)))))
                if let pinned = tab.pinnedURL, pinned != state.address(of: id, in: window, for: .visible) { entries.append(entry(ActionID.resetTab.spec.title, .tab(.reset(.item(id))))) }
                if !moves.isEmpty { entries += [.separator] + moves }
                entries.append(.separator)
                switch role.kind {
                case .today, .scratch:
                    entries.append(entry(ActionID.archiveTab.spec.title, .tab(.close(.item(id)))))
                case .pinned, .favorites:
                    entries.append(entry("Close and Keep Pinned", .tab(.close(.item(id)))))
                    entries.append(entry(ActionID.archiveTab.spec.title, .tab(.archive(.item(id)))))
                }
                return MenuModel(entries: entries)
            }
        }
    }

    /// App and window chrome. These change no state (except Esc closing an overlay), so their transitions carry
    /// effects with `changed == false`; the store runs them anyway.
    mutating func app(_ command: AppCommand, in window: WindowID) {
        switch command {
        case .quit: effects.append(.app(.quit))
        case .hide: effects.append(.app(.hide))
        case .hideOthers: effects.append(.app(.hideOthers))
        case .minimize: effects.append(.window(window, .miniaturize))
        case .toggleFullScreen: effects.append(.window(window, .toggleFullScreen))
        case .showAbout: effects.append(.app(.showAbout))
        case .setAsDefaultBrowser: effects.append(.app(.registerAsDefaultBrowser))
        case .revealDataDirectory: effects.append(.app(.revealDataDirectory))
        case .export(let subject):
            // Share-by-link replaced by a file (user decision): the document is built here from state, so the
            // writer (BrkApp/ShareExport.swift) never reads the tree.
            if let document = exportDocument(for: subject, in: window) { effects.append(.export(document, owner: window)) }
        case .exit:
            // Arc's "Exit" (Esc; the menu takes Esc before text fields, as Arc's nib does): close the open overlay,
            // else cancel a rename or dialog, else leave full screen (the window decides whether it is in one).
            // The overlay rule has already closed an open overlay for this command (Exit does not keep it).
            guard !closedOverlay, var session = state.session.windows[window] else { return }
            if session.overlay != nil { session.overlay = nil }
            else if session.renaming != nil { session.renaming = nil }
            else if session.dialog != nil { session.dialog = nil }
            else if session.profileDialog != nil { session.profileDialog = nil }
            else { effects.append(.window(window, .leaveFullScreen)) }
            state.session.windows[window] = session
        }
    }

    mutating func windowEvent(_ event: WindowEvent, in window: WindowID) {
        guard state.doc.windows[window] != nil, var session = state.session.windows[window] else { return }
        switch event {
        case .geometry(let bounds, let contentSize):
            if state.doc.windows[window]!.bounds != bounds { state.doc.windows[window]!.bounds = bounds }
            session.contentSize = contentSize
            state.session.windows[window] = session
        case .modifiersChanged(let held):
            let was = session.heldModifiers
            session.heldModifiers = held
            state.session.windows[window] = session
            // Control up commits a pending Ctrl+Tab cycle; Control down with a cycle still pending commits it too, so
            // each new hold starts a fresh walk (regression finding 6). flagsChanged only fires on a change, so a
            // report equal to the last one with Control held means a release went missing in between (it was
            // delivered elsewhere): that is a new press. Shift going down or up during a hold changes nothing.
            let controlChanged = was.contains(.control) != held.contains(.control)
            let missedRelease = held == was && held.contains(.control)
            if controlChanged || missedRelease { commitCycle(in: window) }
        case .closed:
            // A standard window keeps its WindowDoc when it is the last one (the next launch restores it; quitting
            // after the last window closes is AppKit's applicationShouldTerminateAfterLastWindowClosed) and is
            // removed otherwise; an ephemeral window goes with its tree (`WindowCommand.close` does the archiving).
            guard let doc = state.doc.windows[window] else { return }
            switch doc.kind {
            case .standard:
                if state.doc.windows.values.contains(where: { $0.kind == .standard && $0.id != window }) { removeWindow(window) }
            case .little, .incognito:
                windows(.close, in: window)
            }
        }
    }

    /// "Share…": a space (its Pinned and Today with folders), the focused tab, or chosen items, as an export
    /// document. Nil when there is nothing to export.
    func exportDocument(for subject: ExportSubject, in window: WindowID) -> ExportDocument? {
        let tree = state.doc.tree
        func entries(under parent: ItemID) -> [ExportEntry] {
            (tree[parent]?.children ?? []).flatMap { child -> [ExportEntry] in
                guard let item = tree[child] else { return [] }
                switch item.body {
                case .tab: return state.displayedTab(child, in: window, for: .savedDocument).flatMap { t in t.url.map { [.link(title: t.displayTitle, url: $0)] } } ?? []
                case .folder(let f): return [.folder(title: f.title, children: entries(under: child))]
                case .split: return entries(under: child)
                case .section: return []
                }
            }
        }
        switch subject {
        case .space(let ref):
            let id: SpaceID? = switch ref {
            case .current: state.doc.windows[window]?.space
            case .space(let s): s
            }
            guard let id, let space = state.doc.spaces[id] else { return nil }
            return ExportDocument(title: state.displayTitle(of: id), entries: entries(under: space.pinnedRoot) + entries(under: space.todayRoot))
        case .focusedTab:
            guard let tab = state.resolveTab(.focused, in: window), let t = state.displayedTab(tab, in: window, for: .savedDocument), let url = t.url else { return nil }
            return ExportDocument(title: t.displayTitle, entries: [.link(title: t.displayTitle, url: url)])
        case .items(let ids):
            let list = ids.flatMap { id -> [ExportEntry] in
                guard let item = tree[id] else { return [] }
                switch item.body {
                case .tab: return state.displayedTab(id, in: window, for: .savedDocument).flatMap { t in t.url.map { [.link(title: t.displayTitle, url: $0)] } } ?? []
                case .folder(let f): return [.folder(title: f.title, children: entries(under: id))]
                case .split: return entries(under: id)
                case .section: return []
                }
            }
            return list.isEmpty ? nil : ExportDocument(title: "Tabs", entries: list)
        }
    }
}

/// A theme as the reducer stores it: 1 to 3 colors (the default primary when none), noise and intensity in 0...1.
func clamped(_ theme: SpaceTheme) -> SpaceTheme {
    var t = theme
    t.colors = t.colors.isEmpty ? SpaceTheme.default.colors : Array(t.colors.prefix(3))
    t.noise = t.noise.isFinite ? min(max(t.noise, 0), 1) : SpaceTheme.default.noise
    t.intensity = t.intensity.isFinite ? min(max(t.intensity, 0), 1) : SpaceTheme.default.intensity
    return t
}
