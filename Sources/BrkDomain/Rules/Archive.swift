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
        // TODO(W1): .autoArchive(t): settings.autoArchive = t.
        fatalError("not implemented")
    }

    /// `SystemEvent.clockTick`. Archives (reason .auto) Today tabs idle longer than the threshold, never a tab on
    /// screen in any window, never Pinned or Favorites. Idempotent: a second tick at the same `now` is a no-op.
    mutating func sweepAutoArchive() {
        // TODO(W1): commit pending cycles first (regression finding 5); idle = ctx.now.since(tab.lastActiveAt).
        fatalError("not implemented")
    }

    /// Moves tabs into the archive (newest first, capped), removing them from the tree and from `loaded`.
    mutating func archiveTabs(_ tabs: [ItemID], reason: ArchiveReason) {
        fatalError("not implemented")
    }
}
