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
// Overlay rule, enforced once in `reduce` (`Command.keepsCommandBar` / `keepsLibrary` / `keepsPeek`): every command
// first closes an open command bar except `.commandBar` itself and the sidebar's peek and resize (pointer motion
// at the edge must not dismiss what the user is typing); every command closes an open Library page except
// `.library`, `.archive`, `.settings`, `.sidebar(.peek)` and `.sidebar(.resize)`; every command closes an open Peek
// except `.peek`, `.page` (browsing acts on the peeked page), `.settings` and the sidebar's peek and resize.
// Picking an action or a tab in the command bar is therefore just dispatching that action's command.
// OverlayPolicyTests pins the table against the behavioral inventory.

public enum Input: Sendable, Equatable {
    case user(WindowID, Command)
    /// A key-down from one delivery path for a page or native view in this window (KeyRouting.swift). If routing
    /// decides it is an app shortcut, the action's command runs in the same transition and `keyHandled` is true.
    case key(WindowID, KeyInput)
    case system(SystemEvent)
}

public enum Command: Hashable, Sendable, Codable {
    case assist(AIIntent)
    case find(FindIntent)
    case sidebarData(SidebarDataCommand)
    case commandBar(CommandBarCommand)
    case archive(ArchiveCommand)
    case tab(TabCommand)
    case tabTools(TabToolsCommand)
    case capture(CaptureCommand)
    case page(PageCommand)
    case item(ItemCommand)
    case space(SpaceCommand)
    case split(SplitCommand)
    case sidebar(SidebarCommand)
    case app(AppCommand)
    case settings(SettingsCommand)
    /// The Library (downloads, history, archive, media, easels and notes, boosts, spaces). F5.
    case library(LibraryCommand)
    case boost(BoostCommand)
    /// Easels: the whiteboard rows and their boards (Easels.swift).
    case easel(EaselCommand)
    /// Windows: new standard, incognito and Little Arc windows, closing, "Open in <space>". F3.
    case window(WindowCommand)
    /// Peek: a link previewed in a card over the content. F3.
    case peek(PeekCommand)
    /// Profiles: create, rename, delete, assign to a space, the dialogs. F2.
    case site(SiteCommand)
    case profile(ProfileCommand)
    /// A menu row whose feature is a later wave: the reducer ignores it, `enabledActions` greys it out and the
    /// command bar does not list it. Every Arc menu row exists in `ActionID` with its key, so remapping, the
    /// menu and the command bar index are complete before the features are.
    case later(LaterFeature)
}

/// Features behind the greyed-out menu rows. One case per feature, not per row, so a wave that ships a feature
/// replaces every `.later(x)` in the table with real commands and deletes the case.
public enum LaterFeature: String, Hashable, Sendable, Codable, CaseIterable {
    case importer, blankWindow, boosts, notes, captures, savePage, print, toolbar
    case sidebarKeyboardFocus, siteData, cast, spaceManager, aiCommandBar, joinMeeting
    case peekEmail, duplicate, folderTools, linearTabCycling, resetSpace, extensions, onboarding
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
    case calculate(String)
    case queryChangedForSite(SearchEngineID, String)
    case open(CommandBarMode)
    /// Typed text or a history URL; resolved by `resolveTypedInput` with the profile's engine and applied per the
    /// open bar's target.
    case submit(String)
    /// Site search (Tab or Space on a known engine's name): `query` searched with `engine`, applied like `submit`.
    case submitSearch(engine: SearchEngineID, query: String)
    /// The typed query changed (the view keeps the text; this asks for search suggestions when the profile allows
    /// them: `Effect.fetchSuggestions`, answered by `SystemEvent.suggestions`). F4.
    case queryChanged(String)
    /// Esc in the bar.
    case dismiss
}

public enum ArchiveCommand: Hashable, Sendable, Codable {
    case restore(ArchiveID)
    /// Cmd+Shift+T: newest manual or clear entry first, then auto.
    case restoreLast
    /// Present the same confirmation used by the Archive page. No records are deleted by this intent.
    case requestClear
    case clear
}

