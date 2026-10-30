import BrkBase
import Foundation

// The one shortcut table. Three consumers derive from it and from nothing else:
// - the AppKit main menu (BrkApp/MainMenu.swift): menus in `MenuName` order, items in `ActionID` order within a
//   menu, separators between groups, key equivalents from the first binding;
// - key routing while a page has focus (KeyRouting.swift, called from the CEF key handler): every binding;
// - the command bar's action rows (`CommandBarSnapshot.actions`): entries with `commandBar != nil`.
//
// Titles, keys and priorities are Arc's menu nib (anatomy 2.3). `ActionID` raw values are Arc's `arcKeyBindingID`
// of the primary binding, so a later remap file (Arc: `StorableKeyBindings.json`) can use Arc's ids.
// Adding a case to `ActionID` without a `spec` fails to compile (exhaustive switch); the table has no second list.

public enum ActionID: String, Hashable, Sendable, Codable, CaseIterable, CodingKeyRepresentable {
    // App menu
    case hideArc, hideOthers, quitArc
    // File
    case newTab, reopenLastClosedTab, addressBar, archiveTab
    // Edit (standard Undo/Cut/Copy/Paste/Select All are AppKit items, not actions; Chromium handles them in pages)
    case copyCurrentURL
    // View
    case showSidebar, stopLoading, reloadPage, forceReloadPage, addSplitView, removeSplitView
    case resetZoom, zoomIn, zoomOut, developerTools, fullscreen, exit
    // Spaces
    case newSpace, editSpaceTheme, focusNextSpace, focusPreviousSpace, togglePinnedSection
    // Tabs
    case pinTab, newFolder, rename, selectNextTab, selectPreviousTab, cycleNextTab, cyclePreviousTab
    case clearExplore, resetTab
    // Archive (Arc's Archive menu also holds history navigation)
    case goBack, goForward, viewArchive, clearArchive
    // Window
    case minimize
}

/// Arc's `KeyBinding.Priority` (anatomy 1.14, 2.2), named for what happens:
/// - `app` (overrideWebView): taken in `OnPreKeyEvent`; the page never sees it.
/// - `pageThenApp` (promptAfterConsumedByWebView): the page gets it first; if the page consumed it, pressing it
///   again within Metrics.keys.pressTwiceWindow takes it for the app ("press twice to use Arc's shortcut").
/// - `page` (low, or unset in the nib): the page gets it first; the app acts only if the page did not consume it.
public enum KeyPriority: String, Hashable, Sendable, Codable { case app, pageThenApp, page }

/// One key binding of an action. Arc gives alternates their own binding id and priority (goBack is
/// overrideWebView on Cmd+[ but unset on Cmd+Left, so Cmd+Left still moves the caret in a text field).
public struct KeyBinding: Hashable, Sendable {
    public let chord: KeyChord
    public let priority: KeyPriority
    public init(_ chord: KeyChord, _ priority: KeyPriority) {
        self.chord = chord
        self.priority = priority
    }
}

/// Menu bar position, left to right (Arc's order; Extensions and Help land later).
public enum MenuName: String, Hashable, Sendable, CaseIterable { case app, file, edit, view, spaces, tabs, archive, window }

public struct CommandBarListing: Hashable, Sendable {
    /// Extra search words (Arc: `arcTypeTravelTriggers`).
    public let triggers: [String]
    /// SF Symbol name (Arc: `arcTypeTravelIcon`).
    public let symbol: String
}

public struct ActionSpec: Hashable, Sendable {
    /// Menu title and command bar row text. `{app}` is replaced with `Product.name`.
    public let title: String
    public let menu: MenuName
    /// Separators fall between different groups of one menu.
    public let group: Int
    /// The first binding is the menu's key equivalent; all of them route while a page has focus.
    public let bindings: [KeyBinding]
    /// Argument-free; resolved against the dispatching window (`.focused`, `.current`).
    public let command: Command
    public let commandBar: CommandBarListing?
    /// Auto-repeat dispatches again (stepping, cycling, zoom); toggles ignore repeats.
    public let repeats: Bool
}

private func entry(
    _ title: String, _ menu: MenuName, _ group: Int, _ bindings: [KeyBinding], _ command: Command,
    bar: CommandBarListing? = nil, repeats: Bool = false
) -> ActionSpec {
    ActionSpec(title: title, menu: menu, group: group, bindings: bindings, command: command, commandBar: bar, repeats: repeats)
}

