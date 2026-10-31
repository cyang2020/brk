import BrkBase
import Foundation

// The one shortcut table: Arc's menu nib as data (anatomy-m 2.3, every row). Three consumers derive from it and
// from nothing else:
// - the AppKit main menu (BrkApp/MainMenu.swift): menus in `MenuName` order, items in `ActionID` order within a
//   menu, submenus from `submenu`, separators between groups, key equivalents from `KeyBindings.resolve` (so a
//   remapped or conflicting shortcut shows what routing really does), hidden rows hidden (their keys still work);
// - key routing while a page has focus (KeyRouting.swift, called from the CEF key handler): `KeyMap`, built from the
//   table plus `Doc.keyOverrides`;
// - the command bar's action rows (`CommandBarSnapshot.actions`): entries with `commandBar != nil` whose command is
//   not `.later`; F4's type-travel index ranks them by title and `CommandBarListing.triggers`.
//
// `ActionID` raw values are Arc's `arcKeyBindingID` where the row has one (so a remap file written for Arc names the
// same actions), else a name from the row's selector. `row` is the row number in anatomy-m 2.3; ActionsTests pins
// that every row of the table is an action, an alternate binding, a standard AppKit item or a row the user dropped.
// Rows whose feature is a later wave carry `.later(feature)`: they exist with Arc's key, priority and placement
// and are greyed out until the feature lands. Adding a case to `ActionID` without a `spec` fails to compile.

public enum ActionID: String, Hashable, Sendable, Codable, CaseIterable, CodingKeyRepresentable {
    // Arc menu (rows 2 to 14). Share Arc, Sign Out and Privacy Policy are dropped (no account, no referrals, no
    // Browser Company links); Services and Show All are AppKit items.
    case aboutArc, viewPreferences, setAsDefaultBrowser, importFromBrowser, checkForUpdates, hideArc, hideOthers, quitArc
    // File (16 to 39). Send to Dia is dropped (open question in wave2.md).
    case newTab, newWindow, newBlankWindow, newIncognitoWindow, showLittleArc, reopenLastClosedTab, addressBar
    case newBoost, editBoost, newLegacyBoost, boostGallery, newProfile, newNote, newNoteInSplitView, newEasel
    case closeWindow, archiveTab, share, capturePage, captureFullPage, capturePrettyScreenshot, savePageAs, printPage
    // Edit (45 to 58). Undo through Select All and the Spelling, Substitutions, Transformations, Speech and Font
    // submenus are AppKit first-responder items (MainMenu.standardEditItems); Chromium handles them in pages.
    case copyCurrentURL, copyCurrentURLMarkdown, copyCurrentURLAsQuote
    case find, findAndReplace, findNext, findPrevious, useSelectionForFind, jumpToSelection
    // View (88 to 122). Rows 107, 108, 110 and 115 are alternate keys of zoomIn, zoomOut and developerTools.
    case appearanceAutomatic, appearanceLight, appearanceDark
    case showSidebar, toggleToolbar, expandPinnedSection, collapsePinnedSection, focusSidebar
    case stopLoading, reloadPage, forceReloadPage, clearCookies, clearCache
    case addSplitView, removeSplitView, separateTabFromSplitView, maximizeSplitPane
    case resetZoom, zoomIn, zoomOut, cast
    case viewSource, developerTools, inspectElements, javaScriptConsole, networkInspector, allowJavaScriptFromAppleEvents, toggleDeveloperMode
    case fullscreen, exit
    // Spaces (124 to 130)
    case newSpace, editSpaceTheme, renameSpace, changeProfile, focusNextSpace, focusPreviousSpace, openSpaceManager
    // Tabs (133 to 155). Row 132 is a second New Tab… (same action); rows 150 to 152 are nib placeholders.
    case gptMessage, joinLiveMeeting, peekEmail, pinTab, openTabIn, newFolder, duplicate, rename, collapseAllFolders, expandAllFolders
    case selectNextTab, selectPreviousTab, cycleNextTab, cyclePreviousTab, cycleTabForward, cycleTabBackward, revealTabInSidebar
    case clearExplore, resetSpace, resetTab
    // Archive (157 to 163). Rows 158 and 160 are the arrow-key alternates of goBack and goForward.
    case goBack, goForward, viewHistory, viewArchive, clearArchive
    // Extensions (165, 166)
    case addExtension, manageExtensions
    // Window (168 to 174). Zoom and Bring All to Front are AppKit items.
    case minimize, viewLibrary, viewDownloads, viewEaselsAndNotes, viewMedia, viewBoosts
    // Help (177 to 189)
    case gettingStarted, keyboardShortcutsEDU, releaseNotes, contactTheTeam, visitHelpCenter, restoreData, exportArcNotes
    case recordTrace, cancelTrace, openTaskManager, revealArcData, copyArcInfo
}

/// Arc's `KeyBinding.Priority` (anatomy 1.14, 2.2), named for what happens:
/// - `app` (overrideWebView): taken in `OnPreKeyEvent`; the page never sees it.
/// - `pageThenApp` (promptAfterConsumedByWebView): the page gets it first; if the page consumed it, pressing it
///   again within Metrics.keys.pressTwiceWindow takes it for the app ("press twice to use Arc's shortcut").
/// - `page` (low, or unset in the nib): the page gets it first; the app acts only if the page did not consume it.
public enum KeyPriority: String, Hashable, Sendable, Codable, CaseIterable { case app, pageThenApp, page }

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

/// Menu bar position, left to right (Arc's order, anatomy-m 2.3).
public enum MenuName: String, Hashable, Sendable, Codable, CaseIterable {
    case app, file, edit, view, spaces, tabs, archive, extensions, window, help
}

