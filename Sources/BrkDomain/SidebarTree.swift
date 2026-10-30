import BrkBase
import Foundation

// The sidebar as Arc stores it (anatomy 1.4): one flat map of items keyed by id. Hierarchy is `parent` on every
// non-root item plus ordered children on containers. What an item is lives in `body`, and its kind never changes.
//
// Single writer, by construction: `Item.parent`, `Item.body`, `Folder.children`, `Section.children`, `Split.panes`
// are `fileprivate(set)`, `Item.init` is fileprivate and `SidebarTree.items` is `private(set)`,
// so only code in this file can create, move or delete items, change the hierarchy, or swap a payload for one of
// another kind. Rules elsewhere change payload fields through `updateTab`, `updateFolder` and `updateSplit`, whose
// closures see the payload but cannot reach children or panes.
//
// Invariants this file keeps (never repaired by `normalize`, because they cannot break):
// - a root has no parent and a `.section` body; every other item has a parent that lists it once;
// - a split has 2 to Metrics.content.maxPanes distinct panes (`SplitPanes`), and a
//   split that would drop to one pane is dissolved into that pane in the same mutation (`move`, `removeSubtree`);
// - nothing is placed inside a split except through `splitInPlace`/`addPane`; `Placement.canPlace` gates the rest;
// - a tree holds only the roots of its `scope`: saved trees never contain a scratch root, and scratch trees
//   (Little Arc, Peek, incognito) never contain a space's roots.
//
// Dominant reads and how this structure serves them:
// - render a section: walk children from its root (ordered).                                     O(rows)
// - which section and space is this tab in (Cmd+D, auto-archive, focus): walk `parent` up.      depth <= 4
// - what a window shows: WindowDoc.activeBySpace[space] -> tab or split -> split.panes.           O(1)
// - recent-tab order (Ctrl+Tab): sort the space's tabs by `lastActiveAt`; no MRU list to keep in sync.

struct Item: Sendable, Equatable {
    let id: ItemID
    let createdAt: Instant
    /// Nil exactly for section roots.
    fileprivate(set) var parent: ItemID?
    /// The kind is fixed for the item's life; only this file assigns a body.
    fileprivate(set) var body: ItemBody

    fileprivate init(id: ItemID, createdAt: Instant, parent: ItemID?, body: ItemBody) {
        self.id = id
        self.createdAt = createdAt
        self.parent = parent
        self.body = body
    }

    /// Ordered children: a folder's or section's items, a split's panes; empty for tabs.
    var children: [ItemID] { body.children }
    var kind: ItemKind { body.kind }
}

enum ItemBody: Sendable, Equatable {
    case tab(Tab)
    case folder(Folder)
    case split(Split)
    case section(Section)

    var children: [ItemID] {
        switch self {
        case .tab: []
        case .folder(let f): f.children
        case .split(let s): s.panes.ids
        case .section(let s): s.children
        }
    }

    var kind: ItemKind {
        switch self {
        case .tab: .tab
        case .folder: .folder
        case .split: .split
        case .section: .section
        }
    }
}

/// Arc: `SidebarTab`.
struct Tab: Sendable, Equatable {
    /// Current location: set by the user (submit, reset) and by committed navigations. Nil only for an empty split
    /// pane waiting for the command bar. A failed load never changes it.
    var url: URL?
    /// As last reported by the page.
    var title: String
    /// Set by rename; shown instead of `title`. Separate so page title events never clobber it.
    var customTitle: String?
    var favicon: URL?
    /// URL when the tab entered Pinned or Favorites (Arc: `savedURL`); the target of "Reset Tab". Nil exactly
    /// while the tab is in Today. Maintained by `SidebarTree.insert` and `move`, and set by the command bar when it
    /// gives an empty pane in Pinned its first URL.
    var pinnedURL: URL?
    /// Last time the tab started or stopped being on screen. Drives auto-archive and recent-tab order.
    var lastActiveAt: Instant
    /// User-chosen icon shown instead of the favicon (Arc: `SidebarCustomIcon`).
    var icon: CustomIcon?

