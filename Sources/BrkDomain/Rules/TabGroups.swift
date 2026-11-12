import BrkBase
import Foundation

// Owner: R3-6. Tab groups (Arc: `SidebarTabGroup { title }`, `TabGroupHeaderCellView`): a titled run of tabs. Brk
// keeps a group as a folder with `isGroup`, so it saves, archives and restores like one. Arc's header has a × that
// closes the group ("Tooltip for the button to close a group of tabs in the sidebar", `ArchiveReason.clearTabGroup`)
// and a menu ("Tab Group Context Menu") whose own item is "Remove tab group header", undoable. Dragging a tab onto
// a group adds it, dragging it out takes it out, and a group dropped onto a group merges into it. A group whose last
// tab left is gone: Arc has no empty group.

extension Work {
    /// The header's ×: the group's tabs are archived as one unit (Cmd+Shift+T brings the group back) and the header
    /// goes with them. Brk files it under "Closed manually"; Arc's own reason is `clearTabGroup`.
    mutating func closeGroup(_ id: ItemID, in window: WindowID) {
        guard isGroup(id) else { return }
        let (entries, from) = archiving { $0.archiveTabs([id], reason: .manual, in: window) }
        if !entries.isEmpty { undoToast("Closed Tab Group! Use", undo: .restore(entries, from: from), in: window) }
    }

    /// "Remove Group Header": the tabs stay where they are, the header goes. ⌘Z while the toast shows puts it back.
    mutating func removeGroupHeader(_ id: ItemID, in window: WindowID) {
        guard isGroup(id), let scope = state.locate(id), let tree = state.tree(scope), let node = tree[id],
              case .folder(let folder) = node.body, let parent = node.parent,
              let index = tree[parent]?.children.firstIndex(of: id) else { return }
        let children = node.children
        for (offset, child) in children.enumerated() {
            _ = moveItem(child, to: .into(parent: parent, index: index + 1 + offset))
        }
        _ = removeItem(id)
        undoToast("Removed Group Header! Use", undo: .regroup(id: id, folder: folder, parent: parent, children: children), in: window)
    }

    /// ⌘Z after "Remove Group Header": the header comes back above its tabs that are still in place.
    mutating func restoreGroupHeader(id: ItemID, folder: Folder, parent: ItemID, children: [ItemID]) {
        guard let scope = state.locate(parent), let tree = state.tree(scope), state.tree(scope)?[id] == nil else { return }
        let present = children.filter { tree[$0]?.parent == parent }
        guard let first = present.compactMap({ tree[parent]?.children.firstIndex(of: $0) }).min() else { return }
        var header = Folder(title: folder.title, collapsed: folder.collapsed, icon: folder.icon)
        header.isGroup = true
        var inserted = false
        state.withTree(scope) { t in inserted = (try? t.insert(id, .folder(header), at: .into(parent: parent, index: first), createdAt: ctx.now)) != nil }
        guard inserted else { return }
        for (offset, child) in present.enumerated() { _ = moveItem(child, to: .into(parent: id, index: offset)) }
    }

    /// A group dropped into a group: its tabs join the target at `index`, in order, and its header goes. Returns
    /// false when this is not a group-onto-group drop.
    mutating func mergeGroup(_ id: ItemID, into target: ItemID, at index: Int) -> Bool {
        guard id != target, isGroup(id), isGroup(target), let scope = state.locate(id), state.locate(target) == scope,
              let tree = state.tree(scope), !tree.isDescendant(target, of: id), let children = tree[id]?.children else { return false }
        let start = min(max(0, index), state.tree(scope)?[target]?.children.count ?? 0)
        for (offset, child) in children.enumerated() { _ = moveItem(child, to: .into(parent: target, index: start + offset)) }
        _ = removeItem(id)
        return true
    }

    /// A group left with no tabs (its last one dragged or moved out) is removed.
    mutating func dropEmptyGroup(_ id: ItemID?) {
        guard let id, isGroup(id), let scope = state.locate(id), state.tree(scope)?[id]?.children.isEmpty == true else { return }
        _ = removeItem(id)
    }

    func isGroup(_ id: ItemID) -> Bool {
        guard let scope = state.locate(id), case .folder(let f)? = state.tree(scope)?[id]?.body else { return false }
        return f.isGroup
    }
}

extension AppState {
    /// Arc's "Tab Group Context Menu".
    func groupMenu(_ id: ItemID, folder: Folder, tree: SidebarTree, links: Bool) -> [MenuEntry] {
        [.action(title: "Rename Group…", command: .item(.beginRename(.item(id))), enabled: true)]
        + (doc.settings.max.enabled(.folderNames) ? [.action(title: AICopy.nameWithAI, command: .assist(.nameFolder(id)), enabled: !tree.tabs(under: id).isEmpty)] : [])
        + [
            .action(title: "Remove Group Header", command: .tabTools(.removeGroupHeader(id)), enabled: true), .separator,
            .action(title: "Copy All Links", command: .tabTools(.copyLinks(.items([id]))), enabled: links), .separator,
            .action(title: "Close Tab Group", command: .tabTools(.closeGroup(id)), enabled: !tree.tabs(under: id).isEmpty),
        ]
    }
}
