import BrkBase
import CoreGraphics
import Foundation

// Owner: W1. Sidebar structure (rename, move, folders), spaces, sidebar chrome, app commands and window events.

extension Work {
    mutating func items(_ command: ItemCommand, in window: WindowID) {
        // Shared dock/space actions have their own policy. Item editing never crosses a private container.
        let target: ItemID?
        switch command {
        case .beginRename(.item(let id)), .rename(let id, _), .move(let id, _), .dropOnSpaceHeader(let id), .toggleFolder(let id), .deleteFolder(let id), .setIcon(let id, _): target = id
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
            state.session.windows[window]?.renameHint = nil
            if state.session.windows[window]?.renaming != id { state.session.windows[window]!.renaming = id }
            peekIfHidden(window)
        case .rename(let id, let title):
            // Ends a rename. Nil cancels. A tab's custom title is the trimmed text ("" clears it, so the page title
            // shows again); a folder keeps its old title for blank text. At most 500 characters.
            if state.session.windows[window]?.renaming != nil { state.session.windows[window]!.renaming = nil }
            guard let title, let scope = state.locate(id) else { return }
            state.session.windows[window]?.renameHint = nil
            let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            state.withTree(scope) { tree in
                tree.updateTab(id) { tab in
                    let custom = trimmed.isEmpty ? nil : trimmed
                    // Return on the AI's name unchanged keeps it the AI's; any other commit makes the title the user's
                    // for good, so Name Tabs never touches it again.
                    if tab.customTitle == nil, let name = tab.aiName, custom == name.title { return }
                    if tab.customTitle != custom {
                        tab.customTitle = custom
                        tab.userNamed = true
                        tab.aiName = nil
                    }
                }
                if !trimmed.isEmpty { tree.updateFolder(id) { if $0.title != trimmed { $0.title = trimmed } } }
            }
        case .move(let id, .into(let parent, let index)):
            // Refused (no-op) for roots, cycles and what Placement forbids. A window whose shown item left its space
            // is repaired by normalize; a split the move dissolved is replaced by its pane.
            let wasPinned = state.role(of: id)?.kind == .pinned || state.role(of: id)?.kind == .favorites
            if mergeGroup(id, into: parent, at: index) { return }
            if moveItem(id, to: .into(parent: parent, index: index)), !wasPinned,
               state.role(of: id)?.kind == .pinned || state.role(of: id)?.kind == .favorites {
                setPinnedAddresses(under: id, in: window)
            }
        case .dropOnSpaceHeader(let id):
            guard let space = state.doc.windows[window]?.space, let root = state.doc.spaces[space]?.pinnedRoot else { return }
            items(.move(id, to: .into(parent: root, index: 0)), in: window)
            if state.role(of: id)?.kind == .pinned, state.tree(of: window)?[id]?.kind == .tab { state.session.windows[window]?.renameHint = id }
        case .move(let id, .space(let target)):
            // Dropped on a dock space: a Pinned item goes to the end of that space's Pinned, anything else to the top
            // of its Today. The moved tabs count as used now (regression finding 5: a dragged tab is not swept
            // right after the drop).
            guard let space = state.doc.spaces[target], let role = state.role(of: id), state.locate(id) == .global else { return }
            let position: TreePosition = role.kind == .pinned ? .into(parent: space.pinnedRoot, index: Int.max) : .into(parent: space.todayRoot, index: 0)
            guard moveItem(id, to: position) else { return }
            stamp(Set(state.doc.tree.tabs(under: id)))
            movedToast(id, to: target, in: window)
        case .newFolder:
            guard state.doc.windows[window]?.kind == .standard else { return }
            // "New Folder" at the top of the current space's Pinned, which expands; the folder is in rename mode.
            guard let space = state.doc.windows[window]?.space, let folder = insertNewFolder(in: space) else { return }
            state.session.windows[window]!.renaming = folder
            peekIfHidden(window)
        case .toggleFolder(let id):
            guard state.locate(id) != nil else { return }
            guard state.tree(of: window)?[id] != nil else { return }
            let expanded = !state.folderIsExpanded(id, in: window)
            state.doc.windows[window]?.folderExpansion[id] = expanded
            // Opening a Live Folder whose rows are old (or from before launch) refreshes it.
            if expanded, state.liveFolderNeedsRefresh(id, now: ctx.now) { siteTools(.refreshFolder(id), in: window) }
        case .deleteFolder(let id):
            // "Deleting this folder will archive the tabs inside it."
            guard let scope = state.locate(id), case .folder? = state.tree(scope)?[id]?.body else { return }
            archiveTabs([id], reason: .containerDeleted, in: window, preservingStructure: false)
            toast(ToastCopy.folderDeleted, in: window)
        case .setIcon(let id, let icon):
            guard let scope = state.locate(id) else { return }
            state.withTree(scope) { tree in
                tree.updateTab(id) { if $0.icon != icon { $0.icon = icon } }
                tree.updateFolder(id) { if $0.icon != icon { $0.icon = icon } }
                tree.updateSplit(id) { if $0.icon != icon { $0.icon = icon } }
            }
        }
    }