    init(url: URL?, title: String, customTitle: String? = nil, favicon: URL? = nil, pinnedURL: URL? = nil,
         lastActiveAt: Instant, icon: CustomIcon? = nil) {
        self.url = url
        self.title = title
        self.customTitle = customTitle
        self.favicon = favicon
        self.pinnedURL = pinnedURL
        self.lastActiveAt = lastActiveAt
        self.icon = icon
    }
}

/// Arc: `SidebarList`. Lives in Pinned (and Favorites later). `collapsed` is global; Arc keeps it per window.
struct Folder: Sendable, Equatable {
    var title: String
    var collapsed: Bool
    var icon: CustomIcon?
    fileprivate(set) var children: [ItemID]
    // Later: `live: LiveFolderSource?` (Arc: `automaticLiveFolderData`), filled by `SystemEvent.liveFolder`.

    init(title: String, collapsed: Bool, icon: CustomIcon? = nil) {
        self.title = title
        self.collapsed = collapsed
        self.icon = icon
        children = []
    }
}

/// Arc: `SidebarSplitViewData`. The panes are the item's children, left to right (or top to bottom).
struct Split: Sendable, Equatable {
    fileprivate(set) var panes: SplitPanes
    /// Relative widths keyed by pane (Arc: `itemWidthFactors`), so removing a pane cannot misalign an array.
    /// A missing key counts as 1. Normalized on read.
    var widths: [ItemID: Double]
    /// Arc: `layoutOrientation`. v1 lays out `.horizontal`; the value is saved either way.
    var orientation: SplitOrientation
    var lastActiveAt: Instant
    var icon: CustomIcon?
}

/// Two to Metrics.content.maxPanes distinct pane ids, validated once at construction, so a one-pane or
/// five-pane split cannot exist in memory. The tree dissolves a split that would drop below two.
struct SplitPanes: Sendable, Equatable {
    private(set) var ids: [ItemID]

    init?(_ ids: [ItemID]) {
        guard ids.count >= 2, ids.count <= Metrics.content.maxPanes.value, Set(ids).count == ids.count else { return nil }
        self.ids = ids
    }

    var count: Int { ids.count }
    func contains(_ id: ItemID) -> Bool { ids.contains(id) }

    /// Nil when the result would have fewer than two panes (the caller dissolves the split).
    func removing(_ id: ItemID) -> SplitPanes? { SplitPanes(ids.filter { $0 != id }) }

    /// Nil when already at the cap or `id` is already a pane.
    func inserting(_ id: ItemID, at index: Int) -> SplitPanes? {
        var copy = ids
        copy.insert(id, at: min(max(0, index), copy.count))
        return SplitPanes(copy)
    }
}

public enum SplitOrientation: String, Hashable, Sendable, Codable, CaseIterable { case horizontal, vertical }

/// A section root. Never moves, never archived. Arc: `SidebarItemContainer.ContainerType`.
struct Section: Sendable, Equatable {
    let role: SectionRole
    fileprivate(set) var children: [ItemID]
}

/// Which section a root is. The space (or profile, or window) it belongs to is part of the role, so a Pinned root
/// without a space cannot be built.
enum SectionRole: Sendable, Equatable, Hashable {
    /// One per profile, shared by every space of that profile (Arc: `topApps(Profile)`).
    case favorites(ProfileID)
    case pinned(SpaceID)
    /// Arc's unpinned container, called "Today" in the UI.
    case today(SpaceID)
    /// The one section of an ephemeral window's own container (Arc: `SidebarContainerType.littleBrowser`,
    /// `.incognito`; Peek's holding section). Lives only in `Session.scratch`; the codec never sees it.
    case scratch(WindowID)

    var kind: SectionKind {
        switch self {
        case .favorites: .favorites
        case .pinned: .pinned
        case .today: .today
        case .scratch: .scratch
        }
    }