private func listing(_ symbol: String, _ triggers: String...) -> CommandBarListing {
    CommandBarListing(triggers: triggers, symbol: symbol)
}

private let cmd = Modifiers.command, shift = Modifiers.shift, opt = Modifiers.option, ctrl = Modifiers.control

extension ActionID {
    public var spec: ActionSpec {
        switch self {
        case .hideArc: entry("Hide {app}", .app, 1, [.init(.init(cmd, .h), .app)], .app(.hide))
        case .hideOthers: entry("Hide Other Windows", .app, 1, [.init(.init([opt, cmd], .h), .page)], .app(.hideOthers))
        case .quitArc: entry("Quit {app}", .app, 2, [.init(.init(cmd, .q), .app)], .app(.quit))

        case .newTab: entry("New Tab…", .file, 0, [.init(.init(cmd, .t), .app)], .commandBar(.open(.newTab)))
        case .reopenLastClosedTab:
            entry("Restore Last Closed Tab", .file, 0, [.init(.init([shift, cmd], .t), .app)], .archive(.restoreLast),
                 bar: listing("arrow.uturn.backward", "reopen", "undo close"))
        case .addressBar: entry("Open Command Bar", .file, 0, [.init(.init(cmd, .l), .app)], .commandBar(.open(.editCurrent)))
        case .archiveTab:
            entry("Archive Tab", .file, 1, [.init(.init(cmd, .w), .app)], .tab(.close(.focused)), bar: listing("archivebox", "close"))

        case .copyCurrentURL:
            entry("Copy URL", .edit, 1, [.init(.init([shift, cmd], .c), .app)], .page(.copyURL), bar: listing("link", "copy link"))

        case .showSidebar:
            entry("Show/Hide Sidebar", .view, 0, [.init(.init(cmd, .s), .pageThenApp)], .sidebar(.toggle),
                 bar: listing("sidebar.leading", "toggle sidebar"))
        case .stopLoading: entry("Stop Loading", .view, 1, [.init(.init(cmd, .period), .page)], .page(.stop(.focused)))
        case .reloadPage:
            entry("Refresh the Page", .view, 1, [.init(.init(cmd, .r), .page)], .page(.reload(.focused, ignoringCache: false)),
                 bar: listing("arrow.clockwise", "reload"))
        case .forceReloadPage:
            entry("Force Refresh the Page", .view, 1, [.init(.init([shift, cmd], .r), .page)], .page(.reload(.focused, ignoringCache: true)))
        case .addSplitView:
            entry("Add Split View", .view, 2, [.init(.init([ctrl, shift], .equals), .pageThenApp)], .split(.addPane),
                 bar: listing("rectangle.split.2x1", "split"))
        case .removeSplitView:
            entry("Close this Split Pane", .view, 2, [.init(.init([ctrl, shift], .minus), .pageThenApp)], .split(.closePane))
        case .resetZoom: entry("Zoom to Actual Size", .view, 3, [.init(.init(cmd, .zero), .page)], .page(.zoom(.reset)))
        case .zoomIn:
            entry("Zoom In", .view, 3, [.init(.init([shift, cmd], .equals), .page), .init(.init(cmd, .equals), .page)],
                 .page(.zoom(.zoomIn)), repeats: true)
        case .zoomOut:
            entry("Zoom Out", .view, 3, [.init(.init(cmd, .minus), .page), .init(.init([shift, cmd], .minus), .page)],
                 .page(.zoom(.zoomOut)), repeats: true)
        case .developerTools:
            entry("Developer Tools", .view, 4, [.init(.init([opt, cmd], .i), .pageThenApp), .init(.init([], .f12), .pageThenApp)],
                 .page(.toggleDevTools), bar: listing("hammer", "inspect", "devtools"))
        case .fullscreen:
            entry("Enter/Exit Full Screen", .view, 4, [.init(.init([ctrl, cmd], .f), .pageThenApp)], .app(.toggleFullScreen))
        case .exit: entry("Exit", .view, 4, [.init(.init([], .escape), .pageThenApp)], .app(.exit))

        case .newSpace:
            entry("New Space…", .spaces, 0, [], .sidebar(.openDialog(.newSpace)), bar: listing("plus.square.on.square", "create space"))
        case .editSpaceTheme:
            entry("Edit Theme…", .spaces, 0, [], .sidebar(.openDialog(.editSpace(.current))), bar: listing("paintpalette", "theme", "color"))
        case .focusNextSpace:
            entry("Next Space", .spaces, 1, [.init(.init([opt, cmd], .rightArrow), .page)], .space(.step(.next)), repeats: true)
        case .focusPreviousSpace:
            entry("Previous Space", .spaces, 1, [.init(.init([opt, cmd], .leftArrow), .page)], .space(.step(.previous)), repeats: true)
        case .togglePinnedSection:
            entry("Expand/Collapse Pinned Section", .spaces, 1, [], .space(.togglePinnedSection(.current)))

        case .pinTab:
            entry("Pin/Unpin Tab", .tabs, 0, [.init(.init(cmd, .d), .pageThenApp)], .tab(.togglePin(.focused)), bar: listing("pin", "pin"))
        case .newFolder:
            entry("New Folder…", .tabs, 0, [.init(.init([shift, cmd], .n), .page)], .item(.newFolder), bar: listing("folder.badge.plus", "folder"))
        case .rename: entry("Rename Current Item", .tabs, 0, [], .item(.beginRename(.focused)), bar: listing("pencil", "rename"))
        case .selectNextTab:
            entry("Next Tab", .tabs, 1, [.init(.init([opt, cmd], .downArrow), .app)], .tab(.step(.next)), repeats: true)
        case .selectPreviousTab:
            entry("Previous Tab", .tabs, 1, [.init(.init([opt, cmd], .upArrow), .app)], .tab(.step(.previous)), repeats: true)
        case .cycleNextTab:
            entry("Tab Switcher (forward)", .tabs, 1, [.init(.init(ctrl, .tab), .app)], .tab(.cycleRecent(.next)), repeats: true)
        case .cyclePreviousTab:
            entry("Tab Switcher (backward)", .tabs, 1, [.init(.init([ctrl, shift], .tab), .app)], .tab(.cycleRecent(.previous)), repeats: true)
        case .clearExplore:
            entry("Clear Unpinned Tabs", .tabs, 2, [.init(.init([shift, cmd], .k), .page)], .tab(.clearToday), bar: listing("xmark.bin", "clear today"))
        case .resetTab: entry("Reset Tab to Original URL", .tabs, 2, [], .tab(.reset(.focused)), bar: listing("arrow.uturn.left", "reset"))

        case .goBack:
            entry("Go Back", .archive, 0, [.init(.init(cmd, .leftBracket), .app), .init(.init(cmd, .leftArrow), .page)],
                 .page(.back(.focused)), repeats: true)
        case .goForward:
            entry("Go Forward", .archive, 0, [.init(.init(cmd, .rightBracket), .app), .init(.init(cmd, .rightArrow), .page)],
                 .page(.forward(.focused)), repeats: true)
        case .viewArchive: entry("View Archive", .archive, 1, [], .archive(.open), bar: listing("archivebox", "archive", "history"))
        case .clearArchive: entry("Clear Archive", .archive, 1, [], .archive(.clear))

        case .minimize: entry("Minimize Window", .window, 0, [.init(.init(cmd, .m), .app)], .app(.minimize))
        }
    }

    /// The menu title with `{app}` filled in.
    public func title(appName: String) -> String { spec.title.replacingOccurrences(of: "{app}", with: appName) }
}

/// Chord -> action, built once from the table. Arc's nib has one real collision (Shift+Cmd+N on New Incognito
/// Window and New Folder, anatomy 2.4); v1 has no incognito action, and ActionsTests pins that no chord maps to two
/// actions until the remap layer gives conflicts a state (Arc: `KeyBinding.State.conflict`).
public struct KeyMap: Sendable {
    public let entries: [KeyChord: (action: ActionID, priority: KeyPriority)]

    public init(actions: [ActionID] = ActionID.allCases) {
        var entries: [KeyChord: (action: ActionID, priority: KeyPriority)] = [:]
        for action in actions {
            for binding in action.spec.bindings where entries[binding.chord] == nil {
                entries[binding.chord] = (action, binding.priority)
            }
        }
        self.entries = entries
    }

    public func lookup(_ chord: KeyChord) -> (action: ActionID, priority: KeyPriority)? { entries[chord] }
}
