# Feature ledger: Arc 1.170 against Brk

## About this ledger

This is the Arc feature inventory and the archived wave-1 implementation snapshot. The table and counts below describe `c61735f`, not the current checkout. Read [Wave 2 status](wave2-status.md) for the settings, profiles, windows, command bar, and Library changes and their current verification.

The Arc side comes from `docs/arc-anatomy/model-and-shortcuts.md` (sections 1 to 4, written "anatomy-m 2.3" and so on) and `docs/arc-anatomy/visual-and-copy.md` section 3 ("anatomy-v 3"). Bundle names such as `ARC_LittleBrowser` are the resource bundles in anatomy-m 3.1. The Brk side was read from `main` at `c61735f` (Swift wave 1 merged), on 2026-10-30.

What was checked directly, and how:

- `swift test --scratch-path /tmp/brk-ledger-build` on `c61735f`: 302 tests executed, 0 failures. The test results below belong to that revision.
- The e2e scenarios (ids 0 to 9, R2 to R10, N1 to N4, defined in `docs/design/swift/module-map.md`, "E2E scenarios") have not yet produced a result. The first integrated run against the real Chromium app crashed the runner before it wrote `7adf40f551:verify/swift/REPORT.md` (audit row 2026-10-30T11:45:31Z; `/tmp/int-swift-e2e.log` ends with "Trace/BPT trap: 5"). That run left screenshots in `7adf40f551:verify/swift/shots/`, failure captures for N1, R2 and R3, and no log at all for N2, N3 and N4. A scenario id in this ledger therefore means "this scenario covers it", not "it passed on the real app", unless the row says otherwise.
- Screenshots `7adf40f551:verify/swift/shots/2-command-bar.png` and `7-archive.png` were looked at: sidebar with title row, URL pill, the Favorites empty state, the New Tab row, a selected Today row, the dock, a white rounded card, the centered command bar, and the archive page inside the card.

### Status words

- `done`: implemented, and covered by a passing unit test or a scenario (named in the evidence column).
- `partial`: some of it exists; the evidence column says what exists and what is missing.
- `planned`: not built, but `docs/design/swift/rationale.md` ("Where later features plug in") names where it goes.
- `stand-in`: an external-service feature that the user decided to replace with a local version (own OpenAI key, local-folder sync, free translation API). None of these are built yet.
- `not started`: not built and no plug-in point is written down.

`done` is about behavior. No screen has yet been compared with a capture of the real Arc, so pixel identity is tracked as its own row in the last group.

### Test file short names

| Short name | File |
|---|---|
| RS | `Tests/BrkDomainTests/ReduceSpecTests.swift` |
| PS | `Tests/BrkDomainTests/PolicySpecTests.swift` |
| TT | `Tests/BrkDomainTests/TreeTests.swift` |
| KR | `Tests/BrkDomainTests/KeyRoutingSpecTests.swift` |
| AT | `Tests/BrkDomainTests/ActionsTests.swift` |
| AG | `Tests/BrkLayoutTests/ArcGeometryTests.swift` |
| LS | `Tests/BrkLayoutTests/LayoutSpecTests.swift` |
| CB | `Tests/BrkOverlaysTests/CommandBarViewTests.swift` |
| SG | `Tests/BrkOverlaysTests/SuggestSpecTests.swift` |
| AP | `Tests/BrkOverlaysTests/ArchivePageViewTests.swift` |
| SD | `Tests/BrkOverlaysTests/SpaceDialogTests.swift` |
| TH | `Tests/BrkThemeTests/ThemeRendererTests.swift` and `TextureTests.swift` |
| APP | `Tests/BrkAppTests/AppSpecTests.swift` |

### Shortcut column

The numbers are row numbers of the 189-row table in anatomy-m 2.3. "yes" means `Sources/BrkDomain/Actions.swift` has an `ActionID` for it (the id is given), "no" means it does not. Today `Actions.swift` has 39 actions; Arc's nib has 89 items with an `arcKeyBindingID`.

### Size of what is left

S: up to a day of one worker. M: a few days. L: about a week, or several workers in parallel. XL: more than a week across several workers. "none" means nothing is left beyond the cross-cutting pixel check.

## The ledger