    /// The tree this root may live in.
    var scope: ContainerScope {
        switch self {
        case .favorites, .pinned, .today: .global
        case .scratch(let window): .window(window)
        }
    }
}

public enum SectionKind: String, Hashable, Sendable, Codable, CaseIterable {
    case favorites, pinned, today
    /// Reserved for ephemeral containers (Little Arc, Peek, incognito). v1 never creates one.
    case scratch
}

public enum ItemKind: String, Hashable, Sendable, Codable { case tab, folder, split, section }

/// Where an item may be placed. The one rule table: the reducer refuses a move it forbids, and the sidebar's drag
/// feedback calls the same function with the row kinds from its snapshot instead of re-deriving the rules.
public enum Placement {
    /// Favorites: tabs only, flat. Pinned: tabs, splits and nested folders. Today: tabs and splits, never folders.
    /// Scratch: tabs only. Nothing goes inside a tab, and nothing goes inside a split except through split rules.
    public static func canPlace(_ kind: ItemKind, inSection section: SectionKind, parentKind: ItemKind) -> Bool {
        guard kind != .section else { return false }
        switch parentKind {
        case .tab, .split: return false
        case .folder: return section == .pinned && (kind == .tab || kind == .folder || kind == .split)
        case .section: break
        }
        switch section {
        case .favorites, .scratch: return kind == .tab
        case .pinned: return kind == .tab || kind == .folder || kind == .split
        case .today: return kind == .tab || kind == .split
        }
    }
}

/// Where an insert or move lands. Arc: `SidebarInsertionStrategy`.
enum TreePosition: Sendable, Equatable {
    /// `index` counts the parent's children after the moved item is detached, so applying a move twice is a no-op.
    case into(parent: ItemID, index: Int)
    case after(ItemID)
    case before(ItemID)
}

enum TreeError: Error, Equatable {
    case itemNotFound, invalidHierarchy, forbiddenPlacement, wouldCreateCycle, splitFull, wrongScope
}

/// A split that a move or removal left with one pane, and the pane that took its place in its parent.
struct Dissolved: Sendable, Equatable {
    let split: ItemID
    let pane: ItemID
}

/// What `removeSubtree` took out: the tabs in sidebar order, and the parent split it dissolved, if any.
struct Removal: Sendable {
    let tabs: [(ItemID, Tab)]
    let dissolved: Dissolved?
}

struct SidebarTree: Sendable, Equatable {
    /// Which container this tree is. `makeRoot` refuses a role of another scope.
    let scope: ContainerScope
    private(set) var items: [ItemID: Item]

    init(scope: ContainerScope) {
        self.scope = scope
        items = [:]
    }

    subscript(id: ItemID) -> Item? { items[id] }

    // MARK: Hierarchy writes

    /// Creates a section root. Used by space creation and fresh-profile setup only. Refuses a role of another scope.
    @discardableResult
    mutating func makeRoot(_ id: ItemID, _ role: SectionRole, createdAt: Instant) -> Bool {
        guard role.scope == scope, items[id] == nil else { return false }
        items[id] = Item(id: id, createdAt: createdAt, parent: nil, body: .section(Section(role: role, children: [])))
        return true
    }

    /// Inserts a new tab or folder. Throws for an existing id, an invalid position, a split or section body (use
    /// `splitInPlace`/`makeRoot`), or what `Placement` forbids. Sets `pinnedURL` when a tab lands in Pinned or Favorites.
    mutating func insert(_ id: ItemID, _ body: ItemBody, at position: TreePosition, createdAt: Instant) throws(TreeError) {
        guard items[id] == nil else { throw .invalidHierarchy }
        switch body {
        case .tab, .folder: break
        case .split, .section: throw .invalidHierarchy
        }
        let (parent, index) = try resolve(position, detaching: nil)
        try checkPlacement(body.kind, under: parent)
        items[id] = Item(id: id, createdAt: createdAt, parent: parent, body: body)
        attach(id, to: parent, at: index)
        stampPinnedURLs(under: id)
    }

