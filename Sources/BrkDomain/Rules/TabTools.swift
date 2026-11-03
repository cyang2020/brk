import BrkBase
import Foundation

extension AppState {
    /// The rows a bulk or menu command names, before validation: the selection (else what the window shows), the
    /// given ids, or an item's siblings.
    func requestedItems(_ target: TabTargets, in window: WindowID) -> [ItemID] {
        guard let tree = tree(of: window) else { return [] }
        switch target {
        case .items(let ids): return ids
        case .selected:
            return session.windows[window]?.tabSelection.items.isEmpty == false
                ? session.windows[window]!.tabSelection.items : shownItem(in: window).map { [$0] } ?? []
        case .other(let id):
            return tree[id]?.parent.flatMap { tree[$0]?.children.filter { $0 != id } } ?? []
        case .below(let id):
            let siblings = tree[id]?.parent.flatMap { tree[$0]?.children } ?? []
            return siblings.firstIndex(of: id).map { Array(siblings.dropFirst($0 + 1)) } ?? []
        }
    }
    func folderIsExpanded(_ id: ItemID, in window: WindowID) -> Bool {
        if let value = doc.windows[window]?.folderExpansion[id] { return value }
        guard let tree = tree(of: window), case .folder(let f)? = tree[id]?.body else { return false }
        return !f.collapsed
    }
    func visibleUnits(in window: WindowID, space: SpaceID) -> [ItemID] {
        guard let tree = tree(of: window), let s = doc.spaces[space] else { return [] }
        func walk(_ root: ItemID) -> [ItemID] {
            (tree[root]?.children ?? []).flatMap { child -> [ItemID] in
                switch tree[child]?.body {
                case .folder?: return folderIsExpanded(child, in: window) ? walk(child) : []
                case .tab?, .split?: return [child]
                default: return []
                }
            }
        }
        return (favoritesRoot(for: s).map(walk) ?? []) + (s.pinnedCollapsed ? [] : walk(s.pinnedRoot)) + walk(s.todayRoot)
    }
    func visibleRows(in window: WindowID) -> [ItemID] {
        guard let w = doc.windows[window], let tree = tree(of: window), let s = doc.spaces[w.space] else { return [] }
        func walk(_ root: ItemID) -> [ItemID] {
            (tree[root]?.children ?? []).flatMap { child -> [ItemID] in
                if tree[child]?.kind == .folder, folderIsExpanded(child, in: window) { return [child] + walk(child) }
                return [child]
            }
        }
        if w.kind != .standard { return tree.root(for: .scratch(window)).map(walk) ?? [] }
        return (s.pinnedCollapsed ? [] : walk(s.pinnedRoot)) + walk(s.todayRoot)
    }
}

extension Work {
    mutating func toast(_ text: String, link: ToastLink? = nil, in window: WindowID) {
        state.session.windows[window]?.toast = ToastSnapshot(text: text, expiresAt: ctx.now.advanced(by: .seconds(4)), link: link)
        state.session.windows[window]?.toastUndo = nil
    }
    /// Arc's undo toast ("Cleared Tabs! Use ⌘Z to undo"), about 5 s; ⌘Z meanwhile runs `undo`.
    mutating func undoToast(_ text: String, undo: ToastUndo, in window: WindowID) {
        state.session.windows[window]?.toast = ToastSnapshot(text: text, expiresAt: ctx.now.advanced(by: .seconds(5)), keycap: "⌘Z", trailing: "to undo")
        state.session.windows[window]?.toastUndo = undo
    }

    /// The archive entries `body` adds, oldest sidebar position first.
    mutating func archiving(_ body: (inout Work) -> Void) -> [ArchiveID] {
        let before = Set(state.doc.archive.map(\.id))
        body(&self)
        return state.doc.archive.filter { !before.contains($0.id) }.sorted { ($0.fromIndex ?? 0) < ($1.fromIndex ?? 0) }.map(\.id)
    }