public enum TabCommand: Hashable, Sendable, Codable {
    /// Sidebar click, favorite click, command bar "switch to tab". Switches space when needed.
    case focus(ItemID)
    /// Cmd+Opt+Down/Up: next or previous stop in sidebar order, no wrap; a split is one stop.
    case step(Step)
    /// Ctrl+Tab / Ctrl+Shift+Tab: move the switcher's selection along the frozen recent order. The window switches
    /// to the selection only when the walk commits (Control released, or any other command); Esc cancels it.
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
    /// The command bar's New document row: a new tab in the current space at the profile's "New documents" app
    /// (`ProfileSettings.documentApp`); nothing without one.
    case newDocument
}

/// Browsing actions on a tab's page. Each resolves the target and becomes `Effect.page`; an unloaded target is a no-op.
public enum PageCommand: Hashable, Sendable, Codable {
    case back(ItemRef)
    case forward(ItemRef)
    case reload(ItemRef, ignoringCache: Bool)
    case stop(ItemRef)
    case zoom(ZoomStep)
    case toggleDevTools
    case cast
    case pictureInPicture(PictureInPictureIntent)
    case media(ItemRef, MediaPlayerID, MediaOperation)
    /// A mini player's transport buttons: the tab as a whole, not one player. Muted, they do nothing (Arc, Q18).
    case mediaSession(ItemRef, MediaSessionOperation)
    /// A mini player's volume slider, 0 to 1.
    case mediaVolume(ItemRef, Double)
    /// A mini player's ×: the card goes, the sound goes on.
    case closeMiniPlayer(ItemID)
    case output(OutputIntent)
    case cancelOutput
    case developer(DeveloperOperation)
    /// Cmd+Shift+C (plain), Opt+Shift+Cmd+C (Markdown), Ctrl+Shift+Cmd+C (quote: Arc rows 45 to 47).
    case copyURL(CopyURLFormat)
    /// The URL pill's Share Quote (text highlighted, Shared Quotes on): the link to the highlight, "Copied Shared URL".
    case shareQuote
    /// AppleScript's `set URL of tab`: the tab's page goes to `url` in place (an address the bar could open).
    case navigate(ItemRef, URL)
}

public enum CopyURLFormat: String, Hashable, Sendable, Codable {
    case plain
    /// `[title](url)`.
    case markdown
    /// `> title` then the url (Arc's "Copy URL as Quote" is disabled in the nib; ours copies the same shape).
    case quote
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
    /// Dropped on the Space name strip (Arc, Q13-g/h): the first item of the current space's Pinned; a tab shows
    /// "Double-click to rename" under its title.
    case dropOnSpaceHeader(ItemID)
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
    case create(title: String, icon: SpaceIcon, theme: SpaceTheme, profile: ProfileID = .default)
    case update(SpaceID, title: String?, icon: SpaceIcon?, theme: SpaceTheme?)
    /// Archives every tab in the space. Refused for the last space.
    case requestDelete(SpaceID)
    case confirmDelete(SpaceID, token: String, confirmed: Bool)
    case exportIntoFolder(SpaceID)
    case delete(SpaceID)
    case move(SpaceID, index: Int)
    /// A Library Spaces card's New Folder or Live Folders row, for that card's space (P30-c).
    case inSpace(SpaceID, SpaceCardAction)
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
    /// Arc's split menu "Add Left Split" ("Add Top Split" when stacked): `addPane` with the empty pane before the
    /// focused one (a shown tab becomes [empty pane, tab]).
    case addPaneBefore
    /// Arc's split menu "Move Left" / "Move Right" ("Move Up" / "Move Down" when stacked): the focused pane trades
    /// places with its neighbour; at the end it is a no-op. Its width and focus go with it.
    case movePane(Step)
    /// Command bar "Add Left/Right/Top/Bottom Split": `addPane` with the new pane on that side; the split takes
    /// that edge's orientation.
    case addPaneAt(SplitEdge)
    /// Ctrl+Shift+-. Closes the focused pane; a split left with one pane dissolves into that tab.
    case closePane
    /// Close one sidebar pane without selecting or loading its background split.
    case closePaneAt(ItemID)
    /// Divider drag. Relative fractions; the reducer normalizes and enforces Metrics.content.minPaneFraction.
    case resize(ItemID, fractions: [ItemID: Double])
    /// Context menu on a split (Arc: `layoutOrientation`). Saved with the split; v1's layout draws both.
    case setOrientation(ItemID, SplitOrientation)
    case orientCurrent(SplitOrientation)
    /// One-based pane number. Missing panes and next/previous at the ends are no-ops.
    case focusPane(Int)
    case stepPane(Step)
    /// Keeps the pane's section, window slots, live browser, and position immediately after its split.
    case separatePane(ItemRef)
    case separateAll
    /// Transient presentation in this window. The split and hidden pages remain intact.
    case toggleExpanded
    case restore
    /// `at`: the pane index of a slot between two panes (Arc's insertion index); nil is the end `edge` says.
    case dropTab(SplitDropOffer, edge: SplitEdge, at: Int? = nil)
    /// A tab dropped on a framed pane of a split: it takes that pane and the focus; the tab that was there becomes the row
    /// right after the split, in the split's section, with its page (Arc, Q17-split-drop-on-framed-pane).
    case replacePane(SplitDropOffer, pane: Int)
    /// A tab dropped on the middle of another row (Arc, Q15): the tab and the standalone tab become a split where the row
    /// was, or the tab joins the split row. `at` is its place among the panes (on a standalone tab: 0 left, 1 right).
    case joinRow(ItemID, onto: ItemID, at: Int = 0)
}

