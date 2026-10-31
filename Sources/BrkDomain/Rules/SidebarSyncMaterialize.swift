import BrkBase
import Foundation

extension Work {
    mutating func materializeSidebarSync() {
        guard let local = state.doc.sidebarData.sync, let favorite = state.doc.favorites[local.profile] else { return }
        typealias Record = SidebarTree.RestoredItem
        let inverse = Dictionary(local.aliases.map { ($0.value, $0.key) }, uniquingKeysWith: { a, b in min(a, b) })
        func raw(_ key: String) -> String { inverse[key] ?? key }
        func itemID(_ key: String) -> ItemID {
            if key == "favorites" { return favorite }
            let value = raw(key)
            return ItemID(value.hasPrefix("i-") ? String(value.dropFirst(2)) : "sync-" + value)
        }
        func spaceID(_ key: String) -> SpaceID {
            let value = raw(key)
            return SpaceID(value.hasPrefix("s-") ? String(value.dropFirst(2)) : "sync-" + value)
        }
        let values = local.document.records.compactMapValues(\.value)
        let liveItemIDs = Set(values.keys.filter { key in
            if case .space? = values[key]?.payload { return false }; return true
        }.map(itemID))
        let sortedKeys = values.keys.sorted {
            let a = values[$0]!, b = values[$1]!
            return a.order == b.order ? $0 < $1 : a.order < b.order
        }
        let sharedPinned = sortedKeys.first {
            if case .root(let space)? = values[$0]?.payload, let space, case .space? = values[space]?.payload { return true }
            return false
        }
        func effectiveParent(_ key: String) -> String? {
            guard let value = values[key], let parent = value.parent else { return sharedPinned }
            var cursor = key, seen: Set<String> = []
            while seen.insert(cursor).inserted, let next = values[cursor]?.parent, let node = values[next] {
                if case .root(let space) = node.payload {
                    if space == nil { return parent }
                    if let space, case .space? = values[space]?.payload { return parent }
                    return sharedPinned
                }
                switch node.payload {
                case .folder: cursor = next
                case .split:
                    if case .tab? = values[cursor]?.payload { cursor = next }
                    else { return sharedPinned }
                default: return sharedPinned
                }
            }
            // Never choose a device's Today root to repair a shared orphan or cycle.
            if let sharedPinned { return sharedPinned }
            if case .tab = value.payload { return "favorites" }
            return nil
        }
        // Preserve all unrelated and local-only items. Rebuild only the enrolled subset through the tree's
        // existing invariant-preserving boundary, never by assigning Item.parent or children.
        var records: [ItemID: Record] = [:]
        for (id, item) in state.doc.tree.items {
            let payload: Record.Payload
            switch item.body {
            case .tab(let tab): payload = .tab(tab)
            case .folder(let f): payload = .folder(title: f.title, collapsed: f.collapsed, icon: f.icon)
            case .split(let s): payload = .split(widths: s.widths, orientation: s.orientation, lastActiveAt: s.lastActiveAt, icon: s.icon)
            case .section(let s): payload = .section(s.role)
            }
            records[id] = Record(id: id, createdAt: item.createdAt, parent: item.parent, children: item.children, payload: payload)
        }
        for (key, record) in local.document.records where record.value == nil {
            if key == "favorites" { continue }
            let id = itemID(key)
            if liveItemIDs.contains(id) { continue }
            if state.doc.tree[id] != nil {
                guard state.doc.tree.role(of: id)?.kind != .today,
                      state.browsingContext(of: id) == .profile(local.profile) else { continue }
                if case .tab(let tab)? = state.doc.tree[id]?.body,
                   tab.pinnedURL.map({ !SidebarSync.safeURL($0) }) ?? true { continue }
            }
            if state.doc.spaces.values.contains(where: { $0.pinnedRoot == id }) { records[id]?.children = [] }
            else { records[id] = nil }
            // A deleted space may still contain device-local Today tabs or be shown in a window. Keep its
            // local shell. Its shared metadata remains tombstoned and excluded from further publication.
        }
        for (key, record) in local.document.records where record.value == nil && key.hasPrefix("s-") {
            let id = spaceID(key)
            guard let space = state.doc.spaces[id], space.profile == local.profile, state.doc.spaces.count > 1,
                  !state.doc.windows.values.contains(where: { $0.space == id }) else { continue }
            let localContent = state.doc.tree.items.values.contains { item in
                guard item.kind != .section, records[item.id] != nil, let role = state.doc.tree.role(of: item.id), role.space == id else { return false }
                if role.kind == .today { return true }
                let raw = "i-" + item.id.rawValue
                if local.document.records[local.aliases[raw] ?? raw] == nil { return true }
                if case .tab(let tab) = item.body { return tab.pinnedURL.map({ !SidebarSync.safeURL($0) }) ?? true }
                return false
            }
            guard !localContent else { continue }
            records[space.pinnedRoot] = nil; records[space.todayRoot] = nil
            state.doc.spaces[id] = nil; state.doc.spaceOrder.removeAll { $0 == id }
            for window in Array(state.doc.windows.keys) {
                state.doc.windows[window]?.activeBySpace[id] = nil
                state.doc.windows[window]?.emptySelections.remove(id)
            }
        }
        for key in sortedKeys {
            guard let value = values[key], case .space(let title, let icon, let theme) = value.payload else { continue }
            let id = spaceID(key)
            if var existing = state.doc.spaces[id] {
                guard existing.profile == local.profile else { continue }
                existing.title = title; existing.icon = icon; existing.theme = clamped(theme)
                state.doc.spaces[id] = existing
            } else {
                let pinnedKey = sortedKeys.first { if case .root(let space)? = values[$0]?.payload { return space == key }; return false }
                let pinned = pinnedKey.map(itemID) ?? ItemID("sync-pinned-" + key)
                let today = ItemID("sync-today-" + key)
                state.doc.spaces[id] = Space(id: id, title: title, icon: icon, theme: clamped(theme), profile: local.profile,
                                             pinnedRoot: pinned, todayRoot: today, pinnedCollapsed: false)
                state.doc.spaceOrder.append(id)
                records[today] = Record(id: today, createdAt: ctx.now, parent: nil, children: [], payload: .section(.today(id)))
                records[pinned] = Record(id: pinned, createdAt: ctx.now, parent: nil, children: [], payload: .section(.pinned(id)))
            }
        }
        var sharedChildren: [ItemID: [ItemID]] = [:]
        for key in sortedKeys {
            guard let value = values[key] else { continue }
            let id = itemID(key)
            if state.doc.tree[id] != nil, state.browsingContext(of: id) != .profile(local.profile) { continue }
            let parent: ItemID?
            switch value.payload {
            case .root, .space: parent = nil
            default:
                parent = effectiveParent(key).map(itemID)
                if parent == nil { continue }
            }
            let payload: Record.Payload
            switch value.payload {
            case .space: continue
            case .root(let space):
                if let space {
                    let sid = spaceID(space)
                    guard state.doc.spaces[sid]?.profile == local.profile else { continue }
                    // Root IDs are immutable for a space. Refuse a conflicting root rather than moving its pages.
                    guard state.doc.spaces[sid]?.pinnedRoot == id else { continue }
                    payload = .section(.pinned(sid))
                } else {
                    guard key == "favorites" else { continue }
                    payload = .section(.favorites(local.profile))
                }
            case .tab(let title, let url, let icon):
                guard SidebarSync.safeURL(url) else { continue }
                var tab: Tab
                if case .tab(let existing)? = records[id]?.payload { tab = existing }
                else { tab = Tab(url: url, title: title, lastActiveAt: ctx.now) }
                // A live/saved per-window address stays local. This changes only the pinned home/reset address.
                tab.customTitle = title; tab.pinnedURL = url; tab.icon = icon
                payload = .tab(tab)
            case .folder(let title, let icon):
                let collapsed: Bool
                if case .folder(_, let c, _)? = records[id]?.payload { collapsed = c } else { collapsed = false }
                payload = .folder(title: title, collapsed: collapsed, icon: icon)
            case .split(let orientation, let icon):
                if case .split(let widths, _, let activity, _)? = records[id]?.payload {
                    payload = .split(widths: widths, orientation: orientation, lastActiveAt: activity, icon: icon)
                } else { payload = .split(widths: [:], orientation: orientation, lastActiveAt: ctx.now, icon: icon) }
            }
            records[id] = Record(id: id, createdAt: records[id]?.createdAt ?? ctx.now, parent: parent, children: records[id]?.children ?? [], payload: payload)
            if let parent { sharedChildren[parent, default: []].append(id) }
        }
        // Local-only children of a deleted shared folder retain their original profile and section.
        for id in Array(records.keys) {
            guard let parent = records[id]?.parent, records[parent] == nil, let role = state.doc.tree.role(of: id) else { continue }
            switch role {
            case .pinned(let space): records[id]?.parent = state.doc.spaces[space]?.pinnedRoot
            case .today(let space): records[id]?.parent = state.doc.spaces[space]?.todayRoot
            case .favorites(let profile): records[id]?.parent = state.doc.favorites[profile]
            case .scratch: break
            }
        }
        let syncedIDs = Set(local.document.records.keys.filter { key in
            guard !key.hasPrefix("s-") else { return false }
            let id = itemID(key)
            if let role = state.doc.tree.role(of: id) {
                if state.browsingContext(of: id) != .profile(local.profile) { return false }
                if role.kind == .today, local.document.records[key]?.value == nil { return false }
                if case .tab(let tab)? = state.doc.tree[id]?.body,
                   tab.pinnedURL.map({ !SidebarSync.safeURL($0) }) ?? true { return false }
            }
            return true
        }.map(itemID))
        for id in records.keys {
            let localOnly = records[id]!.children.filter { records[$0] != nil && !syncedIDs.contains($0) }
            records[id]!.children = (sharedChildren[id] ?? []) + localOnly
        }
        // All decisions are based on shared order and IDs. Cycles and missing/deleted parents use the same
        // deterministic shared-root-first traversal on every device, then the tree's normal placement repair.
        let sharedRoots = sortedKeys.compactMap { key -> ItemID? in
            if case .root? = values[key]?.payload { return itemID(key) }; return nil
        }
        let otherRoots = records.keys.filter { records[$0]?.parent == nil && !sharedRoots.contains($0) }.sorted()
        let rest = records.keys.filter { !sharedRoots.contains($0) && !otherRoots.contains($0) }.sorted()
        let rebuilt = SidebarTree.restored((sharedRoots + otherRoots + rest).compactMap { records[$0] }, scope: .global)
        state.doc.tree = rebuilt.tree
        for (split, pane) in rebuilt.dissolved { redirect(Dissolved(split: split, pane: pane)) }
        let remoteOrder = sortedKeys.compactMap { key -> SpaceID? in
            if case .space? = values[key]?.payload { return spaceID(key) }; return nil
        }
        // Other profiles retain their relative dock positions. Only replace this profile's enrolled order.
        var iterator = remoteOrder.makeIterator()
        state.doc.spaceOrder = state.doc.spaceOrder.map { id in
            if remoteOrder.contains(id) { return iterator.next() ?? id }; return id
        }
    }
}