| Feature | Arc evidence | What Arc does | Brk status | Status evidence | Shortcut rows, in Actions.swift | Left |
|---|---|---|---|---|---|---|
| **Sidebar and tabs** | | | | | | |
| Window shell and title row | anatomy-m 1.15 `SidebarHeaderView`; `layout-constants.md` | Traffic lights, sidebar toggle, back, forward and reload buttons above the URL pill | done | `Sources/BrkSidebar/SidebarView.swift`; AG `testTrafficLightCentreLine`, `testSidebarColumnStack`; scenario 0 (shot `0-launch-smoke.png`); N3 has not run yet | none | none |
| URL pill | anatomy-m 1.15 `CommandBarPlaceholderView`; anatomy-v 3 "Search or Enter URL…" | Shows the focused tab's address; a click opens the command bar on top of it | done | `URLPillSnapshot` in `Sources/BrkDomain/Snapshot.swift`; RS `test_commandbarOpenEditCurrentIsCenteredWhileTheSidebarIsHidden...`; shot `2-command-bar.png` | 22 yes (`addressBar`) | S: Arc's short placeholder text is unknown |
| Sidebar width | anatomy-m 1.8 `SidebarViewPreferences` | Drag the edge between 164 and 500 pt, snaps, hides below 82 | done | AG `testSidebarResizeDragSnapsAndHides`; RS `test_sidebarResizeClampsTheWidth...`; scenario 9 | none | none |
| Show and hide sidebar | row 91; anatomy-m 1.8 `SidebarMode` | Cmd+S hides the sidebar; the card fills the window | done | RS `test_sidebarToggleHidesTheSidebar...`; LS `test_sidebarHiddenTheContentCardSpans...`; scenario 5 (shot `5-sidebar-hidden.png`) | 91 yes (`showSidebar`) | none |
| Floating sidebar on hover | anatomy-m 1.8 `SidebarPresentation.floating`; anatomy-v 3 "Hide sidebar" | With the sidebar hidden, pointing at the left edge slides it in over the page | partial | Exists: RS `test_sidebarPeekFloatsTheHiddenSidebar...`, LS `test_hiddenPeekFloatingSidebar...`. Missing: R2 failed on the real app (`verify/swift/shots/R2-failure.png`); the hidden sidebar render is a known pending fix (audit row 2026-10-30T11:44:44Z) | none | S |
| Toolbar mode | row 92; anatomy-m 4.4 `topBarURLEnabled`; Advanced "Show full URL when Toolbar is enabled" | Optional address bar above the page instead of in the sidebar | not started | No command for it in `Sources/BrkDomain/Command.swift` | 92 no | M |
| Space header | anatomy-v 3 "Show Space Header" and "Hide Space Header"; `showSpaceHeaderOnSingleUnnamedSpaces` | The space's name and icon above its tab list, can be hidden | partial | Exists: `SpaceHeaderView` in `Sources/BrkSidebar/SidebarView.swift`. Missing: its frame is not computed yet (pending fix D1, audit row 2026-10-30T11:44:44Z; no header in `2-command-bar.png`), no show or hide option | none | S |
| Today section and New Tab row | anatomy-m 1.9; `NewTabCellView` | Unpinned tabs, newest at top; the "+ New Tab" row opens the command bar | done | RS `test_commandbarSubmitWithTheNewTabBarOpenAddsATabAtTheTop...`; `Sources/BrkSidebar/TablistView.swift` (NewTab row); scenario 2 | 16, 132 yes (`newTab`) | none |
| Closing a tab archives it | row 32; anatomy-v 3 "Archive this tab" | Cmd+W or the hover x moves a Today tab to the Archive | done | RS `test_tabCloseOnATodayTabArchivesItWithReasonManual...`; scenario 8 | 32 yes (`archiveTab`) | none |
| Pinned tabs | row 136, 155; anatomy-m 1.6; anatomy-v 3 "Pinned" | Cmd+D pins; pinned tabs keep their URL, "Close and Keep Pinned", "Back to Pinned URL" | done | RS `test_tabTogglePinMovesToday...`, `test_tabCloseOnAPinnedTabKeepsTheRow...`, `test_tabResetOnAPinnedTab...`; scenario 3 | 136 yes (`pinTab`), 155 yes (`resetTab`) | S: "Separate From Pinned Tab" and "Replace Pinned Tab with the Current Site" |
| Reset all pinned tabs in a space | row 154 | Returns every pinned tab of the space to its pinned URL | not started | No command in `Sources/BrkDomain/Command.swift` | 154 no | S |
| Collapse pinned section | rows 93, 94; anatomy-m 1.6 `PinnedSectionExpansionState` (expanded, collapsed, peeked) | Folds the pinned list; "peeked" keeps the current pinned tab visible | partial | Exists: RS `test_spaceTogglePinnedSectionCollapsesAndExpands...`. Missing: the `peeked` state; Arc's two menu items are one combined toggle | 93 and 94 as one action (`togglePinnedSection`) | S |
| Favorites grid | `ARC_AppTray`; anatomy-v 3 "Drag to add Favorites" | Tiles shared by every space of a profile; drag in, reorder, empty state | done | `Sources/BrkSidebar/FavoritesView.swift`; RS `testFavoritesReorderInsideTheGrid`; LS `testFavoriteTilesReorderInsideTheGrid`; PS `test_letsFavoritesHoldTabsOnlyFlat`; empty state in shot `2-command-bar.png` | none | none |
| Favorite badges and subtitles | `ARC_AppTray` badge colors; anatomy-m 1.6 `TopApp` (11 sites), `topAppsBadgingDisabledHosts` | Unread counts on Gmail and WhatsApp tiles, next event under Calendar | not started | No badge field in `TabRow` (`Sources/BrkDomain/Snapshot.swift`) | none | M |
| Join meeting | row 134 | Ctrl+Cmd+J opens the next calendar meeting | not started | Not in `Sources/BrkDomain/Actions.swift` | 134 no | S |
| Next and previous tab | rows 143, 144 | Opt+Cmd+Down and Up walk the sidebar | done | RS `test_tabStepWalksSidebarOrderWithoutWrapping...` | 143, 144 yes (`selectNextTab`, `selectPreviousTab`) | none |
| Recent-tab switcher | rows 145, 146; `ModalItemSwitcher` | Ctrl+Tab walks recent tabs with an on-screen switcher panel | partial | Exists: RS `test_tabCycleRecentFreezesTheRecentOrder...`, KR `testControlReleaseCommitsTheCycle`; scenarios R5a, R6. Missing: the switcher panel (no such case in `Overlay`, `Sources/BrkDomain/Model.swift`) | 145, 146 yes (`cycleNextTab`, `cyclePreviousTab`) | M |
| Linear tab cycling | rows 147, 148; `linearTabSwitcherState` | Ctrl+Cmd+Right and Left cycle tabs | not started | Not in `Sources/BrkDomain/Actions.swift` | 147, 148 no | S |
| Jump to item 1 to 9 and to space N | anatomy-m 2.5 | Number shortcuts jump to a sidebar item or a space | not started | Not in `Sources/BrkDomain/Actions.swift` | not in the nib (2.5) | S |
| Rename an item | row 140; anatomy-v 3 "Double-click to rename" | Row becomes a text field | done | RS `test_itemRenameWithNullCancels...`, `testBeginRenameExpandsCollapsedAncestors` | 140 yes (`rename`) | none |
| Custom icons | anatomy-m 1.4 `SidebarCustomIcon`, 61 `SidebarIconType`; `ARC_CustomInfoPicker`, `ARC_Emojis` | Pick an icon or emoji for a tab, folder, split or space | partial | Exists: RS `testCustomIconsOnTabsFoldersAndSplits`; emoji for spaces in the space dialog (SD `testTheLastEmojiTypedBecomesTheIcon...`). Missing: 45 of 61 icon names (`NamedIcon` in `Sources/BrkDomain/Model.swift` has 16), the picker grid, a "Change Icon" menu entry for items (`menuModel` in `Sources/BrkDomain/Rules/Sidebar.swift`) | none | M |
| Drag and drop in the sidebar | anatomy-m 1.4 `SidebarMutation.move` | Reorder rows, drop into folders, onto Favorites, onto a dock space | done | `Sources/BrkSidebar/DragController.swift`; LS `testRowDropTargetsFollowTheRowHalves...`; RS `test_itemMoveToADockSpace...`; scenario R5b | none | none |
| Multi-select and bulk actions | anatomy-m 1.8 `multiSelectedItems`; anatomy-v 3 "Archive Other Tabs", "Archive Tabs Below", "New Folder from Selection…" | Select several rows and act on them at once | not started | No selection field in `Sources/BrkDomain/Model.swift` | none | M |
| Duplicate | row 139 | Duplicates the selected tabs | not started | Not in `Sources/BrkDomain/Actions.swift` | 139 no | S |
| Reveal tab and keyboard focus in the sidebar | rows 95, 149 | Ctrl+Space moves focus to the sidebar on the current tab | not started | `FocusTarget.sidebar` is reserved in `Sources/BrkDomain/Snapshot.swift`, no command uses it | 95, 149 no | M |
| Clear Today | row 153; anatomy-v 3 "Clear Today tabs" | Archives every unpinned tab not on screen | done | RS `test_tabClearTodayKeepsTheTabsVisibleInAnyWindow`; also in N1, which failed on the real app (`N1-failure.png`) | 153 yes (`clearExplore`) | none |
| Restore last closed tab | row 21 | Shift+Cmd+T reopens the newest closed tab | done | RS `test_archiveRestoreLastRestoresArchive0...`, `test_archiveRestoreLastPrefersTheNewestManual...` | 21 yes (`reopenLastClosedTab`) | none |
| Sidebar context menus | `ARC_ContextMenus` (`SidebarMenu`, `SpaceMenu`, `SplitScreenMenu`, `DownloadMenu`) | Right-click menus on tabs, folders, splits and spaces | partial | Exists: RS `test_sidebarPopupMenuEmitsANativeMenu...`, APP `test_popupMenuItemsDispatchTheirCommands`; entries in `menuModel`, `Sources/BrkDomain/Rules/Sidebar.swift`. Missing: Copy Link, Duplicate, Change Icon, split conversions, Share, bulk archive, Arc's own menu style (`ARC_ArcMenu`) | none | M |
| Audio indicator and mute | anatomy-m 1.6 `savedMuteStatus`, `TabCellState.isAudible`; command `muteAllTabs` | Speaker icon on playing tabs, click to mute | not started | No audio field in `TabRow` (`Sources/BrkDomain/Snapshot.swift`) | none | S |
| Page loading glow | `ARC_GlowProgressLoadingIndicator` (Metal shaders) | A glow shows page load progress | partial | Exists: a spinner (`SpinnerLayer`, `Sources/BrkSidebar/Glyphs.swift`). Missing: the glow | none | M |
| Hover cards and link previews | `HoverCards` module (anatomy-m 3.4); General "Show Arc Previews" | Preview cards for Gmail, Calendar, folders and recent pages on hover | not started | Nothing in `Sources/` | none | L |
| Crashed page | `ARC_SadTab` | Sad-tab image, recovery | partial | Exists: RS `testRendererGoneShowsTheCrashedCardAndAsksForRecovery`; scenarios R7b, R10 (no result yet). Missing: Arc's image (text placeholder, TODO at `Sources/BrkContent/ContentAreaView.swift:57`) | none | S |
| Tidy titles rule list | `ARC_WebContentBehaviorConfigurationClient` `tidyTitles`; `TidyTabTitles` module | Shortens known site titles without AI | not started | Nothing in `Sources/` | none | S |
| Toasts | `Toasts` module (64 types); anatomy-v 3 "Pinned Tab to “%@”", "Auto archived %d tabs" | Short confirmations at the bottom of the window | not started | No toast state in `Sources/BrkDomain/Model.swift` | none | M |
| Tab groups | anatomy-m 1.4 `SidebarTabGroup`; `TabGroupHeaderCellView` | A titled group of tabs | not started | No such kind in `Sources/BrkDomain/SidebarTree.swift` | none | M |
| **Page and browsing (View, Edit and Archive menus)** | | | | | | |
| Back, forward, reload, stop | rows 96 to 98, 157 to 160 | Page navigation with Arc's key priorities | done | RS `test_browsingCommandsResolveTheFocusedTabIntoEffects...`; `Sources/BrkCEF/CEFEngine.swift` `perform` | 96 to 98 yes (`stopLoading`, `reloadPage`, `forceReloadPage`); 157 to 160 yes (`goBack`, `goForward`) | none |
| Key priorities and press twice | anatomy-m 1.14, 2.2 | App wins, page wins, or page first then app on a second press | partial | Exists: KR (16 tests), APP `test_aPageFirstChordIsTakenOnTheSecondPress`. Missing: N1 failed on the real app (`N1-failure.png`) | all bound rows | S |
| Zoom | rows 105 to 110 | Zoom in, out, reset with Chrome's zoom steps | partial | Exists: `Sources/BrkCEF/CEFEngine.swift` `perform(.zoom)`. Missing: fixed 0.5 steps instead of Chrome's presets (TODO at line 120), zoom indicator | 105 yes (`resetZoom`), 106 to 108 yes (`zoomIn`), 109, 110 yes (`zoomOut`) | S |
| Find in page | rows 53 to 58 | Find bar, next, previous, replace, jump to selection | not started | Not in `Sources/BrkDomain/Actions.swift` | 53 to 58 no | M |
| Copy URL | rows 45 to 47 | Copy the URL, as Markdown, or as a quote | partial | Exists: RS line 541 (`copyToPasteboard`). Missing: Markdown and quote forms | 45 yes (`copyCurrentURL`); 46, 47 no | S |
| Developer tools | rows 113 to 120 | View source, DevTools, inspect, console, network, developer mode | partial | Exists: DevTools toggle (`toggleDevTools`, `Sources/BrkCEF/CEFEngine.swift`). Missing: the other five | 114, 115 yes (`developerTools`); 113, 116 to 120 no | S |
| Clear cookies or cache and refresh | rows 99, 100 | Reload after clearing site data | not started | Not in `Sources/BrkDomain/Actions.swift` | 99, 100 no | S |
| Website appearance | rows 86 to 90 | Websites, Easels and Notes use automatic, light or dark | not started | Not in `Sources/BrkDomain/Actions.swift` | 88 to 90 no | S |
| Save, print, share, cast | rows 33, 38, 39, 111 | Standard page actions | not started | Not in `Sources/BrkDomain/Actions.swift` | 33, 38, 39, 111 no | M |
| Full screen and Exit | rows 121, 122 | Ctrl+Cmd+F; Esc leaves the current context | done | RS `testExitClosesTheOverlayWithoutLeavingFullScreen` | 121 yes (`fullscreen`), 122 yes (`exit`) | none |
| Edit menu | rows 41 to 51, 59 to 84 | Standard editing, spelling, substitutions, transformations, speech, font | partial | Exists: Undo, Redo, Cut, Copy, Paste, Paste and Match Style, Select All as plain AppKit items (`addStandardEditItems`, `Sources/BrkApp/MainMenu.swift`). Missing: Delete and rows 59 to 84 | 41 to 44, 48, 49, 51 as AppKit items, not in Actions.swift; 50, 59 to 84 no | S |
| History | row 161 | Cmd+Y shows the full history | partial | Exists: history is stored and offered in the command bar (RS `test_pageEventsUrlPushesAHistoryEntry...`, SG). Missing: the history page | 161 no | M |
| Downloads | row 171; Library downloads page; Profiles "Download location"; `StorableDownloadMetadata` | Downloads list, location setting, download menu | not started | No download handling in `Sources/BrkCEF/` | 171 no | L |
| Links that open new tabs and popups | anatomy-m 1.10 `browserPopup`; RS spec | Cmd+click opens a background tab; popups open | partial | Exists: RS `test_openrequestedBackgroundTrueMarksTheTabLoaded...`. Missing: R3 failed on the real app (`R3-failure.png`); popups become tabs and lose `window.opener` (`Sources/BrkCEF/ChromePage.swift` line 107; rationale "Open questions") | none | M |
| Session restore | Advanced "When opening Arc, restore windows from previous session" | Reopens windows, spaces, tabs; loads lazily | done | RS `test_statecodecEncodeThenStateCodecRestoreRoundTrips...`, `test_restoreStaysLazy...`; scenarios 9, R8 | none | S: the on or off setting |
| **Windows** | | | | | | |
| Several standard windows | rows 17, 31; anatomy-m 1.8 | New Window, Close Window, all sharing one sidebar | partial | Exists: state keyed by window (`Doc.windows`, `Sources/BrkDomain/Model.swift`), RS `testWindowCloseKeepsTheWindowForTheNextLaunch`. Missing: a second window; v1 opens one (rationale "Tradeoffs accepted") | 17, 31 no | M |
| Blank window | row 18 | A window with no sidebar items | not started | Not in `Sources/BrkDomain/Actions.swift` | 18 no | S |
| Hide, minimize, zoom, bring all to front | rows 10 to 12, 14, 168, 169, 175 | Standard window and app commands | partial | Exists: AT `testAppShortcutsRouteThroughTheTable`. Missing: Show All, Zoom, Bring All to Front | 10, 11, 14, 168 yes (`hideArc`, `hideOthers`, `quitArc`, `minimize`); 12, 169, 175 no | S |
| Window placement on restore | anatomy-m 1.8 | A window saved off screen comes back on screen | done | AG `testWindowPlacementOffScreen`; scenario R8 (shot `R8-back-on-screen.png`) | none | none |
| Stay on top | anatomy-m 1.8 `WindowState.stayOnTop` | Keeps a window above others | not started | No field in `Sources/BrkDomain/Model.swift` | none | S |
| **Spaces and themes** | | | | | | |
| Create a space | row 124; `ARC_SpaceCreation`; anatomy-v 3 "Spaces" | Animated flow with name, icon, theme card and profile card | partial | Exists: RS `test_spaceCreateCreatesAnEmptySpace...`, SD `testSaveOnANewSpaceSends...`, `Sources/BrkOverlays/SpaceDialogHost.swift`. Missing: Arc's card flow and animation, the profile card | 124 yes (`newSpace`) | M |
| Switch spaces | rows 128, 129 | Dock click, Opt+Cmd+arrows; background crossfades | done | RS `test_spaceFocusSwitchesTheGradientAndRows...`, `test_spaceStepMovesToTheNeighbour...`; scenarios 4 (shot `4-space-switched.png`), R9 | 128, 129 yes (`focusNextSpace`, `focusPreviousSpace`) | none |
| Swipe between spaces | `space_swiping.mp4`; `SidebarPagingContainerViewController` | Two-finger swipe pages the sidebar from space to space | not started | No scroll or gesture handling in `Sources/BrkSidebar/` | none | M |
| Rename, icon and theme of a space | rows 125, 126; anatomy-v 3 "Rename Space", "Change Space Icon…" | Edit name, icon and theme | partial | Exists: SD `testEditingStartsFromTheSpaceAndSaveUpdatesIt`, RS `test_spaceUpdatePatchesTitleIconAndTheme...`. Missing: a Rename Space menu action (only through the context menu) | 125 yes (`editSpaceTheme`), 126 no | S |
| Delete and reorder spaces | anatomy-v 3 "Delete your “%@” Space?", "Drag to Reorder Space" | Delete with confirmation; drag to reorder | partial | Exists: RS `test_spaceDeleteArchivesItsPinnedAndTodayTabs...`, `test_spaceMoveReordersTheDock...`. Missing: confirmation dialog, dock drag to reorder (`Sources/BrkSidebar/DockView.swift`) | none | S |
| Space manager | row 130; `SpaceManagementView` | Grid of all spaces, search, reorder, "Export into Folder" | not started | Not in `Sources/BrkDomain/Actions.swift` | 130 no | M |
| Theme background | `ARC_WindowThemeUI`; anatomy-m 1.13, 4.5 | Metal gradient with grain, sand, denim or tweed texture | partial | Exists: `Sources/BrkTheme/ThemeRenderer.swift` (Metal), TH (5 tests), scenario 4. Missing: Arc's texture pixels (ours are procedural, rationale "Tradeoffs accepted") | none | M |
| Theme editor | `ARC_SpaceStyleEditor`; anatomy-m 1.13 `SpaceStyleEditor.State` | Color pad, number of colors, saturation, noise, intensity, preset pages, dark mode bias, undo | partial | Exists: SD `testTheFourPresetSetsOfNineInEditorOrder`, PS `test_wheelRuleDerivesCompanionHues`, `test_noiseAndIntensityResolveSeparately`. Missing: Arc's editor layout, the draggable color pad, preset paging, undo stack | 125 yes (`editSpaceTheme`) | L |
| Light and dark theme values | anatomy-m 1.13 `AppearanceBasedConfiguration` | A theme can hold separate light and dark values | partial | Exists: one appearance choice, PS `test_letsAForcedAppearanceOverrideTheLuminance`. Missing: separate light and dark pairs | none | S |
| Theme colors for websites | Advanced "Allow websites to get your theme data" | Pages can read the space's colors as CSS | not started | Nothing in `Sources/` | none | S |
| **Command bar** | | | | | | |
| New-tab bar and address bar | rows 16, 22; anatomy-m 1.11 `CommandBarDestinationType` | Cmd+T centered bar makes a tab; Cmd+L edits the current tab | done | RS `test_commandbarSubmit...` (4 tests); CB (6 tests); scenario 2 (shot `2-command-bar.png`) | 16 yes (`newTab`), 22 yes (`addressBar`) | none |
| Suggestions | anatomy-v 3 suggestion sources (13 kinds) | Open tabs, history, search suggestions, top domains, calculator, bookmarks | partial | Exists: tabs, typed text, history (SG, 12 tests). Missing: search engine suggestions, `TopDomains.json`, calculator, bookmarks, ranking memory (`StorableCommandBarAdditionalRanking`), host dedup list | none | M |
| Actions in the bar ("Type Travel") | anatomy-m 1.11; 114 menu items with `arcTypeTravelID`; 35 `TypeTravelCandidate` cases | Every menu command, space, folder move and extension is searchable | partial | Exists: 15 actions with a `bar:` listing in `Sources/BrkDomain/Actions.swift`; SG `test_onlyListsActionsWithACommandBarListing`. Missing: the rest of the menu, focus or move to space, move to folder, extensions, open settings pane | none | M |
| Site search | anatomy-v 3 "Change Site Search", Tab and Space hints | Type a site name, press Tab, search that site | not started | Nothing in `Sources/BrkOverlays/Suggest.swift` | none | M |
| Search engine choice | Profiles "Default Search Engine", `SearchEngine` records | Per-profile default engine and suggestions switch | partial | Exists: one fixed search template (`searchURL`, `Sources/BrkDomain/Rules/CommandBar.swift`). Missing: choice per profile | none | S |
| **Split view** | | | | | | |
| Add and close panes | rows 101, 102; anatomy-v 3 "Split view" | Up to four panes, gap 10 | done | RS `test_splitAddPane...` (4 tests), `test_splitClosePane...`; TT `testSplitPanesHoldTwoToMaxDistinctIDs`; scenario 6 (shot `6-split.png`) | 101 yes (`addSplitView`), 102 yes (`removeSplitView`) | none |
| Resize panes | `SplitViewDraggerHandleView` | Drag the divider | done | RS `test_splitResizeNormalizesFractions...`; `DividerView` in `Sources/BrkContent/ContentAreaView.swift` | none | none |
| Split as one sidebar row | `SplitViewCellView` | A split is one row showing its panes | done | `Sources/BrkSidebar/TablistView.swift`; scenario 6 asserts one split row | none | none |
| Horizontal and vertical | anatomy-v 3 "Convert to Horizontal Split View" | Side by side or stacked | partial | Exists: RS `testSplitOrientationIsSavedAndProjected`; stacked layout in `WindowLayout.cards` (`Sources/BrkLayout/WindowLayout.swift`). Missing: a menu entry to convert | none | S |
| Separate, expand, separate all | rows 103, 104; anatomy-v 3 "Separate All Tabs" | Take a pane out, or maximize the current pane | not started | Not in `Sources/BrkDomain/Actions.swift` | 103, 104 no | S |
| Drag a tab into the page to split | anatomy-v 3 "Drag a tab from your sidebar into the middle of the screen…" | Dropping a row on the content makes a split | not started | `Sources/BrkSidebar/DragController.swift` drops only inside the sidebar | none | M |
| Jump between panes | anatomy-m 2.5 `switchToNextWindowPane` | Keys for first to fourth, next and previous pane | not started | Not in `Sources/BrkDomain/Actions.swift` | not in the nib (2.5) | S |
| **Archive and Library** | | | | | | |
| Auto-archive | anatomy-m 4.3; anatomy-v 3 "Auto-archive options" | Idle Today tabs go to the Archive after 1 h to 30 days, or never | done | RS `test_clocktickArchivesIdleTodayTabs...`, `test_aTabReadFor11HoursThenLeftWithCtrlTab...`; scenarios 7, R5a, R5b | none | S: per-profile thresholds |
| Archive page | rows 162, 163; anatomy-v 3 "Archive page" | Grouped list, filter, restore, clear, threshold picker | done | AP (8 tests); RS `test_archiveRestorePutsTheTabBack...`; scenario 7 (shot `7-archive.png`) | 162 yes (`viewArchive`), 163 yes (`clearArchive`) | none |
| Archive whole folders and splits | anatomy-m 1.9 `ArchivedItem` keeps the full sidebar item | A folder or split comes back as one unit | partial | Exists: archiving archives each tab inside. Missing: unit restore (`ArchivedTab` comment, `Sources/BrkDomain/Model.swift`) | none | S |
| Library | row 170; `ARC_HomeButton`; anatomy-m 1.9 `HomePageID` | One place for Downloads, Archive, Easels and Notes, Media, Boosts, Spaces | not started | Only a comment ("Later: case library", `Sources/BrkDomain/Model.swift` line 236); the dock's Library button opens the Archive (`Sources/BrkSidebar/DockView.swift`) | 170 no | L |
| Auto-archive education banner | `ARC_SidebarBanner` `AutoArchiveEducationView` | A card at the bottom of the sidebar explaining auto-archive | not started | Nothing in `Sources/BrkSidebar/` | none | S |
| **Little Arc and Peek** | | | | | | |
| Little Arc window | row 20; `ARC_LittleBrowser`; anatomy-m 1.10 | A small one-tab floating window | planned | rationale "Little Arc": a `WindowKind` case and a scratch tree; seam in `ContainerScope` (`Sources/BrkDomain/Model.swift`) | 20 no | L |
| Little Arc "Open In" and move to a space | row 137; anatomy-m 2.5 `showLittleArcOpenInMenu` | Move the page into a space or folder | planned | rationale "Little Arc" | 137 no | M |
| Little Arc entry points | Links pane; anatomy-m 1.10 `LittleBrowserEntryPoint` | Links from other apps, global hotkey, Opt+Cmd+click, menu bar item | planned | rationale "Little Arc" and "Air Traffic Control"; `externalURL` reserved in `Sources/BrkDomain/Command.swift` line 204 | none | M |
| Little Arc auto-archive | Links "Archive Little Arcs after:" | Closes idle Little Arc windows | planned | rationale "Little Arc" | none | S |
| Peek | anatomy-v 3 "Peek"; anatomy-m 1.7 `modalV2` | Opens a link in a panel over the page; Shift+click; links from Pinned and Favorites | planned | rationale "Peek"; "Later: case peek" in `Sources/BrkDomain/Model.swift` line 235 | none | L |
| Peek Email | row 135 | Shift+Cmd+E peeks Gmail | not started | Not in `Sources/BrkDomain/Actions.swift`; needs Peek and Favorites | 135 no | S |
| **Folders and Live Folders** | | | | | | |
| Folders | row 138; anatomy-m 1.6 `SidebarList` | Nested folders in Pinned; delete archives the tabs inside | done | RS `test_itemNewFolderAddsAFolderAtTheTopOfPinned...`, `test_itemDeleteFolderArchivesEveryTab...`; PS `test_letsPinnedHoldTabsSplitsAndNestedFolders` | 138 yes (`newFolder`) | S: "Clean up Folders", "Close All Folders" |
| Collapse and expand all folders | rows 141, 142 | One command for all folders | not started | Not in `Sources/BrkDomain/Actions.swift` | 141, 142 no | S |
| Folder open state per window | anatomy-m 1.6 `WindowState.expandedItems` | Each window remembers which folders are open | partial | Exists: one global open state. Missing: per window (rationale "Tradeoffs accepted") | none | S |
| Live Folders | anatomy-m 1.6 `AutomaticLiveFolderData` (GitHub); `LiveFoldersFeature` | A folder filled from GitHub pull requests | planned | rationale "Live Folders"; comment at `Sources/BrkDomain/SidebarTree.swift` line 108 | none | L |
| **Profiles and incognito** | | | | | | |
| Profiles | rows 27, 127; `ARC_ProfilesUI`; anatomy-m 1.12 | Separate browser data per space; own Favorites, search engine, archive time, extensions | planned | rationale "Profiles"; TODO at `Sources/BrkCEF/ChromePage.swift` line 37; `ProfileID` already on spaces | 27, 127 no | L |
| Incognito window | row 19 | A window with no saved data | planned | rationale "Incognito" | 19 no | M |
| Privacy and clear browsing data | Profiles pane "Privacy and Security", "Clear Browsing Data" | Per-profile privacy settings | not started | Nothing in `Sources/` | none | S |
| **Extensions** | | | | | | |
| Install and manage | rows 165, 166 | Chrome Web Store and `chrome://extensions` | partial | Exists: the Chrome runtime can show `chrome://extensions` (`docs/swift/cef-hosting-results.md`). Missing: an Extensions menu (`MenuName` in `Sources/BrkDomain/Actions.swift` has no Extensions menu) | 165, 166 no | M |
| Extension buttons and picker | `ARC_ContentPanel` `ExtensionButton`; anatomy-m 2.5 `openExtensionsPicker` | Toolbar buttons and a pinned extensions picker | planned | rationale "Extensions" | not in the nib (2.5) | M |
| Extension shortcuts | Shortcuts pane "Extension Shortcuts" | Keys for extension commands | not started | Nothing in `Sources/` | none | S |
| **Boosts** | | | | | | |
| Boosts | rows 23 to 26, 174; `ARC_BoostsEditor`, `ARC_BoostsDialog` | Per-site CSS and JavaScript, Zap, editor, gallery, install and share dialogs | planned | rationale "Boosts" | 23 to 26, 174 no | XL |
| **Easels and Notes** | | | | | | |
| Notes | rows 28, 29, 183; `ARC_ArcRichTextEditor`, `ARC_TextEditor` | Rich text notes in the sidebar and in a split; Arc is retiring them | planned | rationale "Easels, Notes" (`PaneContent` cases) | 28, 29, 183 no | L |
| Easels | rows 30, 172; `ARC_EaselUI` | A canvas for captures, drawing and text | planned | rationale "Easels, Notes" | 30, 172 no | XL |
| **Captures and media** | | | | | | |
| Capture | rows 35 to 37; `ARC_Capture`; Shortcuts "Hold Command and Shift to start a Capture." | Area, full page and portrait screenshots | planned | rationale "Captures" | 35 to 37 no | L |
| Media page | row 173 | Library page of captures | not started | Needs Library | 173 no | M |
| Picture in picture | `ARC_PictureInPicture`; Advanced "Enable Picture in Picture when you leave a video tab" | Video and Meet PiP, auto PiP on leaving the tab | planned | rationale "Picture in picture" | none | L |
| Media controls | `ARC_MediaControlsFeature` (`MiniPlayerFeature`) | Play and pause controls for a playing tab | not started | Nothing in `Sources/` | none | M |
| Sound effects | `ARC_SoundEffects`; Advanced "Play Arc sound effects" | Capture and event sounds | not started | Nothing in `Sources/` | none | S |
| **Site control center and permissions** | | | | | | |
| Site control center | `ARC_SiteControlCenter` | Popover with site settings, Boosts, capture, copy URL, share | planned | rationale "Site control center" | none | M |
| Site permissions | Info.plist permission prompts (anatomy-v 3) | Camera, microphone, location, notifications prompts | not started | No permission handler in `Sources/BrkCEF/ChromePage.swift` | none | M |
| Ad blocker | `ARC_AdBlocking`, `ARCClients_BlockListClient` (EasyList, EasyPrivacy); General pane | Built-in ad, tracker and cookie-banner blocking | not started | Nothing in `Sources/` | none | L |
| Per-site behavior rules | `ARC_WebContentBehaviorConfigurationClient` | Keep-alive list, PiP rules, tab suspension block list | not started | Nothing in `Sources/` | none | S |
| **Air Traffic Control and link routing** | | | | | | |
| Air Traffic Control | Links pane; anatomy-v 3 "Air Traffic Control"; `StorableLinkRouting.json` | Routes send matching links to a chosen space or Little Arc | planned | rationale "Air Traffic Control" | none | M |
| Default browser and links from other apps | row 5; General "is not your default web browser" | Becomes the default browser and handles incoming links | not started | `externalURL` is only a comment in `Sources/BrkDomain/Command.swift` line 204 | 5 no | M |
| **Settings panes** | | | | | | |
| Settings window | row 3; anatomy-m 4.1 (nine panes) | Account, General, Max, Profiles, Shortcuts, Links, Advanced, App Icon | planned | rationale "Settings"; today only `SettingsCommand.autoArchive` exists (`Sources/BrkDomain/Command.swift`) | 3 no | L |
| General pane | anatomy-m 4.2 | Warn before quitting, auto update, previews, ad blocker, translation | not started | Nothing in `Sources/` | none | M |
| Profiles pane | anatomy-m 4.2 | Search engine, document app, download location, archive after | partial | Exists: the "Archive tabs after" picker on the archive page (AP `testThresholdMenuOffersArcsSevenChoices...`). Missing: the pane and the other settings | none | M |
| Shortcuts pane and remapping | anatomy-m 1.14, 2.2; `StorableKeyBindings.json` | Change any shortcut, per-shortcut priority, conflicts shown | planned | rationale "Shortcut remapping"; `ActionID` raw values are already Arc's binding ids (`Sources/BrkDomain/Actions.swift`) | all bound rows | L |
| Advanced pane | anatomy-m 4.2 | Restore windows, sounds, haptics, toolbar URL, window dragging, auto PiP, theme CSS, Boosts, shared quotes, update channel | not started | Nothing in `Sources/` | none | M |
| App Icon pane | anatomy-m 4.2; `ARCClients_BaseAssets` (10 icons) | Pick one of the app icons | not started | Nothing in `Sources/` | none | S |
| **Onboarding, import, account and membership** | | | | | | |
| Onboarding | `ARC_AuthFeature`; anatomy-v 3 "Onboarding" (16 steps) | Welcome, theme, Favorites, ad blocker, Max, import, default browser | planned | rationale "Onboarding" | none | L |
| Arc 101 welcome | row 177; `ARC_WelcomeToArcFeature` (4 videos) | First-window guide with videos | not started | Not in `Sources/BrkDomain/Actions.swift` | 177 no | M |
| Seed tabs for a new profile | `ARC_StorableSidebar` (21 seed tabs) | Starter tabs and favorites | planned | rationale "Onboarding"; today a fresh profile has one Today tab (RS `test_statecodecRestoreOfNullIsAFreshProfile...`) | none | S |
| Import from other browsers | row 6; `ARC_ImportFeature`, `ARC_ImportMenuFeature` | Bookmarks, history, passwords from Chrome, Safari and others | planned | rationale "Import" | 6 no | L |
| Account and sign in | row 13; `ARC_AuthFeature`, `ARC_DeleteAccountFeature`; Account pane | Sign in, name, email, password, delete account | not started | Nothing in `Sources/`; needs a product decision (questions below) | 13 no | M |
| Referrals and membership card | row 4; `ARC_ReferralCodeFeature`, `ARC_MembershipCard` | Share Arc, unlock icons, member card | not started | Nothing in `Sources/`; needs a product decision | 4 no | S |
| Help menu | rows 176 to 189 | Shortcuts guide, release notes, help, restore data, export notes, task manager, troubleshooting | not started | `MenuName` has no Help menu (`Sources/BrkDomain/Actions.swift`) | 177 to 189 no | M |
| Send to Dia | row 34 | Sends the tab to The Browser Company's other browser | not started | Nothing in `Sources/`; probably dropped | 34 no | S |
| **Updates, menu bar and dock tile** | | | | | | |
| Software updates | row 7; `ARC_SoftwareUpdaterClient` (Sparkle); update channels | Checks for and installs updates | not started | Nothing in `Sources/` | 7 no | M |
| Update banner | `ARC_SidebarBanner` `SoftwareUpdateBannerUpdateAvailableView` | Card in the sidebar when an update is ready | not started | Nothing in `Sources/` | none | S |
| About window | row 2; `ARC_AboutWindow` | About panel with credits | not started | App menu built from `Sources/BrkDomain/Actions.swift` has only Hide, Hide Others, Quit | 2 no | S |
| Menu bar coverage | anatomy-m 2.3 (10 menus, 189 items) | Arc, File, Edit, View, Spaces, Tabs, Archive, Extensions, Window, Help | partial | Exists: 8 menus from `MenuName` and 39 actions (`Sources/BrkDomain/Actions.swift`); APP `test_buildsMenusInTableOrder...`. Missing: Extensions and Help menus, the space list in the Spaces menu, about 100 items | see the other rows | M |
| Dock tile | anatomy-m 4.1 (Dock tile plugin plists) | Custom Dock icon behavior | not started | Nothing in `Sources/` | none | S |
| Menu bar status item | anatomy-m 1.10 entry point `statusItem` | Menu bar icon that opens Little Arc | not started | Nothing in `Sources/` | none | S |
| AppleScript | anatomy-m 1.1 (4 classes, 10 commands) | Scripting windows, tabs and spaces | not started | Nothing in `Sources/` | none | M |
| **AI features** | | | | | | |
| ChatGPT in the command bar | row 133; Max "ChatGPT in the Command Bar" | Ask a question from the bar, Opt+Cmd+G | stand-in | Planned replacement: user's own OpenAI key (audit row 2026-10-30T06:53:30Z); nothing built | 133 no | M |
| Ask on Page | Max "Press Command + F on any page to ask a question" | Questions about the current page | stand-in | Same as above; nothing built; needs Find in page | none | M |
| 5-second previews | Max "5-Second Previews" | Link summaries on hover | stand-in | Same as above; nothing built; needs hover cards | none | M |
| Tidy Tabs and Organize Today Tabs | Max `tidyTabs`; anatomy-v 3 "Organize Today Tabs" | Groups Today tabs into folders | stand-in | Same as above; nothing built | none | M |
| Tidy pinned titles and downloads | Max `renamedPinnedTabs`, `renameDownloads` | Shorter tab titles on pin; renamed downloads | stand-in | Same as above; nothing built; downloads first | none | S |
| Instant Links | Max `instantLinks`; `InstantLinks` module | Opens the best result directly from the bar | stand-in | Same as above; nothing built | none | M |
| Browse for Me (Ask Arc) | `ARC_AskArc` | Reads several pages and builds an answer page | stand-in | Same as above; nothing built | none | L |
| Translation | `ARC_Translation` `TranslateBubble`; General translation setting | Translate a page, never-translate lists | stand-in | Planned replacement: a free translation API (audit row 2026-10-30T06:53:30Z); nothing built | none | M |
| Max pane | anatomy-m 4.2 "Max" | Switches for each AI feature and the API key | stand-in | Nothing built; needs the settings window | none | S |
| **Sync** | | | | | | |
| Sidebar sync | Account "Arc Sync", "Sync Sidebar with iCloud"; `ARC_SidebarSyncCloudKit`; `StorableSidebar.sidebarSyncState` | Spaces, pinned tabs and favorites synced across Macs | stand-in | Planned replacement: local-folder sync (audit row 2026-10-30T06:53:30Z); nothing built | none | L |
| Sharing by link | `ARC_SharableObjectsFeature`; "Share Split View…"; Easel sharing | Share a space, folder, tab set or Easel by link | not started | Nothing in `Sources/`; needs a server or a product decision | none | M |
| **Cross-cutting** | | | | | | |
| Saved state and repair | anatomy-m 1.3 | JSON stores, versioned, repaired on load | done | RS `test_statecodec...` (6 tests), `testRestoreRepairsAStoredSplit`, APP `test_aStaleDebouncedWriteNeverOverwritesAFlush`; `Sources/BrkDomain/Codec.swift` | none | none |
| Clean quit with many pages | (Brk need) | No crash on quit | done | APP `test_orderedQuitFlushesBeforeShutdown...`; W2's gate: 15 of 15 clean quits (audit row 2026-10-30T11:44:44Z); scenario N4 has not run yet | 14 yes (`quitArc`) | S: run N4 |
| E2E report on the real app | `docs/design/swift/module-map.md` "E2E scenarios" | (Brk need) proof that each scenario passes | partial | Exists: 24 scenarios in `Sources/BrkE2E/`. Missing: the runner traps before writing `7adf40f551:verify/swift/REPORT.md`; N1, R2, R3 failed; N2 to N4 never ran (`verify/swift/logs/`) | none | S |
| Pixel identity with Arc | user decision "pixel-identical UI" (audit row 2026-10-30T06:53:30Z); `docs/arc-anatomy/layout-constants.md` | Every screen matches Arc | not started | N3 compares frames with our constants only; no capture of the real Arc exists to compare against | none | L |