public enum SidebarCommand: Hashable, Sendable, Codable {
    /// Cmd+S.
    case toggle
    /// Resize drag, after `SidebarResizeDrag` applied snapping. 0 hides the sidebar. Clamped by the reducer.
    case resize(width: Double)
    /// Hidden sidebar: pointer reached the left edge (true) or left the floating sidebar (false).
    case peek(Bool)
    case toggleToolbar
    case toggleSpaceHeader
    case openDialog(SpaceDialogRequest?)
    /// Right-click a row or a space, or the "+" button. `at` is in window coordinates.
    case popupMenu(PopupMenuRequest, at: CGPoint)
}

public enum SpaceDialogRequest: Hashable, Sendable, Codable {
    /// Arc's Create a Space flow, in place of the sidebar.
    case newSpace
    /// Rename Space: the small centred dialog with the name selected.
    case rename(SpaceRef)
    /// Change Space Icon…: the Emoji / Icon popover under the space header.
    case icon(SpaceRef)
    /// Edit Theme…, Edit Theme Color… and the Library Space card's Edit Space…: the theme panel. Its changes apply to
    /// the space as they are made.
    case theme(SpaceRef)
}

public enum PopupMenuRequest: Hashable, Sendable, Codable {
    case item(ItemID)
    case selection([ItemID])
    case space(SpaceID)
    /// Product controls include confirmation and view preferences; `.space` retains the existing model-query contract.
    case spaceControls(SpaceID)
    /// The … of a card on the Library's Spaces page (and the card's right-click; P30-c): the space's menu as Arc shows
    /// it there, its New Folder and Live Folders acting on the card's space and Delete Space asking first.
    case spaceCard(SpaceID)
}

/// What a Library Spaces card's New Folder and Live Folders rows do to the card's space (`SpaceCommand.inSpace`).
public enum SpaceCardAction: Hashable, Sendable, Codable {
    /// "New Folder" at the top of the space's Pinned. The card shows it; the rename field is the sidebar's, which the
    /// Library covers, so it keeps Arc's default name.
    case newFolder
    /// Live Folders > "New GitHub Live Folder…" and "Connect Calendar File…": a source request belongs to the space
    /// the window shows (its folder lands in that space's Pinned), so the window shows the card's space first.
    case connectGitHub
    case connectCalendar
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
    /// "About {app}": the standard about panel (`AppEffect.showAbout`).
    case showAbout
    /// "Set as Default Browser" (`AppEffect.registerAsDefaultBrowser`).
    case setAsDefaultBrowser
    /// Share-by-link, replaced by file export (user decision): the reducer builds an `ExportDocument` from the
    /// subject and emits `Effect.export`; BrkApp asks where to save it and writes JSON or HTML.
    case export(ExportSubject)
    /// Help > Troubleshooting > "Reveal {app} Data": the data directory in the Finder.
    case revealDataDirectory
    /// The Help menu's other rows and Check for Updates (`HelpAction`).
    case help(HelpAction)
    /// Edit > Undo through Select All on a chord the Shortcuts pane gave them (`AppEffect.standardEdit`): the
    /// item's AppKit selector, sent to the first responder of the window that has the key.
    case standardEdit(StandardEdit)
}