/// Arc's submenus that hold actions (Edit > Find, View > Appearance, View > Developer, Help > Troubleshooting).
/// Titles are in MainMenu. The AppKit-only submenus (Spelling and Grammar, Substitutions, Transformations, Speech,
/// Format > Font, Services) are built there too.
public enum Submenu: String, Hashable, Sendable, Codable, CaseIterable { case find, appearance, developer, troubleshooting }

public struct CommandBarListing: Hashable, Sendable {
    /// Extra search words (Arc: `arcTypeTravelTriggers`). `{app}` is replaced with `Product.name`.
    public let triggers: [String]
    /// SF Symbol name (Arc: `arcTypeTravelIcon`).
    public let symbol: String
    /// The result's title where Arc gives one that differs from the menu's (Arc: `arcTypeTravelTitle`: View >
    /// Appearance > Dark is "Switch to Dark Mode" in the bar).
    public let title: String?
}

public struct ActionSpec: Hashable, Sendable {
    /// Menu title and command bar row text. `{app}` is replaced with `Product.name`.
    public let title: String
    public let menu: MenuName
    public let submenu: Submenu?
    /// Arc's separators: a separator falls between two neighbours of one menu (or submenu) whose groups differ. The
    /// numbers are the separator-delimited runs of Arc's nib (anatomy-m 2.1, `mainmenu-tree.txt`), counted per menu
    /// with the AppKit items MainMenu adds (Undo, Services, Zoom) in the same count.
    public let group: Int
    /// The first binding is the primary, remappable one (Arc's `arcKeyBindingID`); the rest are Arc's hidden
    /// alternates (own rows in the nib, own priority). All of them route while a page has focus.
    public let bindings: [KeyBinding]
    /// Argument-free; resolved against the dispatching window (`.focused`, `.current`). `.later(feature)` for a
    /// row whose feature is a later wave.
    public let command: Command
    /// Arc's type-travel attributes. Rows without one in Arc's nib that Arc still reaches from the bar (New Folder,
    /// Rename, Duplicate, Reset Tab through `TypeTravelCandidate`) carry ours; New Tab and Open Command Bar open the
    /// bar itself and the Tab Switcher commits on a Control release a bar choice never has, so those have none.
    public let commandBar: CommandBarListing?
    /// Auto-repeat dispatches again (stepping, cycling, zoom); toggles ignore repeats.
    public let repeats: Bool
    /// Arc: "hidden, key works while hidden". Not shown in the menu; the key equivalent still fires.
    public let hidden: Bool
    /// Arc: an alternate item that replaces the one above it while its extra modifier is held (Force Refresh).
    public let alternate: Bool
    /// The row in anatomy-m 2.3 this action comes from.
    public let row: Int

    /// A greyed-out row of a later wave.
    public var later: LaterFeature? {
        if case .later(let feature) = command { return feature }
        return nil
    }
}

private func entry(
    _ row: Int, _ title: String, _ menu: MenuName, _ group: Int, _ bindings: [KeyBinding], _ command: Command,
    in submenu: Submenu? = nil, bar: CommandBarListing? = nil, repeats: Bool = false, hidden: Bool = false, alternate: Bool = false
) -> ActionSpec {
    ActionSpec(title: title, menu: menu, submenu: submenu, group: group, bindings: bindings, command: command, commandBar: bar,
               repeats: repeats, hidden: hidden, alternate: alternate, row: row)
}

/// Arc's `arcTypeTravelIcon` and `arcTypeTravelTriggers` for the row, word for word.
private func listing(_ symbol: String, title: String? = nil, _ triggers: String...) -> CommandBarListing {
    CommandBarListing(triggers: triggers, symbol: symbol, title: title)
}

private let cmd = Modifiers.command, shift = Modifiers.shift, opt = Modifiers.option, ctrl = Modifiers.control

/// Arc's priority column: overrideWebView -> `.app`, promptAfterConsumedByWebView -> `.pageThenApp`, blank -> `.page`.
private func key(_ modifiers: Modifiers, _ key: Key, _ priority: KeyPriority) -> KeyBinding { KeyBinding(KeyChord(modifiers, key), priority) }

