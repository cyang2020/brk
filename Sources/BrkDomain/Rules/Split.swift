import BrkBase
import Foundation

// Owner: W1. Split view as Arc stores it: one sidebar item whose children are the panes (anatomy 1.7).

extension Work {
    mutating func splits(_ command: SplitCommand, in window: WindowID) {
        switch command {
        case .addPane, .addPaneBefore:
            guard state.doc.windows[window]?.kind != .little else { return }
            // A shown tab becomes a split [tab, new empty pane] in its place; a shown split below the pane cap gets
            // an empty pane after its focused pane, with an equal share. The new pane is focused and the command bar
            // opens to fill it. Nothing shown, a Favorites tab (Favorites hold tabs only), or a full split: no-op.
            // `addPaneBefore` puts the empty pane before the tab or the focused pane instead.
            let leading = command == .addPaneBefore
            guard let shown = state.shownItem(in: window), let scope = state.locate(shown), let tree = state.tree(scope) else { return }
            let pane = ItemID(ctx.newID())
            let empty = Tab(url: nil, title: "", lastActiveAt: ctx.now)
            var added = false
            switch tree[shown]?.body {
            case .tab?:
                let split = ItemID(ctx.newID())
                state.withTree(scope) { tree in
                    added = (try? tree.splitInPlace(shown, splitID: split, newPane: pane, empty, leading: leading, createdAt: ctx.now)) != nil
                }
                if added { state.doc.windows[window]!.activeBySpace[state.doc.windows[window]!.space] = split }
            case .split(let s)?:
                let weights = s.panes.ids.map { s.widths[$0] ?? 1 }
                let after = state.focusedPane(of: shown, in: window) ?? s.panes.ids[0]
                state.withTree(scope) { tree in
                    added = (try? tree.addPane(to: shown, newPane: pane, empty, after: after, leading: leading, createdAt: ctx.now)) != nil
                    if added, !s.widths.isEmpty {
                        // The mean, divided before adding so huge saved widths cannot overflow to infinity.
                        tree.updateSplit(shown) { $0.widths[pane] = weights.reduce(0) { $0 + $1 / Double(weights.count) } }
                    }
                }
            case .folder?, .section?, nil:
                return
            }
            guard added else {
                if case .split(let s)? = tree[shown]?.body, s.panes.ids.count >= Metrics.content.maxPanes.value { toast(ToastCopy.cannotAddPane, in: window) }
                return
            }
            state.session.windows[window]?.expandedSplit = nil
            focus(pane, in: window)
            openOverlay({ .commandBar(openID: $0, target: .fillPane(tab: pane)) }, in: window)
        case .addPaneAt(let edge):
            // Arc's Add Left/Top Split puts the empty pane before the focused one (`addPaneBefore`), Right/Bottom after.
            splits(edge == .left || edge == .top ? .addPaneBefore : .addPane, in: window)
            guard let shown = state.shownItem(in: window), let scope = state.locate(shown), case .split? = state.tree(scope)?[shown]?.body else { return }
            state.withTree(scope) { tree in tree.updateSplit(shown) { if $0.orientation != edge.orientation { $0.orientation = edge.orientation } } }
        case .movePane(let step):
            guard let split = state.shownItem(in: window), state.canUseSplit(split, in: window),
                  let pane = state.focusedPane(of: split, in: window), let scope = state.locate(split) else { return }
            state.withTree(scope) { tree in try? tree.movePane(pane, step) }
        case .closePane:
            // The focused pane leaves: archived from Today; moved out to sit right after the split and unloaded
            // from Pinned; an empty pane (no URL) is removed either way without an archive entry. A split left with
            // one pane dissolves into it in place, and windows that showed the split show that pane.
            guard let shown = state.shownItem(in: window), let tab = state.focusedPane(of: shown, in: window) else { return }
            closeSplitPane(tab, in: window)
        case .closePaneAt(let pane):
            guard let tab = state.resolveTab(.item(pane), in: window) else { return }
            closeSplitPane(tab, in: window)
        case .resize(let split, let fractions):
            // Fractions keyed by pane must name exactly the split's panes; they are normalized to sum 1 with each at
            // least Metrics.content.minPaneFraction, and stored as the split's widths.
            guard state.canUseSplit(split, in: window), let scope = state.locate(split), case .split(let s)? = state.tree(scope)?[split]?.body,
                  Set(fractions.keys) == Set(s.panes.ids), fractions.values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
            let clamped = clampFractions(s.panes.ids.map { fractions[$0]! })
            state.withTree(scope) { tree in
                tree.updateSplit(split) { sp in
                    for (pane, value) in zip(s.panes.ids, clamped) where sp.widths[pane] != value { sp.widths[pane] = value }
                }
            }
        case .setOrientation(let split, let orientation):
            guard state.canUseSplit(split, in: window), let scope = state.locate(split) else { return }
            state.withTree(scope) { $0.updateSplit(split) { if $0.orientation != orientation { $0.orientation = orientation } } }
        case .orientCurrent(let orientation):
            if let split = state.shownItem(in: window) { splits(.setOrientation(split, orientation), in: window) }
        case .focusPane(let number):
            guard let split = state.shownItem(in: window), state.canUseSplit(split, in: window) else { return }
            let panes = state.panes(of: split)
            guard number > 0, number <= panes.count else { return }
            focus(panes[number - 1], in: window)
        case .stepPane(let step):
            guard let split = state.shownItem(in: window), state.canUseSplit(split, in: window),
                  let pane = state.focusedPane(in: window), let index = state.panes(of: split).firstIndex(of: pane) else { return }
            splits(.focusPane(index + (step == .next ? 2 : 0)), in: window)
        case .toggleExpanded:
            guard let split = state.shownItem(in: window), state.canUseSplit(split, in: window) else { return }
            let wasExpanded = state.session.windows[window]?.expandedSplit == split
            state.session.windows[window]?.expandedSplit = wasExpanded ? nil : split
        case .restore:
            state.session.windows[window]?.expandedSplit = nil
        case .separatePane(let ref):
            guard let pane = state.resolveTab(ref, in: window), let tree = state.tree(of: window),
                  let split = tree.splitContaining(pane), state.canUseSplit(split, in: window) else { return }
            let previous = splitSelections(split)
            guard moveItem(pane, to: .after(split)) else { return }
            restoreSplitSelections(previous, split: split)
            focus(pane, in: window)
        case .separateAll:
            guard let split = state.shownItem(in: window), state.canUseSplit(split, in: window) else { return }
            let previous = splitSelections(split)
            // Remove from the end. The last move dissolves the split into its first pane at the old position.
            for pane in state.panes(of: split).dropFirst().reversed() {
                guard moveItem(pane, to: .after(split)) else { return }
            }
            restoreSplitSelections(previous, split: split)
        case .dropTab(let offer, let edge):
            let source = offer.source, target = offer.target
            guard offer.window == window, let admission = state.splitDrop(in: window), admission.offers[source] == offer,
                  let scope = state.locate(target) else { return }
            group(source, with: target, edge: edge, in: scope, window: window)
        case .joinRow(let source, let target):
            let units = state.units(in: window)
            guard state.doc.windows[window]?.kind != .little, units.contains(source), units.contains(target),
                  let scope = state.locate(target), state.locate(source) == scope, state.tree(scope)?[target]?.kind == .tab else { return }
            group(source, with: target, edge: .left, in: scope, window: window)
        }
    }

