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
    case importer, updater, blankWindow, boosts, notes, easels, captures, savePage, print, toolbar
    case sidebarKeyboardFocus, siteData, cast, developerMenu, spaceManager, aiCommandBar, joinMeeting
    case peekEmail, duplicate, folderTools, linearTabCycling, resetSpace, extensions, onboarding, help, restoreData
    case troubleshooting
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
    case cast
    case pictureInPicture(PictureInPictureIntent)
    case media(ItemRef, MediaPlayerID, MediaOperation)
    case output(OutputIntent)
    case cancelOutput
    case developer(DeveloperOperation)
    /// Cmd+Shift+C (plain), Opt+Shift+Cmd+C (Markdown), Ctrl+Shift+Cmd+C (quote: Arc rows 45 to 47).
    case copyURL(CopyURLFormat)
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
    case dropTab(SplitDropOffer, edge: SplitEdge)
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
    case newSpace
    case editSpace(SpaceRef)
}

public enum PopupMenuRequest: Hashable, Sendable, Codable {
    case item(ItemID)
    case selection([ItemID])
    case space(SpaceID)
    /// Product controls include confirmation and view preferences; `.space` retains the existing model-query contract.
    case spaceControls(SpaceID)
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
    /// "About {app}": the standard about panel (`AppEffect.showAbout`).
    case showAbout
    /// "Set as Default Browser" (`AppEffect.registerAsDefaultBrowser`).
    case setAsDefaultBrowser
    /// Share-by-link, replaced by file export (user decision): the reducer builds an `ExportDocument` from the
    /// subject and emits `Effect.export`; BrkApp asks where to save it and writes JSON or HTML.
    case export(ExportSubject)
    /// Help > Troubleshooting > "Reveal {app} Data": the data directory in the Finder.
    case revealDataDirectory
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
}

public enum GeneralSetting: Hashable, Sendable, Codable {
    case warnBeforeQuitting(Bool)
    case dismissDefaultBrowserPrompt
    case webAppearance(WebAppearance)
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
}

public enum LinkSetting: Hashable, Sendable, Codable {
    case externalLinksInLittleArc(Bool)
    case optionCommandClickLittleArc(Bool)
    case shiftClickPeek(Bool)
    case peekFromPinnedAndFavorites(Bool)
    case littleArcAutoArchive(AutoArchiveThreshold)
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

/// The Library: its panel replaces the sidebar and the open page fills the content area. Searching within a page
/// is view-local (like the archive's filter).
public enum LibraryCommand: Hashable, Sendable, Codable {
    /// Shift+Cmd+L, the dock's Library button, View Archive, View Downloads, Cmd+Y. Nil toggles (Arc's
    /// `toggleLibrary:`): it closes an open Library, else reopens the window's last page, else the archive. An
    /// explicit page already open is a no-op that keeps its `openID`.
    case open(LibraryPage?)
    case close
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
    case find(FindUpdate)
    case sidebarData(SidebarDataEvent)
    case page(BrowserToken, PageEvent)
    case download(DownloadUpdate)
    case output(OutputUpdate)
    case exportFinished(WindowID, ExportOutcome)
    case contextDisposed(ContextDisposalResult)
    case websiteRulesLoaded(BrowsingContext, WebsiteRulesUpdate)
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
    /// The provider answered (or could not) an `Effect.ai` request.
    case aiResult(AIRequestID, AIOutcome)
    case aiPartial(AIRequestID, String)
    case aiPageRead(AIRequestID, PageID, AIPageContent?)
    case aiDeadline(AIRequestID)
    case aiHoverReady(WindowID, URL)
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
        case .page(.media), .tabTools(.dismissToast), .commandBar, .window(.toggleStayOnTop), .sidebar(.peek), .sidebar(.resize), .split(.dropTab): true
        default: false
        }
    }

    /// Whether this command leaves an open Library page open (the archive's own commands, settings such as the
    /// threshold picker, and the sidebar's pointer-driven peek and resize).
    var keepsLibrary: Bool {
        switch self {
        case .capture(.begin): false
        case .boost, .capture, .tabTools(.dismissToast), .library, .archive, .settings, .window(.toggleStayOnTop), .sidebar(.peek), .sidebar(.resize), .split(.dropTab), .sidebar(.openDialog), .space(.requestDelete), .space(.confirmDelete),
             .space(.move), .space(.exportIntoFolder), .space(.update), .space(.create): true
        default: false
        }
    }

    /// Whether this command leaves an open Peek open: browsing acts on the peeked page (`.focused` resolves to it,
    /// Rules/Queries.swift), so Cmd+W closes the peeked tab and not the one underneath; everything that changes what
    /// the window shows closes it (Arc closes the Peek when the user picks a sidebar tab).
    var keepsPeek: Bool {
        switch self {
        case .capture, .tabTools(.dismissToast), .find, .site, .peek, .page, .settings, .app(.export), .window(.openIn), .window(.openInFolder), .window(.toggleStayOnTop), .sidebar(.peek), .sidebar(.resize), .tab(.close(.focused)), .split(.dropTab): true
        default: false
        }
    }
}