extension ActionID {
    public var spec: ActionSpec {
        switch self {
        // MARK: Arc menu (groups: About | Preferences… to Default Browser | Import, Updates | Services | Hide to Show All | Quit)
        case .aboutArc: entry(2, "About {app}", .app, 0, [], .app(.showAbout), bar: listing("book.closed"))
        case .viewPreferences:
            // Arc reaches the panes through `TypeTravelCandidate.openPreferencePane`; the row's own listing is ours.
            entry(3, "Preferences…", .app, 1, [key(cmd, .comma, .page)], .settings(.openPane(.general)), bar: listing("gearshape", "Settings"))
        case .setAsDefaultBrowser: entry(5, "Set as Default Browser", .app, 1, [], .app(.setAsDefaultBrowser), bar: listing("heart", "Default Browser"))
        case .importFromBrowser:
            entry(6, "Import from Another Browser…", .app, 2, [], .sidebarData(.importFile),
                  bar: listing("arrow.turn.right.down", "Import Bookmarks", "Import Settings", "Import Logins", "Import Passwords", "Transfer Bookmarks",
                               "Transfer Settings", "Transfer Logins", "Transfer Passwords", "Bookmarks"))
        case .checkForUpdates: entry(7, "Check for Updates…", .app, 2, [], .later(.updater), bar: listing("sparkles", "Download", "Update", "Check for Updates"))
        case .hideArc: entry(10, "Hide {app}", .app, 4, [key(cmd, .h, .app)], .app(.hide), bar: listing("macwindow", "Hide {app}"))
        case .hideOthers: entry(11, "Hide Other Windows", .app, 4, [key([opt, cmd], .h, .page)], .app(.hideOthers), bar: listing("macwindow", "Hide Others"))
        case .quitArc: entry(14, "Quit {app}", .app, 6, [key(cmd, .q, .app)], .app(.quit), bar: listing("hand.wave", "Quit App"))

        // MARK: File (groups: New Tab… to Restore | Open Command Bar | Boosts to New Easel | Close, Archive | Share… to Print)
        case .newTab: entry(16, "New Tab…", .file, 0, [key(cmd, .t, .app)], .commandBar(.open(.newTab)))
        case .newWindow:
            entry(17, "New Window", .file, 0, [key(cmd, .n, .app)], .window(.new), bar: listing("plus.rectangle", "Create Window", "Copy Window", "Duplicate Window"))
        case .newBlankWindow: entry(18, "Blank Window", .file, 0, [key([ctrl, cmd], .n, .page)], .later(.blankWindow), bar: listing("macwindow.on.rectangle", "Create Window"))
        case .newIncognitoWindow:
            entry(19, "New Incognito Window", .file, 0, [key([shift, cmd], .n, .app)], .window(.newIncognito),
                  bar: listing("macwindow.on.rectangle", "Create Incognito Window", "New Private Window", "Incognito"))
        case .showLittleArc:
            // Arc writes this row's triggers with commas, as one phrase; split here like every other row.
            entry(20, "New Little {app} Window", .file, 0, [key([opt, cmd], .n, .app)], .window(.newLittle(nil)),
                  bar: listing("macwindow.on.rectangle", "Quick Lookup", "Mini Window", "Floating Window"))
        case .reopenLastClosedTab:
            entry(21, "Restore Last Closed Tab", .file, 0, [key([shift, cmd], .t, .app)], .archive(.restoreLast),
                  bar: listing("arrow.uturn.backward", "Reopen Closed Tab"))
        case .addressBar: entry(22, "Open Command Bar", .file, 1, [key(cmd, .l, .app)], .commandBar(.open(.editCurrent)))
        case .newBoost:
            entry(23, "New Boost", .file, 2, [], .later(.boosts), bar: listing("paintbrush", "Boost", "New Boost", "Create boost", "extension",
                                                                               "Boost the Current Page", "Edit Boost"), hidden: true)
        case .editBoost:
            entry(24, "Edit Boost", .file, 2, [], .later(.boosts), bar: listing("paintbrush", "Boost", "New Boost", "Create boost", "extension",
                                                                                "Boost the Current Page", "Edit Boost"), hidden: true)
        case .newLegacyBoost:
            entry(25, "New Legacy Boost (Advanced)", .file, 2, [], .later(.boosts), bar: listing("burst", "Create legacy boost", "legacy boost"), hidden: true)
        case .boostGallery:
            entry(26, "Boost Gallery", .file, 2, [], .later(.boosts), bar: listing("paintbrush", "Boost Gallery", "Boosts Gallery", "Boost Store", "Boosts Store"),
                  hidden: true)
        case .newProfile: entry(27, "New Profile", .file, 2, [], .profile(.openDialog(.create)), bar: listing("person.fill", "Profile"))
        case .newNote:
            entry(28, "New Note", .file, 2, [key([ctrl, shift], .n, .pageThenApp)], .later(.notes), bar: listing("note.text", "Create Note", "Note", "Scratchpad"))
        case .newNoteInSplitView:
            entry(29, "New Note (in Split)", .file, 2, [key([ctrl, opt], .n, .pageThenApp)], .later(.notes),
                  bar: listing("note.text", "Create Note in Split View", "Note Split", "Scratchpad Split"), hidden: true)
        case .newEasel: entry(30, "New Easel", .file, 2, [key([ctrl, shift], .e, .page)], .later(.easels), bar: listing("scribble.variable", "Mood Board"))
        case .closeWindow: entry(31, "Close Window", .file, 3, [key([shift, cmd], .w, .app)], .window(.close), bar: listing("xmark.circle", "Exit Window"))
        case .archiveTab:
            entry(32, "Archive Tab", .file, 3, [key(cmd, .w, .app)], .tab(.close(.focused)), bar: listing("archivebox", "Exit Tab", "Unload", "Deselect", "Close"))
        case .share:
            // Arc titles the result "Share URL"; Brk's Share… exports to a file, so the menu title stays and "Export" is ours.
            entry(33, "Share…", .file, 4, [], .app(.export(.focusedTab)), bar: listing("square.and.arrow.up", "Share", "Export"))
        case .capturePage:
            entry(35, "Capture…", .file, 4, [key([shift, cmd], .two, .page)], .later(.captures), bar: listing("camera", "Capture", "Screenshot", "Snapshot", "Cut Out"))
        case .captureFullPage:
            entry(36, "Capture Full Page", .file, 4, [], .later(.captures),
                  bar: listing("newspaper", "Full Page Capture", "Capture Entire Page", "Screenshot Full Page", "Capture Full Page", "Screenshot"))
        case .capturePrettyScreenshot:
            entry(37, "Capture in Portrait Mode", .file, 4, [], .later(.captures),
                  bar: listing("camera.macro", "Screenshot in Portrait Mode", "Capture Portrait", "Portrait Mode", "Screenshot"))
        case .savePageAs: entry(38, "Save Page As", .file, 4, [key([shift, cmd], .s, .page)], .later(.savePage), bar: listing("square.and.arrow.down", "Save Page", "Save File"))
        case .printPage: entry(39, "Print", .file, 4, [key(cmd, .p, .pageThenApp)], .later(.print), bar: listing("printer", "Print Page"))

        // MARK: Edit (groups: Undo, Redo | Cut to Select All | the submenus, Find first)
        case .copyCurrentURL:
            entry(45, "Copy URL", .edit, 1, [key([shift, cmd], .c, .app)], .page(.copyURL(.plain)), bar: listing("doc.on.doc", "Copy URL", "Copy Link"))
        case .copyCurrentURLMarkdown:
            entry(46, "Copy URL as Markdown", .edit, 1, [key([opt, shift, cmd], .c, .app)], .page(.copyURL(.markdown)),
                  bar: listing("doc.on.doc", "Copy Link as Markdown", "Copy Markdown"))
        case .copyCurrentURLAsQuote:
            entry(47, "Copy URL as Quote", .edit, 1, [key([ctrl, shift, cmd], .c, .app)], .page(.copyURL(.quote)),
                  bar: listing("quote.bubble", "Copy URL as Quote", "Copy Quote", "Copy Link to Highlight"))
        case .find: entry(53, "Find…", .edit, 0, [key(cmd, .f, .page)], .later(.findInPage), in: .find, bar: listing("magnifyingglass", "Find in Page"))
        case .findAndReplace: entry(54, "Find and Replace", .edit, 0, [key([opt, cmd], .f, .page)], .later(.findInPage), in: .find, bar: listing("magnifyingglass"))
        case .findNext: entry(55, "Find Next", .edit, 0, [key(cmd, .g, .page)], .later(.findInPage), in: .find, bar: listing("arrow.right", "Next"))
        case .findPrevious: entry(56, "Find Previous", .edit, 0, [key([shift, cmd], .g, .page)], .later(.findInPage), in: .find, bar: listing("arrow.left", "Previous"))
        case .useSelectionForFind:
            entry(57, "Use Selection to Find", .edit, 0, [], .later(.findInPage), in: .find, bar: listing("magnifyingglass", "Find Selection", "Find Selected"))
        case .jumpToSelection:
            entry(58, "Jump to Selection", .edit, 0, [key(cmd, .j, .page)], .later(.findInPage), in: .find,
                  bar: listing("arrow.turn.right.down", "Jump to Selected", "Selection"))

        // MARK: View (groups: Appearance | Sidebar | Loading | Split | Zoom | Cast | Developer | Full Screen, Exit)
        case .appearanceAutomatic:
            entry(88, "Automatic", .view, 0, [], .settings(.general(.webAppearance(.automatic))), in: .appearance,
                  bar: listing("sparkles", title: "Switch to Automatic Appearance", "Switch to Automatic Appearance", "Switch Automatic Mode", "Automatic Mode"))
        case .appearanceLight:
            entry(89, "Light", .view, 0, [], .settings(.general(.webAppearance(.light))), in: .appearance,
                  bar: listing("sun.max", title: "Switch to Light Mode", "Switch to Light Mode", "Switch Light Mode", "Light Mode"))
        case .appearanceDark:
            entry(90, "Dark", .view, 0, [], .settings(.general(.webAppearance(.dark))), in: .appearance,
                  bar: listing("moon.stars.fill", title: "Switch to Dark Mode", "Switch to Dark Mode", "Switch Dark Mode", "Dark Mode", "Night Mode"))
        case .showSidebar:
            entry(91, "Show/Hide Sidebar", .view, 1, [key(cmd, .s, .pageThenApp)], .sidebar(.toggle), bar: listing("sidebar.left", "Toggle Sidebar"))
        case .toggleToolbar:
            entry(92, "Show/Hide Toolbar", .view, 1, [key([shift, cmd], .d, .pageThenApp)], .later(.toolbar),
                  bar: listing("rectangle.topthird.inset.filled", "Toggle Hide Show Toolbar"), hidden: true)
        case .expandPinnedSection:
            entry(93, "Expand Pinned Section", .view, 1, [], .space(.togglePinnedSection(.current)),
                  bar: listing("chevron.down", "Expand Pinned Tabs", "Show Pinned Tabs", "Pinned"), hidden: true)
        case .collapsePinnedSection:
            entry(94, "Collapse Pinned Section", .view, 1, [], .space(.togglePinnedSection(.current)),
                  bar: listing("chevron.right", "Collapse Pinned Tabs", "Hide Pinned Tabs", "Pinned"), hidden: true)
        case .focusSidebar:
            entry(95, "Reveal Current Tab", .view, 1, [key(ctrl, .space, .pageThenApp)], .later(.sidebarKeyboardFocus), bar: listing("sidebar.left"), hidden: true)
        case .stopLoading:
            // Arc gives Stop Loading no type-travel attributes; the icon and word are ours.
            entry(96, "Stop Loading", .view, 2, [key(cmd, .period, .page)], .page(.stop(.focused)), bar: listing("xmark", "Stop"))
        case .reloadPage:
            entry(97, "Refresh the Page", .view, 2, [key(cmd, .r, .page)], .page(.reload(.focused, ignoringCache: false)),
                  bar: listing("arrow.clockwise", "Reload Page"))
        case .forceReloadPage:
            entry(98, "Force Refresh the Page", .view, 2, [key([shift, cmd], .r, .page)], .page(.reload(.focused, ignoringCache: true)),
                  bar: listing("arrow.clockwise", "Force Reload", "Force Refresh"), alternate: true)
        case .clearCookies: entry(99, "Clear Cookies and Refresh", .view, 2, [], .later(.siteData), bar: listing("trash", "Clear Cookies"))
        case .clearCache: entry(100, "Clear Cache and Refresh", .view, 2, [], .later(.siteData), bar: listing("trash", "Clear Cache"))
        case .addSplitView:
            entry(101, "Add Split View", .view, 3, [key([ctrl, shift], .equals, .pageThenApp)], .split(.addPane),
                  bar: listing("square.split.2x1", "Add Split View", "Split View", "Create Split View Pane", "New Split View", "Split"))
        case .removeSplitView:
            entry(102, "Close this Split Pane", .view, 3, [key([ctrl, shift], .minus, .pageThenApp)], .split(.closePane),
                  bar: listing("xmark.square", "Close Split View"))
        case .separateTabFromSplitView:
            entry(103, "Separate Page from Split View", .view, 3, [], .later(.splitTools), bar: listing("scissors", "Separate from split view", "separate tab"))
        case .maximizeSplitPane:
            entry(104, "Expand Current Split", .view, 3, [], .later(.splitTools),
                  bar: listing("arrow.up.left.and.arrow.down.right", "Expand", "Expand Split View", "Maximize"))
        case .resetZoom: entry(105, "Zoom to Actual Size", .view, 4, [key(cmd, .zero, .page)], .page(.zoom(.reset)), bar: listing("magnifyingglass", "Reset Zoom"))
        case .zoomIn:
            entry(106, "Zoom In", .view, 4, [key([shift, cmd], .equals, .page), key(cmd, .equals, .page)], .page(.zoom(.zoomIn)),
                  bar: listing("plus.magnifyingglass"), repeats: true)
        case .zoomOut:
            entry(109, "Zoom Out", .view, 4, [key(cmd, .minus, .page), key([shift, cmd], .minus, .page)], .page(.zoom(.zoomOut)),
                  bar: listing("minus.magnifyingglass"), repeats: true)
        case .cast: entry(111, "Cast", .view, 5, [], .later(.cast), bar: listing("rectangle.portrait.and.arrow.right.fill"))
        case .viewSource:
            entry(113, "View Source", .view, 0, [key([opt, cmd], .u, .pageThenApp)], .later(.developerMenu), in: .developer, bar: listing("curlybraces", "View Source"))
        case .developerTools:
            entry(114, "Developer Tools", .view, 0, [key([opt, cmd], .i, .pageThenApp), key([], .f12, .pageThenApp)],
                  .page(.toggleDevTools), in: .developer, bar: listing("hammer.fill", "Developer Tools", "Debug Tools", "Devtools"))
        case .inspectElements:
            entry(116, "Inspect Elements", .view, 0, [key([opt, cmd], .c, .pageThenApp)], .later(.developerMenu), in: .developer,
                  bar: listing("scope", "Inspect Element"))
        case .javaScriptConsole:
            entry(117, "JavaScript Console", .view, 0, [key([opt, cmd], .j, .page)], .later(.developerMenu), in: .developer,
                  bar: listing("terminal", "Toggle console", "Console", "Javascript Console", "JS console"))
        case .networkInspector:
            entry(118, "Network Inspector", .view, 0, [], .later(.developerMenu), in: .developer, bar: listing("wifi", "Network Inspector"))
        case .allowJavaScriptFromAppleEvents: entry(119, "Allow JavaScript from Apple Events", .view, 0, [], .later(.developerMenu), in: .developer)
        case .toggleDeveloperMode:
            entry(120, "Toggle Developer Mode", .view, 0, [key(ctrl, .d, .pageThenApp)], .later(.developerMenu), in: .developer,
                  bar: listing("hammer.fill", "Developer Mode", "Enable Developer Mode", "Disable Developer Mode"))
        case .fullscreen:
            entry(121, "Enter/Exit Full Screen", .view, 7, [key([ctrl, cmd], .f, .pageThenApp)], .app(.toggleFullScreen),
                  bar: listing("arrow.up.left.and.arrow.down.right", "Enter Full Screen", "Exit Full Screen", "Full Screen", "Toggle Full Screen"))
        case .exit: entry(122, "Exit", .view, 7, [key([], .escape, .pageThenApp)], .app(.exit), bar: listing("escape", "Exit", "Exit Modal", "Exit Full Screen"))

        // MARK: Spaces (groups: New Space… to Change Profile | Next, Previous | Manage Spaces…)
        case .newSpace: entry(124, "New Space…", .spaces, 0, [], .sidebar(.openDialog(.newSpace)), bar: listing("plus.rectangle.portrait", "Create New Space"))
        case .editSpaceTheme:
            entry(125, "Edit Theme…", .spaces, 0, [], .sidebar(.openDialog(.editSpace(.current))),
                  bar: listing("paintbrush.pointed.fill", "Theme", "Edit Theme", "Edit Space Theme"))
        case .renameSpace: entry(126, "Rename Space", .spaces, 0, [], .sidebar(.openDialog(.editSpace(.current))), bar: listing("character.cursor.ibeam"))
        case .changeProfile: entry(127, "Change Profile", .spaces, 0, [], .profile(.openDialog(.change(.current))), bar: listing("person.fill"))
        case .focusNextSpace:
            entry(128, "Next Space", .spaces, 1, [key([opt, cmd], .rightArrow, .page)], .space(.step(.next)), bar: listing("arrow.right.to.line", "Focus Next Space"),
                  repeats: true)
        case .focusPreviousSpace:
            entry(129, "Previous Space", .spaces, 1, [key([opt, cmd], .leftArrow, .page)], .space(.step(.previous)),
                  bar: listing("arrow.left.to.line", "Focus Previous Space"), repeats: true)
        case .openSpaceManager:
            entry(130, "Manage Spaces…", .spaces, 2, [], .later(.spaceManager),
                  bar: listing("rectangle.portrait.on.rectangle.portrait", "Space Management", "Organize", "Toggle Space Manager", "View Spaces"))

        // MARK: Tabs (groups: New Tab… to Expand All Folders | Next Tab to Reveal Tab | Clear to Reset Tab; Arc's
        // placeholder submenu between the last two is a separator item)
        case .gptMessage: entry(133, "New ChatGPT Message…", .tabs, 0, [key([opt, cmd], .g, .page)], .later(.aiCommandBar), hidden: true)
        case .joinLiveMeeting: entry(134, "Join Meeting", .tabs, 0, [key([ctrl, cmd], .j, .pageThenApp)], .later(.joinMeeting), hidden: true)
        case .peekEmail: entry(135, "Peek Email…", .tabs, 0, [key([shift, cmd], .e, .pageThenApp)], .later(.peekEmail), hidden: true)
        case .pinTab: entry(136, "Pin/Unpin Tab", .tabs, 0, [key(cmd, .d, .pageThenApp)], .tab(.togglePin(.focused)), bar: listing("pin", "save"))
        case .openTabIn:
            entry(137, "Open Little {app} or Peek in…", .tabs, 0, [key(cmd, .o, .pageThenApp)], .window(.openIn(.current)),
                  bar: listing("arrow.up.forward.square", "Open in"))
        case .newFolder:
            // Arc: `TypeTravelCandidate.createNewFolder` ("Create a new folder").
            entry(138, "New Folder…", .tabs, 0, [key([shift, cmd], .n, .page)], .item(.newFolder), bar: listing("folder.badge.plus", "Create a new folder", "Folder"))
        case .duplicate:
            entry(139, "Duplicate", .tabs, 0, [], .later(.duplicate), bar: listing("plus.square.on.square", "Duplicate Current Tab"), hidden: true)
        case .rename:
            // Arc: `TypeTravelCandidate.renameCurrentTab` ("Rename Current Tab…").
            entry(140, "Rename Current Item", .tabs, 0, [], .item(.beginRename(.focused)), bar: listing("pencil", "Rename Current Tab"), hidden: true)
        case .collapseAllFolders: entry(141, "Collapse All Folders", .tabs, 0, [], .later(.folderTools), bar: listing("folder"), hidden: true)
        case .expandAllFolders: entry(142, "Expand All Folders", .tabs, 0, [], .later(.folderTools), bar: listing("folder"), hidden: true)
        case .selectNextTab:
            entry(143, "Next Tab", .tabs, 1, [key([opt, cmd], .downArrow, .app)], .tab(.step(.next)), bar: listing("arrow.right"), repeats: true)
        case .selectPreviousTab:
            entry(144, "Previous Tab", .tabs, 1, [key([opt, cmd], .upArrow, .app)], .tab(.step(.previous)), bar: listing("arrow.left"), repeats: true)
        case .cycleNextTab:
            entry(145, "Tab Switcher (forward)", .tabs, 1, [key(ctrl, .tab, .app)], .tab(.cycleRecent(.next)), repeats: true, hidden: true)
        case .cyclePreviousTab:
            entry(146, "Tab Switcher (backward)", .tabs, 1, [key([ctrl, shift], .tab, .app)], .tab(.cycleRecent(.previous)), repeats: true, hidden: true)
        case .cycleTabForward: entry(147, "Cycle Tab Forward", .tabs, 1, [key([ctrl, cmd], .rightArrow, .app)], .later(.linearTabCycling), hidden: true)
        case .cycleTabBackward: entry(148, "Cycle Tab Backward", .tabs, 1, [key([ctrl, cmd], .leftArrow, .app)], .later(.linearTabCycling), hidden: true)
        case .revealTabInSidebar:
            entry(149, "Reveal Tab in Sidebar", .tabs, 1, [], .later(.sidebarKeyboardFocus),
                  bar: listing("arrow.left.circle", "Show Tab in Sidebar", "Reveal in Sidebar", "Go to Current Tab"))
        case .clearExplore:
            entry(153, "Clear Unpinned Tabs", .tabs, 2, [key([shift, cmd], .k, .page)], .tab(.clearToday),
                  bar: listing("bubbles.and.sparkles", "Close Unpinned Tabs", "Clear Tabs", "Clear Today"))
        case .resetSpace: entry(154, "Reset all tabs in this Space", .tabs, 2, [], .later(.resetSpace), bar: listing("arrow.backward.to.line"))
        case .resetTab:
            // Arc has the trigger and no icon for this row.
            entry(155, "Reset Tab to Original URL", .tabs, 2, [], .tab(.reset(.focused)), bar: listing("arrow.uturn.left", "Reset Tab"), hidden: true)

        // MARK: Archive (groups: Back, Forward | History, Archive, Clear)
        case .goBack:
            entry(157, "Go Back", .archive, 0, [key(cmd, .leftBracket, .app), key(cmd, .leftArrow, .page)], .page(.back(.focused)),
                  bar: listing("arrow.backward", "Go Back", "Back", "Navigate Back"), repeats: true)
        case .goForward:
            entry(159, "Go Forward", .archive, 0, [key(cmd, .rightBracket, .app), key(cmd, .rightArrow, .page)], .page(.forward(.focused)),
                  bar: listing("arrow.right", "Go Forward", "Forward", "Navigate Forward"), repeats: true)
        case .viewHistory: entry(161, "View History", .archive, 1, [key(cmd, .y, .page)], .library(.open(.history)), bar: listing("book", "Show History", "History"))
        case .viewArchive: entry(162, "View Archive", .archive, 1, [], .library(.open(.archive)), bar: listing("archivebox", "Archive"))
        case .clearArchive: entry(163, "Clear Archive", .archive, 1, [], .archive(.clear), bar: listing("archivebox", "Clear Archive", "Delete Archive"))

        // MARK: Extensions
        case .addExtension:
            entry(165, "Add Extension…", .extensions, 0, [], .later(.extensions),
                  bar: listing("plus.circle", "Install Extensions", "Extension Store", "Plugins", "Chrome Extensions", "Chrome Store"))
        case .manageExtensions:
            entry(166, "Manage Extensions…", .extensions, 0, [], .later(.extensions),
                  bar: listing("puzzlepiece", "Manage Extensions", "Extensions", "Plugins", "Chrome Extensions"))

        // MARK: Window (groups: Minimize, Zoom | the Library pages | Bring All to Front)
        case .minimize: entry(168, "Minimize Window", .window, 0, [key(cmd, .m, .app)], .app(.minimize), bar: listing("arrow.down.right.and.arrow.up.left"))
        case .viewLibrary: entry(170, "View Library", .window, 1, [key([shift, cmd], .l, .page)], .library(.open(nil)), bar: listing("archivebox", "Library"))
        case .viewDownloads:
            // Chrome runtime can consume this accelerator before OnKeyEvent. Brk's Library owns the default;
            // users can still choose page priority in Settings.
            entry(171, "View Downloads", .window, 1, [key([shift, cmd], .j, .app)], .library(.open(.downloads)), bar: listing("arrow.down.circle", "Downloads"))
        case .viewEaselsAndNotes:
            entry(172, "View Easels & Notes", .window, 1, [], .library(.open(.easelsAndNotes)), bar: listing("scribble.variable", "Easels", "Notes"))
        case .viewMedia:
            entry(173, "View Media", .window, 1, [], .library(.open(.media)), bar: listing("photo.on.rectangle.angled", "Screenshots", "Captures", "Videos", "Media"))
        case .viewBoosts: entry(174, "View Boosts", .window, 1, [], .library(.open(.boosts)), bar: listing("paintbrush", "Boosts"))

        // MARK: Help (groups: Getting Started to Export Notes | Troubleshooting; inside it: Trace, Task Manager | Data, Info)
        case .gettingStarted: entry(177, "Getting Started", .help, 0, [], .sidebarData(.welcome), bar: listing("safari", "Welcome to {app}"))
        case .keyboardShortcutsEDU:
            entry(178, "Essential Keyboard Shortcuts", .help, 0, [], .settings(.openPane(.shortcuts)),
                  bar: listing("keyboard", "Essential Keyboard Shortcuts", "keyboard", "shortcuts"))
        case .releaseNotes:
            entry(179, "Release Notes", .help, 0, [], .later(.help), bar: listing("clock", "Changelog", "Whats new", "What's new", "{app} updates"))
        case .contactTheTeam:
            entry(180, "Contact the Team", .help, 0, [], .later(.help),
                  bar: listing("ellipsis.message", "Idea", "Feedback", "Request", "Feature Request", "Send Feedback", "Report Bug", "Bug", "Question"))
        case .visitHelpCenter:
            entry(181, "Visit Help Center", .help, 0, [], .later(.help), bar: listing("heart.circle", "Question", "Inquiry", "Help Center", "Help", "Resources"))
        case .restoreData: entry(182, "Restore Data", .help, 0, [], .later(.restoreData), bar: listing("opticaldiscdrive", "Restore", "Backup"))
        case .exportArcNotes:
            entry(183, "Export {app} Notes", .help, 0, [], .later(.notes), bar: listing("arrow.down.doc", "Export Notes", "Backup Notes", "Download Notes"))
        case .recordTrace: entry(185, "Record Trace", .help, 0, [], .later(.troubleshooting), in: .troubleshooting, bar: listing("flag"))
        case .cancelTrace:
            entry(186, "Cancel Trace", .help, 0, [], .later(.troubleshooting), in: .troubleshooting, bar: listing("exclamationmark.triangle"), hidden: true)
        case .openTaskManager:
            entry(187, "Open Task Manager", .help, 0, [], .later(.troubleshooting), in: .troubleshooting,
                  bar: listing("exclamationmark.triangle", "Task", "Manager", "Task Manager", "Cpu", "Memory: RAM"))
        case .revealArcData: entry(188, "Reveal {app} Data", .help, 1, [], .app(.revealDataDirectory), in: .troubleshooting, bar: listing("list.clipboard"))
        case .copyArcInfo: entry(189, "Copy {app} Info", .help, 1, [], .later(.troubleshooting), in: .troubleshooting, bar: listing("list.clipboard"))
        }
    }