/// Edit > Undo, Redo, Cut, Copy, Paste, Paste and Match Style, Delete and Select All (Arc rows 41 to 51): AppKit
/// first-responder items. Native fields get them from the menu; a page gets the same selector through its surface's
/// responder (BrkCEF's `EmbeddedSurface` runs the focused frame's edit command).
public enum StandardEdit: String, Hashable, Sendable, Codable, CaseIterable {
    case undo, redo, cut, copy, paste, pasteAndMatchStyle, delete, selectAll

    /// The menu item's selector, as AppKit's own Edit menu names it.
    public var selector: String {
        switch self {
        case .pasteAndMatchStyle: "pasteAsPlainText:"
        default: rawValue + ":"
        }
    }
}

/// Check for Updates… and the Help menu (Arc rows 7, 179 to 189). Most run in BrkApp (`AppEffect.help`); `open` is
/// the page BrkApp resolved for one of them, opened as a new tab of the dispatching window.
public enum HelpAction: Hashable, Sendable, Codable {
    /// Brk has no update feed: an alert names the running build and says how a new one is made.
    case checkForUpdates
    /// The release notes bundled with this build (made from the build's git history).
    case releaseNotes
    /// Arc's help center (the command bar's Help Center row opens the same page).
    case helpCenter
    /// A new issue on Brk's repository, its body filled with Copy {app} Info's text.
    case contactTeam
    /// The Restore Data window: pick a saved copy of the state file, check it, restore and relaunch.
    case restoreData
    /// Record Trace: starts a Chromium trace; while one records, the row stops it and saves the file.
    case trace
    /// Cancel Trace: stops the recording and discards it.
    case cancelTrace
    /// Open Task Manager: Brk's window listing the browser's processes (CPU, memory, End Process).
    case taskManager
    /// Copy {app} Info: version, build, Chromium, macOS and the data directory, on the pasteboard.
    case copyInfo
    /// A page one of the rows above resolved: a new tab in the dispatching window.
    case open(URL)
}

/// What "Share…" exports. Arc shares spaces, folders, tab sets and Easels by link.
public enum ExportSubject: Hashable, Sendable, Codable {
    case space(SpaceRef)
    case focusedTab
    case items([ItemID])
}

/// Every settings field has a case, so the window, the control socket and the tests change settings the same way.
/// `autoArchive` is the archive page's picker: it sets the current space's profile. `openPane` and `closeWindow`
/// are the settings window itself (one, app-wide).
public enum SettingsCommand: Hashable, Sendable, Codable {
    case autoArchive(AutoArchiveThreshold)
    case general(GeneralSetting)
    case profile(ProfileID, ProfileSetting)
    case links(LinkSetting)
    case shortcuts(ShortcutSetting)
    case max(MaxSetting)
    case advanced(AdvancedSetting)
    case openPane(SettingsPane)
    case closeWindow
    /// A Chromium page in a new tab: Profiles' "Your Data and Settings" rows (in a space of `profile`) and the
    /// About window's credit links (nil: the dispatching window's space). Closes the settings window.
    case openBrowserPage(BrowserPage, profile: ProfileID?)
}

/// The Chromium pages the settings and About windows open in a tab (Arc opens its arc://settings pages the same way).
public enum BrowserPage: String, Hashable, Sendable, Codable, CaseIterable {
    case privacy, passwords, paymentMethods, notifications, credits, chromium

    public var url: URL {
        switch self {
        case .privacy: URL(string: "chrome://settings/privacy")!
        case .passwords: URL(string: "chrome://password-manager/passwords")!
        case .paymentMethods: URL(string: "chrome://settings/payments")!
        case .notifications: URL(string: "chrome://settings/content/notifications")!
        case .credits: URL(string: "chrome://credits/")!
        case .chromium: URL(string: "https://www.chromium.org/")!
        }
    }
}