    /// The only way an item changes place. Refuses roots, cycles and forbidden placements. Keeps `parent` and
    /// children in agreement, maintains `pinnedURL` for every tab of the moved subtree whose section changed, and
    /// dissolves the old parent split if the move left it with one pane, all in this one mutation. Returns that
    /// dissolution, so callers can point references to the split at the pane that took its place.
    @discardableResult
    mutating func move(_ id: ItemID, to position: TreePosition) throws(TreeError) -> Dissolved? {
        guard let item = items[id] else { throw .itemNotFound }
        guard let oldParent = item.parent else { throw .invalidHierarchy }
        let (parent, index) = try resolve(position, detaching: id)
        if parent == id || isDescendant(parent, of: id) { throw .wouldCreateCycle }
        try checkPlacement(item.kind, under: parent)
        detach(id, from: oldParent)
        items[id]!.parent = parent
        attach(id, to: parent, at: index)
        stampPinnedURLs(under: id)
        return dissolveIfSinglePane(oldParent)
    }

    /// Removes the item and its subtree: the removed tabs in sidebar order (callers archive them) and the parent
    /// split's dissolution if the removal left it with one pane. Roots cannot be removed (`removeRoot` does).
    mutating func removeSubtree(_ id: ItemID) -> Removal {
        guard let item = items[id], let parent = item.parent else { return Removal(tabs: [], dissolved: nil) }
        detach(id, from: parent)
        let tabs = deleteNodes(from: id)
        return Removal(tabs: tabs, dissolved: dissolveIfSinglePane(parent))
    }

    /// Deletes a section root and everything under it (a deleted space's Pinned and Today). Nil for anything that
    /// is not a root of this tree.
    mutating func removeRoot(_ id: ItemID) -> [(ItemID, Tab)]? {
        guard let item = items[id], item.parent == nil, case .section = item.body else { return nil }
        return deleteNodes(from: id)
    }

    /// Ctrl+Shift+= on a tab: a new split item takes the tab's place and holds [tab, newPane]. The tab must sit
    /// directly in a Pinned or Today section or folder (never Favorites, never already a pane).
    mutating func splitInPlace(_ tab: ItemID, splitID: ItemID, newPane: ItemID, _ pane: Tab, createdAt: Instant) throws(TreeError) {
        guard let item = items[tab], case .tab = item.body, let parent = item.parent else { throw .itemNotFound }
        guard items[splitID] == nil, items[newPane] == nil else { throw .invalidHierarchy }
        try checkPlacement(.split, under: parent)
        guard let panes = SplitPanes([tab, newPane]) else { throw .invalidHierarchy }
        let index = items[parent]!.children.firstIndex(of: tab) ?? 0
        detach(tab, from: parent)
        let split = Split(panes: panes, widths: [:], orientation: .horizontal, lastActiveAt: createdAt, icon: nil)
        items[splitID] = Item(id: splitID, createdAt: createdAt, parent: parent, body: .split(split))
        attach(splitID, to: parent, at: index)
        items[tab]!.parent = splitID
        items[newPane] = Item(id: newPane, createdAt: createdAt, parent: splitID, body: .tab(pane))
        stampPinnedURLs(under: newPane)
    }

    /// Ctrl+Shift+= on a split: a new pane after `after` (a current pane). Throws `splitFull` at the cap.
    mutating func addPane(to splitID: ItemID, newPane: ItemID, _ pane: Tab, after: ItemID, createdAt: Instant) throws(TreeError) {
        guard let item = items[splitID], case .split(var split) = item.body else { throw .itemNotFound }
        guard items[newPane] == nil, let at = split.panes.ids.firstIndex(of: after) else { throw .invalidHierarchy }
        guard let panes = split.panes.inserting(newPane, at: at + 1) else { throw .splitFull }
        split.panes = panes
        items[splitID]!.body = .split(split)
        items[newPane] = Item(id: newPane, createdAt: createdAt, parent: splitID, body: .tab(pane))
        stampPinnedURLs(under: newPane)
    }