    /// ⌘Z on an undo toast. Cleared tabs go back where they were; a deleted space comes back at its dock position
    /// with its own roots, and its tabs return into it.
    mutating func undoFromToast(in window: WindowID) {
        guard let undo = state.session.windows[window]?.toastUndo else { return }
        state.session.windows[window]?.toastUndo = nil
        state.session.windows[window]?.toast = nil
        switch undo {
        case .restore(let entries):
            for id in entries { _ = restoreEntry(id, in: window) }
        case .space(let space, let index, let entries):
            guard state.doc.spaces[space.id] == nil,
                  state.doc.tree.makeRoot(space.pinnedRoot, .pinned(space.id), createdAt: ctx.now),
                  state.doc.tree.makeRoot(space.todayRoot, .today(space.id), createdAt: ctx.now) else { return }
            state.doc.spaces[space.id] = space
            state.doc.spaceOrder.insert(space.id, at: min(index, state.doc.spaceOrder.count))
            showSpace(space.id, in: window)
            for id in entries { _ = restoreEntry(id, in: window) }
            showSpace(space.id, in: window)
        }
    }
    mutating func reveal(_ id: ItemID, in window: WindowID, focusSidebar: Bool = false) {
        guard let tree = state.tree(of: window), tree[id] != nil else { return }
        var parent = tree[id]?.parent
        while let p = parent {
            if tree[p]?.kind == .folder { state.doc.windows[window]?.folderExpansion[p] = true }
            parent = tree[p]?.parent
        }
        if let space = tree.role(of: id)?.space { state.doc.spaces[space]?.pinnedCollapsed = false }
        state.session.windows[window]?.revealItem = tree.splitContaining(id) ?? id
        state.session.windows[window]?.revealGeneration &+= 1
        state.session.windows[window]?.sidebarFocused = focusSidebar
        peekIfHidden(window)
    }
    mutating func tabTools(_ command: TabToolsCommand, in window: WindowID) {
        guard let w = state.doc.windows[window], let tree = state.tree(of: window) else { return }
        switch command {
        case .site(let command): siteTools(command, in: window)
        case .resetPinned:
            guard w.kind == .standard, let root = state.doc.spaces[w.space]?.pinnedRoot else { return }
            for tab in tree.tabs(under: root) {
                guard let home = state.tab(tab)?.pinnedURL else { continue }
                let page = PageID(window: window, item: tab)
                if state.session.loaded.contains(page) { request(home, for: page) }
                else { state.doc.windows[window]?.slots[tab] = SavedSlot(committedURL: home, observedTitle: nil) }
            }
            toast("Pinned tabs reset", in: window)
        case .cycleLinear(let step):
            let order = state.units(in: window)
            guard !order.isEmpty else { return }
            let at = state.shownItem(in: window).flatMap { order.firstIndex(of: $0) }
            let index = at.map { ($0 + (step == .next ? 1 : -1) + order.count) % order.count } ?? (step == .next ? 0 : order.count - 1)
            focus(order[index], in: window)
            state.session.windows[window]?.sidebarFocused = false
        case .jumpItem(let n):
            guard (1...9).contains(n) else { return }
            var order = state.units(in: window)
            if !state.doc.tabPreferences.includeFavoritesInNumbers { order.removeAll { state.role(of: $0)?.kind == .favorites } }
            let index = n == 9 ? order.count - 1 : n - 1
            guard order.indices.contains(index) else { return }
            focus(order[index], in: window)
            state.session.windows[window]?.sidebarFocused = false
        case .jumpSpace(let n):
            guard w.kind == .standard, (1...9).contains(n), state.doc.spaceOrder.indices.contains(n - 1) else { return }
            showSpace(state.doc.spaceOrder[n - 1], in: window)
        case .select(let id, let gesture):
            let rows = state.visibleRows(in: window)
            guard rows.contains(id) else { return }
            var selection = state.session.windows[window]?.tabSelection ?? TabSelection()
            switch gesture {
            case .replace: selection = TabSelection(items: [id], anchor: id)
            case .toggle:
                if selection.items.contains(id) { selection.items.removeAll { $0 == id } } else { selection.items.append(id) }
                selection.anchor = id
            case .range:
                if let anchor = selection.anchor, let a = rows.firstIndex(of: anchor), let b = rows.firstIndex(of: id) {
                    selection.items = Array(rows[min(a, b)...max(a, b)])
                } else { selection = TabSelection(items: [id], anchor: id) }
            }
            state.session.windows[window]?.tabSelection = selection
        case .bulk(let targets, let action): bulkTabs(targets, action, in: window)
        case .reveal:
            if let id = state.focusedPane(in: window) { reveal(id, in: window, focusSidebar: true) }
        case .sidebarStep(let step):
            let rows = state.visibleRows(in: window)
            guard !rows.isEmpty else { return }
            let at = state.session.windows[window]?.revealItem.flatMap { rows.firstIndex(of: $0) } ?? 0
            let next = rows[min(max(at + (step == .next ? 1 : -1), 0), rows.count - 1)]
            state.session.windows[window]?.revealItem = next
            state.session.windows[window]?.revealGeneration &+= 1
            if tree[next]?.kind != .folder { focus(next, in: window) }
            state.session.windows[window]?.sidebarFocused = true
        case .leaveSidebar: state.session.windows[window]?.sidebarFocused = false
        case .folders(let expanded):
            guard w.kind == .standard, let s = state.doc.spaces[w.space] else { return }
            for (id, item) in tree.items where item.kind == .folder && tree.role(of: id)?.space == s.id {
                state.doc.windows[window]?.folderExpansion[id] = expanded
            }
            if expanded { state.doc.spaces[s.id]?.pinnedCollapsed = false }
        case .cancelRecent:
            suppressActivityStamp = true
            guard let cycle = state.session.windows[window]?.recentCycle else { return }
            state.session.windows[window]?.recentCycle = nil
            if let original = cycle.original { focus(original, in: window) }
            else { select(nil, in: window, space: w.space) }
        case .chooseIcon(let id):
            guard tree[id] != nil, tree[id]?.kind != .section else { return }
            let icon: CustomIcon? = switch tree[id]?.body {
            case .tab(let t): t.icon
            case .folder(let f): f.icon
            case .split(let s): s.icon
            default: nil
            }
            effects.append(.iconPicker(window, id, initial: icon))
        case .iconPickerClosed: break
        case .mute(let ref):
            guard let id = state.resolveTab(ref, in: window), let scope = state.locate(id), let t = state.tab(id) else { return }
            let muted = !t.muted
            state.withTree(scope) { $0.updateTab(id) { $0.muted = muted } }
        case .dismissToast:
            state.session.windows[window]?.toast = nil
            state.session.windows[window]?.toastUndo = nil
        case .undoToast: undoFromToast(in: window)
        case .dismissArchiveEducation:
            if w.kind == .standard { state.doc.tabPreferences.archiveEducationDismissed = true }
        case .dismissFavoritesHint:
            if w.kind == .standard { state.doc.tabPreferences.favoritesHintDismissed = true }
        case .preferences(let favorites, let previews):
            guard w.kind == .standard else { return }
            state.doc.tabPreferences.includeFavoritesInNumbers = favorites
            state.doc.tabPreferences.hoverPreviews = previews
        case .copyLinks(let targets):
            let urls = state.requestedItems(targets, in: window).flatMap { tree.tabs(under: $0) }
                .compactMap { state.displayedTab($0, in: window)?.url?.absoluteString }
            if !urls.isEmpty { effects.append(.copyToPasteboard(urls.joined(separator: "\n"))) }
        case .openInSplit(let targets):
            let ids = state.requestedItems(targets, in: window).filter { tree[$0]?.kind == .tab }
            guard let first = ids.first, w.kind != .little else { return }
            if let offer = state.splitDrop(in: window)?.offers[first] {
                splits(.dropTab(offer, edge: .right), in: window)
            } else {
                focus(first, in: window)
                guard state.shownItem(in: window) == (tree.splitContaining(first) ?? first) else { return }
                if ids.count == 1 { splits(.addPane, in: window); return }
            }
            for id in ids.dropFirst() {
                guard let offer = state.splitDrop(in: window)?.offers[id] else { continue }
                splits(.dropTab(offer, edge: .right), in: window)
            }
        case .newNestedFolder(let parent):
            guard let scope = state.locate(parent), case .folder? = tree[parent]?.body else { return }
            let folder = ItemID(ctx.newID())
            var inserted = false
            state.withTree(scope) { t in
                inserted = (try? t.insert(folder, .folder(Folder(title: "New Folder", collapsed: false)), at: .into(parent: parent, index: 0), createdAt: ctx.now)) != nil
            }
            guard inserted else { return }
            state.doc.windows[window]?.folderExpansion[parent] = true
            state.session.windows[window]?.renaming = folder
            reveal(folder, in: window)
        case .folderToSpace(let folder):
            guard w.kind == .standard, state.locate(folder) == .global, case .folder(let f)? = state.doc.tree[folder]?.body,
                  let source = state.doc.tree.role(of: folder)?.space, let from = state.doc.spaces[source] else { return }
            let before = Set(state.doc.spaceOrder)
            spaces(.create(title: f.title, icon: .none, theme: from.theme, profile: from.profile), in: window)
            guard let made = state.doc.spaceOrder.first(where: { !before.contains($0) }), let pinned = state.doc.spaces[made]?.pinnedRoot else { return }
            let wasPinned = Set(state.doc.tree.tabs(under: folder).filter { state.role(of: $0)?.kind == .pinned })
            for child in state.doc.tree[folder]?.children ?? [] {
                guard moveItem(child, to: .into(parent: pinned, index: Int.max)) else { continue }
                setPinnedAddresses(under: child, in: window, excluding: wasPinned)
            }
            if state.doc.tree[folder]?.children.isEmpty == true { _ = removeItem(folder) }
            toast("Folder turned into Space", in: window)
        case .customize(let id):
            focus(id, in: window)
            guard state.focusedPane(in: window) == id else { return }
            boosts(.editCurrent, in: window)
        case .addToSplit(let split):
            guard case .split? = tree[split]?.body else { return }
            focus(split, in: window)
            guard state.shownItem(in: window) == split else { return }
            splits(.addPane, in: window)
        case .spaceIntoFolder(let source, let target):
            guard w.kind == .standard, source != target, let from = state.doc.spaces[source], let into = state.doc.spaces[target] else { return }
            let folder = ItemID(ctx.newID())
            let title = state.displayTitle(of: source)
            do {
                try state.doc.tree.insert(folder, .folder(Folder(title: title, collapsed: false)), at: .into(parent: into.pinnedRoot, index: 0), createdAt: ctx.now)
            } catch { return }
            let wasPinned = Set(state.doc.tree.tabs(under: from.pinnedRoot))
            for child in (state.doc.tree[from.pinnedRoot]?.children ?? []) + (state.doc.tree[from.todayRoot]?.children ?? []) {
                guard moveItem(child, to: .into(parent: folder, index: Int.max)) else { continue }
                setPinnedAddresses(under: child, in: window, excluding: wasPinned)
            }
            if into.pinnedCollapsed { state.doc.spaces[target]?.pinnedCollapsed = false }
            showSpace(target, in: window)
            spaces(.delete(source), in: window)
            toast("Space turned into folder", in: window)
        }
    }