public enum GeneralSetting: Hashable, Sendable, Codable {
    case warnBeforeQuitting(Bool)
    case dismissDefaultBrowserPrompt
    case webAppearance(WebAppearance)
    case appIcon(AppIconChoice)
    /// View > Developer > "Allow JavaScript from Apple Events" (AppleScript's `execute`).
    case javaScriptFromAppleEvents(Bool)
    /// The menu row: flips the setting above.
    case toggleJavaScriptFromAppleEvents
    /// The app-wide ad blocker and cookie banners (`GeneralSettings.blockAds`, `hideCookieBanners`).
    case blockAds(Bool)
    case hideCookieBanners(Bool)
}

public enum ProfileSetting: Hashable, Sendable, Codable {
    case addSiteSearch(name: String, keyword: String, template: String)
    case removeSiteSearch(SearchEngineID)
    case searchEngine(SearchEngineID)
    case searchSuggestions(Bool)
    case autoArchive(AutoArchiveThreshold)
    /// Nil: the system Downloads folder.
    case downloadsDirectory(String?)
    case promptForDownloadLocation(Bool)
    /// "New documents"; nil is "——".
    case documentApp(DocumentApp?)
}

public enum LinkSetting: Hashable, Sendable, Codable {
    case externalLinksInLittleArc(Bool)
    case optionCommandClickLittleArc(Bool)
    case shiftClickPeek(Bool)
    case peekFromPinnedAndFavorites(Bool)
    case littleArcAutoArchive(AutoArchiveThreshold)
    case globalLittleArcShortcut(Bool)
    case defaultRoute(LinkDestination?)
    /// Air Traffic Control: a route is added at the end (the first match wins), edited in place, or removed.
    case addRoute(LinkRoute)
    case updateRoute(LinkRoute)
    case removeRoute(LinkRouteID)
    case moveRoute(LinkRouteID, index: Int)
}

/// The Shortcuts pane (Arc: "Customized Shortcuts", "Reset Shortcut to Default", "Reset All Shortcuts",
/// "Remove Conflicting Shortcut", the priority picker).
public enum ShortcutSetting: Hashable, Sendable, Codable {
    /// Nil unsets the shortcut (Arc: `KeyBinding.State.unset`).
    case setChord(ActionID, KeyChord?)
    case setPriority(ActionID, KeyPriority)
    case reset(ActionID)
    case resetAll
}

public enum MaxSetting: Hashable, Sendable, Codable {
    case feature(AIFeature, Bool)
    case resetTranslationExclusions
    case provider(AIProviderChoice)
    case renamePinnedTabs(Bool)
    case tidyTabs(Bool)
    case autoEnableFutureFeatures(Bool)
    /// "Turn On Max": the automatic provider when none is chosen, and every feature the user never switched on.
    /// Off: the provider is `.off`.
    case enable(Bool)
}

public enum AdvancedSetting: Hashable, Sendable, Codable {
    case restoreWindowsOnLaunch(Bool)
    case soundEffects(Bool)
    case hapticsOnReorder(Bool)
    case showFullURLInToolbar(Bool)
    case windowDraggingFromPages(Bool)
    case autoPictureInPicture(Bool)
    case themeToCSS(Bool)
    case boostsEnabled(Bool)
    case sharedQuotes(Bool)
}

/// The Library: its panel replaces the sidebar, a navigation column beside the open page's column, and the content
/// area keeps showing the page. Searching within a page is view-local (like the archive's filter).
public enum LibraryCommand: Hashable, Sendable, Codable {
    /// Shift+Cmd+L, the dock's Library button, View Archive, View Downloads. Nil toggles (Arc's `toggleLibrary:`): it
    /// closes an open Library, else reopens the window's last page, else Media. An explicit page already open is a
    /// no-op that keeps its `openID`.
    case open(LibraryPage?)
    case close
    /// Cmd+Y, View History: the space's History tab (`HistoryPage`) is shown, or a new one at the top of Today.
    /// Closes the Library.
    case openHistory
    case cancelDownload(DownloadID)
    /// Reveal the file in the Finder (`Effect.revealFile`).
    case revealDownload(DownloadID)
    case removeDownload(DownloadID)
    case clearDownloads
    case removeHistoryVisit(HistoryVisitID)
    case removeHistory(URL)
    case clearHistory
}