    // MARK: Payload writes (kind-preserving; cannot reach children or panes)

    mutating func updateTab(_ id: ItemID, _ change: (inout Tab) -> Void) {
        guard case .tab(var tab)? = items[id]?.body else { return }
        change(&tab)
        items[id]!.body = .tab(tab)
    }

    mutating func updateFolder(_ id: ItemID, _ change: (inout Folder) -> Void) {
        guard case .folder(var folder)? = items[id]?.body else { return }
        change(&folder)
        items[id]!.body = .folder(folder)
    }

    mutating func updateSplit(_ id: ItemID, _ change: (inout Split) -> Void) {
        guard case .split(var split)? = items[id]?.body else { return }
        change(&split)
        items[id]!.body = .split(split)
    }

    // MARK: Restore

    /// One item as the state file stores it, before validation. Only the codec builds these. Containers carry
    /// their stored children as ids; the payload holds everything else, so the codec never builds a body.
    struct RestoredItem: Sendable {
        enum Payload: Sendable {
            case tab(Tab)
            case folder(title: String, collapsed: Bool, icon: CustomIcon?)
            case split(widths: [ItemID: Double], orientation: SplitOrientation, lastActiveAt: Instant, icon: CustomIcon?)
            case section(SectionRole)

            var kind: ItemKind {
                switch self {
                case .tab: .tab
                case .folder: .folder
                case .split: .split
                case .section: .section
                }
            }
        }

        var id: ItemID
        var createdAt: Instant
        var parent: ItemID?
        /// Folder and section children, or a split's panes in order. Ignored for tabs.
        var children: [ItemID]
        var payload: Payload
    }

