import BrkBase
import Foundation

/// Every rule that spans entities, run after each transition and after decoding a file. It repairs; it never
/// decides: an absent active item stays absent (the space shows an empty card) until a user action fills it, and a
/// tab the user has not asked to see is never loaded. Idempotent: a normalized state comes back equal. Returns one
/// line per repair (restore reports them; `reduce` ignores them). In order:
///
/// 1. (Split membership, pane count, split focus and `pinnedURL` are kept by `SidebarTree` itself and need no
///    repair at run time; `SidebarTree.restored` repairs them in a file.)
/// 2. Every window's space exists (else the first space); `spaceOrder` lists exactly the spaces; every window has
///    a session and a scratch tree with its `SectionRole.scratch` root, and neither outlives its window; the default
///    profile exists and every profile has a settings record and a Favorites root.
/// 3. `activeBySpace` entries: an entry for a missing space is deleted; one naming a split pane names its split;
///    one naming something the space cannot show (gone, not a tab or split, under another space) is repaired to the
///    space's most recent loaded item, or deleted when there is none.
/// 4. Overlay, rename, dialog and cycle targets exist; otherwise they close.
/// 5. Every visible tab (a pane of any window's shown item) is in `session.loaded`; `loaded` names only existing
///    tabs and `live` only loaded ones.
/// 6. Archive and history caps; sidebar width within Metrics.sidebar bounds (a non-finite width becomes the default).
@discardableResult
func normalize(_ state: inout AppState) -> [String] {
    var repairs: [String] = []
    repairProfiles(&state, &repairs)
    repairSpaces(&state, &repairs)
    repairShownItems(&state, &repairs)
    repairSessionTargets(&state)
    closeEmptyLittleWindows(&state)
    repairLoaded(&state)
    applyCaps(&state, &repairs)
    return repairs
}

private func repairSpaces(_ state: inout AppState, _ repairs: inout [String]) {
    var order: [SpaceID] = []
    for space in state.doc.spaceOrder where state.doc.spaces[space] != nil && !order.contains(space) { order.append(space) }
    for space in state.doc.spaces.keys.sorted() where !order.contains(space) { order.append(space) }
    if order != state.doc.spaceOrder {
        repairs.append("spaceOrder rebuilt from the spaces")
        state.doc.spaceOrder = order
    }
    for id in state.doc.windows.keys.sorted() {
        if state.doc.spaces[state.doc.windows[id]!.space] == nil, let first = order.first {
            repairs.append("window \(id) was on a missing space")
            state.doc.windows[id]!.space = first
        }
        if state.session.windows[id] == nil {
            state.session.windows[id] = .fresh(contentSize: Metrics.window.defaultSize.value)
        }
        if state.session.scratch[id] == nil {
            // The window's own container (Peek's tab in a standard window; every tab of an ephemeral one). Ids come
            // from the window id, so the repair is deterministic without a `Context`.
            var tree = SidebarTree(scope: .window(id))
            tree.makeRoot(ItemID("scratch-\(id.rawValue)"), .scratch(id), createdAt: Instant(milliseconds: 0))
            state.session.scratch[id] = tree
        }
    }
    for id in state.session.windows.keys where state.doc.windows[id] == nil {
        state.session.windows[id] = nil
    }
    for id in state.session.scratch.keys where state.doc.windows[id] == nil {
        state.session.scratch[id] = nil
    }
}

/// The default profile always exists; every profile a space names exists; every profile has a settings record and
/// a Favorites root (the codec repairs roots in a file; a profile created at run time gets one from its rule, so
/// this only guards against a profile named by a space but missing from `profiles`).
private func repairProfiles(_ state: inout AppState, _ repairs: inout [String]) {
    if state.doc.profiles[.default] == nil {
        repairs.append("added the default profile")
        state.doc.profiles[.default] = .default
    }
    for space in state.doc.spaces.values where state.doc.profiles[space.profile] == nil {
        repairs.append("space \(space.id) named a missing profile \(space.profile); profile added")
        state.doc.profiles[space.profile] = Profile(id: space.profile, name: space.profile.rawValue, icon: nil)
    }
    for id in state.doc.profiles.keys where state.doc.settings.profiles[id] == nil {
        state.doc.settings.profiles[id] = .default
    }
    for id in state.doc.settings.profiles.keys where state.doc.profiles[id] == nil {
        state.doc.settings.profiles[id] = nil
    }
}

private func repairShownItems(_ state: inout AppState, _ repairs: inout [String]) {
    for id in state.doc.windows.keys.sorted() {
        let window = state.doc.windows[id]!
        for (space, item) in window.activeBySpace.sorted(by: { $0.key < $1.key }) {
            guard state.doc.spaces[space] != nil else {
                state.doc.windows[id]!.activeBySpace[space] = nil
                continue
            }
            guard let tree = state.tree(window.container) else { continue }
            if showable(item, in: space, tree) { continue }
            if let split = tree.splitContaining(item), showable(split, in: space, tree) {
                state.doc.windows[id]!.activeBySpace[space] = split
                continue
            }
            let next = state.mostRecentLoaded(in: space, window: id, excluding: item)
            repairs.append("window \(id) showed \(item) in space \(space), now \(next.map(\.rawValue) ?? "nothing")")
            state.doc.windows[id]!.activeBySpace[space] = next
        }
    }
}

