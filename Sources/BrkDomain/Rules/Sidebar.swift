import BrkBase
import CoreGraphics
import Foundation

// Owner: W1. Sidebar structure (rename, move, folders), spaces, and sidebar chrome.

extension Work {
    mutating func items(_ command: ItemCommand, in window: WindowID) {
        // TODO(W1):
        // .beginRename(ref): renaming = target; with the sidebar hidden, peek it so the field is visible.
        // .rename(id, nil) cancels; "" on a tab clears customTitle; else customTitle/title = trimmed (max 500 chars).
        // .move(id, .into(parent, index)): tree.move; refused (no-op) for cycles and what Placement forbids.
        // .move(id, .space(s)): top of s's Today, or end of s's Pinned if the item came from Pinned; stamp
        //   lastActiveAt of moved tabs (regression finding 5: a dragged tab is not swept right after).
        // .newFolder: folder "New Folder" at top of current Pinned, expand Pinned, renaming = folder.
        // .toggleFolder(id): collapsed.toggle(). .deleteFolder(id): archive its tabs (.containerDeleted), remove.
        fatalError("not implemented")
    }

    mutating func spaces(_ command: SpaceCommand, in window: WindowID) {
        // TODO(W1):
        // .create: new space with pinned/today roots, fallback title "Space N" for blank, switch the window to it,
        //   close the dialog. .update: patch, close the edit dialog; same values -> no change.
        // .delete: refused for the last space; archive its tabs (.containerDeleted); windows on it move to the
        //   neighbour in spaceOrder. .move: reorder with the index clamped.
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
        //   real commands ("Close and Keep Pinned", "Archive Tab", "Rename", "Delete Space", "New Tab", ...).
        fatalError("not implemented")
    }

    mutating func app(_ command: AppCommand, in window: WindowID) {
        // TODO(W1): .quit/.hide/.hideOthers -> Effect.app; .minimize -> Effect.window(.miniaturize);
        // .toggleFullScreen -> Effect.window(.toggleFullScreen); .exit (Esc; the menu takes Esc before text fields,
        // as Arc's nib does) -> close the overlay if one is open, else cancel a rename or dialog, else leave full
        // screen, else nothing.
        fatalError("not implemented")
    }

    mutating func windowEvent(_ event: WindowEvent, in window: WindowID) {
        // TODO(W1): .geometry -> doc bounds (saved) + session contentSize; .modifiersChanged(held) -> compare with
        // heldModifiers: Control up commits a pending Ctrl+Tab cycle, Control down with a cycle still pending commits
        // it too; store held; .closed -> keep the WindowDoc so the next launch restores it (v1 has one
        // window). Quitting after the last window closes is AppKit's applicationShouldTerminateAfterLastWindowClosed,
        // which reaches the same ordered quit as Cmd+Q; the reducer does not emit a second quit.
        fatalError("not implemented")
    }
}
