import BrkBase
import Foundation

// Owner: W1. The archive and auto-archive (anatomy 1.9, 4.3).

extension Work {
    mutating func archive(_ command: ArchiveCommand, in window: WindowID) {
        // TODO(W1):
        // .open: overlay = .archive (in the content card); idempotent (same openID when already open).
        // .restore(id): back to its source section if the space still exists, else top of the dispatching window's
        //   current Today; reuse the tab id unless taken; lastActiveAt = now (not swept again at once); focus it.
        // .restoreLast: newest .manual/.clearToday entry first, else newest; empty archive -> no-op.
        // .clear: empty the archive.
        fatalError("not implemented")
    }

    mutating func settings(_ command: SettingsCommand, in window: WindowID) {
        switch command {
        case .autoArchive(let threshold): state.doc.settings.autoArchive = threshold
        }
    }

    /// `SystemEvent.clockTick`. Archives (reason .auto) Today tabs idle longer than the threshold, never a tab on
    /// screen in any window, never Pinned or Favorites, never an empty pane (no URL). Pending Ctrl+Tab cycles are
    /// committed first so a tab just left is stamped (regression finding 5). Idempotent: a second tick at the same
    /// `now` is a no-op.
    mutating func sweepAutoArchive() {
        for window in state.doc.windows.keys { commitCycle(in: window) }
        guard let threshold = state.doc.settings.autoArchive.interval else { return }
        let onScreen = state.onScreenTabs()
        var victims: [ItemID] = []
        for space in state.doc.spaceOrder.compactMap({ state.doc.spaces[$0] }) {
            for tab in state.doc.tree.tabs(under: space.todayRoot) where !onScreen.contains(tab) {
                guard case .tab(let t)? = state.doc.tree[tab]?.body, t.url != nil else { continue }
                if ctx.now.since(t.lastActiveAt) >= threshold { victims.append(tab) }
            }
        }
        archiveTabs(victims, reason: .auto)
    }

    /// Moves tabs into the archive (newest first, capped by normalize), removing them from the tree and from
    /// `loaded`/`live`. A folder or split id archives every tab inside it. Empty panes (no URL) are removed without
    /// an archive entry.
    mutating func archiveTabs(_ tabs: [ItemID], reason: ArchiveReason) {
        for id in tabs {
            guard let role = state.doc.tree.role(of: id), state.doc.tree[id]?.kind != .section else { continue }
            let removed = state.doc.tree.removeSubtree(id)
            for (tabID, tab) in removed.reversed() {
                state.session.loaded.remove(tabID)
                state.session.live[tabID] = nil
                guard tab.url != nil else { continue }
                state.doc.archive.insert(
                    ArchivedTab(id: ArchiveID(ctx.newID()), tabID: tabID, tab: tab, archivedAt: ctx.now, reason: reason,
                                fromSpace: role.space, fromSection: role.kind),
                    at: 0
                )
            }
        }
    }
}