    /// The menu title with `{app}` filled in.
    public func title(appName: String) -> String { spec.title.replacingOccurrences(of: "{app}", with: appName) }

    /// The command bar's row title: Arc's type-travel title where it has one, else the menu title.
    public func barTitle(appName: String) -> String {
        (spec.commandBar?.title ?? spec.title).replacingOccurrences(of: "{app}", with: appName)
    }

    /// The command bar's search words besides the title.
    public func barTriggers(appName: String) -> [String] {
        (spec.commandBar?.triggers ?? []).map { $0.replacingOccurrences(of: "{app}", with: appName) }
    }

    /// Rows of anatomy-m 2.3 that are not actions, so ActionsTests can prove the table covers the whole menu:
    /// menu titles and submenu headers, AppKit first-responder items (MainMenu.standardEditItems and the Window and
    /// app standards), alternate keys of an action above, nib placeholders and the label row, and rows the user
    /// dropped (Share Arc, Privacy Policy, Sign Out, Send to Dia).
    public static let menuTitleRows: Set<Int> = [1, 15, 40, 52, 59, 65, 73, 77, 80, 81, 85, 86, 112, 123, 131, 156, 164, 167, 176, 184]
    public static let standardItemRows: Set<Int> = [8, 12, 41, 42, 43, 44, 48, 49, 50, 51, 60, 61, 62, 63, 64, 66, 67, 68, 69, 70, 71, 72,
                                                   74, 75, 76, 78, 79, 82, 83, 84, 169, 175]
    public static let alternateKeyRows: Set<Int> = [107, 108, 110, 115, 132, 158, 160]
    public static let placeholderRows: Set<Int> = [87, 150, 151, 152]
    public static let droppedRows: Set<Int> = [4, 9, 13, 34]
}