/// Window commands. The dispatching window is the one the command came from; a new window takes its space.
public enum WindowCommand: Hashable, Sendable, Codable {
    /// A public, session-only window with its own empty sidebar.
    case newBlank
    case toggleStayOnTop
    /// Cmd+N: a second standard window on the current space, sharing the global sidebar.
    case new
    /// Shift+Cmd+N (Arc's nib; conflicts with New Folder, see `KeyBindings`): a session-only window whose pages
    /// browse in `BrowsingContext.incognito`.
    case newIncognito
    /// Opt+Cmd+N: Little Arc with `url`, or with the command bar open when nil.
    case newLittle(URL?)
    /// Shift+Cmd+W: this window. The last standard window closing quits (AppKit). An ephemeral window's tabs
    /// are archived from a Little Arc (reason manual, source littleArc) and dropped from incognito.
    case close
    /// Cmd+O "Open Little Arc or Peek in…": the held tab (a Little Arc's tab, or the peeked tab) moves to the top of
    /// that space's Today and a standard window on that space shows it; the Little Arc window or Peek closes.
    /// `.current` is the most recently focused standard window's space.
    case openIn(SpaceRef)
    case openInFolder(ItemID)
}

/// Peek (Arc: `modalV2`): a card over the content showing a scratch tab of this window.
public enum PeekCommand: Hashable, Sendable, Codable {
    /// Gmail in the initiating standard window's current profile.
    case email
    /// Shift+click, or a link from a Pinned or Favorites tab to another site per `LinkSettings`.
    case open(URL)
    /// Esc, the card's close button, Cmd+W while peeking.
    case close
    /// The card's ⤢ button: the peeked page becomes the last tab of the window's Today, focused, keeping its live
    /// page (scroll position and form state).
    case openAsTab
    /// The card's split button: the peeked page joins the shown tab in a split, to its right, keeping its live page.
    case openInSplit
}

public enum ProfileCommand: Hashable, Sendable, Codable {
    case create(name: String, icon: CustomIcon?)
    case rename(ProfileID, name: String)
    /// Refused for the default profile and for a profile with spaces. `Effect.disposeContext` revokes and drains the profile.
    case delete(ProfileID)
    /// "Change Profile" for a space: its Favorites, settings and new pages follow the profile.
    case assign(SpaceRef, to: ProfileID)
    case openDialog(ProfileDialogRequest?)
}

public enum ProfileDialogRequest: Hashable, Sendable, Codable {
    case create
    case change(SpaceRef)
    case delete(ProfileID)
}

// MARK: - System events

public enum SystemEvent: Sendable, Equatable {
    case capture(CaptureEvent)
    case easel(EaselEvent)
    case find(FindUpdate)
    case sidebarData(SidebarDataEvent)
    case page(BrowserToken, PageEvent)
    case download(DownloadUpdate)
    case output(OutputUpdate)
    case exportFinished(WindowID, ExportOutcome)
    case contextDisposed(ContextDisposalResult)
    case websiteRulesLoaded(BrowsingContext, WebsiteRulesUpdate)
    /// A filter list download finished (`Effect.fetchFilterList`).
    case filterListFetched(BrowsingContext, String, FilterListFetch)
    case boost(BoostEvent)
    case extensionOperationFailed(BrowsingContext, String)
    case extensionsRead(ExtensionCatalog)
    case siteDataCleared(ClearSiteDataResult)
    case profileDataCleared(ClearProfileDataResult)
    /// Auto-archive sweep: on a real-time interval, and after the e2e clock moves.
    case clockTick
    case siteResult(String, SiteOutcome)
    case spaceExportFinished(WindowID, token: String, SpaceExportOutcome)
    case window(WindowID, WindowEvent)
    /// A link from another app (Apple Event GetURL, BrkApp/Lifecycle.swift). Routed by `Doc.linkRoutes`, else
    /// `LinkSettings.defaultRoute` and `externalLinksInLittleArc`. F3.
    case externalURL(URL)
    /// The default engine answered `Effect.fetchSuggestions` for this query (stale answers are dropped). F4.
    case suggestions(WindowID, query: String, [String])
    /// Which local AI command-line tools BrkApp found on PATH at launch (`AIProviderSeam.detect`).
    case aiProvidersDetected([AIProviderKind])
    /// What registering the system-wide New Little Arc Window shortcut came to (BrkApp/LittleEntryPoints.swift).
    case globalShortcut(GlobalShortcutStatus)
    /// The provider answered (or could not) an `Effect.ai` request.
    case aiResult(AIRequestID, AIOutcome)
    case aiPartial(AIRequestID, String)
    case aiPageRead(AIRequestID, PageID, AIPageContent?)
    case aiDeadline(AIRequestID)
    /// Shift was held over the hovered link long enough; `link` is its box in the page (points, top-left), if known.
    case aiHoverReady(WindowID, URL, CGRect?)
    case aiTranslated(AIRequestID, Bool)
    case aiDownloadRenamed(DownloadID, originalPath: String, newPath: String?, error: String?)
    // Later: case liveFolder(ItemID, [URL])   -- a live folder fetch finished.
}

