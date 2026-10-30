import BrkBase
import Foundation

/// Every rule that spans entities, run after each transition and after decoding a file. It repairs; it never
/// decides: an absent active item stays absent (the space shows an empty card) until a user action fills it, and a
/// tab the user has not asked to see is never loaded. Idempotent: a normalized state comes back equal. Returns one
/// line per repair (restore reports them; `reduce` ignores them). In order:
///
/// 1. (Split membership, pane count, split focus and `pinnedURL` are kept by `SidebarTree` itself and need no
///    repair at run time; `SidebarTree.restored` repairs them in a file.)
/// 2. Every window's space exists (else the first space); `spaceOrder` lists exactly the spaces; every saved window
///    has a session and no session outlives its window.
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
    repairSpaces(&state, &repairs)
    repairShownItems(&state, &repairs)
    repairSessionTargets(&state)
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
            state.session.windows[id] = WindowSession(contentSize: Metrics.window.defaultSize.value, overlay: nil, overlayOpens: 0,
                                                      peek: false, renaming: nil, dialog: nil, recentCycle: nil, heldModifiers: [],
                                                      keyRouting: .empty)
        }
    }
    for id in state.session.windows.keys where state.doc.windows[id] == nil {
        state.session.windows[id] = nil
        state.session.scratch[id] = nil
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
            let next = state.mostRecentLoaded(in: space, excluding: item)
            repairs.append("window \(id) showed \(item) in space \(space), now \(next.map(\.rawValue) ?? "nothing")")
            state.doc.windows[id]!.activeBySpace[space] = next
        }
    }
}

/// A tab (not a pane) or a split, under the space's own sections or Favorites.
private func showable(_ item: ItemID, in space: SpaceID, _ tree: SidebarTree) -> Bool {
    guard let node = tree[item], node.kind == .tab || node.kind == .split, tree.splitContaining(item) == nil,
          let role = tree.role(of: item) else { return false }
    return role.space == space || role.kind == .favorites
}

private func repairSessionTargets(_ state: inout AppState) {
    for id in state.session.windows.keys.sorted() {
        guard let window = state.doc.windows[id], var session = state.session.windows[id] else { continue }
        let tree = state.tree(window.container)
        let before = session
        if let renaming = session.renaming, tree?[renaming] == nil { session.renaming = nil }
        switch session.overlay {
        case .commandBar(_, .navigate(let tab, _)), .commandBar(_, .fillPane(let tab)):
            if tree?[tab]?.kind != .tab { session.overlay = nil }
        case .commandBar(_, .newTab), .archive, nil:
            break
        }
        if case .editSpace(let space)? = session.dialog, state.doc.spaces[space] == nil { session.dialog = nil }
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

private func repairLoaded(_ state: inout AppState) {
    var loaded = state.session.loaded.filter { state.tab($0) != nil }
    loaded.formUnion(state.onScreenTabs().filter { state.tab($0) != nil })
    if loaded != state.session.loaded { state.session.loaded = loaded }
    let live = state.session.live.filter { loaded.contains($0.key) }
    if live.count != state.session.live.count { state.session.live = live }
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