/// A tab (not a pane) or a split, under the space's own sections or Favorites; in a window's own container
/// (an ephemeral window's tree), any of its tabs.
private func showable(_ item: ItemID, in space: SpaceID, _ tree: SidebarTree) -> Bool {
    guard let node = tree[item], node.kind == .tab || node.kind == .split, tree.splitContaining(item) == nil,
          let role = tree.role(of: item) else { return false }
    return role.space == space || role.kind == .favorites || role.kind == .scratch
}

private func repairSessionTargets(_ state: inout AppState) {
    for id in state.session.windows.keys.sorted() {
        guard let window = state.doc.windows[id], var session = state.session.windows[id] else { continue }
        let tree = state.tree(window.container)
        let before = session
        if let pending = session.pendingSpaceDeletion, state.doc.spaces[pending.id] == nil || state.doc.spaces.count <= 1 { session.pendingSpaceDeletion = nil }
        if let renaming = session.renaming, tree?[renaming] == nil { session.renaming = nil }
        switch session.overlay {
        case .commandBar(_, .navigate(let tab, _)), .commandBar(_, .fillPane(let tab)):
            if tree?[tab]?.kind != .tab { session.overlay = nil }
        case .peek(_, let tab):
            if state.session.scratch[id]?[tab]?.kind != .tab { session.overlay = nil }
        case .commandBar(_, .newTab), .library, nil:
            break
        }
        if case .commandBar? = session.overlay {} else if session.suggestions != nil { session.suggestions = nil }
        if case .editSpace(let space)? = session.dialog, state.doc.spaces[space] == nil { session.dialog = nil }
        switch session.profileDialog {
        case .change(let space)? where state.doc.spaces[space] == nil: session.profileDialog = nil
        case .delete(let profile)? where state.doc.profiles[profile] == nil: session.profileDialog = nil
        default: break
        }
        if let cycle = session.recentCycle {
            let order = cycle.order.filter { tree?[$0] != nil }
            if order.count < 2 { session.recentCycle = nil }
            else if order != cycle.order {
                session.recentCycle = RecentCycle(order: order, index: min(cycle.index, order.count - 1), baseline: cycle.baseline)
            }
        }
        if session != before { state.session.windows[id] = session }
    }
}

/// A Little Arc holds one tab (Arc: `LittleBrowser`; F3): when its last tab is gone (Cmd+W, the page closed itself,
/// the sweep) and no command bar is waiting for a URL, the window closes with it, session and scratch tree included.
/// Runs after the session targets are repaired, so a bar whose tab vanished does not keep the window alive.
private func closeEmptyLittleWindows(_ state: inout AppState) {
    for id in state.doc.windows.keys.sorted() where state.doc.windows[id]?.kind == .little {
        if case .commandBar? = state.session.windows[id]?.overlay { continue }
        let hasTab = state.session.scratch[id]?.items.values.contains { if case .tab = $0.body { true } else { false } } ?? false
        guard !hasTab else { continue }
        state.doc.windows[id] = nil
        state.session.windows[id] = nil
        state.session.scratch[id] = nil
    }
}

private func repairLoaded(_ state: inout AppState) {
    let removed = state.session.loaded.filter { !state.owns($0) }
    for page in removed.sorted() {
        if let saved = state.doc.windows[page.window]?.slots[page.item], let scope = state.locate(page.item),
           !state.session.loaded.subtracting(removed).contains(where: { $0.item == page.item }) {
            state.withTree(scope) { $0.updateTab(page.item) { $0.url = saved.committedURL } }
        }
        state.session.loaded.remove(page)
    }
    for id in state.doc.windows.keys {
        state.doc.windows[id]!.emptySelections = state.doc.windows[id]!.emptySelections.filter { state.doc.spaces[$0] != nil }
        for space in state.doc.windows[id]!.emptySelections { state.doc.windows[id]!.activeBySpace[space] = nil }
    }
    for page in state.onScreenPages() { state.demand(page) }
    state.session.live = state.session.live.filter { state.session.loaded.contains($0.key) }
    for page in state.session.loaded {
        if state.session.live[page]?.requestContext != nil,
           state.session.live[page]?.requestContext != state.browsingContext(of: page.item) {
            state.session.live[page] = LivePage()
        }
    }
    for id in state.doc.windows.keys {
        state.doc.windows[id]!.slots = state.doc.windows[id]!.slots.filter { state.owns(PageID(window: id, item: $0.key)) }
        state.doc.windows[id]!.splitFocus = state.doc.windows[id]!.splitFocus.filter { split, pane in
            state.tree(of: id)?[split]?.kind == .split && state.panes(of: split).contains(pane)
        }
    }
}

private func applyCaps(_ state: inout AppState, _ repairs: inout [String]) {
    let archiveCap = Metrics.persistence.archiveCap.value, historyCap = Metrics.persistence.historyCap.value
    if state.doc.archive.count > archiveCap { state.doc.archive.removeLast(state.doc.archive.count - archiveCap) }
    if state.doc.history.count > historyCap { state.doc.history.removeLast(state.doc.history.count - historyCap) }
    for id in state.doc.windows.keys.sorted() {
        let width = state.doc.windows[id]!.sidebarWidth
        let clamped = width.isFinite ? min(max(width, Metrics.sidebar.minWidth.value), Metrics.sidebar.maxWidth.value) : Metrics.sidebar.defaultWidth.value
        if clamped != width {
            repairs.append("window \(id) sidebar width \(width) clamped to \(clamped)")
            state.doc.windows[id]!.sidebarWidth = clamped
        }
    }
}