    /// Builds a tree from decoded records and repairs what a file can get wrong, in this order (each step sees the
    /// result of the previous one):
    /// 1. a second record for an id, and roots of another scope, are dropped;
    /// 2. walking down from the roots (in record order), a child reference to a missing item, a section, an item
    ///    already placed, or an item `Placement` forbids there (a split holds only tabs, up to the pane cap) is
    ///    dropped from the list, and a child whose `parent` disagrees is corrected (the list wins);
    /// 3. every item not reached is re-attached at the end of the first container that may hold it, trying the
    ///    parent it names, that parent's section root, the Pinned root of that root's space, then the first Today,
    ///    Pinned and Favorites roots; an item nothing may hold is dropped;
    /// 4. splits with fewer than two panes are dissolved (the pane takes the split's place); a split's focus that
    ///    is not a pane becomes its first pane, and widths keep only panes with positive finite values;
    /// 5. `pinnedURL` is set exactly under Pinned and Favorites (kept, else the tab's url) and cleared elsewhere.
    /// Returns one line per repair, for `RestoreOutcome.restored(repairs:)`, and the splits step 4 dissolved with the
    /// pane that took each one's place (the codec points windows that showed such a split at that pane).
    static func restored(_ records: [RestoredItem], scope: ContainerScope) -> (tree: SidebarTree, repairs: [String], dissolved: [ItemID: ItemID]) {
        var repairs: [String] = []
        var byID: [ItemID: RestoredItem] = [:]
        var order: [ItemID] = []
        for record in records {
            if byID[record.id] != nil { repairs.append("\(record.id): dropped a second record with the same id"); continue }
            if case .section(let role) = record.payload, role.scope != scope {
                repairs.append("\(record.id): dropped a root of another container"); continue
            }
            byID[record.id] = record
            order.append(record.id)
        }
        let roots = order.filter { byID[$0]!.payload.kind == .section }
        func role(_ root: ItemID) -> SectionRole? {
            if case .section(let r)? = byID[root]?.payload { return r }
            return nil
        }

        var visited = Set(roots)
        var parentOf: [ItemID: ItemID] = [:]
        var childrenOf: [ItemID: [ItemID]] = [:]
        var sectionOf: [ItemID: SectionKind] = [:]
        for root in roots { sectionOf[root] = role(root)!.kind }

        func fits(_ child: ItemKind, in container: ItemID, count: Int) -> Bool {
            guard let section = sectionOf[container], let kind = byID[container]?.payload.kind else { return false }
            if kind == .split { return child == .tab && count < Metrics.content.maxPanes.value }
            return Placement.canPlace(child, inSection: section, parentKind: kind)
        }

        func walk(_ container: ItemID) {
            guard let record = byID[container], record.payload.kind != .tab else { return }
            var keep: [ItemID] = []
            for child in record.children {
                guard let node = byID[child] else {
                    repairs.append("\(container): dropped a reference to missing item \(child)"); continue
                }
                if node.payload.kind == .section || visited.contains(child) {
                    repairs.append("\(container): dropped a second reference to \(child)"); continue
                }
                if !fits(node.payload.kind, in: container, count: keep.count) {
                    repairs.append("\(container): detached \(node.payload.kind.rawValue) \(child), which may not live there"); continue
                }
                visited.insert(child)
                keep.append(child)
                if node.parent != container { repairs.append("\(child): parent corrected to \(container)") }
                parentOf[child] = container
                if node.payload.kind != .tab {
                    sectionOf[child] = sectionOf[container]
                    walk(child)
                }
            }
            childrenOf[container] = keep
        }
        for root in roots { walk(root) }

        // Orphans: everything not reached from a root.
        let firstToday = roots.first { role($0)?.kind == .today }
        let firstPinned = roots.first { role($0)?.kind == .pinned }
        let firstFavorites = roots.first { role($0)?.kind == .favorites }
        func candidates(_ record: RestoredItem) -> [ItemID] {
            var list: [ItemID] = []
            if let named = record.parent { list.append(named) }
            var seen: Set<ItemID> = []
            var current = record.parent
            while let c = current, !seen.contains(c), let node = byID[c] {
                seen.insert(c)
                if case .section(let r) = node.payload {
                    list.append(c)
                    if let space = r.space, let pinned = roots.first(where: { role($0) == .pinned(space) }) { list.append(pinned) }
                    break
                }
                current = node.parent
            }
            list += [firstToday, firstPinned, firstFavorites].compactMap { $0 }
            return list
        }
        while true {
            let orphans = order.filter { !visited.contains($0) }
            guard !orphans.isEmpty else { break }
            // Top-most first, so a container is placed before the children it lists.
            let id = orphans.first { byID[$0]!.parent.map { visited.contains($0) || byID[$0] == nil } ?? true } ?? orphans[0]
            let record = byID[id]!
            let target = candidates(record).first { c in
                visited.contains(c) && byID[c]?.payload.kind != .tab && fits(record.payload.kind, in: c, count: childrenOf[c]?.count ?? 0)
            }
            visited.insert(id)
            guard let target else {
                repairs.append("\(id): dropped unreachable \(record.payload.kind.rawValue), no section may hold it")
                byID[id] = nil
                continue
            }
            childrenOf[target, default: []].append(id)
            parentOf[id] = target
            repairs.append("\(id): unreachable \(record.payload.kind.rawValue) re-attached to \(target)")
            if record.payload.kind != .tab {
                sectionOf[id] = sectionOf[target]
                walk(id)
            }
        }

        // Splits below two panes dissolve into their pane, in place.
        var dissolved: [ItemID: ItemID] = [:]
        for id in order where byID[id]?.payload.kind == .split && visited.contains(id) {
            let panes = childrenOf[id] ?? []
            guard panes.count < 2, let parent = parentOf[id] else { continue }
            var siblings = childrenOf[parent] ?? []
            let at = siblings.firstIndex(of: id) ?? siblings.count
            siblings.removeAll { $0 == id }
            if let pane = panes.first {
                siblings.insert(pane, at: min(at, siblings.count))
                parentOf[pane] = parent
                dissolved[id] = pane
                repairs.append("\(id): split with one pane became tab \(pane)")
            } else {
                repairs.append("\(id): split with no panes was removed")
            }
            childrenOf[parent] = siblings
            visited.remove(id)
            byID[id] = nil
        }

        // Build the items.
        var tree = SidebarTree(scope: scope)
        for id in order {
            guard let record = byID[id], visited.contains(id) else { continue }
            let children = childrenOf[id] ?? []
            let body: ItemBody
            switch record.payload {
            case .tab(var tab):
                let section = sectionOf[parentOf[id] ?? id] ?? .today
                let want: URL? = switch section {
                case .pinned, .favorites: tab.pinnedURL ?? tab.url
                case .today, .scratch: nil
                }
                if tab.pinnedURL != want {
                    repairs.append("\(id): pinnedURL set for its section")
                    tab.pinnedURL = want
                }
                body = .tab(tab)
            case .folder(let title, let collapsed, let icon):
                var folder = Folder(title: title, collapsed: collapsed, icon: icon)
                folder.children = children
                body = .folder(folder)
            case .split(let widths, let orientation, let lastActiveAt, let icon):
                guard let panes = SplitPanes(children) else { continue }
                let kept = widths.filter { panes.contains($0.key) && $0.value.isFinite && $0.value > 0 }
                if kept.count != widths.count { repairs.append("\(id): split widths kept only its panes") }
                body = .split(Split(panes: panes, widths: kept,
                                    orientation: orientation, lastActiveAt: lastActiveAt, icon: icon))
            case .section(let role):
                body = .section(Section(role: role, children: children))
            }
            tree.items[id] = Item(id: id, createdAt: record.createdAt, parent: parentOf[id], body: body)
        }
        return (tree, repairs, dissolved)
    }