    /// `source` joins `target` in a split (`SidebarTree.groupTab`) and the window shows it with `source` focused. Any
    /// window that showed either tab shows the split instead, with the pane it showed focused.
    private mutating func group(_ source: ItemID, with target: ItemID, edge: SplitEdge, in scope: ContainerScope, window: WindowID) {
        let before = state.doc.windows.mapValues { doc in
            doc.activeBySpace.filter { $0.value == target || $0.value == source }.mapValues { shown in
                shown == source ? source : (state.focusedPane(of: target, in: doc.id) ?? target)
            }
        }
        var grouped: ItemID?
        state.withTree(scope) { tree in
            grouped = try? tree.groupTab(source, with: target, splitID: ItemID(ctx.newID()), edge: edge, createdAt: ctx.now)
        }
        guard let split = grouped else { return }
        for (owner, spaces) in before {
            for (space, pane) in spaces {
                select(split, in: owner, space: space)
                state.doc.windows[owner]?.splitFocus[split] = pane
            }
        }
        focus(source, in: window)
        // `focus` resolves both original standalone tab selections to their new shared split.
        assert(state.shownItem(in: window) == split)
    }
    private mutating func closeSplitPane(_ tab: ItemID, in window: WindowID) {
        guard let scope = state.locate(tab), let tree = state.tree(scope), let split = tree.splitContaining(tab),
              state.canUseSplit(split, in: window), let role = tree.role(of: split) else { return }
        if role.kind == .pinned, state.address(of: tab, in: window, for: .savedDocument) != nil {
            guard moveItem(tab, to: .after(split)) else { return }
            unload(tab)
        } else {
            archiveTabs([tab], reason: .manual, in: window)
        }
    }

}

/// Relative positive finite weights -> fractions summing to 1, none below Metrics.content.minPaneFraction (or 1/n
/// when that is smaller). `.split(.resize)` stores these and the projection reads widths through it, so reading never
/// disagrees with writing. Only ratios matter: the weights are divided by the largest first, so no sum below can
/// overflow (two weights of 1e308 are two equal panes).
func clampFractions(_ raw: [Double]) -> [Double] {
    guard let largest = raw.max() else { return [] }
    let weights = raw.map { $0 / largest }
    let minimum = min(Metrics.content.minPaneFraction.value, 1 / Double(weights.count))
    var fixed: Set<Int> = []
    while true {
        let free = weights.indices.filter { !fixed.contains($0) }.reduce(0.0) { $0 + weights[$1] }
        let room = 1 - Double(fixed.count) * minimum
        let out = weights.indices.map { fixed.contains($0) ? minimum : (free > 0 ? weights[$0] / free * room : room / Double(weights.count - fixed.count)) }
        guard let low = out.indices.first(where: { !fixed.contains($0) && out[$0] < minimum }) else { return out }
        fixed.insert(low)
    }

}
