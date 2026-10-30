import BrkBase
import Foundation

/// Every rule that spans entities, run after each transition and after decoding a file. It repairs; it never
/// decides: an absent active item stays absent (the space shows an empty card) until a user action fills it.
///
/// 1. (Split membership, pane count and focus are kept by `SidebarTree` itself and need no repair.)
/// 2. `activeBySpace` entries name existing tabs or splits of that window's spaces (or Favorites tabs); dangling
///    entries are removed.
/// 3. Every window's space exists; `spaceOrder` lists exactly the spaces; every saved window has a session.
/// 4. Overlay, rename, dialog and cycle targets exist; otherwise they close.
/// 5. Every visible tab (a pane of a window's shown item) is in `session.loaded`; `loaded` and `live` name only
///    existing tabs, and `live` only loaded ones.
/// 6. Archive and history caps; sidebar width within Metrics.sidebar bounds.
func normalize(_ state: inout AppState) {
    repairSpaces(&state)
    repairShownItems(&state)
    repairSessionTargets(&state)
    repairLoaded(&state)
    applyCaps(&state)
}

private func repairSpaces(_ state: inout AppState) {
    var order = state.doc.spaceOrder.filter { state.doc.spaces[$0] != nil }
    for space in state.doc.spaces.keys.sorted() where !order.contains(space) { order.append(space) }
    if order != state.doc.spaceOrder { state.doc.spaceOrder = order }
    for (id, var window) in state.doc.windows {
        if state.doc.spaces[window.space] == nil, let first = order.first {
            window.space = first
            state.doc.windows[id] = window
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

private func repairShownItems(_ state: inout AppState) {
    for (id, var window) in state.doc.windows {
        var changed = false
        for (space, item) in window.activeBySpace {
            let tree = state.tree(window.container)
            guard state.doc.spaces[space] != nil, let node = tree?[item], let role = tree?.role(of: item),
                  node.kind == .tab || node.kind == .split, role.space == space || role.kind == .favorites
            else {
                window.activeBySpace[space] = nil
                changed = true
                continue
            }
        }
        if changed { state.doc.windows[id] = window }
    }
}

private func repairSessionTargets(_ state: inout AppState) {
    for (id, var session) in state.session.windows {
        guard let window = state.doc.windows[id] else { continue }
        let tree = state.tree(window.container)
        var changed = false
        if let renaming = session.renaming, tree?[renaming] == nil { session.renaming = nil; changed = true }
        switch session.overlay {
        case .commandBar(_, .navigate(let tab, _)), .commandBar(_, .fillPane(let tab)):
            if tree?[tab] == nil { session.overlay = nil; changed = true }
        case .commandBar(_, .newTab), .archive, nil:
            break
        }
        if case .editSpace(let space)? = session.dialog, state.doc.spaces[space] == nil { session.dialog = nil; changed = true }
        if let cycle = session.recentCycle {
            let order = cycle.order.filter { tree?[$0] != nil }
            if order.count < 2 { session.recentCycle = nil; changed = true }
            else if order != cycle.order { session.recentCycle = RecentCycle(order: order, index: min(cycle.index, order.count - 1), baseline: cycle.baseline); changed = true }
        }
        if changed { state.session.windows[id] = session }
    }
}

private func repairLoaded(_ state: inout AppState) {
    var loaded = state.session.loaded.filter { tab in
        guard let scope = state.locate(tab), case .tab? = state.tree(scope)?[tab]?.body else { return false }
        return true
    }
    loaded.formUnion(state.onScreenTabs())
    if loaded != state.session.loaded { state.session.loaded = loaded }
    let live = state.session.live.filter { loaded.contains($0.key) }
    if live.count != state.session.live.count { state.session.live = live }
}

private func applyCaps(_ state: inout AppState) {
    let archiveCap = Metrics.persistence.archiveCap.value, historyCap = Metrics.persistence.historyCap.value
    if state.doc.archive.count > archiveCap { state.doc.archive.removeLast(state.doc.archive.count - archiveCap) }
    if state.doc.history.count > historyCap { state.doc.history.removeLast(state.doc.history.count - historyCap) }
    for (id, var window) in state.doc.windows {
        let clamped = min(max(window.sidebarWidth, Metrics.sidebar.minWidth.value), Metrics.sidebar.maxWidth.value)
        if clamped != window.sidebarWidth {
            window.sidebarWidth = clamped
            state.doc.windows[id] = window
        }
    }
}