public enum WindowEvent: Sendable, Equatable {
    case becameKey
    case activity
    case resignedKey
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
        switch self {
        case .page(.media), .tabTools(.dismissToast), .tabTools(.quoteLinkCopied), .commandBar, .window(.toggleStayOnTop), .sidebar(.peek), .sidebar(.resize), .split(.dropTab), .split(.replacePane): true
        default: false
        }
    }

    /// Whether this command leaves an open Library page open (the archive's own commands, settings such as the
    /// threshold picker, and the sidebar's pointer-driven peek and resize).
    var keepsLibrary: Bool {
        switch self {
        case .capture(.begin), .library(.openHistory): false
        case .boost, .capture, .tabTools(.dismissToast), .tabTools(.quoteLinkCopied), .library, .archive, .settings, .window(.toggleStayOnTop), .sidebar(.peek), .sidebar(.resize), .split(.dropTab), .split(.replacePane), .sidebar(.openDialog), .space(.requestDelete), .space(.confirmDelete),
             .space(.move), .space(.exportIntoFolder), .space(.update), .space(.create),
             .easel(.requestDelete), .easel(.confirmDelete), .easel(.rename): true
        // A Spaces card's … menu and what its rows do (P30-c): the Library stays, so the card shows the result.
        case .sidebar(.popupMenu(.spaceCard, _)), .space(.inSpace), .profile(.assign), .app(.export), .tabTools(.spaceIntoFolder): true
        // The save panel of Share Space… answering (a destination, or Cancel) changes nothing the window shows.
        case .sidebarData(.exportSelected), .sidebarData(.cancelFilePanel): true
        default: false
        }
    }

    /// Whether this command leaves an open Peek open: browsing acts on the peeked page (`.focused` resolves to it,
    /// Rules/Queries.swift), so Cmd+W closes the peeked tab and not the one underneath; everything that changes what
    /// the window shows closes it (Arc closes the Peek when the user picks a sidebar tab).
    var keepsPeek: Bool {
        switch self {
        case .capture, .tabTools(.dismissToast), .tabTools(.quoteLinkCopied), .find, .site, .peek, .page, .settings, .app(.export), .window(.openIn), .window(.openInFolder), .window(.toggleStayOnTop), .sidebar(.peek), .sidebar(.resize), .tab(.close(.focused)), .split(.dropTab), .split(.replacePane): true
        default: false
        }
    }
}

/// The system-wide Little Arc shortcut ("Open Little Arc when I press …", A085), as the app last registered it.
public enum GlobalShortcutStatus: Hashable, Sendable, Codable {
    /// The Links switch is off, or the shortcut is unset or in conflict in Shortcuts.
    case off
    case registered(KeyChord)
    /// Another app holds the combination (Carbon `eventHotKeyExistsErr`) or registration failed with `code`.
    case unavailable(KeyChord, code: Int32)
    /// A combination without Command, Option, Control or Shift is never taken system-wide.
    case needsModifier(KeyChord)
}