## Counts per status

Counted from the status column of the ledger above (148 rows) with an awk one-liner over this file.

| Status | Rows |
|---|---|
| done | 27 |
| partial | 33 |
| planned | 21 |
| stand-in | 10 |
| not started | 57 |

`done` rows cluster in the core loop (sidebar, tabs, pinned, Today, archive, split, spaces, command bar basics, restore). Most rows outside that loop are `planned`, `stand-in` or `not started`.

## The ten largest missing pieces, in build order

Foundations first: each item lists what later items need from it.

1. **Settings window and settings model** (L). `Doc.settings` today holds one value. Profiles, Links (Air Traffic Control, Peek, Little Arc), Shortcuts, Max and Advanced all need a pane to live in.
2. **Profiles and incognito** (L). A Chromium request context per profile, per-profile Favorites, search engine, archive time and downloads. Spaces, extensions, import and incognito all hang off this.
3. **More window kinds and external links** (L). A second standard window, then Little Arc and Peek through the scratch-container seam that already exists (`ContainerScope`), plus default-browser handling (`externalURL`) and Air Traffic Control routes, which decide where outside links land.
4. **Command bar and menu completeness, with shortcut remapping** (L). Every menu item searchable, search suggestions, top domains, site search, the missing ~100 menu items, Extensions and Help menus, and the Shortcuts pane with conflicts.
5. **Library with Downloads, History and Media** (L). One page host for downloads, history, captures, Easels and Notes, Boosts and the existing Archive.
6. **Extensions, site control center, permissions, ad blocker** (L). Toolbar buttons and picker, the per-site popover, permission prompts, EasyList blocking.
7. **Onboarding and import** (L). Welcome flow, Arc 101, seed tabs, import of bookmarks, history and passwords from other browsers.
8. **Boosts** (XL). Per-site CSS and JavaScript injection, Zap, editor, gallery, install dialogs.
9. **Easels and Notes** (XL). Native editors in content cards, sidebar rows, export.
10. **AI stand-ins and local-folder sync** (XL). The Max features, Browse for Me and translation on the user's own key or API, then sidebar sync through a local folder.

Picture in picture, captures, media controls, hover cards and the theme editor are each L and come right after these ten. Before any of it, the e2e runner has to finish a run and N1, R2 and R3 have to pass, because that is how every item above gets proven.

## Decisions after this snapshot

The user chose Swift from scratch, the name Brk, local Claude or Codex command-line tools for AI, and file export instead of share links. Account, membership, and referral screens are dropped. The updater waits. Arc was installed for comparison, but no authenticated reference session has been captured. Integration defaults assign Shift+Cmd+N to Incognito and omit Send to Dia. These decisions replace the corresponding questions from the wave-1 snapshot.

## Remaining product choices

- First launch: reproduce Arc's 21 seed tabs (they point at The Browser Company's pages), use our own, or start with one tab as now?
- Notes: Arc itself is retiring Notes ("We've phased out Arc Notes"). Build them anyway?
- Translation: which free API (for example a self-hosted LibreTranslate)?
- Local-folder sync: which folder (iCloud Drive, Dropbox, any folder), and what happens when two Macs change the same space?
- Popups that need `window.opener` (sign-in windows) currently open as tabs and lose it. Is that acceptable until a later wave?