    private mutating func bulkTabs(_ target: TabTargets, _ action: BulkTabAction, in window: WindowID) {
        guard let w = state.doc.windows[window], let tree = state.tree(of: window) else { return }
        let requested = state.requestedItems(target, in: window)
        guard !requested.isEmpty, Set(requested).count == requested.count,
              requested.allSatisfy({ tree[$0] != nil && tree[$0]?.kind != .section }) else { return }
        func walk(_ id: ItemID) -> [ItemID] { [id] + (tree[id]?.children ?? []).flatMap(walk) }
        var roots: [ItemID] = []
        if w.kind == .standard, let space = state.doc.spaces[w.space] {
            if let favorites = state.favoritesRoot(for: space) { roots.append(favorites) }
            roots += [space.pinnedRoot, space.todayRoot]
        } else if let scratch = tree.root(for: .scratch(window)) { roots = [scratch] }
        for requestedID in requested {
            var root = requestedID
            while let parent = tree[root]?.parent { root = parent }
            if !roots.contains(root) { roots.append(root) }
        }
        let order = roots.flatMap(walk)
        let ids = requested.filter { id in !requested.contains { $0 != id && tree.isDescendant(id, of: $0) } }
            .sorted { (order.firstIndex(of: $0) ?? Int.max) < (order.firstIndex(of: $1) ?? Int.max) }
        let descendants = Set(ids.flatMap { tree.tabs(under: $0) })
        let alreadyPinned = Set(descendants.filter { state.role(of: $0)?.kind == .pinned || state.role(of: $0)?.kind == .favorites })
        var draft = self
        switch action {
        case .archive:
            guard ids.allSatisfy({ state.detached($0, in: window)?.isValid() == true }) else {
                toast("The selection exceeds the saved archive limits. No items were archived.", in: window)
                return
            }
            draft.archiveTabs(ids, reason: .manual, in: window)
        case .close:
            for id in ids {
                if tree[id]?.kind == .tab { draft.closeTab(id, in: window) }
                else if tree.role(of: id)?.kind == .pinned {
                    for tab in tree.tabs(under: id) { draft.unload(tab); draft.replaceShown(tab) }
                } else { draft.archiveTabs([id], reason: .manual, in: window) }
            }
        case .duplicate(let destination):
            var copies: [ItemID] = []
            for (offset, id) in ids.enumerated() {
                guard let node = state.detached(id, in: window), let parent = tree[id]?.parent else { return }
                let position: TreePosition
                if let destination { guard let p = bulkPosition(destination, offset: offset, source: id, in: window) else { return }; position = p }
                else { position = .after(id) }
                var result: (root: ItemID, tabs: [(ItemID, Tab)])?
                do {
                    try draft.state.withTreeThrowing(w.container) { t in
                        result = try t.insertArchived(node, at: position, now: ctx.now, freshIDs: true, newID: ctx.newID)
                    }
                } catch { return }
                guard let result, tree[parent] != nil else { return }
                for (tab, value) in result.tabs { draft.state.doc.windows[window]?.slots[tab] = SavedSlot(committedURL: value.url, observedTitle: value.title, favicon: value.favicon) }
                copies.append(result.root)
            }
            if let first = copies.first { draft.focus(first, in: window) }
        case .move(let destination):
            var positions: [(ItemID, ItemID, Int)] = []
            for (offset, id) in ids.enumerated() {
                guard case .into(let parent, let index)? = bulkPosition(destination, offset: offset, source: id, in: window),
                      !ids.contains(parent), !ids.contains(where: { tree.isDescendant(parent, of: $0) }) else { return }
                positions.append((id, parent, index))
            }
            // Stage selected roots at the end first, so destination indices count the unselected siblings.
            for (id, parent, _) in positions { guard draft.moveItem(id, to: .into(parent: parent, index: Int.max)) else { return } }
            for (id, parent, index) in positions {
                guard draft.moveItem(id, to: .into(parent: parent, index: index)) else { return }
                if draft.state.role(of: id)?.kind == .pinned || draft.state.role(of: id)?.kind == .favorites { draft.setPinnedAddresses(under: id, in: window, excluding: alreadyPinned) }
            }
        case .newFolder(let group):
            guard w.kind == .standard, let space = state.doc.spaces[w.space] else { return }
            let folder = ItemID(ctx.newID())
            var payload = Folder(title: group ? "New Group" : "New Folder", collapsed: false)
            payload.isGroup = group
            do { try draft.state.doc.tree.insert(folder, .folder(payload), at: .into(parent: space.pinnedRoot, index: 0), createdAt: ctx.now) } catch { return }
            for id in ids {
                guard draft.moveItem(id, to: .into(parent: folder, index: Int.max)) else { return }
                draft.setPinnedAddresses(under: id, in: window, excluding: alreadyPinned)
            }
            draft.state.session.windows[window]?.renaming = folder
            draft.reveal(folder, in: window)
        }
        switch action {
        case .move, .newFolder: draft.stamp(descendants)
        default: break
        }
        draft.state.session.windows[window]?.tabSelection = TabSelection()
        draft.toast("Updated \(ids.count) item\(ids.count == 1 ? "" : "s")", in: window)
        self = draft
    }

    private func bulkPosition(_ destination: Destination, offset: Int, source: ItemID, in window: WindowID) -> TreePosition? {
        switch destination {
        case .into(let parent, let index):
            guard state.tree(of: window)?[parent] != nil else { return nil }
            return .into(parent: parent, index: index > Int.max - offset ? Int.max : index + offset)
        case .space(let target):
            guard state.doc.windows[window]?.kind == .standard, let space = state.doc.spaces[target] else { return nil }
            return .into(parent: state.role(of: source)?.kind == .pinned ? space.pinnedRoot : space.todayRoot, index: offset)
        }
    }
}

extension AppState {
    mutating func withTreeThrowing(_ scope: ContainerScope, _ body: (inout SidebarTree) throws -> Void) rethrows {
        switch scope {
        case .global: try body(&doc.tree)
        case .window(let id): if session.scratch[id] != nil { try body(&session.scratch[id]!) }
        }
    }
}