    // MARK: Reads

    func role(of id: ItemID) -> SectionRole? {
        var current = id
        for _ in 0..<64 {
            guard let item = items[current] else { return nil }
            if case .section(let s) = item.body { return s.role }
            guard let parent = item.parent else { return nil }
            current = parent
        }
        return nil
    }

    func isDescendant(_ id: ItemID, of ancestor: ItemID) -> Bool {
        var current = items[id]?.parent
        while let c = current {
            if c == ancestor { return true }
            current = items[c]?.parent
        }
        return false
    }

    /// Tabs under `id` (inclusive), depth first in sidebar order.
    func tabs(under id: ItemID) -> [ItemID] {
        guard let item = items[id] else { return [] }
        if case .tab = item.body { return [id] }
        return item.children.flatMap { tabs(under: $0) }
    }

    /// Items in visual order for one section, flattening open folders; a split counts as one stop.
    func sidebarOrder(_ root: ItemID) -> [ItemID] {
        guard let item = items[root] else { return [] }
        return item.children.flatMap { child -> [ItemID] in
            guard let node = items[child] else { return [] }
            switch node.body {
            case .folder(let f): return f.collapsed ? [child] : [child] + sidebarOrder(child)
            case .tab, .split, .section: return [child]
            }
        }
    }

    /// What a window can show under `root`, in sidebar order: tabs and splits (a split is one unit; its panes are
    /// not listed), descending into folders, skipping collapsed folders' contents when `skipCollapsed`.
    func units(under root: ItemID, skipCollapsed: Bool) -> [ItemID] {
        guard let item = items[root] else { return [] }
        return item.children.flatMap { child -> [ItemID] in
            guard let node = items[child] else { return [] }
            switch node.body {
            case .tab, .split: return [child]
            case .folder(let f): return skipCollapsed && f.collapsed ? [] : units(under: child, skipCollapsed: skipCollapsed)
            case .section: return []
            }
        }
    }

    /// The parent split of a pane, or nil when `id` is not a split pane.
    func splitContaining(_ id: ItemID) -> ItemID? {
        guard let parent = items[id]?.parent, case .split? = items[parent]?.body else { return nil }
        return parent
    }

    // MARK: Private

