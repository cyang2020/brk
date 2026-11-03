import BrkBase
import CoreGraphics
import Foundation

// Owner: W1. Sidebar structure (rename, move, folders), spaces, sidebar chrome, app commands and window events.

extension Work {
    mutating func items(_ command: ItemCommand, in window: WindowID) {
        // Shared dock/space actions have their own policy. Item editing never crosses a private container.
        let target: ItemID?
        switch command {
        case .beginRename(.item(let id)), .rename(let id, _), .move(let id, _), .toggleFolder(let id), .deleteFolder(let id), .setIcon(let id, _): target = id
        default: target = nil
        }
        if let target, state.tree(of: window)?[target] == nil { return }
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
                if case .folder = node.body { state.doc.windows[window]?.folderExpansion[a] = true }
                if case .section(let section) = node.body, case .pinned(let space) = section.role, state.doc.spaces[space]?.pinnedCollapsed == true {
                    state.doc.spaces[space]!.pinnedCollapsed = false
                }
                ancestor = node.parent
            }
            reveal(id, in: window)
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
            guard state.doc.windows[window]?.kind == .standard else { return }
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
            guard state.locate(id) != nil else { return }
            guard state.tree(of: window)?[id] != nil else { return }
            let expanded = !state.folderIsExpanded(id, in: window)
            state.doc.windows[window]?.folderExpansion[id] = expanded
        case .deleteFolder(let id):
            // "Deleting this folder will archive the tabs inside it."
            guard let scope = state.locate(id), case .folder? = state.tree(scope)?[id]?.body else { return }
            archiveTabs([id], reason: .containerDeleted, in: window, preservingStructure: false)
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
        case .requestDelete(let id): requestSpaceDeletion(id, in: window)
        case .confirmDelete(let id, let token, let confirmed): confirmSpaceDeletion(id, token: token, confirmed: confirmed, in: window)
        case .exportIntoFolder(let id): exportSpace(id, in: window)
        case .create(let title, let icon, let theme, let profile):
            guard state.doc.windows[window]?.kind == .standard, state.doc.profiles[profile] != nil else { return }
            // Fresh Pinned and Today roots; a blank title is stored "" and shown as "Space N" by dock position. The
            // dispatching window switches to it (nothing shown) and the dialog closes.
            let space = SpaceID(ctx.newID()), pinned = ItemID(ctx.newID()), today = ItemID(ctx.newID())
            guard state.doc.tree.makeRoot(pinned, .pinned(space), createdAt: ctx.now),
                  state.doc.tree.makeRoot(today, .today(space), createdAt: ctx.now) else { return }
            state.doc.spaces[space] = Space(id: space, title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon,
                                            theme: clamped(theme), profile: profile, pinnedRoot: pinned, todayRoot: today, pinnedCollapsed: false)
            state.doc.spaceOrder.append(space)
            showSpace(space, in: window)
            if state.session.windows[window]?.dialog != nil { state.session.windows[window]!.dialog = nil }
        case .update(let id, let title, let icon, let theme):
            // Patches what is given (a blank title keeps the old one) and closes this window's dialog, except the
            // theme panel of this space: Arc applies each edit there while the panel stays open.
            guard var space = state.doc.spaces[id] else { return }
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { space.title = title }
            if let icon { space.icon = icon }
            if let theme { space.theme = clamped(theme) }
            if space != state.doc.spaces[id] { state.doc.spaces[id] = space }
            if let dialog = state.session.windows[window]?.dialog, dialog != .theme(id) { state.session.windows[window]!.dialog = nil }
        case .delete(let id):
            // Refused for the last space. Its tabs are archived (reason containerDeleted, in sidebar order), its roots
            // removed, and windows on it move to the next space in dock order, else the previous one.
            guard let space = state.doc.spaces[id], let index = state.doc.spaceOrder.firstIndex(of: id), state.doc.spaceOrder.count > 1 else { return }
            let order = state.doc.spaceOrder
            let neighbour = index + 1 < order.count ? order[index + 1] : order[index - 1]
            for (wid, w) in state.doc.windows where w.space == id { showSpace(neighbour, in: wid) }
            let contents = [space.pinnedRoot, space.todayRoot].flatMap { state.doc.tree[$0]?.children ?? [] }
            archiveTabs(contents, reason: .containerDeleted, in: window, preservingStructure: false)
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
        case .toggleToolbar:
            state.doc.windows[window]!.toolbarVisible.toggle()
        case .toggleSpaceHeader:
            state.doc.windows[window]!.spaceHeaderVisible.toggle()
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
            case .editSpace(let ref)?, .rename(let ref)?, .icon(let ref)?, .theme(let ref)?:
                let id: SpaceID = switch ref {
                case .current: state.doc.windows[window]!.space
                case .space(let id): id
                }
                guard state.doc.spaces[id] != nil else { return }
                dialog = switch request {
                case .rename?: .rename(id)
                case .icon?: .icon(id)
                case .theme?: .theme(id)
                default: .editSpace(id)
                }
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
    /// - space: Rename Space (the rename dialog), Change Space Icon… (the icon popover), Edit Theme Color… (the theme
    ///   panel), Delete Space
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
                entry("New Folder", .item(.newFolder), enabled: state.doc.windows[window]?.kind == .standard),
                entry("New Space", .sidebar(.openDialog(.newSpace))),
                entry("New GitHub Live Folder…", .tabTools(.site(.connectGitHub(favorite: nil))), enabled: state.doc.windows[window]?.kind == .standard),
                entry("Connect Calendar File…", .tabTools(.site(.connectCalendar)), enabled: state.doc.windows[window]?.kind == .standard),
            ])
        case .spaceControls(let id):
            var model = menuModel(for: .space(id), in: window)
            guard !model.entries.isEmpty else { return model }
            model.entries = model.entries.map { entry in
                if case .action(let title, .space(.delete(let id)), let enabled) = entry {
                    return .action(title: title, command: .space(.requestDelete(id)), enabled: enabled)
                }
                return entry
            }
            model.entries.insert(contentsOf: [
                entry(state.doc.windows[window]?.spaceHeaderVisible == true ? "Hide Space Header" : "Show Space Header", .sidebar(.toggleSpaceHeader)),
                entry("Manage Spaces…", .library(.open(.spaces))),
            ], at: model.entries.count - 1)
            return model
        case .space(let id):
            guard state.doc.spaces[id] != nil else { return MenuModel(entries: []) }
            return MenuModel(entries: [
                entry("Rename Space", .sidebar(.openDialog(.rename(.space(id))))),
                entry("Change Space Icon…", .sidebar(.openDialog(.icon(.space(id))))),
                entry("Edit Theme Color…", .sidebar(.openDialog(.theme(.space(id))))), .separator,
                entry("Reset All Pinned Tabs", .tabTools(.resetPinned), enabled: state.doc.windows[window]?.kind == .standard && state.doc.windows[window]?.space == id),
                entry("Collapse All Folders", .tabTools(.folders(expanded: false)), enabled: state.doc.windows[window]?.kind == .standard && state.doc.windows[window]?.space == id),
                entry("Expand All Folders", .tabTools(.folders(expanded: true)), enabled: state.doc.windows[window]?.kind == .standard && state.doc.windows[window]?.space == id),
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
                return MenuModel(entries: (f.liveRepository == nil ? [] : [entry("Refresh GitHub Folder", .tabTools(.site(.refreshFolder(id))))]) + [
                    entry(ActionID.rename.spec.title, .item(.beginRename(.item(id)))),
                    entry(f.collapsed ? "Expand Folder" : "Collapse Folder", .item(.toggleFolder(id))), .separator,
                    entry("Change Icon…", .tabTools(.chooseIcon(id))),
                    entry(f.isGroup ? "Archive Group" : "Archive Folder", .tabTools(.bulk(.items([id]), .archive))),
                    entry("Duplicate Folder", .tabTools(.bulk(.items([id]), .duplicate(nil)))),
                    entry("Export Folder…", .app(.export(.items([id]))), enabled: scope == .global),
                    entry("Delete Folder", .item(.deleteFolder(id))),
                ])
            case .tab, .split:
                let unit = tree.splitContaining(id) ?? id
                let unitRole = tree.role(of: unit) ?? role
                let home = unitRole.space ?? state.doc.windows[window]?.space
                let prefix = unitRole.kind == .pinned ? "Move to Pinned in " : "Move to Today in "
                let moves = state.doc.spaceOrder.filter { scope == .global && $0 != home && state.doc.spaces[$0] != nil }.map {
                    entry(prefix + state.displayTitle(of: $0), .item(.move(unit, to: .space($0))))
                }
                let pinTarget: ItemID
                if case .split(let s) = node.body { pinTarget = s.panes.ids[0] } else { pinTarget = id }
                var entries = [entry("Export…", .app(.export(.items([id]))), enabled: scope == .global),
                    entry(ActionID.pinTab.spec.title, .tab(.togglePin(.item(pinTarget))), enabled: role.kind != .scratch),
                    entry("Change Icon…", .tabTools(.chooseIcon(id))),
                    entry("Duplicate", .tabTools(.bulk(.items([unit]), .duplicate(nil)))),
                    entry("Archive Item", .tabTools(.bulk(.items([unit]), .archive))),
                    entry("Archive Other Items", .tabTools(.bulk(.other(unit), .archive))),
                    entry("Archive Items Below", .tabTools(.bulk(.below(unit), .archive))),
                    entry("New Group from Selection", .tabTools(.bulk(.selected, .newFolder(group: true))), enabled: scope == .global),
                    entry("New Folder from Selection", .tabTools(.bulk(.selected, .newFolder(group: false))), enabled: scope == .global)]
                if (state.session.windows[window]?.tabSelection.items.count ?? 0) > 1 {
                    entries += [entry("Archive Selected", .tabTools(.bulk(.selected, .archive))),
                                entry("Duplicate Selected", .tabTools(.bulk(.selected, .duplicate(nil))))]
                    entries += state.doc.spaceOrder.map { entry("Move Selected to " + state.displayTitle(of: $0), .tabTools(.bulk(.selected, .move(.space($0))))) }
                }
                entries += state.doc.spaceOrder.filter { _ in scope == .global }.map { entry("Duplicate in " + state.displayTitle(of: $0), .tabTools(.bulk(.items([unit]), .duplicate(.space($0))))) }
                if case .split(let split)? = tree[unit]?.body {
                    let current = state.shownItem(in: window) == unit
                    let pane = node.kind == .tab ? id : (state.focusedPane(of: unit, in: window) ?? split.panes.ids[0])
                    entries += [.separator,
                        entry("Split Side by Side", .split(.setOrientation(unit, .horizontal))),
                        entry("Split Top and Bottom", .split(.setOrientation(unit, .vertical))),
                        entry("Separate Page from Split View", .split(.separatePane(.item(pane)))),
                        entry("Separate All Split Panes", .split(.separateAll), enabled: current),
                        entry(state.session.windows[window]?.expandedSplit == unit ? "Restore Split Panes" : "Expand Current Split", .split(.toggleExpanded), enabled: current),
                    ]
                }
                guard case .tab(let tab) = node.body else {
                    return MenuModel(entries: moves.isEmpty ? entries : entries + [.separator] + moves)
                }
                entries.append(entry(ActionID.rename.spec.title, .item(.beginRename(.item(id)))))
                if role.kind == .favorites { entries.append(entry("Connect GitHub Badge…", .tabTools(.site(.connectGitHub(favorite: id))))) }
                entries.append(entry(tab.muted ? "Unmute Tab" : "Mute Tab", .tabTools(.mute(.item(id)))))
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
            if state.session.windows[window]?.recentCycle != nil { tabTools(.cancelRecent, in: window); return }
            guard !closedOverlay, var session = state.session.windows[window] else { return }
            if let editor = session.boostEditor {
                if editor.picking { session.boostEditor?.picking = false; session.boostEditor?.pickID = nil }
                else {
                    // Escape on unsaved changes warns once; the next Escape or the Cancel button discards (Boost review).
                    let saved = state.session.boosts[editor.profile]?.boosts.first { $0.id == editor.draft.id }
                    if editor.draft != saved, !editor.confirmDiscard {
                        session.boostEditor?.confirmDiscard = true
                        session.boostEditor?.message = "Unsaved changes. Press Escape again or Cancel to discard them."
                    } else { session.boostEditor = nil }
                }
            }
            else if session.overlay != nil { session.overlay = nil }
            else if session.renaming != nil { session.renaming = nil }
            else if session.pendingSpaceDeletion != nil { session.pendingSpaceDeletion = nil }
            else if session.profileDialog != nil { session.profileDialog = nil }
            else if session.dialog != nil { session.dialog = nil }
            else if let tab = state.resolveTab(.focused, in: window), state.session.live[PageID(window: window, item: tab)]?.fullscreen == true {
                effects.append(.page(PageID(window: window, item: tab), .exitFullscreen))
            } else { effects.append(.window(window, .leaveFullScreen)) }
            state.session.windows[window] = session
        }
    }

    mutating func windowEvent(_ event: WindowEvent, in window: WindowID) {
        guard state.doc.windows[window] != nil, var session = state.session.windows[window] else { return }
        switch event {
        case .becameKey:
            session.isKey = true
            session.lastInteraction = ctx.now
            session.activationOrder = (state.session.windows.values.map(\.activationOrder).max() ?? 0) + 1
            state.session.windows[window] = session
        case .resignedKey:
            session.isKey = false
            session.lastInteraction = ctx.now
            state.session.windows[window] = session
        case .activity:
            session.lastInteraction = ctx.now
            state.session.windows[window] = session
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
            state.session.windows[window]?.pendingSpaceDeletion = nil
            state.session.windows[window]?.spaceExport = nil
            // A standard window keeps its WindowDoc when it is the last one (the next launch restores it; quitting
            // after the last window closes is AppKit's applicationShouldTerminateAfterLastWindowClosed) and is
            // removed otherwise; an ephemeral window goes with its tree (`WindowCommand.close` does the archiving).
            guard let doc = state.doc.windows[window] else { return }
            switch doc.kind {
            case .standard:
                if state.doc.windows.values.contains(where: { $0.kind == .standard && $0.id != window }) { removeWindow(window) }
            case .little, .incognito, .blank:
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
    t.colors = (t.colors.isEmpty ? SpaceTheme.default.colors : Array(t.colors.prefix(3))).map {
        RGBA(finite($0.red, fallback: 0, range: 0...1), finite($0.green, fallback: 0, range: 0...1),
             finite($0.blue, fallback: 0, range: 0...1), finite($0.alpha, fallback: 1, range: 0...1))
    }
    if var variants = t.variants {
        variants.light = variants.light.normalized; variants.dark = variants.dark.normalized
        t.variants = variants
    }
    t.noise = t.noise.isFinite ? min(max(t.noise, 0), 1) : SpaceTheme.default.noise
    t.intensity = t.intensity.isFinite ? min(max(t.intensity, 0), 1) : SpaceTheme.default.intensity
    return t
}