// MARK: - Key bindings: table plus user overrides

/// Arc: `KeyBinding.State`. A conflict is a first-class state: neither action routes until the user resolves it
/// (the Shortcuts pane shows "Remove Conflicting Shortcut"). Arc's own nib has one collision, Shift+Cmd+N on New
/// Incognito Window and New Folder (anatomy-m 2.4); Brk resolves that one by default (`KeyBindings.defaultOwners`).
public enum KeyBindingState: Hashable, Sendable, Codable {
    case valid(KeyChord)
    case conflict(KeyChord, with: [ActionID])
    case unset
}

/// Arc: `KeyBinding.Source`.
public enum KeyBindingSource: String, Hashable, Sendable, Codable { case `default`, userDefined }

/// One action's primary shortcut after overrides. The table's alternates (Cmd+Left for Go Back) are not remappable
/// and ride along in `KeyMap` unchanged.
public struct ResolvedBinding: Hashable, Sendable {
    public let action: ActionID
    public let state: KeyBindingState
    public let source: KeyBindingSource
    public let priority: KeyPriority
}

/// Owner: F4. Builds the resolved primary bindings from the table and `Doc.keyOverrides`: an override's chord (or
/// `unset`) replaces the table's first binding, its priority replaces the table's; two actions on one chord are
/// both `.conflict` naming each other. Pure, O(actions).
public enum KeyBindings {
    /// Brk's answer to the nib's one collision (wave 2 decision, a guess: Arc ships the conflict and remapping fixes
    /// it): Shift+Cmd+N opens a New Incognito Window, as in every other browser. New Folder's default is unset while
    /// the owner holds the chord, and comes back if the user moves Incognito elsewhere. A user override onto an owned
    /// chord is an ordinary conflict.
    public static let defaultOwners: [KeyChord: ActionID] = [KeyChord([.shift, .command], .n): .newIncognitoWindow]