    private func resolve(_ position: TreePosition, detaching moved: ItemID?) throws(TreeError) -> (parent: ItemID, index: Int) {
        switch position {
        case .into(let parent, let index):
            guard let p = items[parent] else { throw .itemNotFound }
            let count = p.children.filter { $0 != moved }.count
            return (parent, min(max(0, index), count))
        case .after(let sibling), .before(let sibling):
            guard let s = items[sibling], let parent = s.parent else { throw .itemNotFound }
            let siblings = items[parent]!.children.filter { $0 != moved }
            guard let at = siblings.firstIndex(of: sibling) else { throw .invalidHierarchy }
            if case .after = position { return (parent, at + 1) }
            return (parent, at)
        }
    }

    private func checkPlacement(_ kind: ItemKind, under parent: ItemID) throws(TreeError) {
        guard let p = items[parent], let role = role(of: parent) else { throw .itemNotFound }
        guard Placement.canPlace(kind, inSection: role.kind, parentKind: p.kind) else { throw .forbiddenPlacement }
    }

    private mutating func attach(_ id: ItemID, to parent: ItemID, at index: Int) {
        switch items[parent]!.body {
        case .folder(var f): f.children.insert(id, at: min(index, f.children.count)); items[parent]!.body = .folder(f)
        case .section(var s): s.children.insert(id, at: min(index, s.children.count)); items[parent]!.body = .section(s)
        case .tab, .split: preconditionFailure("checkPlacement admits only folders and sections as parents")
        }
    }

    private mutating func detach(_ id: ItemID, from parent: ItemID) {
        switch items[parent]!.body {
        case .folder(var f): f.children.removeAll { $0 == id }; items[parent]!.body = .folder(f)
        case .section(var s): s.children.removeAll { $0 == id }; items[parent]!.body = .section(s)
        case .split(var sp):
            if let panes = sp.panes.removing(id) {
                // Work repairs each window's focus from the old pane order after this tree mutation.
                sp.panes = panes
                sp.widths[id] = nil
                items[parent]!.body = .split(sp)
            }
            // Fewer than two panes left: `dissolveIfSinglePane` runs right after, in the same mutation.
        case .tab: preconditionFailure("a tab has no children")
        }
    }

    /// A split whose panes list still names one pane that has left (or one pane only) becomes that pane, in place.
    private mutating func dissolveIfSinglePane(_ splitID: ItemID) -> Dissolved? {
        guard let item = items[splitID], case .split(let split) = item.body, let parent = item.parent else { return nil }
        let remaining = split.panes.ids.filter { items[$0]?.parent == splitID }
        guard remaining.count <= 1 else { return nil }
        let index = items[parent]!.children.firstIndex(of: splitID) ?? 0
        detach(splitID, from: parent)
        items[splitID] = nil
        guard let pane = remaining.first else { return nil }
        items[pane]!.parent = parent
        attach(pane, to: parent, at: index)
        return Dissolved(split: splitID, pane: pane)
    }

    /// Deletes `id` and its descendants from `items` (already detached from any parent). Tabs in sidebar order.
    private mutating func deleteNodes(from id: ItemID) -> [(ItemID, Tab)] {
        var removed: [(ItemID, Tab)] = []
        var stack = [id]
        while let next = stack.popLast() {
            guard let node = items.removeValue(forKey: next) else { continue }
            if case .tab(let tab) = node.body { removed.append((next, tab)) }
            stack.append(contentsOf: node.children.reversed())
        }
        return removed
    }

    /// Entering Pinned or Favorites sets `pinnedURL` (if unset); entering Today or scratch clears it.
    private mutating func stampPinnedURLs(under id: ItemID) {
        guard let role = role(of: id) else { return }
        for tab in tabs(under: id) {
            updateTab(tab) { t in
                switch role.kind {
                case .pinned, .favorites: if t.pinnedURL == nil { t.pinnedURL = t.url }
                case .today, .scratch: t.pinnedURL = nil
                }
            }
        }
    }
}
