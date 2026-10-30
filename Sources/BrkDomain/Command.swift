import BrkBase
import CoreGraphics
import Foundation

// The input vocabulary. Every user intent from every source (menu, key through CEF, sidebar click, command bar,
// popup menu, control socket) is one `Command`, scoped to the window it came from. Every observation (page events,
// clock ticks, window geometry, modifier release) is one `SystemEvent`. `reduce` is the only interpreter of both,
// so each thing has one way to happen no matter where it came from.
//
// Totality: `reduce` handles every value of `Input` without trapping (unknown ids are no-ops, numbers are clamped),
// so the control socket's boundary parse is structural only (JSON -> Command). Adding a case is one line here plus
// one `case` in the area's rule file; Swift's exhaustive switch fails the build until both exist.
//
// Overlay rule, enforced once in `reduce` (`Command.keepsCommandBar` / `keepsArchive`): every command except
// `.commandBar` first closes an open command bar; `.archive` and `.settings` keep an open archive page. Picking an
// action or a tab in the command bar is therefore just dispatching that action's command.

public enum Input: Sendable, Equatable {
    case user(WindowID, Command)
    /// A key-down from one delivery path for a page or native view in this window (KeyRouting.swift). If routing
    /// decides it is an app shortcut, the action's command runs in the same transition and `keyHandled` is true.
    case key(WindowID, KeyInput)
    case system(SystemEvent)
}

public enum Command: Hashable, Sendable, Codable {
    case commandBar(CommandBarCommand)
    case archive(ArchiveCommand)
    case tab(TabCommand)
    case page(PageCommand)
    case item(ItemCommand)
    case space(SpaceCommand)
    case split(SplitCommand)
    case sidebar(SidebarCommand)
    case app(AppCommand)
    case settings(SettingsCommand)
}

/// "What the user is looking at" or an explicit item.
public enum ItemRef: Hashable, Sendable, Codable {
    /// The focused pane's tab in the dispatching window.
    case focused
    case item(ItemID)
}

public enum SpaceRef: Hashable, Sendable, Codable {
    case current
    case space(SpaceID)
}

public enum Step: String, Hashable, Sendable, Codable { case next, previous }

public enum CommandBarMode: String, Hashable, Sendable, Codable {
    /// Cmd+T: centered bar that creates a tab (Arc: `createNewTab`).
    case newTab
    /// Cmd+L or a URL pill click: edit the focused tab's URL (Arc: `overrideCurrentTab`).
    case editCurrent
}

public enum CommandBarCommand: Hashable, Sendable, Codable {
    case open(CommandBarMode)
    /// Typed text or a history URL; resolved by `resolveTypedInput` and applied per the open bar's target.
    case submit(String)
    /// Esc in the bar.
    case dismiss
}

public enum ArchiveCommand: Hashable, Sendable, Codable {
    case open
    case restore(ArchiveID)
    /// Cmd+Shift+T: newest manual or clear entry first, then auto.
    case restoreLast
    case clear
}

public enum TabCommand: Hashable, Sendable, Codable {
    /// Sidebar click, favorite click, command bar "switch to tab". Switches space when needed.
    case focus(ItemID)
    /// Cmd+Opt+Down/Up: next or previous stop in sidebar order, no wrap; a split is one stop.
    case step(Step)
    /// Ctrl+Tab / Ctrl+Shift+Tab: walk the frozen recent order; commits on Control release.
    case cycleRecent(Step)
    /// Cmd+W and the hover x. Today: archive. Pinned or Favorites: unload, keep the row ("Close and Keep Pinned").
    case close(ItemRef)
    /// Context-menu "Archive Tab": archive whatever the section.
    case archive(ItemRef)
    /// Cmd+D: Today -> end of Pinned; Pinned or Favorites -> top of Today.
    case togglePin(ItemRef)
    /// "Reset Tab to Original URL".
    case reset(ItemRef)
    /// Cmd+Shift+K and Today's Clear: archive every Today item not on screen in any window.
    case clearToday
}

/// Browsing actions on a tab's page. Each resolves the target and becomes `Effect.page`; an unloaded target is a no-op.
public enum PageCommand: Hashable, Sendable, Codable {
    case back(ItemRef)
    case forward(ItemRef)
    case reload(ItemRef, ignoringCache: Bool)
    case stop(ItemRef)
    case zoom(ZoomStep)
    case toggleDevTools
    /// Cmd+Shift+C.
    case copyURL
}

/// Where a dragged item lands.
public enum Destination: Hashable, Sendable, Codable {
    /// `index` counts the parent's children after the item is detached, so the same move twice is a no-op.
    case into(parent: ItemID, index: Int)
    /// Dropped on a dock space icon: top of its Today, or end of its Pinned if the item came from Pinned.
    case space(SpaceID)
}

