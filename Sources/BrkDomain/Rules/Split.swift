import BrkBase
import Foundation

// Owner: W1. Split view as Arc stores it: one sidebar item whose children are the panes (anatomy 1.7).

extension Work {
    mutating func splits(_ command: SplitCommand, in window: WindowID) {
        switch command {
        case .addPane:
            // A shown tab becomes a split [tab, new empty pane] in its place; a shown split below the pane cap gets
            // an empty pane after its focused pane, with an equal share. The new pane is focused and the command bar
            // opens to fill it. Nothing shown, a Favorites tab (Favorites hold tabs only), or a full split: no-op.
            guard let shown = state.shownItem(in: window), let scope = state.locate(shown), let tree = state.tree(scope) else { return }
            let pane = ItemID(ctx.newID())
            let empty = Tab(url: nil, title: "", lastActiveAt: ctx.now)
            var added = false
            switch tree[shown]?.body {
            case .tab?:
                let split = ItemID(ctx.newID())
                state.withTree(scope) { tree in
                    added = (try? tree.splitInPlace(shown, splitID: split, newPane: pane, empty, createdAt: ctx.now)) != nil
                }
                if added { state.doc.windows[window]!.activeBySpace[state.doc.windows[window]!.space] = split }
            case .split(let s)?:
                let weights = s.panes.ids.map { s.widths[$0] ?? 1 }
                let after = state.focusedPane(of: shown, in: window) ?? s.panes.ids[0]
                state.withTree(scope) { tree in
                    added = (try? tree.addPane(to: shown, newPane: pane, empty, after: after, createdAt: ctx.now)) != nil
                    if added, !s.widths.isEmpty {
                        // The mean, divided before adding so huge saved widths cannot overflow to infinity.
                        tree.updateSplit(shown) { $0.widths[pane] = weights.reduce(0) { $0 + $1 / Double(weights.count) } }
                    }
                }
            case .folder?, .section?, nil:
                return
            }
            guard added else { return }
            focus(pane, in: window)
            openOverlay({ .commandBar(openID: $0, target: .fillPane(tab: pane)) }, in: window)
        case .closePane:
            // The focused pane leaves: archived from Today; moved out to sit right after the split and unloaded
            // from Pinned; an empty pane (no URL) is removed either way without an archive entry. A split left with
            // one pane dissolves into it in place, and windows that showed the split show that pane.
            guard let shown = state.shownItem(in: window), let scope = state.locate(shown), let tree = state.tree(scope),
                  case .split(let s)? = tree[shown]?.body, let role = tree.role(of: shown) else { return }
            let tab = state.focusedPane(of: shown, in: window) ?? s.panes.ids[0]
            if role.kind == .pinned, state.address(of: tab, in: window, for: .savedDocument) != nil {
                guard moveItem(tab, to: .after(shown)) else { return }
                unload(tab)
            } else {
                archiveTabs([tab], reason: .manual, in: window)
            }
        case .resize(let split, let fractions):
            // Fractions keyed by pane must name exactly the split's panes; they are normalized to sum 1 with each at
            // least Metrics.content.minPaneFraction, and stored as the split's widths.
            guard let scope = state.locate(split), case .split(let s)? = state.tree(scope)?[split]?.body,
                  Set(fractions.keys) == Set(s.panes.ids), fractions.values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
            let clamped = clampFractions(s.panes.ids.map { fractions[$0]! })
            state.withTree(scope) { tree in
                tree.updateSplit(split) { sp in
                    for (pane, value) in zip(s.panes.ids, clamped) where sp.widths[pane] != value { sp.widths[pane] = value }
                }
            }
        case .setOrientation(let split, let orientation):
            guard let scope = state.locate(split) else { return }
            state.withTree(scope) { $0.updateSplit(split) { if $0.orientation != orientation { $0.orientation = orientation } } }
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