    public static func resolve(overrides: [ActionID: KeyOverride], actions: [ActionID] = ActionID.allCases) -> [ActionID: ResolvedBinding] {
        var chords: [ActionID: KeyChord] = [:]
        for action in actions {
            if let override = overrides[action] {
                if let chord = override.chord { chords[action] = chord }
            } else if let chord = action.spec.bindings.first?.chord {
                chords[action] = chord
            }
        }
        for action in actions where overrides[action] == nil {
            if let chord = chords[action], let owner = defaultOwners[chord], owner != action, chords[owner] == chord { chords[action] = nil }
        }
        var byChord: [KeyChord: [ActionID]] = [:]
        for action in actions { if let chord = chords[action] { byChord[chord, default: []].append(action) } }
        var out: [ActionID: ResolvedBinding] = [:]
        for action in actions {
            let state: KeyBindingState
            if let chord = chords[action] {
                let others = (byChord[chord] ?? []).filter { $0 != action }
                state = others.isEmpty ? .valid(chord) : .conflict(chord, with: others)
            } else {
                state = .unset
            }
            let override = overrides[action]
            out[action] = ResolvedBinding(action: action, state: state, source: override == nil ? .default : .userDefined,
                                          priority: override?.priority ?? action.spec.bindings.first?.priority ?? .page)
        }
        return out
    }

