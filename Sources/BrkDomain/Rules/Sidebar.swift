import BrkBase
import CoreGraphics
import Foundation

// Owner: W1. Sidebar structure (rename, move, folders), spaces, sidebar chrome, app commands and window events.

extension Work {
    mutating func items(_ command: ItemCommand, in window: WindowID) {
        // TODO(W1):
        // .beginRename(ref): renaming = target; with the sidebar hidden, peek it so the field is visible.
        // .rename(id, nil) cancels; "" on a tab clears customTitle; else customTitle/title = trimmed (max 500 chars).
        // .move(id, .into(parent, index)): tree.move; refused (no-op) for cycles and what Placement forbids.
        // .move(id, .space(s)): top of s's Today, or end of s's Pinned if the item came from Pinned; stamp
        //   lastActiveAt of moved tabs (regression finding 5: a dragged tab is not swept right after).
        // .newFolder: folder "New Folder" at top of current Pinned, expand Pinned, renaming = folder.
        // .toggleFolder(id): collapsed.toggle(). .deleteFolder(id): archiveTabs([id], .containerDeleted).
        // .setIcon(id, icon): updateTab/updateFolder/updateSplit by the item's kind; unknown id -> no-op.
        fatalError("not implemented")
    }

    mutating func spaces(_ command: SpaceCommand, in window: WindowID) {
        // TODO(W1):
        // .create: new space with pinned/today roots (makeRoot), blank title stored as "" (shown "Space N"), switch
        //   the window to it, close the dialog. .update: patch, close the edit dialog; same values -> no change.
        // .delete: refused for the last space; archiveTabs(its roots' tabs, .containerDeleted); windows on it move
        //   to the neighbour in spaceOrder. .move: reorder with the index clamped.
        // .focus(s): stamp tabs leaving the screen; windows[w].space = s; the space's last active item shows again.
        // .step: neighbour, no wrap. .togglePinnedSection: pinnedCollapsed.toggle().
        fatalError("not implemented")
    }

    mutating func sidebar(_ command: SidebarCommand, in window: WindowID) {
        // TODO(W1):
        // .toggle: sidebarVisible.toggle(); ends a peek.
        // .resize(width): 0 -> hide; else clamp to Metrics.sidebar.minWidth...maxWidth.
        // .peek(open): only while hidden.
        // .openDialog(req): dialog = req (peek a hidden sidebar); nil closes.
        // .popupMenu(req, at): Effect.popupMenu(window, menuModel(for: req), at) built from state, entries carry the
        //   real commands ("Close and Keep Pinned", "Archive Tab", "Rename", "Change Icon", "Delete Space", "New Tab").
        fatalError("not implemented")
    }

    /// App and window chrome. These change no state (except Esc closing an overlay), so their transitions carry
    /// effects with `changed == false`; the store runs them anyway.
    mutating func app(_ command: AppCommand, in window: WindowID) {
        switch command {
        case .quit: effects.append(.app(.quit))
        case .hide: effects.append(.app(.hide))
        case .hideOthers: effects.append(.app(.hideOthers))
        case .minimize: effects.append(.window(window, .miniaturize))
        case .toggleFullScreen: effects.append(.window(window, .toggleFullScreen))
        case .exit:
            // Arc's "Exit" (Esc; the menu takes Esc before text fields, as Arc's nib does): close the open overlay,
            // else cancel a rename or dialog, else leave full screen (the window decides whether it is in one).
            guard var session = state.session.windows[window] else { return }
            if session.overlay != nil { session.overlay = nil }
            else if session.renaming != nil { session.renaming = nil }
            else if session.dialog != nil { session.dialog = nil }
            else { effects.append(.window(window, .leaveFullScreen)) }
            state.session.windows[window] = session
        }
    }

    mutating func windowEvent(_ event: WindowEvent, in window: WindowID) {
        guard state.doc.windows[window] != nil, var session = state.session.windows[window] else { return }
        switch event {
        case .geometry(let bounds, let contentSize):
            state.doc.windows[window]!.bounds = bounds
            session.contentSize = contentSize
            state.session.windows[window] = session
        case .modifiersChanged(let held):
            let was = session.heldModifiers
            session.heldModifiers = held
            state.session.windows[window] = session
            // Control up commits a pending Ctrl+Tab cycle; Control down with a cycle still pending (its release was
            // lost) commits it too, so each new hold starts a fresh walk (regression finding 6).
            if was.contains(.control) != held.contains(.control) { commitCycle(in: window) }
        case .closed:
            // Keep the WindowDoc so the next launch restores it (v1 has one window). Quitting after the last window
            // closes is AppKit's applicationShouldTerminateAfterLastWindowClosed, which reaches the same ordered quit
            // as Cmd+Q; the reducer does not emit a second quit.
            break
        }
    }
}