public enum ItemCommand: Hashable, Sendable, Codable {
    /// Double-click a row or "Rename Current Item": the row becomes a text field.
    case beginRename(ItemRef)
    /// Ends a rename. Nil cancels; "" on a tab clears its custom title.
    case rename(ItemID, title: String?)
    case move(ItemID, to: Destination)
    /// Cmd+Shift+N: new folder at the top of the current space's Pinned, in rename mode.
    case newFolder
    case toggleFolder(ItemID)
    /// "Deleting this folder will archive the tabs inside it."
    case deleteFolder(ItemID)
    /// Context menu "Change Icon" on a tab, folder or split (Arc: `SidebarCustomIcon`); nil restores the default
    /// (favicon or folder glyph).
    case setIcon(ItemID, CustomIcon?)
}

public enum SpaceCommand: Hashable, Sendable, Codable {
    case create(title: String, icon: SpaceIcon, theme: SpaceTheme)
    case update(SpaceID, title: String?, icon: SpaceIcon?, theme: SpaceTheme?)
    /// Archives every tab in the space. Refused for the last space.
    case delete(SpaceID)
    case move(SpaceID, index: Int)
    /// Dock icon click.
    case focus(SpaceID)
    /// Cmd+Opt+Right/Left, no wrap.
    case step(Step)
    case togglePinnedSection(SpaceRef)
}

public enum SplitCommand: Hashable, Sendable, Codable {
    /// Ctrl+Shift+=. A tab becomes a split of [tab, empty pane]; a split gains a pane (max Metrics.content.maxPanes).
    /// The command bar opens to fill the new pane.
    case addPane
    /// Ctrl+Shift+-. Closes the focused pane; a split left with one pane dissolves into that tab.
    case closePane
    /// Divider drag. Relative fractions; the reducer normalizes and enforces Metrics.content.minPaneFraction.
    case resize(ItemID, fractions: [ItemID: Double])
    /// Context menu on a split (Arc: `layoutOrientation`). Saved with the split; v1's layout draws both.
    case setOrientation(ItemID, SplitOrientation)
}

public enum SidebarCommand: Hashable, Sendable, Codable {
    /// Cmd+S.
    case toggle
    /// Resize drag, after `SidebarResizeDrag` applied snapping. 0 hides the sidebar. Clamped by the reducer.
    case resize(width: Double)
    /// Hidden sidebar: pointer reached the left edge (true) or left the floating sidebar (false).
    case peek(Bool)
    case openDialog(SpaceDialogRequest?)
    /// Right-click a row or a space, or the "+" button. `at` is in window coordinates.
    case popupMenu(PopupMenuRequest, at: CGPoint)
}

public enum SpaceDialogRequest: Hashable, Sendable, Codable {
    case newSpace
    case editSpace(SpaceRef)
}

public enum PopupMenuRequest: Hashable, Sendable, Codable {
    case item(ItemID)
    case space(SpaceID)
    case plusButton
}

/// App and window chrome. Also the commands behind app shortcuts (Cmd+Q, Cmd+H, Cmd+M): while a page has focus
/// the AppKit menu never sees key equivalents, so even these go through the key router and the reducer.
public enum AppCommand: Hashable, Sendable, Codable {
    case quit
    case hide
    case hideOthers
    case minimize
    case toggleFullScreen
    /// Arc's "Exit" (Esc): close the open overlay, else leave full screen.
    case exit
}

public enum SettingsCommand: Hashable, Sendable, Codable {
    case autoArchive(AutoArchiveThreshold)
}

// MARK: - System events

public enum SystemEvent: Sendable, Equatable {
    case page(PageID, PageEvent)
    /// Auto-archive sweep: on a real-time interval, and after the e2e clock moves.
    case clockTick
    case window(WindowID, WindowEvent)
    // Later: case externalURL(URL)            -- links from other apps (Little Arc, Air Traffic Control routes).
    // Later: case liveFolder(ItemID, [URL])   -- a live folder fetch finished.
}

public enum WindowEvent: Sendable, Equatable {
    /// NSWindow moved or resized. `bounds` (screen) is saved for restore; `contentSize` drives layout.
    case geometry(bounds: CGRect, contentSize: CGSize)
    /// The modifier keys now held, from the window's `flagsChanged` events (sent whichever view has focus).
    /// Control going up commits a Ctrl+Tab cycle; Control going down while a cycle is still pending (its release was
    /// lost) commits it too, so each new hold starts a fresh walk (regression finding 6).
    case modifiersChanged(held: Modifiers)
    /// The user closed the window with its close button.
    case closed
}

extension Command {
    /// Whether this command leaves an open command bar open.
    var keepsCommandBar: Bool {
        if case .commandBar = self { return true }
        return false
    }

    /// Whether this command leaves an open archive page open.
    var keepsArchive: Bool {
        switch self {
        case .archive, .settings, .sidebar(.peek): true
        default: false
        }
    }
}