    /// Chords macOS keeps for itself with its default settings, so an app shortcut on one never fires (Cmd+Tab,
    /// Spotlight, Force Quit, Lock Screen, Mission Control and the Spaces arrows). Arc does not refuse them; its
    /// Shortcuts pane notes "System shortcuts may take priority over this shortcut", and so does ours.
    public static func isSystemShortcut(_ chord: KeyChord) -> Bool { systemShortcuts.contains(chord) }

    private static let systemShortcuts: Set<KeyChord> = [
        KeyChord(.command, .tab), KeyChord([.shift, .command], .tab), KeyChord(.command, .space), KeyChord([.option, .command], .space),
        KeyChord([.option, .command], .escape), KeyChord([.control, .command], .q), KeyChord(.control, .upArrow), KeyChord(.control, .downArrow),
        KeyChord(.control, .leftArrow), KeyChord(.control, .rightArrow),
    ]
}

extension KeyChord {
    /// The chord as macOS menus and Arc's copy write it: ⌃⌥⇧⌘ in that order, then the key ("⌃⇧=", "⌘T"). Shift+Cmd+=
    /// is the plus key, written "⌘+" as Arc's Zoom In row has it.
    public var glyphs: String {
        if key == .equals, modifiers == [.shift, .command] { return "⌘+" }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let glyph: String = switch key {
        case .tab: "⇥"
        case .space: "Space"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .f12: "F12"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .downArrow: "↓"
        case .upArrow: "↑"
        default: key.menuKeyEquivalent.uppercased()
        }
        return text + glyph
    }
}

/// Chord -> action, for routing. Built from `KeyBindings.resolve` (valid primaries, overrides applied) plus the
/// table's alternate bindings. A chord in conflict routes to no one.
public struct KeyMap: Sendable {
    public let entries: [KeyChord: (action: ActionID, priority: KeyPriority)]

    public init(actions: [ActionID] = ActionID.allCases, overrides: [ActionID: KeyOverride] = [:]) {
        var entries: [KeyChord: (action: ActionID, priority: KeyPriority)] = [:]
        for (action, binding) in KeyBindings.resolve(overrides: overrides, actions: actions) {
            if case .valid(let chord) = binding.state { entries[chord] = (action, binding.priority) }
        }
        for action in actions {
            for binding in action.spec.bindings.dropFirst() where entries[binding.chord] == nil {
                entries[binding.chord] = (action, binding.priority)
            }
        }
        self.entries = entries
    }

    public func lookup(_ chord: KeyChord) -> (action: ActionID, priority: KeyPriority)? { entries[chord] }
}