    /// "New Folder" at the top of `space`'s Pinned, which expands. Nil when the space is gone.
    mutating func insertNewFolder(in space: SpaceID) -> ItemID? {
        guard let space = state.doc.spaces[space] else { return nil }
        let folder = ItemID(ctx.newID())
        do {
            try state.doc.tree.insert(folder, .folder(Folder(title: "New Folder", collapsed: false)), at: .into(parent: space.pinnedRoot, index: 0), createdAt: ctx.now)
        } catch { return nil }
        if space.pinnedCollapsed { state.doc.spaces[space.id]!.pinnedCollapsed = false }
        return folder
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
            let entries = archiving { $0.archiveTabs(contents, reason: .containerDeleted, in: window, preservingStructure: false) }
            for root in [space.pinnedRoot, space.todayRoot] {
                for (tab, _) in state.doc.tree.removeRoot(root) ?? [] { unload(tab) }
            }
            // Its AI conversations are not deleted: they move to the profile's first remaining Space (the dialog said so).
            let moved = state.conversationSpaces(space.profile).filter { $0.value == id }.map(\.key).sorted()
            state.doc.spaces[id] = nil
            state.doc.spaceOrder.remove(at: index)
            if let first = state.doc.spaceOrder.first(where: { state.doc.spaces[$0]?.profile == space.profile }) {
                for conversation in moved { state.doc.conversations[conversation]?.space = first }
            }
            for (wid, w) in state.doc.windows where w.activeBySpace[id] != nil { state.doc.windows[wid]!.activeBySpace[id] = nil }
            if state.doc.windows[window]?.kind == .standard {
                undoToast("Space deleted! Use", undo: .space(space, index: index, entries: entries, conversations: moved), in: window)
            }
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
        case .inSpace(let id, let action):
            guard state.doc.windows[window]?.kind == .standard, state.doc.spaces[id] != nil else { return }
            switch action {
            case .newFolder: _ = insertNewFolder(in: id)
            case .connectGitHub, .connectCalendar:
                showSpace(id, in: window)
                siteTools(action == .connectGitHub ? .connectGitHub(favorite: nil) : .connectCalendar, in: window)
            }
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
            case .rename(let ref)?, .icon(let ref)?, .theme(let ref)?:
                let id: SpaceID = switch ref {
                case .current: state.doc.windows[window]!.space
                case .space(let id): id
                }
                guard state.doc.spaces[id] != nil else { return }
                dialog = switch request {
                case .rename?: .rename(id)
                case .icon?: .icon(id)
                default: .theme(id)
                }
            }
            if state.session.windows[window]?.dialog != dialog { state.session.windows[window]!.dialog = dialog }
            // Create a Space takes the sidebar's place, so the Library (New Space on the Space manager) closes.
            if dialog == .newSpace, case .library? = state.session.windows[window]?.overlay { state.session.windows[window]!.overlay = nil }
            if dialog != nil { peekIfHidden(window) }
        case .popupMenu(let request, let at):
            // A native menu built from state; each entry carries the real command it dispatches. A menu with no
            // entries (unknown item or space) emits nothing.
            let menu = menuModel(for: request, in: window)
            if !menu.entries.isEmpty { effects.append(.popupMenu(window, menu, at: at)) }
        }
    }

    /// The popup menus, item for item as Arc 1.170 shows them (verify/visual-pairs/run-20261103 P12, P11-b):
    /// - Today tab: Copy Link, Share ▸ | Change Icon…, Rename…, Mute, Customize Page… | Open in Split View,
    ///   Duplicate, Move to ▸ | Archive Tab, Archive Tabs Below. Pinned and Favorites add Edit Pinned Page ▸ after
    ///   Customize Page… and end with Remove Pin or Remove Favorite instead of the archive rows;
    /// - folder: Share Folder… | New Nested Folder…, Turn “X” into Space, Copy All Links | Change Icon…, Rename… |
    ///   Duplicate, Move to ▸ | Delete;
    /// - split: Share Split View… | Separate All Tabs, Add Tab…, Convert to Vertical (or Horizontal) Split View |
    ///   the grey caption Tab Options and one submenu per pane | Change Icon…, Rename… | Duplicate, Move to ▸ |
    ///   Archive Item, Archive Tabs Below;
    /// - several selected rows: Copy Links, Share N Items… | Change Icon…, Mute (both disabled) | Open in Split View,
    ///   Duplicate, Move to ▸, New Folder with N Items | Archive Tabs, Archive Tabs Below (disabled);
    /// - space (its name, the dock and the sidebar's empty area): Change Space Icon…, Rename Space…, Edit Theme
    ///   Color…, Set Profile ▸ | New Folder, Live Folders ▸ | Share Space…, Export “X” into Folder ▸ | Manage Spaces… |
    ///   Delete Space;
    /// - a Library Spaces card (P30-c): the same four groups without Manage Spaces…; New Folder and Live Folders act
    ///   on the card's space (`.space(.inSpace)`), Delete Space asks first;
    /// - plus button: New Tab, New Folder, New Space, the live folder sources.
    /// Share is a file export (user decision), so each Share row writes the same document the old Export rows did.
    func menuModel(for request: PopupMenuRequest, in window: WindowID) -> MenuModel {
        var model = arcMenuModel(for: request, in: window)
        // Brk's own row goes after all of Arc's, so Arc's rows keep their order; it shows only while the panel's
        // conversation can be used.
        if !model.entries.isEmpty, let sources = askAISources(for: request, in: window), !sources.isEmpty {
            model.entries += [.separator, .action(title: "Ask AI", command: .assist(.attach(sources)), enabled: true)]
        }
        // A kept AI page's way back to its conversation (while the conversation is saved), then its schedule, model and
        // weekdays, also Brk's own.
        if !model.entries.isEmpty, case .item(let id) = request, let profile = state.agentProfile(in: window) {
            var live = state.livePageMenu(state.tab(id)?.url)
            if let page = AIPageTab.id(of: state.tab(id)?.url).flatMap({ state.doc.aiPages[$0] }), let stored = state.doc.conversations[page.conversation],
               stored.profile == profile {
                let language = AILanguage.of(state.liveAnswer(stored.id)?.conversation?.items ?? stored.items, system: ctx.systemLanguage)
                live.insert(.action(title: AIThreadWords.openConversation(language), command: .assist(.showConversation(stored.id)), enabled: true), at: 0)
            }
            if !live.isEmpty { model.entries += [.separator] + live }
        }
        return model
    }

    private func askAISources(for request: PopupMenuRequest, in window: WindowID) -> [AIAttachmentSource]? {
        guard state.doc.settings.max.enabled(.commandBar), state.agentProfile(in: window) != nil else { return nil }
        func source(_ id: ItemID) -> AIAttachmentSource? {
            guard state.locate(id) == .global, let node = state.doc.tree[id] else { return nil }
            switch node.body {
            case .tab, .split: return .tab(id.rawValue)
            case .folder: return .folder(id)
            case .section: return nil
            }
        }
        switch request {
        case .selection(let ids): return ids.compactMap(source)
        case .item(let id): return source(id).map { [$0] }
        case .space(let id), .spaceControls(let id): return state.doc.spaces[id] == nil ? nil : [.space(id)]
        default: return nil
        }
    }

    private func arcMenuModel(for request: PopupMenuRequest, in window: WindowID) -> MenuModel {
        func entry(_ title: String, _ command: Command, enabled: Bool = true) -> MenuEntry {
            .action(title: title, command: command, enabled: enabled)
        }
        let standard = state.doc.windows[window]?.kind == .standard
        /// Every folder of `space` (Pinned, then Today, depth first) that `unit` may move into.
        func folders(in space: SpaceID, excluding unit: [ItemID]) -> [(ItemID, String)] {
            guard let s = state.doc.spaces[space] else { return [] }
            let tree = state.doc.tree
            func walk(_ id: ItemID) -> [(ItemID, String)] {
                (tree[id]?.children ?? []).flatMap { child -> [(ItemID, String)] in
                    guard case .folder(let f)? = tree[child]?.body, !unit.contains(child) else { return [] }
                    return [(child, f.title)] + walk(child)
                }
            }
            return walk(s.pinnedRoot) + walk(s.todayRoot)
        }
        /// Move to ▸: every space in dock order (the item's own one disabled, so the row stays usable with one space,
        /// as Arc's does), then the folders of the item's own space.
        func moves(_ units: [ItemID], home: SpaceID?, scope: ContainerScope?, command: (Destination) -> Command) -> MenuEntry {
            guard scope == .global, standard else { return .submenu(title: "Move to", entries: []) }
            let spaces = state.doc.spaceOrder.filter { state.doc.spaces[$0] != nil }.map {
                entry(state.displayTitle(of: $0), command(.space($0)), enabled: $0 != home)
            }
            let parents = Set(units.compactMap { state.doc.tree[$0]?.parent })
            let inside = home.map { folders(in: $0, excluding: units) }?.filter { folder in
                !parents.contains(folder.0) && !units.contains { state.doc.tree.isDescendant(folder.0, of: $0) }
            } ?? []
            let into = inside.map { entry($0.1, command(.into(parent: $0.0, index: 0))) }
            return .submenu(title: "Move to", entries: spaces + (spaces.isEmpty || into.isEmpty ? [] : [.separator]) + into)
        }
        func hasItemsBelow(_ id: ItemID, in tree: SidebarTree) -> Bool {
            guard let siblings = tree[id]?.parent.flatMap({ tree[$0]?.children }), let i = siblings.firstIndex(of: id) else { return false }
            return i + 1 < siblings.count
        }
        func link(_ tab: ItemID) -> URL? { state.displayedTab(tab, in: window)?.url }
        switch request {
        case .todayCleanup(let space):
            return MenuModel(entries: cleanupMenu(space, in: window))
        case .conversation(let id):
            return MenuModel(entries: conversationMenu(id, in: window))
        case .selection(let ids):
            guard let tree = state.tree(of: window) else { return MenuModel(entries: []) }
            let rows = ids.filter { tree[$0] != nil && tree[$0]?.kind != .section }
            guard !rows.isEmpty else { return MenuModel(entries: []) }
            let publicIDs = rows.filter { state.locate($0) == .global }
            let n = rows.count
            let home = rows.compactMap { tree.role(of: $0)?.space }.first ?? state.doc.windows[window]?.space
            return MenuModel(entries: [
                entry("Copy Links", .tabTools(.copyLinks(.items(rows))), enabled: rows.contains { tree.tabs(under: $0).contains { link($0) != nil } }),
                entry("Share \(n) Items…", .app(.export(.items(publicIDs))), enabled: !publicIDs.isEmpty), .separator,
                entry("Change Icon…", .tabTools(.chooseIcon(rows[0])), enabled: false),
                entry("Mute", .tabTools(.mute(.item(rows[0]))), enabled: false), .separator,
                entry("Open in Split View", .tabTools(.openInSplit(.items(rows))), enabled: standard),
                entry("Duplicate", .tabTools(.bulk(.items(rows), .duplicate(nil)))),
                moves(rows, home: home, scope: publicIDs.count == n ? .global : nil) { .tabTools(.bulk(.items(rows), .move($0))) },
                entry("New Folder with \(n) Items", .tabTools(.bulk(.items(rows), .newFolder(group: false))), enabled: standard && publicIDs.count == n), .separator,
                entry("Archive Tabs", .tabTools(.bulk(.items(rows), .archive))),
                entry("Archive Tabs Below", .tabTools(.bulk(.below(rows[n - 1]), .archive)), enabled: false),
            ])
        case .spaceControls(let id):
            var model = arcMenuModel(for: .space(id), in: window)
            model.entries = model.entries.map { entry in
                if case .action(let title, .space(.delete(let id)), let enabled) = entry {
                    return .action(title: title, command: .space(.requestDelete(id)), enabled: enabled)
                }
                return entry
            }
            return model
        case .space(let id), .spaceCard(let id):
            guard let space = state.doc.spaces[id] else { return MenuModel(entries: []) }
            let card = request == .spaceCard(id)
            let title = state.displayTitle(of: id)
            let current = standard && state.doc.windows[window]?.space == id
            let profiles = state.doc.profiles.values.filter { state.doc.deletingProfiles[$0.id] == nil }
                .sorted { ($0.id == .default ? 0 : 1, $0.name) < ($1.id == .default ? 0 : 1, $1.name) }
            let profileRows: [MenuEntry] = profiles.map {
                .choice(title: $0.name, command: .profile(.assign(.space(id), to: $0.id)), on: $0.id == space.profile)
            } + [.separator, entry("New Profile…", .profile(.openDialog(.create)))]
            let others = state.doc.spaceOrder.filter { $0 != id && state.doc.spaces[$0] != nil }.map {
                entry(state.displayTitle(of: $0), .tabTools(.spaceIntoFolder(id, into: $0)))
            }
            if card {
                return MenuModel(entries: [
                    entry("Change Space Icon…", .sidebar(.openDialog(.icon(.space(id))))),
                    entry("Rename Space…", .sidebar(.openDialog(.rename(.space(id))))),
                    entry("Edit Theme Color…", .sidebar(.openDialog(.theme(.space(id))))),
                    .submenu(title: "Set Profile", entries: standard ? profileRows : []), .separator,
                    entry("New Folder", .space(.inSpace(id, .newFolder)), enabled: standard),
                    .submenu(title: "Live Folders", entries: standard ? [
                        entry("New GitHub Live Folder…", .space(.inSpace(id, .connectGitHub))),
                        entry("Connect Calendar File…", .space(.inSpace(id, .connectCalendar))),
                    ] : []), .separator,
                    entry("Share Space…", .app(.export(.space(.space(id))))),
                    .submenu(title: "Export “\(title)” into Folder", entries: standard ? others + (others.isEmpty ? [] : [.separator])
                        + [entry("Bookmarks Folder on Disk…", .space(.exportIntoFolder(id)))] : []), .separator,
                    entry("Delete Space", .space(.requestDelete(id)), enabled: state.doc.spaceOrder.count > 1),
                ])
            }
            var entries: [MenuEntry] = [
                entry("Change Space Icon…", .sidebar(.openDialog(.icon(.space(id))))),
                entry("Rename Space…", .sidebar(.openDialog(.rename(.space(id))))),
                entry("Edit Theme Color…", .sidebar(.openDialog(.theme(.space(id))))),
                .submenu(title: "Set Profile", entries: standard ? profileRows : []), .separator,
                entry("New Folder", .item(.newFolder), enabled: current),
                .submenu(title: "Live Folders", entries: current ? [
                    entry("New GitHub Live Folder…", .tabTools(.site(.connectGitHub(favorite: nil)))),
                    entry("Connect Calendar File…", .tabTools(.site(.connectCalendar))),
                ] : []), .separator,
                entry("Share Space…", .app(.export(.space(.space(id))))),
                .submenu(title: "Export “\(title)” into Folder", entries: standard ? others + (others.isEmpty ? [] : [.separator])
                    + [entry("Bookmarks Folder on Disk…", .space(.exportIntoFolder(id)))] : []), .separator,
                entry("Manage Spaces…", .library(.open(.spaces))), .separator,
                entry("Delete Space", .space(.delete(id)), enabled: state.doc.spaceOrder.count > 1),
            ]
            // Arc 1.170 has no way to hide the space header (P05-e); a header hidden before can still come back.
            if state.doc.windows[window]?.spaceHeaderVisible == false {
                entries.insert(contentsOf: [entry("Show Space Header", .sidebar(.toggleSpaceHeader))], at: entries.count - 3)
            }
            return MenuModel(entries: entries)
        case .item(let id):
            guard let scope = state.locate(id), let tree = state.tree(scope), let node = tree[id], let role = tree.role(of: id) else {
                return MenuModel(entries: [])
            }
            switch node.body {
            case .section:
                return MenuModel(entries: [])
            case .folder(let f) where f.isGroup:
                return MenuModel(entries: state.groupMenu(id, folder: f, tree: tree, links: tree.tabs(under: id).contains { link($0) != nil }))
            case .folder(let f):
                return MenuModel(entries: (f.liveRepository == nil ? [] : [entry("Refresh GitHub Folder", .tabTools(.site(.refreshFolder(id)))), .separator]) + [
                    entry("Share Folder…", .app(.export(.items([id]))), enabled: scope == .global), .separator,
                    entry("New Nested Folder…", .tabTools(.newNestedFolder(id))),
                    entry("Turn “\(f.title)” into Space", .tabTools(.folderToSpace(id)), enabled: scope == .global && standard),
                    entry("Copy All Links", .tabTools(.copyLinks(.items([id]))), enabled: tree.tabs(under: id).contains { link($0) != nil }), .separator,
                    entry("Change Icon…", .tabTools(.chooseIcon(id))),
                    entry("Rename…", .item(.beginRename(.item(id))))]
                    // Brk's Name with AI, only while its switch is on, so the menu is Arc's otherwise.
                    + (state.doc.settings.max.enabled(.folderNames) ? [entry(AICopy.nameWithAI, .assist(.nameFolder(id)), enabled: !tree.tabs(under: id).isEmpty)] : [])
                    + [.separator,
                    entry("Duplicate", .tabTools(.bulk(.items([id]), .duplicate(nil)))),
                    moves([id], home: role.space, scope: scope) { .item(.move(id, to: $0)) }, .separator,
                    entry("Delete", .item(.deleteFolder(id))),
                ])
            case .tab, .split:
                let unit = tree.splitContaining(id) ?? id
                let unitRole = tree.role(of: unit) ?? role
                let home = unitRole.space ?? state.doc.windows[window]?.space
                let move = moves([unit], home: home, scope: scope) { .item(.move(unit, to: $0)) }
                if case .split(let split)? = tree[unit]?.body {
                    let current = state.shownItem(in: window) == unit
                    let other: SplitOrientation = split.orientation == .vertical ? .horizontal : .vertical
                    let panes: [MenuEntry] = split.panes.ids.map { pane in
                        .submenu(title: state.displayedTab(pane, in: window)?.displayTitle ?? "Tab", entries: [
                            entry("Copy Link", .tabTools(.copyLinks(.items([pane]))), enabled: link(pane) != nil),
                            entry("Rename…", .item(.beginRename(.item(pane)))),
                            entry("Separate Page from Split View", .split(.separatePane(.item(pane)))),
                            entry("Close this Split Pane", .split(.closePaneAt(pane))),
                        ])
                    }
                    return MenuModel(entries: [
                        entry("Share Split View…", .app(.export(.items([unit]))), enabled: scope == .global), .separator,
                        entry("Separate All Tabs", .split(.separateAll), enabled: current),
                        entry("Add Tab…", .tabTools(.addToSplit(unit)), enabled: split.panes.ids.count < Metrics.content.maxPanes.value),
                        entry(other == .vertical ? "Convert to Vertical Split View" : "Convert to Horizontal Split View", .split(.setOrientation(unit, other))),
                        .separator, .header("Tab Options"),
                    ] + panes + [.separator,
                        entry("Change Icon…", .tabTools(.chooseIcon(unit))),
                        entry("Rename…", .item(.beginRename(.item(node.kind == .tab ? id : split.panes.ids[0])))), .separator,
                        entry("Duplicate", .tabTools(.bulk(.items([unit]), .duplicate(nil)))),
                        move, .separator,
                        entry("Archive Item", .tabTools(.bulk(.items([unit]), .archive))),
                        entry("Archive Tabs Below", .tabTools(.bulk(.below(unit), .archive)), enabled: hasItemsBelow(unit, in: tree)),
                    ])
                }
                guard case .tab(let tab) = node.body else { return MenuModel(entries: []) }
                let audible = state.session.live[PageID(window: window, item: id)]?.audible ?? false
                var entries: [MenuEntry] = [
                    entry("Copy Link", .tabTools(.copyLinks(.items([id]))), enabled: link(id) != nil),
                    .submenu(title: "Share", entries: [entry("Export…", .app(.export(.items([id]))), enabled: scope == .global)]), .separator,
                    entry("Change Icon…", .tabTools(.chooseIcon(id))),
                    entry("Rename…", .item(.beginRename(.item(id)))),
                    entry(tab.muted ? "Unmute" : "Mute", .tabTools(.mute(.item(id))), enabled: audible || tab.muted),
                    entry("Customize Page…", .tabTools(.customize(id)), enabled: state.boostProfile(in: window) != nil && link(id) != nil),
                ]
                if role.kind == .pinned || role.kind == .favorites {
                    let drifted = tab.pinnedURL.map { $0 != state.address(of: id, in: window, for: .visible) } ?? false
                    entries.append(.submenu(title: "Edit Pinned Page", entries: [
                        entry(ActionID.resetTab.spec.title, .tab(.reset(.item(id))), enabled: drifted),
                        entry("Replace Pinned URL with Current", .tabTools(.replacePinned(id)), enabled: drifted),
                        entry("Close and Keep Pinned", .tab(.close(.item(id))), enabled: state.session.loaded.contains(PageID(window: window, item: id))),
                    ]))
                    // The address the row shows (a Favorite that never loaded has only its requested one).
                    let display = state.siteDisplayEntries(url: state.displayedTab(id, in: window)?.url ?? tab.url, favorite: role.kind == .favorites, item: id)
                    if !display.isEmpty { entries += [.separator] + display }
                }
                entries += [.separator,
                    entry("Open in Split View", .tabTools(.openInSplit(.items([id]))), enabled: role.kind != .scratch),
                    entry("Duplicate", .tabTools(.bulk(.items([unit]), .duplicate(nil)))),
                    move, .separator]
                switch role.kind {
                case .today, .scratch:
                    entries.append(entry(ActionID.archiveTab.spec.title, .tab(.close(.item(id)))))
                    entries.append(entry("Archive Tabs Below", .tabTools(.bulk(.below(unit), .archive)), enabled: hasItemsBelow(unit, in: tree)))
                case .pinned:
                    entries.append(entry("Remove Pin", .tab(.togglePin(.item(id)))))
                case .favorites:
                    entries.append(entry("Remove Favorite", .tab(.togglePin(.item(id)))))
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
        case .standardEdit(let edit): effects.append(.app(.standardEdit(edit)))
        case .help(.open(let url)):
            // A page a Help row resolved (release notes, help center, a new issue): a new focused tab, in the
            // window's current space or, for a Little or incognito window, its own container.
            guard isOpenableURL(url), let doc = state.doc.windows[window] else { return }
            if doc.kind == .standard { openTab(url, inSpace: doc.space, window: window, focus: true) }
            else { openScratchTab(url, in: window, focus: true) }
        case .help(.copyInfo):
            // Arc: "Copied Arc Info!" (a toast with list.clipboard.fill); BrkApp writes the text.
            effects.append(.app(.help(.copyInfo, owner: window)))
            toast("Copied \(Product.name) Info!", in: window)
        case .help(let action): effects.append(.app(.help(action, owner: window)))
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
                // Escape leaves Zap first; then it closes the Boost panel the way its × does, keeping the edits (Arc saves on close).
                if editor.picking { session.boostEditor?.picking = false; session.boostEditor?.pickID = nil }
                else { boosts(.close, in: window); return }
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
