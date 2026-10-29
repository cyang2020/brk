# Arc 1.170.0 anatomy: domain model, menus, features, and settings

## About this report

This report describes how Arc for macOS (version 1.170.0, build 89123) organizes its data, its menu bar and keyboard shortcuts, its feature bundles, and its settings. It is written for someone rebuilding Arc's UI.

Everything here comes from reading the shipped files. Arc was never launched and none of its files were executed.

### How to read the evidence pointers

Each claim ends with a pointer and a label.

- `ev/...` means a file under `/Users/administrator/.t3/projects/brk/.audit/arc-evidence/a/`. A `:N` suffix is a line number in that file.
- `app/...` means a file under `/Users/administrator/.cache/arc-target/Arc.app/Contents/`.
- **observed** means the fact is read directly from a shipped file.
- **inferred** means it is my reading of observed names or structure. It is likely, but not proven.
- **unknown** means static files do not answer the question.

### Target identity

- Arc 1.170.0, build 89123, commit `Release-89123-9f5625b3740d579b8dfd1e30e19a452433ae5c8c`, built 21 Oct 2026. Bundle id `company.thebrowser.Browser`, minimum macOS 13.0. `ev/info-plist.txt:3-5,34,38,69,84` (observed)
- The app class is `Arc.BrowserApp` and the main nib is `MainMenu`. AppleScript is enabled through `Arc.sdef`. `ev/info-plist.txt:85,99,101,108` (observed)
- Main binary `app/MacOS/Arc` is universal (x86_64 and arm64). The arm64 slice UUID is `BE2EB88A-675C-357B-8143-840A9196E154`, and the universal file's SHA-256 is `25af5f4eaaae5aca25021f2737e90cc4d41fdf195c4a5c4012ea31a1bba4b86a`. `ev/rea-inspect-macho-arc.json` (observed)
- `app/Frameworks/ArcCore.framework` is about 500 MB and is most likely the embedded Chromium layer. This report does not analyze it. `ev/frameworks-sizes.txt:1` (observed size; role inferred)

### Method and tool notes

1. **Menu nib.** I ran `rea decode-interface-builder`, which decoded 678 objects in `MainMenu.nib`. REA's graph leaves out the NSArray objects that hold menu item order, so I also wrote a small NIBArchive reader (`ev/scripts/nibarchive.py`, `ev/scripts/menutree.py`). Both tools agree on all 219 menu items' key equivalents and modifier masks, with 0 mismatches. `ev/crosscheck-rea-vs-nibarchive.txt` (observed)
2. **REA reports every boolean in this nib inverted.** For example, it reports "Boost Gallery" as not hidden. My reader's "is separator" flag lands on exactly the 30 empty-title items only when NIBArchive value type 5 is read as true, so I used my reader for the hidden, disabled, separator, and alternate flags. `ev/crosscheck-rea-vs-nibarchive.txt`, `ev/mainmenu-nibarchive-dump.jsonl` (observed)
3. **Swift types.** The main binary is stripped: its symbol table has only 8,508 entries, 7,646 of them imports and 453 Swift symbols, far too few to describe the app. It still ships Swift reflection metadata. `ev/nm-arc-arm64.txt` `ev/scripts/swiftmeta.py` reads the type list (`__swift5_types`, `__swift5_protos`) and the stored-field records (`__swift5_fieldmd`), resolves the in-binary references, and demangles names with `xcrun swift-demangle`. Result: 11,658 types and 39,631 stored fields or enum cases. `ev/swift-types-arc-arm64.tsv`, `ev/swift-fields-arc-arm64.tsv` (observed)
4. **Limits of the field lists.** They show stored properties and enum cases only. Methods and computed properties are not in this metadata. In the evidence files, a `[var]` tag means the field is declared `var`; no tag means `let`. 361 of 39,631 field types (0.9%) could not be fully demangled. They appear as `mangled:` with the real type names in angle brackets. `ev/swift-fields-arc-arm64.tsv` (observed)
5. **Strings.** `strings -arch arm64` output is in `ev/strings-arc-arm64.txt`. Swift stores strings of 15 bytes or less inside the code, so short identifiers and short labels (for example "12 hours") do not appear there. (inferred from how Swift compiles string literals)
6. **Assets.** Asset catalogs were listed with `xcrun assetutil --info`. `ev/assetutil/*.json`, summary in `ev/bundle-asset-names.txt` (observed)

## 1. Domain model

### 1.1 AppleScript dictionary (complete)

`Arc.sdef` has a single suite, "Standard Suite" (code `core`). It defines 4 classes and 10 commands. The line numbers below refer to `ev/Arc.sdef.xml`, a byte-for-byte copy of `app/Resources/Arc.sdef`. The scripting code lives in `AppDelegate+Applescript.swift`. `app/Resources/README.md` (observed)

In the sdef format, a property or element with no `access` attribute is read-write by default. The rows marked "rw (default)" rely on that rule. (inferred from the sdef format)

**Class `application`** (code `capp`, Cocoa class `NSApplication`) `ev/Arc.sdef.xml:31-47` (observed)

| Kind | Name | Code | Type | Access | Cocoa key or method | Notes |
|---|---|---|---|---|---|---|
| element | window | | window | rw (default) | `appleScriptWindows` | Ordered front to back |
| element | tab | | tab | w | `appleScriptTabs` | "Write-only collection that allows you to create new Little Arc tabs" |
| property | name | `pnam` | text | r | | |
| property | frontmost | `pisf` | boolean | r | `isActive` | |
| property | version | `vers` | text | r | | |
| responds to | quit | | | | `handleQuitScriptCommand:` | No `quit` command element is defined in this sdef |

**Class `window`** (code `WiND`, plural `windows`, Cocoa class `AppleScriptWindowWrapper`) `ev/Arc.sdef.xml:53-109` (observed)

| Kind | Name | Code | Type | Access | Cocoa key or method | Notes |
|---|---|---|---|---|---|---|
| element | tab | | tab | rw | `appleScriptTabs` | Tabs in this window |
| element | space | | space | rw (default) | `appleScriptSpaces` | Spaces reachable in this window |
| property | id | `ID  ` | text | r | `id` | |
| property | name | `pnam` | text | r | `title` | |
| property | index | `pidx` | integer | rw (default) | `orderedIndex` | Front-to-back order |
| property | closeable | `hclb` | boolean | r | `hasCloseBox` | |
| property | minimizable | `ismn` | boolean | r | `isMiniaturizable` | |
| property | minimized | `pmnd` | boolean | rw (default) | `isMiniaturized` | |
| property | resizable | `prsz` | boolean | r | `isResizable` | |
| property | visible | `pvis` | boolean | rw (default) | `isVisible` | |
| property | zoomable | `iszm` | boolean | r | `isZoomable` | |
| property | zoomed | `pzum` | boolean | rw (default) | `isZoomed` | |
| property | active tab | `acTa` | tab | r | `activeTab` | |
| property | active space | `acSp` | space | r | `activeSpace` | |
| property | incognito | `inco` | boolean | rw (default) | `isIncognito` | |
| property | mode | `mode` | text | rw (default) | `mode` | "normal" or "incognito"; can be set only once, when the window is created |
| responds to | close | | | | `close:` | |

**Class `tab`** (code `tAbB`, plural `tabs`, Cocoa class `AppleScriptTabWrapper`) `ev/Arc.sdef.xml:139-175` (observed)

| Kind | Name | Code | Type | Access | Cocoa key or method | Notes |
|---|---|---|---|---|---|---|
| property | id | `ID  ` | text | r | `id` | |
| property | title | `pnam` | text | r | `title` | |
| property | URL | `URL ` | text | rw | `URL` | |
| property | loading | `ldng` | boolean | r | | |
| property | location | `loca` | text | rw (default) | `location` | "topApp", "pinned", or "unpinned" |
| responds to | select, go back, go forward, reload, stop, execute, close | | | | `select:`, `goBack:`, `goForward:`, `reload:`, `stopLoading:`, `executeJavascript:`, `close:` | |

**Class `space`** (code `sPaC`, plural `spaces`, Cocoa class `AppleScriptSpaceWrapper`) `ev/Arc.sdef.xml:181-195` (observed)

| Kind | Name | Code | Type | Access | Cocoa key or method |
|---|---|---|---|---|---|
| property | id | `ID  ` | text | r | `id` |
| property | title | `pnam` | text | r | `title` |
| element | tab | | tab | rw | `appleScriptTabs` |
| responds to | focus | | | | `focus:` |

**Commands** `ev/Arc.sdef.xml` (observed)

| Command | Code | Direct parameter | Other parameters | Result | Lines |
|---|---|---|---|---|---|
| make | `corecrel` (`NSCreateCommand`) | none | `new` (`kocl`, type); `with properties` (`prdt`, record, optional) | specifier | 9-19 |
| count | `corecnte` (`NSCountCommand`) | specifier | `each` (`kocl`, type, optional) | integer | 21-29 |
| close | `coreclos` | specifier | | | 49-51 |
| select | `CrSelect` | the tab | | | 111-113 |
| go back | `CrSuBack` | the tab | | | 115-117 |
| go forward | `CrSuFwd ` | the tab | | | 119-121 |
| reload | `CrSuRlod` | the tab | | | 123-125 |
| stop | `CrSustop` | the tab | | | 127-129 |
| execute | `CrSuExJa` | the tab | `javascript` (`JvSc`, text) | text | 131-137 |
| focus | `SpaFocus` | the space | | | 177-179 |

The wrapper classes behind these objects are thin. `AppleScriptTabWrapper` holds a `SidebarItem`, `AppleScriptSpaceWrapper` holds a `SpaceModel`, and `AppleScriptWindowWrapper` holds a `BrowserWindow` plus its state store. `ev/types-applescript-wrappers.txt:1-11` (observed). A scripting "tab" is therefore any sidebar item, and "location" is the same three-value context as `BaseModels.SidebarItemContextType` (topApp, pinned, unpinned). `ev/types-basemodels-sidebar-core.txt:424` (inferred)

### 1.2 Architecture in one paragraph

Arc's model code is split into many Swift modules. The core models live in `BaseModels` (524 types), `ADKModels`, `SidebarDataStore`, `SharedWindowFeature`, `WindowContents`, and `Arc` (515 types). `ev/swift-types-arc-arm64.tsv` (observed). Window state is held in ComposableArchitecture stores: `BrowserWindow` holds `store: Store<WindowState, WindowAction>`, and most features are a `State` plus `Action` pair. `ev/types-arc-window-state.txt:8-10` (observed). The UI is AppKit view controllers built in code (`XiblessViewController`) that host SwiftUI views where needed (`ThemeAwareHostingController`). `ev/classes-arc-module.txt` (observed)

### 1.3 What is saved to disk

The binary names these JSON stores, one per feature: `StorableSidebar.json`, `StorableWindows.json`, `StorableArchive.json`, `StorableArchiveItems.json`, `StorableKeyBindings.json`, `StorableProfiles.json`, `StorableProfileContainers.json`, `StorableLiveData.json`, `StorableHome.json`, `StorableLibrary.json`, `StorableLinkRouting.json`, `StorableCaptures.json`, `StorableBoostsData.json`, `StorableFeatureFlags.json`, `StorableAuthState.json`, `StorableSessionRestorationData.json`, `StorableCommandBarAdditionalRanking.json`, `StorableTodosData.json`, `StorableDownloadMetadata.json`, and a few sync and debug stores. `ev/strings-arc-arm64.txt:547134-547175` (observed)

| Store type | Stored fields | File it most likely maps to | Evidence | Label |
|---|---|---|---|---|
| `StorableSidebar.StorableSidebar` | `version`, `sidebar: AppSidebarReducerState`, `sidebarSyncState: ZoneSyncData?`, `firebaseSyncState` | `StorableSidebar.json` | `ev/types-storage-keybindings-littlearc.txt:147` | observed fields; file mapping inferred |
| `StorableWindows.StorableWindows` | `version`, `sidebarViewPreferences?`, `windows: [CodableWindowData]?`, `lastFocusedSpaceID?`, `platformData?` | `StorableWindows.json` | `ev/types-storage-keybindings-littlearc.txt:154` | observed fields; file mapping inferred |
| `StorableArchive.StorableArchive` | `version`, `autoArchiveStartTime: Date?` | `StorableArchive.json` | `ev/types-storage-keybindings-littlearc.txt:48` | observed fields; file mapping inferred |
| `ArchiveDataStoreClient.StorableArchivedItems` | `version`, `items: OrderedDictionary<Identifier<SidebarItem>, ArchivedItem>` | `StorableArchiveItems.json` | `ev/types-storage-keybindings-littlearc.txt:66` | observed fields; file mapping inferred |
| `KeyBindings.StorableKeyBindings` | `version`, `userOverrides: [KeyBinding]` | `StorableKeyBindings.json` | `ev/types-storage-keybindings-littlearc.txt:43` | observed fields; file mapping inferred |
| `Storable.BackupPolicy` | `interval`, `duration`, `maxAllowableBackups` | backup copies of the stores | `ev/types-storage-keybindings-littlearc.txt:1` | observed fields; role inferred |

### 1.4 The sidebar tree (core types)

**Short version.** The whole sidebar is one flat dictionary of `SidebarItem` records keyed by ID. A tree is built from each item's `parentID` and its ordered `childrenIds`. What an item is (tab, folder, split view, note, and so on) is decided by its `data` enum. Spaces are separate `SpaceModel` records that point at "container" items for their pinned and unpinned sections. Favorites are one container item per profile. Normal windows share one global `SidebarContainer`; each incognito, Little Arc, and standalone window gets its own. The fields are observed; how they fit together is my reading of the types (inferred). `ev/types-basemodels-sidebar-core.txt`, `ev/types-window-sidebar-support.txt:87`

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `BaseModels.SidebarItem` (struct) | `id: Identifier<SidebarItem>`, `title: String?`, `childrenIds: OrderedSet<Identifier<SidebarItem>>`, `parentID?`, `data: SidebarItemData`, `createdAt: Date`, `isUnread: Bool`, `originatingDevice: String?` | One node in the sidebar tree | `ev/types-basemodels-sidebar-core.txt:406` | observed |
| `BaseModels.SidebarItemData` (enum) | `tab(SidebarTab)`, `list(SidebarList)`, `arcDocument`, `easel`, `itemContainer(SidebarItemContainer)`, `welcomeToArc`, `splitView(SidebarSplitViewData)`, `sharedObject`, `instantLinks`, `tabGroup`; old keys `archiveContent`, `download`, `arcSearch` | The kind of a sidebar item and its payload | `ev/types-basemodels-sidebar-core.txt:96` | observed |
| `BaseModels.SidebarItemContainer` | `containerType: topApps(Profile)` or `spaceItems(Identifier<SpaceModel>)` | A root node: either a profile's favorites, or one section of a space | `ev/types-basemodels-sidebar-core.txt:86-90` | observed cases; role inferred |
| `BaseModels.SidebarContainer` | `items: [Identifier<SidebarItem> : SidebarItem]`, `spaces: OrderedDictionary<Identifier<SpaceModel>, SpaceModel>`, `topAppsContainerIDs: [Profile : Identifier<SidebarItem>]`; JSON keys also include `activeSpaceIDs`, `pendingSpaceID`, `topAppsContainerID` | All items and spaces for one sidebar, in order | `ev/types-basemodels-sidebar-core.txt:289` | observed |
| `SidebarContainer.SidebarMutationError` | `missingContainer`, `itemNotFound`, `itemAlreadyExists`, `spaceNotFound`, `invalidIndex`, `invalidHierarchy` | Edit validation | `ev/types-basemodels-sidebar-core.txt:237` | observed |
| `BaseModels.SidebarContainerType` | `global`, `incognito(WindowID)`, `littleBrowser(WindowID)`, `standalone(WindowID)` | Which sidebar a window uses. Normal windows share `global`; the others are per window | `ev/types-basemodels-sidebar-core.txt:300` | observed cases; sharing inferred |
| `SidebarDataStore.AppSidebarReducerState` | `containers: [SidebarContainerType : SidebarContainer]` | Every sidebar in the app | `ev/types-window-sidebar-support.txt:87` | observed |
| `BaseModels.SidebarMutation` | `insert(item, strategy)`, `upsert`, `rawDelete`, `move(itemID, strategy, indexingStyle)`, `delete`, `updateItem(itemID, updater)`, `insertSpace(space, index)`, `upsertSpace`, `moveSpace`, `deleteSpace`, `sortSpaces`, `updateSpace` | The full list of sidebar edit operations | `ev/types-basemodels-sidebar-core.txt:224` | observed |
| `BaseModels.SidebarInsertionStrategy` | `absolute(SidebarLocation)` or `relative(targetID, before or after)` | Where an insert or move lands | `ev/types-basemodels-sidebar-core.txt:392-397` | observed |
| `BaseModels.SidebarLocation` | `parent: Identifier<SidebarItem>`, `index: Int` | A position in the tree | `ev/types-basemodels-sidebar-core.txt:439` | observed |
| `BaseModels.SidebarItemContextType` | `topApp`, `pinned`, `unpinned` | Which section an item sits in | `ev/types-basemodels-sidebar-core.txt:424` | observed |
| `BaseModels.SidebarCustomIcon` | `emoji(Character)`, `icon(SidebarIconType)`, `symbol(String)` | User-chosen icon for a tab, folder, split, or space | `ev/types-basemodels-sidebar-core.txt:317` | observed |
| `BaseModels.SidebarIconType` | 61 named icons, for example `star`, `bookmark`, `heart`, `flag`, `folder`, `calendar`, `mail`, `terminal`, `egg` | Built-in icon set | `ev/types-basemodels-sidebar-core.txt:321` | observed |
| `BaseModels.TablistItem` | `sidebarItem(id, type)` or `accessory(TablistAccessoryViewType)` | One row in the sidebar outline view | `ev/types-basemodels-sidebar-core.txt:493` | observed |
| `BaseModels.SelectableItemInfo` | `single(itemID)` or `container(itemID, children)` | What is selected | `ev/types-basemodels-sidebar-core.txt:221` | observed |
| `SidebarDataStore` module | `SidebarDataStore` (protocol), `SidebarDataStoreImpl`, `SidebarDataStoreTransaction`, `SidebarDataStoreChangeSet`, `SidebarDataStoreLiveQuery` | Transactions and live queries over the sidebar | `ev/swift-types-arc-arm64.tsv` | observed names; role inferred |

### 1.5 Spaces

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `BaseModels.SpaceModel` | `id`, `title: String?`, `containerIDs: [SpaceModel.ContainerType : Identifier<SidebarItem>]`, `customInfo`, `profile: Profile` | One space: its name, icon, theme, profile, and section roots | `ev/types-basemodels-sidebar-core.txt:465` | observed |
| `SpaceModel.ContainerType` | `pinned`, `unpinned(UnpinnedContainerType)` | The two sections of a space | `ev/types-basemodels-sidebar-core.txt:471` | observed |
| `SpaceModel.ContainerType.UnpinnedContainerType` | `desktop(machineID: String, windowID: WindowID)`, `shared` | The unpinned ("Today") section can be scoped to one machine and window, or shared | `ev/types-basemodels-sidebar-core.txt:474` | observed cases; meaning inferred |
| `SpaceModel.CustomInfo` | `iconType: SidebarCustomIcon?`, `windowTheme: WindowTheme?` | Space icon and theme | `ev/types-basemodels-sidebar-core.txt:477` | observed |
| `SpaceModel.MachineFilter` | `machine(MachineID)`, `all`, `current` | Filtering spaces by device | `ev/types-basemodels-sidebar-core.txt:388` | observed |
| `BaseModels.SidebarSpaceDataModel` | `space`, `resolvedTitle`, `rootItemIDs`, `items` | A ready-to-display copy of one space | `ev/types-basemodels-sidebar-core.txt:460` | observed |
| `SharedWindowFeature.SidebarSpaceState` | about 60 fields, including `spaceID`, `unpinnedContainerID`, `selectedItemInfo`, `expandedItems`, `sidebarMode`, `sidebarPresentation`, `pinnedSectionExpansionState`, `hasTopApps`, `canAutoOrganizeTodayTabs`, `profile`, `themeContext` | Everything one space's sidebar page needs to draw | `ev/types-sidebarspacestate.txt:1` | observed |
| `SidebarSpaceState.SpaceContainerType` | `home`, `sidebar` | Space shown in the sidebar or in Library (Home) | `ev/types-sidebarspacestate.txt:66` | observed cases; meaning inferred |
| `SpaceCreation.SpaceCreation.State` | `options`, `title?`, `selectedProfile`, `customInfo`, `spaceStyleEditor`, `phase: editing, animating, complete` | The new-space flow | `ev/types-misc-ui.txt:46-56` | observed |
| `SidebarDock.SidebarDockViewController.ViewState.Item` | `identifier`, `spaceID?`, `iconType`, `title`, `profile`, `keyboardShortcut: ARCKeyboardShortcut?` | The row of space icons at the bottom of the sidebar | `ev/types-extra.txt:35` | observed fields; placement inferred |
| `Arc.SpacesMainMenuProvider` | NSObject class; its ViewState has `spaces: OrderedDictionary<Identifier<SpaceModel>, SpaceModel>` | Fills the Spaces menu with the space list at runtime | `ev/classes-arc-module.txt`, `ev/swift-fields-arc-arm64.tsv` | inferred |

### 1.6 Tabs, pinned tabs, favorites, folders

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `BaseModels.SidebarTab` | `savedURL: URL?`, `savedFavicon`, `savedTitle`, `savedMuteStatus` (`allowAudio` or `mute`), `customInfo` (icon), `referrerID`, `activeTabBeforeCreationID`, `timeLastActiveAt`, `liveItemID`; old keys `url_legacy`, `title_legacy`, `pageInfoWhenSaved_legacy` | A tab's saved identity. "Saved URL" is what "Reset Tab to Original URL" returns to | `ev/types-basemodels-sidebar-core.txt:177-205` | observed fields; reset meaning inferred |
| `Arc.TabCellState` | `titleSourceInfo`, `subtitle`, `isCurrentItem`, `isAudible`, `isMuted`, `canResetTab`, `icon`, `closeButtonConfiguration`, `unreadBadgeType`, `isLoadingAITitle`, `isRecording`, `dropTargetRegion`, `isTabShareable`, and more | What one tab row in the sidebar shows | `ev/types-sidebar-cells.txt:44` | observed |
| `BaseModels.CloseItemsSource` | 21 sources, including `closeItemHotkey`, `sidebarCell`, `autoArchive`, `clearUnpinnedTabs`, `deleteSpace`, `modalItemSwitcher`, `sync` | Why a tab was closed or archived | `ev/types-basemodels-sidebar-core.txt:1` | observed |
| `SharedWindowFeature.DeselectedItemsState` | `deselectedItemIDs`, `reopenableItemID` | Pinned or favorite tabs that were "closed" but stay in the sidebar | `ev/types-window-sidebar-support.txt:115` | observed fields; meaning inferred |
| `BaseModels.SidebarTabGroup` | `title: String` | A titled group of tabs | `ev/types-basemodels-sidebar-core.txt:208` | observed |
| `ModalItemSwitcher.CycleRecentTabsTarget` | `exact(index)`, `previous`, `next`, `first`, `last` | The Ctrl+Tab recent-tab switcher | `ev/types-extra.txt:26` | observed cases; tie to Ctrl+Tab inferred |
| Pinned: `SpaceModel.ContainerType.pinned` | see 1.5 | Pinned section root per space | `ev/types-basemodels-sidebar-core.txt:471` | observed |
| Pinned: `BaseModels.CollapsedPinnedSection` | `id: Identifier<SpaceModel>`, `peekedItemID?` | A collapsed pinned section, with one item allowed to show | `ev/types-basemodels-sidebar-core.txt:41` | observed |
| Pinned: `SidebarSpaceState.PinnedSectionExpansionState` | `expanded`, `collapsed`, `peeked` | Pinned section display state | `ev/types-sidebarspacestate.txt:62` | observed |
| Favorites: `SidebarItemContainer.ContainerType.topApps(Profile)` and `SidebarContainer.topAppsContainerIDs: [Profile : ...]` | see 1.4 | Favorites ("top apps") are one container per profile, so every space that uses the same profile shows the same favorites | `ev/types-basemodels-sidebar-core.txt:88,289` | observed fields; sharing inferred |
| Favorites: `BaseModels.TopApp` | `whatsapp`, `twitter`, `gmail`, `gcal`, `notionCalendar`, `spotify`, `youtube`, `notion`, `slack`, `figma`, `outlook` | Sites with special favorite tiles (badges and subtitles) | `ev/types-misc-ui.txt:4` | observed cases; role inferred |
| Favorites: `WindowState` fields | `topAppsSubtitleDisabledHosts`, `topAppsBadgingDisabledHosts`, `topAppsEmptyStateDismissedForProfiles` | Per-site badge and subtitle switches | `ev/types-arc-window-state.txt:69` | observed |
| Folders: `BaseModels.SidebarList` | `customInfo` (icon), `automaticLiveFolderData?` | A folder. The menu action for "New Folder…" is `newList:` | `ev/types-basemodels-sidebar-core.txt:122`, `ev/mainmenu-tree.txt` | observed |
| Folders: `BaseModels.AutomaticLiveFolderData` | `dataSource: github`, `lastFetch`, `hiddenItems`, `filter` | A "live folder" filled from GitHub pull requests | `ev/types-basemodels-sidebar-core.txt:23-30` | observed |
| Folders: `SharedWindowFeature.SidebarItemExpansionState` | `expanded` or `peeked(OrderedSet<ID>)`; held per window in `WindowState.expandedItems` | Folder open or closed, per window | `ev/types-window-sidebar-support.txt:99` | observed |
| Other item kinds | `SidebarEasel` (`easelID`, `shareStatus`, `title`), `SidebarArcDocument` (`arcDocumentID`, `isEditable`), `SidebarSharedObject` (`space`, `tab`, or `tabs` shared by link), `SidebarInstantLinks` (`status`) | Easels, Notes, shared objects | `ev/types-basemodels-sidebar-core.txt:49-140` | observed |

### 1.7 Split view and Peek

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `BaseModels.SidebarSplitViewData` | `itemWidthFactors: [Identifier<SidebarItem> : CGFloat]`, `layoutOrientation: horizontal or vertical`, `timeLastActiveAt`, `customInfo`, `focusItemID` | A split view saved as one sidebar item whose children are the panes | `ev/types-basemodels-sidebar-core.txt:158-168` | observed fields; child panes inferred |
| `WindowContents.SplitViewState` | `windowContentIDs: OrderedSet<WindowContentID>`, `layoutOrientation`, `interactionState`, `focusedContentID` | The live split in a window | `ev/types-splitview-peek.txt:17-28` | observed |
| `WindowContents.WindowSplitViewLayout` | `paneWidths: [CGFloat]` | Pane sizes to restore | `ev/types-window-sidebar-support.txt:93` | observed |
| `WindowContentPresentationDisposition.SplitViewTarget` | `paneAtIndex(Int)`, `newPane(index, after, before, last, afterFocusedPane)`, `pane(WindowContentID)`, `replaceAllPanes`, `firstEmptyOrNewPane` | Where new content opens in a split | `ev/types-splitview-peek.txt:1-12` | observed |
| `SidebarUI.SplitViewCellState` | `layoutStyle: childItems(...)` or `customInfo(title, icon)`, `closeButtonConfiguration`, and more | How a split appears as one sidebar row | `ev/types-sidebar-cells.txt:109` | observed |
| `WindowContentPresentationDisposition.modalV2(ModalV2Target)` | `ModalV2Target`: `source`, `presentationSource`, `animated` | Opening content as a Peek window | `ev/types-splitview-peek.txt:13`, `ev/types-windowcontents.txt:1` | observed cases; "modalV2 is Peek" inferred from Links settings text "Open a Peek window…" (`ev/strings-arc-arm64.txt:560704`) |
| `WindowContents.ModalWindowContentStateV2` | `modalByWindowContent`, `sourceToWindowContentMap`; `ModalState`: `source`, `presentationState`, `presentationSource` | Open Peek windows | `ev/types-splitview-peek.txt:58-64` | observed |

### 1.8 Windows

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `Arc.WindowsState` | `restorableWindows`, `persistedWindows: IdentifiedArray<WindowID, PersistedWindowState>`, `sidebarViewPreferences`, `sidebar: AppSidebarReducerState`, `keyBindingsState`, `lastFocusedSpaceID`, `spacesWithCollapsedPinnedSections`, `persistedLiveFoldersState`, `pictureInPictureState`, `softwareUpdateState`, `isRestoringSession`, and more | App-wide state shared by all windows | `ev/types-arc-window-state.txt:35` | observed |
| `Arc.WindowState` | About 100 fields, including `id`, `focusedSpaceID`, `layoutPresentation` (`home` or `spaces`), `sidebarWidth`, `sidebarMode`, `windowContentsState`, `expandedItems`, `multiSelectedItems`, `editingItem`, `itemLastActiveDates`, `lastActiveTabsPerSpace`, `fullscreen`, `style`, `toasts`, `captureState`, `findInPageQuery`, `stayOnTop`, `modalItemSwitcherPresentation`, `linearTabSwitcherState` | Everything about one browser window | `ev/types-arc-window-state.txt:69-172` | observed |
| `Arc.PersistedWindowState` | Same core fields as `WindowState`, without the app-wide copies | The saved form of a window | `ev/types-window-sidebar-support.txt:1` | observed |
| `Arc.BrowserWindow` (NSWindow) | `store: Store<WindowState, WindowAction>`, `viewStore`, `windowButtons`, `lifecycleEligibility`; ViewState: `sidebarMode`, `fullscreen`, `theme`, `isIncognito`, `isStandalone`, `stayOnTop`, `canCycleBetweenSpaces` | The normal browser window | `ev/types-arc-window-state.txt:8-34` | observed |
| `SharedWindowFeature.WindowStyle` | `standard(StandardWindowState)`, `little(PersistedLittleBrowserState)` | Normal window or Little Arc | `ev/types-window-sidebar-support.txt:118` | observed |
| `BaseModels.SidebarMode` | `anchored`, `noChrome` | Sidebar shown, or hidden (the Cmd+S toggle) | `ev/types-basemodels-sidebar-core.txt:445` | observed cases; tie to Cmd+S inferred |
| `BaseModels.SidebarPresentation` | `locked`, `floating`, `hidden` | Hidden sidebar sliding out on hover | `ev/types-basemodels-sidebar-core.txt:448` | observed cases; meaning inferred |
| `SharedWindowsFeature.SidebarViewPreferences` | `sidebarMode`, `sidebarWidth` | Saved sidebar width and mode | `ev/types-window-sidebar-support.txt:127` | observed |
| `SharedWindowFeature.FullscreenState` | `entering`, `expanded`, `exiting` (each with a `FullscreenMode`) | Full-screen transitions | `ev/types-window-sidebar-support.txt:95` | observed |
| `WindowContents.WindowContents.State` | `windowContents: [WindowContentID : WindowContent]`, `splitViewState`, `modalWindowContentV2State`, `windowContentSidebarItemMap: BidirectionalMap<WindowContentID, Identifier<SidebarItem>>` | What the content area shows, and which sidebar item each piece of content belongs to | `ev/types-windowcontents.txt:12` | observed |
| `WindowContents.WindowContent.Blueprint` | `webContent`, `arcDocument`, `easel`, `welcomeTab`, `welcomeToArc`, `placeholder`, `sharedObject` | Kinds of content a pane can host | `ev/types-splitview-peek.txt:50` | observed |
| `ADKModels.WindowID` | `rawValue: String` | Window identity | `ev/types-theme-profile-archive.txt:9` | observed |

### 1.9 Archive and "Today" tabs

The unpinned section of a space is called "Today" in the UI. Supporting strings: "Action to move this tab to the Today section of a space.", "Organize Today Tabs", and "Clear Today tabs". `ev/strings-arc-arm64.txt:559671,541387-541392` (observed). Its menu action is still named `clearExplore:`, which looks like an older name for the same section. `ev/mainmenu-tree.txt` (observed name; history inferred)

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `ArchiveDataStoreClient.ArchivedItem` | `sidebarItem: SidebarItem`, `reason`, `archivedAt: Date`, `source` | One archived tab, keeping the full sidebar item | `ev/types-storage-keybindings-littlearc.txt:61` | observed |
| `ArchiveDataStoreClient.ArchiveReason` | `auto`, `manual`, `clearButton`, `clearTabGroup` | Why it was archived | `ev/types-storage-keybindings-littlearc.txt:51` | observed |
| `ArchiveDataStoreClient.ArchivedItemSource` | `space(Identifier<SpaceModel>)`, `littleArc`, `standaloneSidebar`, `unknown` | Where it came from | `ev/types-storage-keybindings-littlearc.txt:56` | observed |
| `Archive.ArchiveFeature.State` | `autoArchiveStartTime`, `itemsToExclude`, `sidebar`, `autoArchiveLittleArcWindowsEnabled`, `perProfileAutoArchivePrefAvailable` | The auto-archive job | `ev/types-storage-keybindings-littlearc.txt:69` | observed |
| `Archive.AutoArchiveType` | `todayTabs`, `littleArc` | The two things that auto-archive | `ev/types-theme-profile-archive.txt:118` | observed |
| `Archive.AutoArchiveInactiveThreshold` | `twentySeconds` (internal), `oneHour`, `sixHours`, `twelveHours`, `twentyFourHours`, `sevenDays`, `thirtyDays`, `never` | Idle time before archiving | `ev/types-theme-profile-archive.txt:121` | observed |
| `Archive.AutoArchiveTimeThresholdsPerProfile` | `thresholds: [Profile : AutoArchiveInactiveThreshold]` | Per-profile thresholds | `ev/types-theme-profile-archive.txt:130` | observed |
| `BaseHomeComponents.HomePageID` | `downloads`, `archive`, `easelsAndNotes`, `screenshotsAndCaptures`, `boosts`, `spaces` | Library pages; the Archive is one of them | `ev/types-misc-ui.txt:62` | observed |

### 1.10 Little Arc

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `LittleBrowser.LittleBrowser.State` | `id`, `downloads`, `session`, `moveToDestinationInfo`, `profile`, `shouldShowProfileIndicators`, `activeMenuType`, `moveMenuState`, `modalState`, `nuxState` | One Little Arc window | `ev/types-storage-keybindings-littlearc.txt:75` | observed |
| `LittleBrowser.LittleBrowserSession` | `id`, `entryPoint`, `preferredFrame: WindowFrame?`, `startTime` | One opening of Little Arc | `ev/types-storage-keybindings-littlearc.txt:106` | observed |
| `LittleBrowser.LittleBrowserEntryPoint` | `internalLink(URL)`, `externalLink(URL)`, `floatingWindow(URL)`, `mainMenu`, `statusItem`, `globalHotkey`, `sidebarPlusButton`, `browserPopup`, `draggedTab` | Every way Little Arc opens | `ev/types-storage-keybindings-littlearc.txt:96` | observed |
| `Arc.LittleBrowserWindow` (NSPanel) | `littleWindowViewController`, `modalLayoutController`, `layoutState`; ViewState: `currentItemID`, `session`, `theme`, `profile`, `presentModally` | The small floating panel window | `ev/types-arc-window-state.txt:174-200` | observed |
| `SidebarContainerType.littleBrowser(WindowID)` | | Each Little Arc window has its own one-tab sidebar container | `ev/types-basemodels-sidebar-core.txt:300` | observed case; meaning inferred |
| `LittleBrowserMoveToStandardWindowDestination`, `LittleBrowserMoveToListOption`, `LittleBrowserMoveMenu` | | Moving a Little Arc tab into a space or folder | `ev/swift-types-arc-arm64.tsv` | observed names; role inferred |

### 1.11 Command bar, URL inputter, and command search ("Type Travel")

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `CommandBar.CommandBarState` | `inputs`, `destinationType`, `query`, `searchOutput`, `pendingSelection`, `windowID`, `scopedSearchType`, `activeSearchEngines`, `entryPoint`, `currentHighlightedResultIndex`, `searchSuggestionPrivacyState` | The command bar | `ev/types-commandbar.txt:84` | observed |
| `CommandBarState.EntryPoint` | `appMenu`, `contentPanel`, `placeholderClick`, `newStandardWindowOpen`, `newLittleWindowOpen`, `topBarURL`, `sidebarNewTabButton`, `sidebarPlusButton`, `sidebarDoubleClick`, `keyboardShortcutT`, `keyboardShortcutL`, `keyboardShortcutCommandOptionG`, `keyboardShortcutFocusSidebar`, `toggleBetweenTypeTravelAndCommandBar`, `littleArcPlaceholderClick`, `splitViewPaneCreated` | Every way the command bar opens | `ev/types-commandbar.txt:61` | observed |
| `CommandBar.CommandBarDestinationType` | `overrideCurrentTab(showCurrentURL)`, `createNewTab`, `noop` | Cmd+L replaces the current tab; Cmd+T opens a new one | `ev/types-commandbar.txt:43` | observed cases; key mapping inferred |
| `CommandBar.CommandBarLayoutDisposition` | `overCommandBarPlaceholder`, `overFocusedContent`, `centered`, `overContentPanel` | Where the bar is drawn | `ev/types-commandbar.txt:47` | observed |
| `CommandBarSelectionOptions.Action` | `navigateToURL`, `openURL(url, disposition, insertionStrategy, ...)`, `openBrowseForMe`, `openBrowseForMePip`, `openTab`, `executeTypeTravel(candidate, context)`, `executeInstantLinksQuery`, `executeInstantLinksIntentQuery` | What choosing a result does | `ev/types-commandbar.txt:52` | observed |
| `ASE2.TypeTravelCandidate` | `focusSpace`, `moveToSpace`, `moveToFolder`, `menuItem(MenuItemInfo)`, `browserExtension`, `openPreferencePane`, `openFolder`, `moveToTopApps`, `removeFromTopApps`, `createNewFolder`, `toggleSidebar`, `addLeftSplit`, `addRightSplit`, `addTopSplit`, `addBottomSplit`, `muteAllTabs`, `newArcNote`, `openAirTrafficControl`, and more | Action results in the command bar | `ev/types-commandbar.txt:1` | observed |
| `TypeTravel` module | `TypeTravelMainMenuIndex`, `MenuItemSnapshot`, `MainMenuClient`, `WindowTypeTravelReducer` | Indexes main-menu items so they can be searched in the command bar. 114 menu items carry `arcTypeTravelID`, an icon, and search trigger words as runtime attributes | `ev/swift-types-arc-arm64.tsv`, `ev/mainmenu-tree.txt` | observed names and attributes; indexing role inferred |
| `URLInputter.URLInputterFeature.State` | `query`, `selectedIndex`, `suggestions`, `linkTextState`, `selectedItem` | A smaller URL field with suggestions. Which screen uses it is unknown | `ev/types-commandbar.txt:37` | observed fields; usage unknown |

### 1.12 Profiles

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `ADKModels.Profile` | `custom(ProfileID)`, `initial`; JSON keys `default`, `custom` | A browser profile. `initial` is stored as "default" | `ev/types-theme-profile-archive.txt:1-6` | observed cases; key mapping inferred |
| `ADKModels.ProfileID` | `directoryBasename: String`, `machineID: String` | The profile's Chromium data folder on one machine | `ev/types-extra.txt:1` | observed fields; folder meaning inferred |
| `PreferencesFeature.ProfilePreferences.State` | `id: Profile`, `inUse`, `defaultSearchEngine`, `availableSearchEngines`, `searchSuggestEnabled`, `downloadFilePath`, `promptForDownloadFilePath`, `defaultDocumentsApp`, `availableDocumentApps`, `spaceIds`, `disableNewNoteEntryPoints` | Per-profile settings | `ev/types-preferences.txt:220-231` | observed |
| Things keyed by `Profile` | `SpaceModel.profile`, `SidebarContainer.topAppsContainerIDs`, `AutoArchiveTimeThresholdsPerProfile`, `WindowState.browserExtensions`, `WindowState.closedProfiles` | Spaces, favorites, archive timing, and extensions all belong to a profile | `ev/types-basemodels-sidebar-core.txt:465,289`, `ev/types-arc-window-state.txt:69` | observed |
| `ProfilesUI` module | `CreateProfileDialog`, `ChangeProfileDialog`, `DeleteProfileDialog`, `DeleteUnusedProfilesDialog`, `ProfileIndicatorView` | Profile dialogs and the small profile badge | `ev/swift-types-arc-arm64.tsv` | observed names |

### 1.13 Themes and space styles

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `BaseModels.WindowTheme` | `background: AppearanceBasedConfiguration<Background>`, `windowAppearance?`, `primaryColorPalette`, `semanticColorPalette: AppearanceBasedConfiguration<SemanticColorPalette>` | A space's theme | `ev/types-theme-profile-archive.txt:26` | observed |
| `BaseModels.AppearanceBasedConfiguration<A>` | `single(A)` or `appearanceBased(light: A, dark: A)` | One value, or separate light and dark values | `ev/types-theme-profile-archive.txt:11` | observed |
| `WindowTheme.Background` | `style`, `contentOverBackgroundAppearance?`, `isVibrant` | Window background | `ev/types-theme-profile-archive.txt:31` | observed |
| `Background.Style.ColorType` | `basicColor`, `blendedSingleColor`, `blendedGradient` | Background kinds | `ev/types-theme-profile-archive.txt:37` | observed |
| `BlendedGradientConfiguration` | `baseColors: [StorableColor]`, `overlayColors`, `translucencyStyle` (`light`, `dark`, `auto`), `modifiers`, `wheel` (`complimentary` or `analogous`) | Gradient themes | `ev/types-theme-profile-archive.txt:41`, `ev/types-extra.txt:23` | observed |
| `BlendedBackgroundModifiers` | `noiseFactor`, `intensityFactor`, `overlay` (`grain`, `sand`, `denim`, `tweed`) | Grain texture and strength | `ev/types-theme-profile-archive.txt:54,83` | observed |
| `WindowTheme.PrimaryColorPalette` | `tintedLight`, `midTone`, `shaded`, `shadedDark` | Derived accent colors | `ev/types-theme-profile-archive.txt:58` | observed |
| `WindowTheme.SemanticColorPalette` | `foregroundPrimary`, `foregroundSecondary`, `foregroundTertiary`, `maxContrastColor`, `minContrastColor`, `backgroundExtra`, `background`, `focus`, `hover`, `cutoutColor`, `title`, `subtitle` | The named UI colors every view reads | `ev/types-theme-profile-archive.txt:63` | observed |
| `ARCUI.StorableColor` | `colorSpace: extendedSRGB`, `red`, `green`, `blue`, `alpha` | How colors are saved | `ev/types-extra.txt:4-11` | observed |
| `SpaceStyleEditor.SpaceStyleEditor.State` | `primaryColor`, `numberOfColors`, `noiseFactor`, `overlay`, `intensityFactor`, `wheel`, `saturation`, `lightnessRange`, `currentPresetPage`, `darkModeBiasSetting` (`value(CGFloat)` or `forceAppearance(light or dark)`), `undoStack` | The theme editor's controls | `ev/types-misc-ui.txt:20-40` | observed |
| Rendering | `WindowThemeUI` has a Metal background renderer and textures `grain`, `sand`, `denim`, `tweed` (each with a `_metal` version) | Draws the themed background | `ev/bundle-asset-names.txt` (ARC_WindowThemeUI), `ev/swift-types-arc-arm64.tsv` | observed |

### 1.14 Key bindings (model)

| Type | Fields or cases | What it likely owns | Evidence | Label |
|---|---|---|---|---|
| `KeyBindings.KeyBinding` | `action: KeyBindableAction` (`identifier`, `name`), `default: DefaultAttributes?`, `state`, `source`, `priority` | One remappable shortcut | `ev/types-storage-keybindings-littlearc.txt:9-17` | observed |
| `KeyBinding.State` | `valid(ARCKeyboardShortcut)`, `conflict(shortcut, conflictingActions)`, `unset` | Conflicts are a first-class state | `ev/types-storage-keybindings-littlearc.txt:18` | observed |
| `KeyBinding.Source` | `userDefined`, `default` | | `ev/types-storage-keybindings-littlearc.txt:22` | observed |
| `KeyBinding.Priority` | `low`, `promptAfterConsumedByWebView`, `overrideWebView` | Whether Arc or the web page gets the key first | `ev/types-storage-keybindings-littlearc.txt:25` | observed |
| `KeyBinding.DefaultAttributes` | `shortcut`, `priority`, `typeTravelTriggers: [String]` | Defaults that come from the menu nib | `ev/types-storage-keybindings-littlearc.txt:29` | observed |
| `KeyBindings.KeyBindingsState` | `bindings: [String : KeyBinding]`, `shortcutToBinding`, `priorityToShortcuts` | All bindings, looked up both ways | `ev/types-storage-keybindings-littlearc.txt:33` | observed |

### 1.15 UI classes (view layer)

These AppKit classes in the `Arc` module show how the window is built. `ev/classes-arc-module.txt` (observed names and superclasses)

- Window and controllers: `BrowserWindow : NSWindow`, `MainWindowController`, `WindowViewController`, `WindowLayoutController`, `LittleBrowserWindow : NSPanel`, `LittleWindowViewController`.
- Sidebar: `SidebarViewController`, `SidebarPagingContainerViewController` (one page per space, with a custom paging layout), `SidebarSpaceViewController`, `TablistViewController`, and `TablistOutlineView : DiffableDataSourceOutlineView<TablistItem>`. Supporting classes: `SidebarHeaderView`, `SidebarSectionHeaderView`, `SidebarResizeRegionView`, `FloatingSidebarBackgroundView`, `SidebarClearButton`, `SidebarTidyButton`, `PinnedTabSectionEduBanner`.
- Sidebar rows: `TabCellView`, `SplitViewCellView`, `NewTabCellView`, `ArcDocumentCellView`, `EaselCellView`, `SharedObjectCellView`, `WelcomeToArcCellView`, `TabGroupHeaderCellView`. Each row view is a `SelectableCellView<State>` driven by a state struct such as `TabCellState`.
- Content: `WindowContentsContainerViewController`, `WindowContentViewController`, `SplitViewDraggerHandleView`, `ModalV2WindowContentContainerViewController` (Peek), `WindowContentPlaceholderViewController`.
- Command bar placeholder in the sidebar: `CommandBarPlaceholderView`, `CommandBarPlaceholderTextView`, `CommandBarIconView`.
- Space manager: `SpaceManagementView`, `SpaceManagementCollectionViewLayout`, `SpaceManagementAddSpaceView`.

The nesting order above (window, then sidebar paging, then per-space page, then outline view) comes from the class names and field types. (inferred)

## 2. Menu bar and keyboard shortcuts

### 2.1 Source and how to read it

There is one menu nib, `app/Resources/Base.lproj/MainMenu.nib`. Each of the 54 language folders has a `MainMenu.strings`, but each is only 177 to 212 bytes. The 35 that parse as plists hold exactly two titles; in German these are "Bearbeiten" (Edit) and "Kopieren" (Copy). All other menu titles exist only in English in the nib. Whether code translates them at runtime is unknown. `ev/mainmenu-strings-entry-counts.txt`, `ev/de-mainmenu-strings-summary.txt` (observed) The nib has 23 menus and 219 menu items, of which 30 are separators. The table below lists the other 189 items in menu order, so the "Menu path" column is the full menu tree. `ev/mainmenu-tree.txt`, `ev/mainmenu-items.tsv` (observed)

Top-level menus, left to right: **Arc, File, Edit, View, Spaces, Tabs, Archive, Extensions, Window, Help**. Submenus: Arc > Services; Edit > Find, Spelling and Grammar, Substitutions, Transformations, Speech, Format > Font; View > Appearance, Developer; Help > Troubleshooting. `ev/mainmenu-tree.txt` (observed)

How to read the shortcut columns:

- The modifier mask uses AppKit bits: Shift = 131072, Ctrl = 262144, Opt = 524288, Cmd = 1048576. Shortcuts are written Ctrl, Opt, Shift, Cmd, then the key. (observed values; bit meanings are AppKit's)
- When the key is an uppercase letter and the mask has no Shift bit, AppKit treats it as Shift plus that letter. Those rows say "(Shift from uppercase key)". (observed raw key; AppKit rule)
- Special keys: `Left`, `Right`, `Up`, `Down` are arrow keys, `Backtab` is Shift+Tab, `Esc` is Escape, `F12` is function key 12. (observed key codes 0xF702, 0xF703, 0xF700, 0xF701, 0x19, 0x1B, 0xF70F)
- **Hidden** items do not appear in the menu. 28 items are hidden, and for 26 of them the nib sets "key equivalent allowed when hidden", so their shortcuts still work. Use these as real shortcuts. `ev/mainmenu-tree.txt`, `ev/crosscheck-rea-vs-nibarchive.txt` (observed)
- Every action targets the first responder except where marked "(AppDelegate)" or "(NSFontManager)". `ev/mainmenu-tree.txt` (observed)
- Rows with an empty action cell that are not submenu titles, such as "Share Arc" and "Import from Another Browser…", have no action in the nib. Both are wired to outlets on `MainMenuOutlets` (`referralCodeMenuItem`, `importMenuItem`), so code most likely sets their action or submenu at launch. `ev/mainmenu-tree.txt` outlet list (observed outlets; runtime wiring inferred)
- **arcKeyBindingID** and **Priority** come from user-defined runtime attributes on each menu item. 89 items have an `arcKeyBindingID`. Priority is `overrideWebView` on 22 items, `promptAfterConsumedByWebView` on 19, and unset on the rest. `ev/mainmenu-items.tsv` (observed)

### 2.2 How Arc turns menu items into remappable shortcuts

- `KeyBindingMenuManager` registers every menu item that carries an `arcKeyBindingID` as a remappable action, using the nib shortcut as the default. Its error text says: "Tried to double-register a key bindable action from the main menu; `arcKeyBindingID` runtime attributes must be unique." `ev/strings-arc-arm64.txt:547529-547531` (observed text; registration flow inferred)
- User changes are saved as `StorableKeyBindings { version, userOverrides: [KeyBinding] }`, most likely in `StorableKeyBindings.json`. `ev/types-storage-keybindings-littlearc.txt:43`, `ev/strings-arc-arm64.txt:547158` (observed type and file name; mapping inferred)
- The Shortcuts settings pane describes the three priorities. "When shortcuts conflict, Arc wins" matches `overrideWebView`. "Press this shortcut once to use the website's shortcut. Press it twice to use Arc's shortcut" matches `promptAfterConsumedByWebView`. "When shortcuts conflict, the website wins" matches `low`. `ev/strings-arc-arm64.txt:561004-561011` (observed text; name-to-text matching inferred from order)
- Items without an `arcKeyBindingID` are fixed: standard Edit shortcuts (Undo, Redo, Cut, Copy, Paste, Select All, spelling, Bold, Italic, Underline), the duplicate Zoom In and Zoom Out items, and the second "New Tab…" in the Tabs menu. `ev/mainmenu-items.tsv` (observed)
- 114 items also carry `arcTypeTravelID`, `arcTypeTravelIcon` (an SF Symbol name), and `arcTypeTravelTriggers` (search words). These make the item searchable as an action in the command bar. The full attribute text for each item is in `ev/mainmenu-items.tsv` column 7. (observed attributes; command-bar role inferred from `TypeTravelMainMenuIndex`)

### 2.3 Full menu and shortcut table

| # | Menu path | Item | Shortcut | Mask | Action selector | arcKeyBindingID | Priority | Flags | Nib object |
|---|---|---|---|---|---|---|---|---|---|
| 1 |  | Arc |  |  |  |  |  |  | 2166 |
| 2 | Arc | About Arc |  |  | `orderFrontStandardAboutPanel:` |  |  |  | 115 |
| 3 | Arc | Preferences… | Cmd+Comma | 1048576 | `showPreferences: (AppDelegate)` | `viewPreferences` |  |  | 1009 |
| 4 | Arc | Share Arc |  |  |  |  |  |  | 369 |
| 5 | Arc | Set as Default Browser |  |  | `setAsDefaultBrowser:` |  |  |  | 249 |
| 6 | Arc | Import from Another Browser… |  |  |  |  |  |  | 1454 |
| 7 | Arc | Check for Updates… |  |  | `checkForUpdates: (AppDelegate)` |  |  |  | 1337 |
| 8 | Arc | Services |  |  |  |  |  |  | 2177 |
| 9 | Arc | Privacy Policy |  |  | `showPrivacyPolicy:` |  |  |  | 353 |
| 10 | Arc | Hide Arc | Cmd+H | 1048576 | `hide:` | `hideArc` | overrideWebView |  | 477 |
| 11 | Arc | Hide Other Windows | Opt+Cmd+H | 1572864 | `hideOtherApplications:` | `hideOthers` |  |  | 731 |
| 12 | Arc | Show All |  |  | `unhideAllApplications:` |  |  |  | 344 |
| 13 | Arc | Sign Out |  |  | `signOut: (AppDelegate)` |  |  |  | 1753 |
| 14 | Arc | Quit Arc | Cmd+Q | 1048576 | `userQuitApp:` | `quitArc` | overrideWebView |  | 988 |
| 15 |  | File |  |  |  |  |  |  | 2190 |
| 16 | File | New Tab… | Cmd+T | 1048576 | `newWindowForTab:` | `newTab` | overrideWebView |  | 830 |
| 17 | File | New Window | Cmd+N | 1048576 | `newWindow: (AppDelegate)` | `newWindow` | overrideWebView |  | 678 |
| 18 | File | Blank Window | Ctrl+Cmd+N | 1310720 | `blankWindow: (AppDelegate)` | `newBlankWindow` |  |  | 1485 |
| 19 | File | New Incognito Window | Shift+Cmd+N (Shift from uppercase key) | 1048576 | `newIncognitoWindow: (AppDelegate)` | `newIncognitoWindow` | overrideWebView |  | 1029 |
| 20 | File | New Little Arc Window | Opt+Cmd+N | 1572864 | `newLittleBrowserWindow: (AppDelegate)` | `showLittleArc` | overrideWebView |  | 463 |
| 21 | File | Restore Last Closed Tab | Shift+Cmd+T (Shift from uppercase key) | 1048576 | `reopenLastTab:` | `reopenLastClosedTab` | overrideWebView |  | 717 |
| 22 | File | Open Command Bar | Cmd+L | 1048576 | `toggleOpenOmnibox:` | `addressBar` | overrideWebView |  | 240 |
| 23 | File | New Boost |  |  | `newBoost:` |  |  | hidden | 879 |
| 24 | File | Edit Boost |  |  | `editBoost:` |  |  | hidden | 416 |
| 25 | File | New Legacy Boost (Advanced) |  |  | `newLegacyBoost:` |  |  | hidden | 1182 |
| 26 | File | Boost Gallery |  |  | `openBoostGallery:` |  |  | hidden | 8 |
| 27 | File | New Profile |  |  | `newProfile:` |  |  |  | 393 |
| 28 | File | New Note | Ctrl+Shift+N (Shift from uppercase key) | 262144 | `newNote:` | `newNote` | promptAfterConsumedByWebView |  | 690 |
| 29 | File | New Note (in Split) | Ctrl+Opt+N | 786432 | `newNoteInSplitView:` | `newNoteInSplitView` | promptAfterConsumedByWebView | hidden, key works while hidden | 1220 |
| 30 | File | New Easel | Ctrl+Shift+E (Shift from uppercase key) | 262144 | `newEasel:` | `newEasel` |  |  | 1263 |
| 31 | File | Close Window | Shift+Cmd+W (Shift from uppercase key) | 1048576 | `closeWindow:` | `closeWindow` | overrideWebView |  | 574 |
| 32 | File | Archive Tab | Cmd+W | 1048576 | `closeCurrentItem:` | `archiveTab` | overrideWebView |  | 968 |
| 33 | File | Share… |  |  | `share:` | `share` |  |  | 602 |
| 34 | File | Send to Dia |  |  | `sendCurrentTabToDia:` |  |  |  | 1157 |
| 35 | File | Capture… | Shift+Cmd+2 | 1179648 | `capturePage:` | `capturePage` |  |  | 263 |
| 36 | File | Capture Full Page |  |  | `captureFullPage:` | `captureFullPage` |  |  | 1242 |
| 37 | File | Capture in Portrait Mode |  |  | `capturePrettyScreenshot:` | `capturePrettyScreenshot` |  |  | 914 |
| 38 | File | Save Page As | Shift+Cmd+S (Shift from uppercase key) | 1048576 | `save:` | `savePageAs` |  |  | 1207 |
| 39 | File | Print | Cmd+P | 1048576 | `printPage:` | `printPage` | promptAfterConsumedByWebView |  | 901 |
| 40 |  | Edit |  |  |  |  |  |  | 2202 |
| 41 | Edit | Undo | Cmd+Z | 1048576 | `undo:` |  |  |  | 1992 |
| 42 | Edit | Redo | Shift+Cmd+Z (Shift from uppercase key) | 1048576 | `redo:` |  |  |  | 124 |
| 43 | Edit | Cut | Cmd+X | 1048576 | `cut:` |  |  |  | 1393 |
| 44 | Edit | Copy | Cmd+C | 1048576 | `copyAction:` |  |  |  | 1465 |
| 45 | Edit | Copy URL | Shift+Cmd+C (Shift from uppercase key) | 1048576 | `copyCurrentURL:` | `copyCurrentURL` | overrideWebView |  | 890 |
| 46 | Edit | Copy URL as Markdown | Opt+Shift+Cmd+C (Shift from uppercase key) | 1572864 | `copyCurrentURLAsMarkdown:` | `copyCurrentURLMarkdown` | overrideWebView |  | 402 |
| 47 | Edit | Copy URL as Quote | Ctrl+Shift+Cmd+C (Shift from uppercase key) | 1310720 | `copyCurrentURLAsQuote:` | `copyCurrentURLAsQuote` | overrideWebView | disabled | 1412 |
| 48 | Edit | Paste | Cmd+V | 1048576 | `paste:` |  |  |  | 1074 |
| 49 | Edit | Paste and Match Style | Shift+Cmd+V (Shift from uppercase key) | 1048576 | `pasteAsPlainText:` | `pasteAndMatchStyle` |  |  | 740 |
| 50 | Edit | Delete |  |  | `delete:` |  |  |  | 1885 |
| 51 | Edit | Select All | Cmd+A | 1048576 | `selectAll:` |  |  |  | 533 |
| 52 | Edit | Find |  |  |  |  |  |  | 2212 |
| 53 | Edit > Find | Find… | Cmd+F | 1048576 | `arc_performFindPanelAction:` | `find` |  |  | 799 |
| 54 | Edit > Find | Find and Replace | Opt+Cmd+F | 1572864 | `arc_performFindPanelAction:` | `findAndReplace` |  |  | 822 |
| 55 | Edit > Find | Find Next | Cmd+G | 1048576 | `arc_performFindPanelAction:` | `findNext` |  |  | 1254 |
| 56 | Edit > Find | Find Previous | Shift+Cmd+G (Shift from uppercase key) | 1048576 | `arc_performFindPanelAction:` | `findPrevious` |  |  | 487 |
| 57 | Edit > Find | Use Selection to Find |  |  | `arc_performFindPanelAction:` | `useSelectionForFind` |  |  | 926 |
| 58 | Edit > Find | Jump to Selection | Cmd+J | 1048576 | `arc_performFindPanelAction:` | `jumpToSelection` |  |  | 543 |
| 59 | Edit | Spelling and Grammar |  |  |  |  |  |  | 2220 |
| 60 | Edit > Spelling and Grammar | Show Spelling and Grammar | Cmd+: | 1048576 | `showGuessPanel:` |  |  |  | 294 |
| 61 | Edit > Spelling and Grammar | Check Document Now | Cmd+; | 1048576 | `checkSpelling:` |  |  |  | 2023 |
| 62 | Edit > Spelling and Grammar | Check Spelling While Typing |  |  | `toggleContinuousSpellChecking:` |  |  |  | 2087 |
| 63 | Edit > Spelling and Grammar | Check Grammar With Spelling |  |  | `toggleGrammarChecking:` |  |  |  | 2044 |
| 64 | Edit > Spelling and Grammar | Correct Spelling Automatically |  |  | `toggleAutomaticSpellingCorrection:` |  |  |  | 1769 |
| 65 | Edit | Substitutions |  |  |  |  |  |  | 2230 |
| 66 | Edit > Substitutions | Show Substitutions |  |  | `orderFrontSubstitutionsPanel:` |  |  |  | 2151 |
| 67 | Edit > Substitutions | Smart Copy/Paste |  |  | `toggleSmartInsertDelete:` |  |  |  | 1789 |
| 68 | Edit > Substitutions | Smart Quotes |  |  | `toggleAutomaticQuoteSubstitution:` |  |  |  | 2017 |
| 69 | Edit > Substitutions | Smart Dashes |  |  | `toggleAutomaticDashSubstitution:` |  |  |  | 2093 |
| 70 | Edit > Substitutions | Smart Links |  |  | `toggleAutomaticLinkDetection:` |  |  |  | 1974 |
| 71 | Edit > Substitutions | Data Detectors |  |  | `toggleAutomaticDataDetection:` |  |  |  | 2109 |
| 72 | Edit > Substitutions | Text Replacement |  |  | `toggleAutomaticTextReplacement:` |  |  |  | 1815 |
| 73 | Edit | Transformations |  |  |  |  |  |  | 2239 |
| 74 | Edit > Transformations | Make Upper Case |  |  | `uppercaseWord:` |  |  |  | 2127 |
| 75 | Edit > Transformations | Make Lower Case |  |  | `lowercaseWord:` |  |  |  | 1980 |
| 76 | Edit > Transformations | Capitalize |  |  | `capitalizeWord:` |  |  |  | 1910 |
| 77 | Edit | Speech |  |  |  |  |  |  | 2247 |
| 78 | Edit > Speech | Start Speaking |  |  | `startSpeaking:` |  |  |  | 1947 |
| 79 | Edit > Speech | Stop Speaking |  |  | `stopSpeaking:` |  |  |  | 1867 |
| 80 | Edit | Format |  |  |  |  |  |  | 2255 |
| 81 | Edit > Format | Font |  |  |  |  |  |  | 2263 |
| 82 | Edit > Format > Font | Bold | Cmd+B | 1048576 | `addFontTrait: (NSFontManager)` |  |  |  | 1839 |
| 83 | Edit > Format > Font | Italic | Cmd+I | 1048576 | `addFontTrait: (NSFontManager)` |  |  |  | 2139 |
| 84 | Edit > Format > Font | Underline | Cmd+U | 1048576 | `underline:` |  |  |  | 1797 |
| 85 |  | View |  |  |  |  |  |  | 2272 |
| 86 | View | Appearance |  |  |  |  |  |  | 2280 |
| 87 | View > Appearance | Websites, Easels, and Notes will use: |  |  |  |  |  | disabled | 2286 |
| 88 | View > Appearance | Automatic |  |  | `setAutomaticAppearance:` |  |  |  | 640 |
| 89 | View > Appearance | Light |  |  | `setLightAppearance:` |  |  |  | 1121 |
| 90 | View > Appearance | Dark |  |  | `setDarkAppearance:` |  |  |  | 305 |
| 91 | View | Show/Hide Sidebar | Cmd+S | 1048576 | `toggleArcSidebar:` | `showSidebar` | promptAfterConsumedByWebView |  | 33 |
| 92 | View | Show/Hide Toolbar | Shift+Cmd+D (Shift from uppercase key) | 1048576 | `toggleArcToolbar:` | `toggleToolbar` | promptAfterConsumedByWebView | hidden, disabled, key off while hidden | 1095 |
| 93 | View | Expand Pinned Section |  |  | `expandPinnedSection:` |  |  | hidden, disabled | 617 |
| 94 | View | Collapse Pinned Section |  |  | `collapsePinnedSection:` |  |  | hidden, disabled | 840 |
| 95 | View | Reveal Current Tab | Ctrl+Space | 262144 | `focusSidebar:` | `focusSidebar` | promptAfterConsumedByWebView | hidden, key works while hidden | 778 |
| 96 | View | Stop Loading | Cmd+Period | 1048576 | `stopLoadingCurrentTab:` | `stopLoading` |  |  | 512 |
| 97 | View | Refresh the Page | Cmd+R | 1048576 | `reloadPage:` | `reloadPage` |  | disabled | 704 |
| 98 | View | Force Refresh the Page | Shift+Cmd+R (Shift from uppercase key) | 1048576 | `forceReloadPage:` | `forceReloadPage` |  | alternate, disabled | 1039 |
| 99 | View | Clear Cookies and Refresh |  |  | `clearCookiesAndRefresh:` | `clearCookies` |  |  | 1436 |
| 100 | View | Clear Cache and Refresh |  |  | `clearCacheAndRefresh:` |  |  |  | 1083 |
| 101 | View | Add Split View | Ctrl+Shift+Equals | 393216 | `addSplitPanel:` | `addSplitView` | promptAfterConsumedByWebView |  | 194 |
| 102 | View | Close this Split Pane | Ctrl+Shift+Minus | 393216 | `closeFocusedSplitViewPanel:` | `removeSplitView` | promptAfterConsumedByWebView | disabled | 228 |
| 103 | View | Separate Page from Split View |  |  | `separateTabFromSplitView:` | `separateTabFromSplitView` |  | disabled | 1300 |
| 104 | View | Expand Current Split |  |  | `maximizeCurrentSplitViewPane:` |  |  |  | 629 |
| 105 | View | Zoom to Actual Size | Cmd+0 | 1048576 | `resetZoom:` | `resetZoom` |  |  | 764 |
| 106 | View | Zoom In | Cmd+Plus | 1048576 | `zoomIn:` | `zoomIn` |  |  | 1051 |
| 107 | View | Zoom In | Cmd+Equals | 1048576 | `zoomIn:` |  |  | hidden, key works while hidden | 2083 |
| 108 | View | Zoom In | Cmd+Equals | 1048576 | `zoomIn:` |  |  | hidden, key works while hidden | 2070 |
| 109 | View | Zoom Out | Cmd+Minus | 1048576 | `zoomOut:` | `zoomOut` |  |  | 93 |
| 110 | View | Zoom Out | Shift+Cmd+Minus | 1179648 | `zoomOut:` |  |  | hidden, key works while hidden | 1881 |
| 111 | View | Cast |  |  | `cast:` | `cast` |  |  | 1371 |
| 112 | View | Developer |  |  |  |  |  |  | 2296 |
| 113 | View > Developer | View Source | Opt+Cmd+U | 1572864 | `viewSource:` | `viewSource` | promptAfterConsumedByWebView |  | 655 |
| 114 | View > Developer | Developer Tools | Opt+Cmd+I | 1572864 | `toggleDevTools:` | `developerTools` | promptAfterConsumedByWebView |  | 1473 |
| 115 | View > Developer | Developer Tools | F12 | 0 | `toggleDevTools:` | `developerTools_Alternate` | promptAfterConsumedByWebView | hidden, key works while hidden | 285 |
| 116 | View > Developer | Inspect Elements | Opt+Cmd+C | 1572864 | `inspectElements:` | `inspectElements` | promptAfterConsumedByWebView |  | 1380 |
| 117 | View > Developer | JavaScript Console | Opt+Cmd+J | 1572864 | `javaScriptConsole:` | `javaScriptConsole` |  |  | 1312 |
| 118 | View > Developer | Network Inspector |  |  | `networkInspector:` | `networkInspector` |  |  | 521 |
| 119 | View > Developer | Allow JavaScript from Apple Events |  |  | `allowJavascriptFromAppleEvents:` |  |  |  | 2038 |
| 120 | View > Developer | Toggle Developer Mode | Ctrl+D | 262144 | `toggleDeveloperMode:` | `toggleDeveloperMode` | promptAfterConsumedByWebView |  | 1276 |
| 121 | View | Enter/Exit Full Screen | Ctrl+Cmd+F | 1310720 | `toggleFullScreen:` | `fullscreen` | promptAfterConsumedByWebView |  | 428 |
| 122 | View | Exit | Esc | 0 | `exit:` | `exit` | promptAfterConsumedByWebView |  | 1324 |
| 123 |  | Spaces |  |  |  |  |  |  | 1674 |
| 124 | Spaces | New Space… |  |  | `newSpace:` | `newSpace` |  |  | 1195 |
| 125 | Spaces | Edit Theme… |  |  | `editSpaceTheme:` |  |  |  | 1424 |
| 126 | Spaces | Rename Space |  |  | `renameFocusedSpace:` |  |  |  | 442 |
| 127 | Spaces | Change Profile |  |  | `changeProfileForCurrentSpace:` |  |  |  | 84 |
| 128 | Spaces | Next Space | Opt+Cmd+Right | 1572864 | `nextSpace:` | `focusNextSpace` |  |  | 808 |
| 129 | Spaces | Previous Space | Opt+Cmd+Left | 1572864 | `previousSpace:` | `focusPreviousSpace` |  |  | 1108 |
| 130 | Spaces | Manage Spaces… |  |  | `toggleSpaceManager:` | `openSpaceManager` |  |  | 554 |
| 131 |  | Tabs |  |  |  |  |  |  | 1685 |
| 132 | Tabs | New Tab… | Cmd+T | 1048576 | `newWindowForTab:` |  |  |  | 1693 |
| 133 | Tabs | New ChatGPT Message… | Opt+Cmd+G | 1572864 | `gptMessage:` | `gptMessage` |  | hidden, key works while hidden | 52 |
| 134 | Tabs | Join Meeting | Ctrl+Cmd+J | 1310720 | `joinLiveMeeting:` | `joinLiveMeeting` | promptAfterConsumedByWebView | hidden, key works while hidden | 1136 |
| 135 | Tabs | Peek Email… | Shift+Cmd+E (Shift from uppercase key) | 1048576 | `peekEmail:` | `peekEmail` | promptAfterConsumedByWebView | hidden, key works while hidden | 219 |
| 136 | Tabs | Pin/Unpin Tab | Cmd+D | 1048576 | `toggleSelectedItemsPinned:` | `pinTab` | promptAfterConsumedByWebView |  | 181 |
| 137 | Tabs | Open Little Arc or Peek in… | Cmd+O | 1048576 | `openInCurrentSpace:` | `openTabIn` | promptAfterConsumedByWebView |  | 1495 |
| 138 | Tabs | New Folder… | Shift+Cmd+N (Shift from uppercase key) | 1048576 | `newList:` | `newFolder` |  |  | 959 |
| 139 | Tabs | Duplicate |  |  | `duplicate:` | `duplicate` |  | hidden, key works while hidden | 566 |
| 140 | Tabs | Rename Current Item |  |  | `rename:` | `rename` |  | hidden, key works while hidden | 142 |
| 141 | Tabs | Collapse All Folders |  |  | `collapseAllFolders:` | `collapseAllFolders` |  | hidden, key works while hidden | 134 |
| 142 | Tabs | Expand All Folders |  |  | `expandAllFolders:` | `expandAllFolders` |  | hidden, key works while hidden | 164 |
| 143 | Tabs | Next Tab | Opt+Cmd+Down | 1572864 | `nextTab:` | `selectNextTab` | overrideWebView |  | 1402 |
| 144 | Tabs | Previous Tab | Opt+Cmd+Up | 1572864 | `previousTab:` | `selectPreviousTab` | overrideWebView |  | 852 |
| 145 | Tabs | Tab Switcher (forward) | Ctrl+Tab | 262144 | `cycleToNextRecentTab:` | `cycleNextTab` | overrideWebView | hidden, key works while hidden | 1018 |
| 146 | Tabs | Tab Switcher (backward) | Ctrl+Shift+Backtab | 393216 | `cycleToPreviousRecentTab:` | `cyclePreviousTab` | overrideWebView | hidden, key works while hidden | 207 |
| 147 | Tabs | Cycle Tab Forward | Ctrl+Cmd+Right | 1310720 | `cycleTabForward:` | `cycleTabForward` | overrideWebView | hidden, key works while hidden | 871 |
| 148 | Tabs | Cycle Tab Backward | Ctrl+Cmd+Left | 1310720 | `cycleTabBackward:` | `cycleTabBackward` | overrideWebView | hidden, key works while hidden | 172 |
| 149 | Tabs | Reveal Tab in Sidebar |  |  | `revealCurrentTabInSidebar:` | `revealTabInSidebar` |  |  | 752 |
| 150 | Tabs >  | Item 1 |  |  |  |  |  | disabled | 1700 |
| 151 | Tabs >  | Item 2 |  |  |  |  |  | disabled | 1704 |
| 152 | Tabs >  | Item 3 |  |  |  |  |  | disabled | 1708 |
| 153 | Tabs | Clear Unpinned Tabs | Shift+Cmd+K (Shift from uppercase key) | 1048576 | `clearExplore:` | `clearExplore` |  |  | 498 |
| 154 | Tabs | Reset all tabs in this Space |  |  | `resetVisiblePinnedTabs:` | `resetSpace` |  |  | 334 |
| 155 | Tabs | Reset Tab to Original URL |  |  | `resetTab:` | `resetTab` |  | hidden, key works while hidden | 1348 |
| 156 |  | Archive |  |  |  |  |  |  | 1538 |
| 157 | Archive | Go Back | Cmd+[ | 1048576 | `navigateTabBack:` | `goBack` | overrideWebView |  | 946 |
| 158 | Archive | Go Back | Cmd+Left | 1048576 | `navigateTabBackArrow:` | `goBack_Alternate` |  | hidden, key works while hidden | 361 |
| 159 | Archive | Go Forward | Cmd+] | 1048576 | `navigateTabForward:` | `goForward` | overrideWebView |  | 61 |
| 160 | Archive | Go Forward | Cmd+Right | 1048576 | `navigateTabForwardArrow:` | `goForward_Alternate` |  | hidden, key works while hidden | 1447 |
| 161 | Archive | View History | Cmd+Y | 1048576 | `showAllHistory:` | `viewHistory` |  |  | 1144 |
| 162 | Archive | View Archive |  |  | `showArchive:` | `viewArchive` |  |  | 935 |
| 163 | Archive | Clear Archive |  |  | `clearArchive:` | `clearArchive` |  |  | 1171 |
| 164 |  | Extensions |  |  |  |  |  |  | 1576 |
| 165 | Extensions | Add Extension… |  |  | `navigateToChromeWebStore:` |  |  |  | 1232 |
| 166 | Extensions | Manage Extensions… |  |  | `navigateToChromeExtensionsPage:` |  |  |  | 978 |
| 167 |  | Window |  |  |  |  |  |  | 1718 |
| 168 | Window | Minimize Window | Cmd+M | 1048576 | `performMiniaturize:` | `minimize` | overrideWebView |  | 999 |
| 169 | Window | Zoom |  |  | `performZoom:` |  |  |  | 1726 |
| 170 | Window | View Library | Shift+Cmd+L (Shift from uppercase key) | 1048576 | `toggleLibrary:` | `viewLibrary` |  |  | 451 |
| 171 | Window | View Downloads | Shift+Cmd+J (Shift from uppercase key) | 1048576 | `toggleDownloads:` | `viewDownloads` |  |  | 150 |
| 172 | Window | View Easels & Notes |  |  | `viewEaselsAndNotes:` |  |  |  | 1516 |
| 173 | Window | View Media |  |  | `viewScreenshotsAndCaptures:` |  |  |  | 668 |
| 174 | Window | View Boosts |  |  | `viewBoosts:` |  |  |  | 862 |
| 175 | Window | Bring All to Front |  |  | `arrangeInFront:` |  |  |  | 1732 |
| 176 |  | Help |  |  |  |  |  |  | 1592 |
| 177 | Help | Getting Started |  |  | `showWelcomeToArc:` |  |  |  | 787 |
| 178 | Help | Essential Keyboard Shortcuts |  |  | `keyboardShortcutsEDU:` |  |  |  | 321 |
| 179 | Help | Release Notes |  |  | `onSelectResource_releaseNotes:` |  |  |  | 1359 |
| 180 | Help | Contact the Team |  |  | `contactTheTeam:` |  |  |  | 1288 |
| 181 | Help | Visit Help Center |  |  | `visitHelpCenter:` |  |  |  | 103 |
| 182 | Help | Restore Data |  |  | `presentRestoreDataFlow:` |  |  |  | 1504 |
| 183 | Help | Export Arc Notes |  |  | `exportArcNotes:` |  |  |  | 1061 |
| 184 | Help | Troubleshooting |  |  |  |  |  |  | 1601 |
| 185 | Help > Troubleshooting | Record Trace |  |  | `recordTrace:` |  |  |  | 276 |
| 186 | Help > Troubleshooting | Cancel Trace |  |  | `cancelTrace:` |  |  | hidden | 75 |
| 187 | Help > Troubleshooting | Open Task Manager |  |  | `openTaskManager:` |  |  |  | 382 |
| 188 | Help > Troubleshooting | Reveal Arc Data |  |  | `revealArcData:` |  |  |  | 594 |
| 189 | Help > Troubleshooting | Copy Arc Info |  |  | `copyArcInfo:` |  |  |  | 585 |

Source for every row: `ev/mainmenu-shortcuts-table.md` (generated by `ev/scripts/menutable.py` from `ev/mainmenu-items.tsv`). Nib object numbers match `ev/mainmenu-nibarchive-dump.jsonl` and `ev/rea-decode-interface-builder.json`. (observed)

Notes on specific rows:

- The "Tabs >" rows with an empty parent title ("Item 1", "Item 2", "Item 3") sit under a separator item (object 1697) that still has a submenu. They look like leftover Interface Builder placeholders. `ev/mainmenu-tree.txt` (observed; meaning inferred)
- "Websites, Easels, and Notes will use:" is a disabled label above the Automatic, Light, and Dark choices. `ev/mainmenu-tree.txt` (observed)
- "Force Refresh the Page" is the menu's only alternate item. It shares its menu slot with "Refresh the Page" and appears when its modifier is held. `ev/crosscheck-rea-vs-nibarchive.txt`, `ev/mainmenu-tree.txt` (observed flag; display behavior is AppKit's)
- "Set as Default Browser" has a runtime attribute `KeyEquivalent=♡`, which is a display glyph, not a real key equivalent. `ev/mainmenu-tree.txt` (observed)

### 2.4 Shortcuts that collide in the nib

`ev/mainmenu-shortcuts-table.md:193-197` (observed)

- **Shift+Cmd+N** is set on both File > New Incognito Window (`newIncognitoWindow:`) and Tabs > New Folder… (`newList:`, binding `newFolder`). Both have binding IDs, so the key-binding layer's `conflict` state will see this. Which one wins at runtime is unknown.
- **Cmd+T** is on both File > New Tab… and Tabs > New Tab…. Both call `newWindowForTab:`, so this is harmless.
- **Cmd+Equals** is on two hidden Zoom In items, alongside the visible Zoom In on Cmd+Plus. These are alternate keys for the same action.

### 2.5 Shortcuts that are not in the menu nib

The Shortcuts settings pane has descriptions for actions that no menu item provides. `ev/strings-arc-arm64.txt:560848-560990` (observed text)

| Action (as described in Settings) | Related identifiers or settings | Default key | Evidence | Label |
|---|---|---|---|---|
| "Jumps to the first … ninth item" in the sidebar ("Go to Sidebar Item 9") | settings `excludeFavoritesInSwitchToNthTab` ("Include Favorites in ordering."), `switchToNinthSidebarItemEnabled` ("Switch to ninth tab.") | unknown | `ev/strings-arc-arm64.txt:560849-560850,560985`, `ev/types-preferences.txt:1` | observed text; default unknown |
| Go to a specific space: "Jumps over to your %@ Space without needing to swipe." | `SidebarDock` items carry a `keyboardShortcut` field | unknown | `ev/strings-arc-arm64.txt:560854`, `ev/types-extra.txt:35` | observed text; default unknown |
| "Jumps to the first / second / third / fourth / next / previous Split View page" | `switchToNextWindowPane`, `switchToPreviousWindowPane` | unknown | `ev/strings-arc-arm64.txt:547576,560960-560965` | observed text; default unknown |
| "Open pinned extensions picker." | `openExtensionsPicker` | unknown | `ev/strings-arc-arm64.txt:547566,560976` | observed text; default unknown |
| "Presents the Little Arc 'Open In' Menu" | `showLittleArcOpenInMenu` | unknown | `ev/strings-arc-arm64.txt:547581,560939` | observed text; default unknown |
| Drag to capture: "Hold Command and Shift to start a Capture." | setting `dragToCaptureDisabled` | Shift+Cmd held, then drag | `ev/strings-arc-arm64.txt:560848,544112` | observed text; the drag step inferred from the setting name |
| Global Little Arc hotkey: "Open Little Arc when I press …" | setting `globalLittleBrowserHotkeyEnabled`; entry point `globalHotkey` | unknown | `ev/strings-arc-arm64.txt:560707`, `ev/types-storage-keybindings-littlearc.txt:96` | observed text; default unknown |
| Opt+Cmd+click a link opens Little Arc; Shift+click opens Peek | settings `optionCommandClickLittleArcEntryPointEnabled`, `shiftClickModalEntryPointEnabled` | Opt+Cmd+click and Shift+click | `ev/types-preferences.txt:1-10`, `ev/strings-arc-arm64.txt:560706,560710` | observed names and text; exact modifiers inferred from the names |
| Modifier-only toggles | user defaults `commandKeyShowsCommandBar`, `controlKeyShowsTypeTravel` | unknown | `ev/strings-arc-arm64.txt:544192-544193` | observed names; behavior inferred |

The default keys for these actions are not in any static string. Short Swift identifiers and key codes are compiled into code, and without a decompiler they cannot be recovered. (unknown)

## 3. Feature inventory

`app/Resources` has 83 `.bundle` folders. All of them are Swift Package Manager resource bundles: their ids look like `arc.CommandBar.resources`, `arcclients.BaseAssets.resources`, or `adk.ADK.resources`. That points to Swift packages named ARC, ARCClients, ARCUI, ARCFoundation, and ADK, plus third-party packages. `ev/bundle-ids.txt` (observed ids; package reading inferred)

A bundle holds only resources. The feature code is compiled into the main binary as a Swift module with the same name; the "Types" column counts that module's types. Many Arc bundles contain only `Info.plist`, a code signature, and `Assets.car` (44 of the 83 bundles have an asset catalog).

Evidence key for the table: **F** = `ev/bundles-file-list.txt`, **A** = `ev/bundle-asset-names.txt`, **J** = `ev/bundle-json-resources-summary.txt`, **T** = `ev/bundle-module-typecounts.txt` with names in `ev/swift-types-arc-arm64.tsv`. The name meaning is inferred. The contents and type names are observed.

### 3.1 Arc feature bundles (`ARC_*`)

| Bundle | What the name says | What the contents confirm | Types | Evidence |
|---|---|---|---|---|
| ARC_AboutWindow | About Arc window | `Credits.html` (licenses) | 2 | F, T |
| ARC_AdBlocking | Built-in ad blocker UI | Checkbox and component colors; types `ManageAdBlockersDialog`, `AdBlockerSelector` | 27 | A, T |
| ARC_AppTray | The favorites ("top apps") grid at the top of the sidebar | Badge colors for Gmail, WhatsApp, Twitter, and GitHub, plus a GCal subtitle; types `AppTrayViewController`, `AppTrayItemBadgeView`, `AppTrayItemSubtitleView`, `AppTrayEmptyStateView` | 67 | A, T |
| ARC_ArcMenu | Arc's own popup menu style, not the system menu | Menu colors; types `ArcMenu`, `ArcMenuWindow`, `ArcMenuItem`; used for `WindowArcMenuType`: `browserExtensions`, `sidebarPlusButton`, `navigationButtonsMore` | 36 | A, T, `ev/types-misc-ui.txt:42` |
| ARC_ArcRichTextEditor | Rich text editor for Notes | Ordered and unordered list icons, format-menu colors | 37 | A, T |
| ARC_AskArc | "Ask Arc" AI search pages ("Browse for me") | The only feature bundle with `en.lproj/Localizable.strings` (6 strings, for example "Making a website for you", "Reading %d web pages") | 202 | F, `ev/askarc-en-localizable.txt`, T |
| ARC_AuthFeature | Sign-in and onboarding | `demo.mov`, `intro-music.mp3`, `static-bg.png`; logos for Brave, Chrome, Edge, Firefox, Opera, and Safari | 126 | F, A, T |
| ARC_BaseHomeComponents | Shared parts for Library ("Home") | Colors; types `HomePreferences`, `StorableHome`, `HomePageID`, `MediaPreviewWindow` | 33 | A, T |
| ARC_BoostsDialog | Boost install and share dialogs | Squiggle and library icons; types `BoostsInstallationDialog`, `BoostsSharingDialog` | 63 | A, T |
| ARC_BoostsEditor | Boost editor | `SelectorPicker.js`, color-scheme icons, Boost palette colors, font controls | 88 | F, A, T |
| ARC_Capture | Screenshot and capture overlay | Camera cursors, overlay colors; types `ContentCaptureViewController` | 37 | A, T |
| ARC_CommandBar | The command bar | `command_bar_behavior.json` (a `dedupByTitleAndHostList` of 10 hosts such as figma.com and github.com); colors; `OpenAIIconTemplate`, `TypeTravelCapsuleBackground` | 163 | J, A, T |
| ARC_ContentPanel | Panel attached to page content (toolbar area) | `ExtensionsIcon`, window-screenshot watermark icons; types `ContentPanelView`, `ExtensionButton`, `WindowScreenshot` | 30 | A, T |
| ARC_ContextMenus | Right-click menus | Split-view icons (add, move, close, separate, horizontal); types `SidebarMenu`, `SpaceMenu`, `SplitScreenMenu`, `DownloadMenu` | 20 | A, T |
| ARC_CustomInfoPicker | Icon and emoji picker for custom icons | `CustomizationBackground` color; types `IconPickerGrid`, `EmojiPickerRepresentable` | 24 | A, T |
| ARC_DeleteAccountFeature | Delete account flow | One error color | 17 | A, T |
| ARC_EaselUI | Easels (shared canvases) | 74 assets: drawing tools, named avatar images (Josh, Nate, Molly, and others), font styles; `DisableInlineLinks.js` | 213 | F, A, T |
| ARC_Emojis | Emoji data | `emojis.json`, 1,870 entries | 7 | J, T |
| ARC_Favicons | Placeholder favicons | Document and Easel favicons | 4 | A, T |
| ARC_GlowProgressLoadingIndicator | Page-loading glow | `default.metallib` (Metal shaders) | 3 | F, T |
| ARC_HomeButton | Library ("Home") pages | Lottie animations `archive`, `boosts`, `downloads`, `easels`, `screenshots`, `spaces`; types `ArchivePage`, `BoostsPage`, `DownloadsPage` | 145 | J, A, T |
| ARC_ImportFeature | Import from other browsers | Logos for Brave, Chrome, Edge, Firefox, Opera, OperaGX, and Safari; Safari keychain import images | 89 | A, T |
| ARC_ImportMenuFeature | Import entry in menus | `password-import-prompt-icon` | 37 | A, T |
| ARC_LittleBrowser | Little Arc | 4 colors (download item, command bar placeholder) | 60 | A, T |
| ARC_MediaControlsFeature | Media controls and mini player | `PlaybackControlForeground`; types `MiniPlayerFeature`, `MediaControlsView` | 40 | A, T |
| ARC_MembershipCard | Arc member card | Gradients, shapes, stamp | 29 | A, T |
| ARC_PictureInPicture | Picture in Picture, including document PiP | Back and forward icons, Google Meet chat icons | 64 | A, T |
| ARC_PreferencesFeature | Settings window panes | `smiley.json` (Lottie); `LittleArcHeroImage`, `LinksPrefPaneIcon`, `MaxBanner` | 167 | J, A, T |
| ARC_ProfilesUI | Profile dialogs | "archie" icons (add, delete, move, question, space) | 48 | A, T |
| ARC_ReferralCodeFeature | "Share Arc" referrals | Ticket and toast colors, gift icon | 28 | A, T |
| ARC_SadTab | Crashed-tab page | `SadTab` image | 8 | A, T |
| ARC_SharableObjectsFeature | Spaces, tabs, and folders shared by link | "Arc Mail" icon; types `SharedObjectView`, `TabRow` | 26 | A, T |
| ARC_SidebarBanner | Cards at the bottom of the sidebar | `update-heart-animation.json`; types `AutoArchiveEducationView`, `SoftwareUpdateBannerUpdateAvailableView`, `SidebarBannerManageAdBlockersView` | 75 | F, J, T |
| ARC_SidebarPlusButton | The sidebar "+" menu | Icons `add-space`, `add-tab`, `folder`, `note`, `easel`, `boost`, `split-add-right`, `split-add-bottom`; the `SidebarPlusButtonMenuItemType` enum | 8 | A, `ev/types-misc-ui.txt:69` |
| ARC_SidebarSyncCloudKit | Older iCloud sidebar sync | Recovery card and phrase colors; types `RecoveryPhraseView`, `ZoneSyncData` | 46 | A, T |
| ARC_SiteControlCenter | Per-site control popover | Icons for boosts, capture full page, copy URL, share, control center | 47 | A, T |
| ARC_SoftwareUpdaterClient | Updates (Sparkle) | `UpdaterButtonBackgroundColor`; `app/Frameworks/Sparkle.framework` exists | 25 | A, T |
| ARC_SoundEffects | UI sounds | `capture.wav`, `event.m4a` | 6 | F, T |
| ARC_SpaceCreation | New-space flow | `smiley` image; types `SpaceCreationView`, `ProfileCardView`, `ThemeCardView` | 28 | A, T |
| ARC_SpaceStyleEditor | Space theme editor | Color presets Drab, Greyscale, and Pastel (9 each); knobs for Denim, Grain, Sand, Tweed; Lottie `automatic`, `moon`, `sun` | 35 | F, A, T |
| ARC_StorableSidebar | Default sidebar for new users | Favicons for Getting Started, Google, Import, Resources, Substack, Wikipedia, YouTube; `DefaultSidebarTabType` (21 seed tabs) | 8 | A, `ev/types-storage-keybindings-littlearc.txt:125` |
| ARC_TextEditor | Note title and gutter editor | Gutter button and title colors | 20 | A, T |
| ARC_TopDomains | Domain suggestions | `TopDomains.json` (458 domains with site names), `TLD-short-list.json` (1,310 TLDs) | 9 | J, T |
| ARC_Translation | Translate bubble | One background color; types `TranslateBubble` | 18 | A, T |
| ARC_URLInputter | URL text field with suggestions | 4 colors | 23 | A, T |
| ARC_WebContentBehaviorConfigurationClient | Per-site web behavior rules | `web_content_behavior.json` with keys `keepaliveAllowList`, `pipDisallowList`, `pipSiteConfigs`, `tidyTitles`, `tabSuspensionBlocklist` | 15 | J, T |
| ARC_WelcomeToArcFeature | "Arc 101" onboarding | Videos `new_tab.mp4`, `pinning.mp4`, `space_swiping.mp4`, `split_view.mp4`; glow and grain images | 31 | F, A, T |
| ARC_WindowThemeUI | Themed window background renderer | `default.metallib`; textures `grain`, `sand`, `denim`, `tweed` and their `_metal` versions | 18 | F, A, T |

### 3.2 Shared Arc bundles

| Bundle | What the name says | What the contents confirm | Types | Evidence |
|---|---|---|---|---|
| ADK_ADK | Arc Development Kit (the Chromium bridge) | `adblock_list.json` (empty list), `selectors.css` | 301 | F, J, T |
| ARCClients_AppRestartClient | App restart helper | `arc_restart_helper.sh` (not executed) | 3 | F |
| ARCClients_BaseAssets | Shared images and colors | 268 assets, including 10 app icon choices (Canary, Candy, Colorful, Dev, EarlyBirds, FlutedGlass, Hologram, Neon, Original, Schoolbook), brand colors, color-picker presets (Brand, Drab, Greyscale, Pastel), service icons, Dia app icons; SVGs for figma, github, linear | 20 | F, A |
| ARCClients_BlockListClient | Ad and tracker block lists | `EasyList.txt`, `EasyPrivacy.txt`, `manifest.json` (`manifest_url`, `known_block_lists`) | 22 | F, J |
| ARCClients_FontsManager | Bundled fonts | About 80 font files: ABC Favorit, ABC Oracle, Marlin, Nunito, Pitch, Inter, GT Ultra, EB Garamond, Inconsolata, National 2 | 26 | F |
| ARCClients_Icons | Icon fonts | `icomoon.ttf`, `ionicons.ttf`. Many `SidebarIconType` names match Ionicons names (inferred) | 10 | F |
| ARCFoundation_ARCFoundationBase | Foundation helpers | `SFSymbolEmojiLookupTable.json` (4,491 SF Symbol names) | 207 | J |
| ARCUI_ARCUI | Shared UI kit | 120 assets (button colors and more), `background.mp4`, `orb.mp4`, `logo-wave.json` (Lottie) | 648 | F, A, J |
| Settings_Settings | A Settings-window package | Only two strings, "Preferences" and "Settings", in 54 languages. Module types `Settings.Pane`, `Settings.PaneIdentifier`, `SettingsWindowController` match an open-source "Settings" window package (inferred) | 21 | F, `ev/settings-bundle-en-localizable.txt`, T |

### 3.3 Third-party bundles

Datadog_DatadogCore, DomainParser_DomainParser (`public_suffix_list.dat`), Firebase_FirebaseAuth, Firebase_FirebaseCore, Firebase_FirebaseCoreExtension, Firebase_FirebaseCoreInternal, Firebase_FirebaseFirestore, GTMSessionFetcher_GTMSessionFetcherCore, six GoogleUtilities bundles, LaunchDarkly_LaunchDarkly (feature flags), Promises_FBLPromises, SDWebImage_SDWebImage, YouTubePlayerKit_YouTubePlayerKit (`YouTubePlayer.html`), ZIPFoundation_ZIPFoundation, abseil_abslWrapper, three gRPC bundles, leveldb_leveldb, nanopb_nanopb, swift-crypto_Crypto. Apart from the two noted files, these hold only `Info.plist` and usually `PrivacyInfo.xcprivacy`. F (observed)

### 3.4 Feature modules with no bundle

Some features have code but no resource bundle. The most relevant for UI work are `SharedWindowFeature` (225 types), `WindowContents` (76), `SidebarUI` (26), `SidebarDock` (27), `SidebarItemUI`, `LiveFoldersFeature` (51), `ModalItemSwitcher` (19, the Ctrl+Tab switcher), `TidyTabTitles`, `KeyBindings` (28), `TypeTravel` (12), `Archive` (9), `HoverCards` (36), `InstantLinks` (31), and `Toasts` (64). `ev/swift-types-arc-arm64.tsv` (observed counts; roles inferred from names)

## 4. Settings

### 4.1 Where settings live

- `Settings_Settings.bundle` holds only the window title strings "Preferences" and "Settings". The settings content comes from the `PreferencesFeature` module. `ev/settings-bundle-en-localizable.txt` (observed)
- The settings window has nine panes, in this enum order: `account`, `general`, `max`, `profiles`, `keyBindings` (Shortcuts), `links`, `advanced`, `staff` (internal), `appIcon`. `ev/types-preferences.txt:283-292` (observed). Pane titles: "Account", "General", "Max", "Profiles", "Shortcuts", "Links", "Advanced", "Staff", "App Icon". `ev/strings-arc-arm64.txt:560622,560645,560661,560697,560716,560765,560801,561039,561042` (observed)
- Saved settings are in `PreferencesFeature.PersistedPreferencesState` (60 fields) and in per-profile `ProfilePreferences.State`. `ev/types-preferences.txt:1,220` (observed)
- Most switches are also stored as user-defaults keys. They sit in one block of strings next to Apple's own user-defaults keys (`NSQuitAlwaysKeepsWindows`, `AppleSpacesSwitchOnActivate`). `ev/strings-arc-arm64.txt:544060-544212` (observed names; "these are user-defaults keys" is inferred)
- No defaults `.plist` ships in the app. The only plists are `Info.plist`, `GoogleService-Info.plist`, and the Dock tile plugin's plists. Default values are therefore unknown. `ev/info-plist.txt`, file listing (observed)

### 4.2 Settings by pane

The pane for each setting comes from the order of strings in the binary: labels follow the source file name of each pane's view controller (for example `PreferencesFeature/GeneralPreferenceViewController.swift`). (inferred). Labels and model fields are observed.

| Pane | User-facing label | Model field | User-defaults key | Options | Evidence |
|---|---|---|---|---|---|
| General | Default browser notice (" is not your default web browser.") | `isDefaultBrowser` | | | `ev/strings-arc-arm64.txt:560664`, `ev/types-preferences.txt:1` |
| General | "Manage your default search engine, Auto-Archive, and downloads in Profile Settings." | | | Link to Profiles pane | `ev/strings-arc-arm64.txt:560665` |
| General | Arc ad blocker ("Use Arc's built-in protection against ads, pop-ups, and trackers…"), "Block Cookie Banners", "Advanced Settings" | `nativeAdBlock: AdBlocking.State`, `nativeAdBlockAvailable` | | On or off; cookie banners on or off | `ev/strings-arc-arm64.txt:560669-560682` |
| General | "Previews Settings", then "Show Arc Previews:" with one switch per source. Observed labels include "Outlook Calendar" and "Recent pages on Linear, Notion, and Figma"; the other sources come from the field names | `TabPreviews`: `gcalEnabled`, `gmailEnabled`, `outlookCalEnabled`, `outlookMailEnabled`, `recentPagesEnabled`, `twitterEnabled`, `folderEnabled`, `notionCalendarEnabled` | `gmailPreviewEnabled`, `calendarPreviewEnabled`, `outlookEmailPreviewEnabled`, `outlookCalendarPreviewEnabled`, `recentPagesPreviewEnabled`, `folderPreviewEnabled` | Each on or off | `ev/types-preferences.txt:152`, `ev/strings-arc-arm64.txt:560686,560769-560772,544182-544187` |
| General | "Warn before quitting" | `shouldWarnBeforeQuitting` | `shouldWarnBeforeQuitting` | On or off | `ev/strings-arc-arm64.txt:560687,544168` |
| General | "Automatically update my Arc" | `automaticallyUpdateArc`, `shouldAutomaticallyUpdateArc` | `shouldAutomaticallyUpdate`, `automaticallyUpdateArc` | On or off | `ev/strings-arc-arm64.txt:560688,544167` |
| General | Translation | `translateEnabled` (in the General pane view state) | `translateNeverHosts`, `translateSourceLanguagesAlwaysOrNever` | | `ev/types-preferences.txt:263`, `ev/strings-arc-arm64.txt:544130-544131` |
| Profiles | Profile list ("Profiles help keep your data separate across Spaces…"), rename, delete ("The Default Profile cannot be deleted."), delete unused | `persistedProfilesPreferences`, `deleteUnusedProfilesButtonEnabled` | `profileOrdering` | | `ev/strings-arc-arm64.txt:560780-560790,544212` |
| Profiles | "Default Search Engine", "Include search engine suggestions", "Search Settings" | `defaultSearchEngine`, `availableSearchEngines`, `searchSuggestEnabled` (per profile) | | Engines are `SearchEngine` records (`name`, `keyword`, `searchURLTemplate`, `faviconURL`, `isPrepopulated`) | `ev/types-preferences.txt:220`, `ev/types-settings-enums.txt:9`, `ev/strings-arc-arm64.txt:560795-560797` |
| Profiles | "Default Document App" | `defaultDocumentsApp: NoteDocument` (per profile) | `defaultNoteDocumentApp` | `arcNote`, or a web document type (`newDocURL`, `title`) | `ev/types-misc-ui.txt:1`, `ev/strings-arc-arm64.txt:560794,544089` |
| Profiles | "Download location" | `downloadFilePath`, `promptForDownloadFilePath` (per profile) | | Tags `promptTag`, `folderTag`, `otherTag` (`arc.promptForDownload`, `arc.folder`, `arc.other`) | `ev/types-settings-enums.txt:26`, `ev/strings-arc-arm64.txt:560774-560778` |
| Profiles | "Archive tabs after" (auto-archive for Today tabs) | `currentArchiveTabThreshold`, `currentArchiveProfileThresholds` | `autoArchiveTimeThreshold`, `autoArchiveTimeThresholdsPerProfile` | See 4.3 | `ev/strings-arc-arm64.txt:560668,544139-544141`, `ev/types-preferences.txt:1` |
| Profiles | "Privacy and Security", "Clear Browsing Data", "Your Data and Settings" | | | Buttons | `ev/strings-arc-arm64.txt:560793,560798,560800` |
| Shortcuts | "Custom Shortcuts", "Default Shortcuts", "Customized Shortcuts", "Extension Shortcuts", "Reset All Shortcuts", "Reset Shortcut to Default", "Remove Conflicting Shortcut" | `keyBindingsState`, `initiallySelectedKeyBindableActionIdentifier`, `systemShortcuts` | (stored in `StorableKeyBindings.json`) | A priority picker per shortcut with 3 choices (see 2.2) | `ev/strings-arc-arm64.txt:560990-561030`, `ev/types-preferences.txt:298` |
| Shortcuts | "Hold Command and Shift to start a Capture." | `dragToCaptureDisabled` | `dragToCaptureDisabled` | On or off | `ev/strings-arc-arm64.txt:560848,544112` |
| Shortcuts | "Include Favorites in ordering." | `excludeFavoritesInSwitchToNthTab` | `excludeFavoritesInSwitchToNthTab` | On or off | `ev/strings-arc-arm64.txt:560850,544107` |
| Shortcuts | "Switch to ninth tab." | `switchToNinthSidebarItemEnabled` | `switchToNinthSidebarItemEnabled` | On or off | `ev/strings-arc-arm64.txt:560849,544106` |
| Links | "Air Traffic Control": routes that send matching links to a chosen space ("…you can route Spotify links to always open inside your Personal space.") | `linkRoutingState: LinkRoutingEditor.State`, `defaultLinkRoutingDestination: LinkDestination?` | (stored in `StorableLinkRouting.json`) | Destination `space(...)` or `littleArc(...)`; "Most Recent Space" | `ev/types-settings-enums.txt:16`, `ev/strings-arc-arm64.txt:560693-560703` |
| Links | "Open a Peek window when clicking on links to other sites" ("Note: This only affects Favorites and Pinned tabs") | `modalEnabled` | `modalEnabled` | On or off | `ev/strings-arc-arm64.txt:560704-560705,544209` |
| Links | "Open a Peek window when clicking on links with Shift held" | `shiftClickModalEntryPointEnabled` | `disableShiftClickToOpenLinksInModal` | On or off | `ev/strings-arc-arm64.txt:560706,544083` |
| Links | "Open Little Arc when I press …" (global hotkey) | `globalLittleBrowserHotkeyEnabled` | `globalLittleBrowserHotkeyEnabled` | On or off | `ev/strings-arc-arm64.txt:560707,544146` |
| Links | "Archive Little Arcs after:" | `currentArchiveLittleArcThreshold` | `autoArchiveLittleArcTimeThreshold` | See 4.3 | `ev/strings-arc-arm64.txt:560708,544140` |
| Links | "Links from other apps open in Little Arc" | (`openExternalLinksInLittleBrowserEnabled` in the Shortcuts view state) | `openExternalLinksInLittleBrowserEnabled` | On or off | `ev/strings-arc-arm64.txt:560709,544144`, `ev/types-preferences.txt:298` |
| Links | "Open Little Arc when clicking on links with … held" | `optionCommandClickLittleArcEntryPointEnabled` | `optionCommandClickLittleArcEntryPointEnabled` | On or off | `ev/strings-arc-arm64.txt:560710,544145` |
| Max | Seven Arc Max features, each with a description: "ChatGPT in the Command Bar" (gptSiteSearch); "5-Second Previews" ("Instant summaries appear when you hover over links…"); Ask on Page ("Press Command + F on any page to ask a question…"); renamed pinned tabs ("Have your tabs automatically renamed with tidier, shorter titles when you Pin them"); renamed downloads ("…smartly renamed downloads"); Tidy Tabs and Instant Links (their descriptions are stored obfuscated as `tidyTabsDescription` and `instantLinksDescription`). Also "Automatically enable future Arc Max features" | `MaxFeature`: `tidyTabs`, `instantLinks`, `askOnPage`, `hoverCards`, `renamedPinnedTabs`, `renameDownloads`, `gptSiteSearch`; `arcMaxAutoOptInEnabled` | `tidyTabsEnabled`, `instantLinksEnabled`, `askOnPageEnabled`, `hoverCardsEnabled`, `renamePinnedTabsEnabled`, `renameDownloadsEnabled`, `gptSiteSearchEnabled`, `arcMaxAutoOptInEnabled` | Each on or off. Short feature names such as "Tidy Tabs" are not in the static strings | `ev/types-preferences.txt:191`, `ev/strings-arc-arm64.txt:560716-560739,544071-544077,544210` |
| Advanced | "When opening Arc, restore windows from previous session" | `restoresWindowsOnLaunch` | `windowRestorationSetting`, `restoreWindowsOnNextLaunch` | On or off | `ev/strings-arc-arm64.txt:560641,544201-544202` |
| Advanced | "Play Arc sound effects" | `playUserInterfaceSounds` | `playUserInterfaceSoundsDisabled` | On or off | `ev/strings-arc-arm64.txt:560644,544111` |
| Advanced | "Haptic feedback when reordering tabs" | `tabReorderingHapticsDisabled` | `tabReorderingHapticsDisabled` | On or off | `ev/strings-arc-arm64.txt:560643,544082` |
| Advanced | "Show full URL when Toolbar is enabled" | `toolbarShowFullURLsEnabledPreference` | `toolbarShowFullURLsEnabledPreference` | On or off | `ev/strings-arc-arm64.txt:560640,544128` |
| Advanced | "Allow window dragging from the top of webpages" | `contentWindowDraggingEnabled` | `contentWindowDraggingEnabled` | On or off | `ev/strings-arc-arm64.txt:560637,544143` |
| Advanced | "Enable Picture in Picture when you leave a video tab" | `disableAutoPipGlobally` | `autoPipGloballyDisabled` | On or off | `ev/strings-arc-arm64.txt:560634,544081` |
| Advanced | "Allow websites to get your theme data" | `allowThemeToCSSSharing` | `themeToCSSSharingAllowed` | On or off | `ev/strings-arc-arm64.txt:560633,544102` |
| Advanced | "Enable Boosts on websites you visit" | `isBoostsPreferencesToggleEnabled` | `hasDisabledBoostsInPreferences` | On or off | `ev/strings-arc-arm64.txt:560632,544157` |
| Advanced | "Enable Shared Quotes when highlighting text." | `shareQuoteLinkEnabledPreference` | `shareQuoteLinkEnabled` | On or off | `ev/strings-arc-arm64.txt:560638,544080` |
| Advanced | "More Settings" (opens `arc://settings`), "Reset Translated-site Prompts" | | | Buttons | `ev/strings-arc-arm64.txt:560627-560630` |
| Advanced | Update channel (Early Birds beta or stable) | `currentUpdaterFeed: SoftwareUpdaterFeed` | `updateChannelOverride` | `release`, `releaseCandidate`, `canary`, `prototype`, `test`, `pullRequest(Int)` | `ev/types-settings-enums.txt:19`, `ev/strings-arc-arm64.txt:544108` |
| App Icon | App icon choice, unlocked by referrals ("Refer %d friends to unlock") | `currentAppIcon: ArcAppIcon` | `currentAppIconName`, `availableAppIconNames` | `original`, `candy`, `hologram`, `neon`, `flutedGlass`, `schoolbook`, `colorful` | `ev/types-settings-enums.txt:1`, `ev/strings-arc-arm64.txt:560646-560650,544122-544123` |
| Account | Email, name, password, Arc Sync (end-to-end encrypted), iCloud sync, delete account | `emailState`, `nameChangeState`, `passwordChangeStatus`, `firebaseSyncEnabled`, `cloudKitSyncEnabled`, `deleteAccountState` | `firebaseSyncEnabled`, `cloudKitSyncEnabled` | | `ev/types-preferences.txt:1`, `ev/strings-arc-arm64.txt:544188-544189,560610` |

### 4.3 Auto-archive options

- Two auto-archive kinds: Today tabs (`todayTabs`) and Little Arc windows (`littleArc`). `ev/types-theme-profile-archive.txt:118` (observed)
- Choices: 1 hour, 6 hours, 12 hours, 24 hours, 7 days, 30 days, never. There is also an internal-only 20 seconds. The localizer comments read "Auto archive threshold; 12 hours" and so on, and "[internal only] 20 seconds". `ev/types-theme-profile-archive.txt:121-128`, `ev/strings-arc-arm64.txt:554907-554915` (observed)
- "Never" and the debug choice are behind `allowNeverArchivePreference` and `allowDebugArchivePreference`. `ev/types-preferences.txt:61` (observed flags; gating inferred)
- Today-tab thresholds can be set per profile (`AutoArchiveTimeThresholdsPerProfile`, behind `perProfileAutoArchivePrefAvailable`). The Little Arc threshold is a single global value. `ev/types-theme-profile-archive.txt:130`, `ev/types-preferences.txt:1` (observed fields; "single global" inferred from there being no per-profile Little Arc field)
- The default threshold is not in static data. (unknown)

### 4.4 Sidebar, window, and appearance options

| Option | Where | Values | Evidence | Label |
|---|---|---|---|---|
| Sidebar shown or hidden | View > Show/Hide Sidebar (Cmd+S); `SidebarViewPreferences.sidebarMode` | `anchored`, `noChrome` | `ev/types-window-sidebar-support.txt:127`, `ev/types-basemodels-sidebar-core.txt:445` | observed |
| Sidebar width | `SidebarViewPreferences.sidebarWidth` | CGFloat | `ev/types-window-sidebar-support.txt:127` | observed |
| Toolbar (URL bar) shown | View > Show/Hide Toolbar (hidden item, Shift+Cmd+D); `topBarDisplayedPreference` | On or off | `ev/types-arc-window-state.txt:35`, `ev/strings-arc-arm64.txt:544142` (`topBarURLEnabled`) | observed |
| Space header on a single unnamed space | `showSpaceHeaderOnSingleUnnamedSpaces` | On or off | `ev/strings-arc-arm64.txt:544127` | observed |
| Pinned section collapsed, per space | View > Expand/Collapse Pinned Section; `spacesWithCollapsedPinnedSections` | expanded, collapsed, peeked | `ev/types-sidebarspacestate.txt:62` | observed |
| Web content appearance | View > Appearance ("Websites, Easels, and Notes will use:") | Automatic, Light, Dark | `ev/mainmenu-tree.txt` | observed |
| Window stays on top | `WindowState.stayOnTop` | On or off | `ev/types-arc-window-state.txt:69` | observed field; UI entry unknown |

### 4.5 Theme (space style) options

From `WindowTheme` and the space style editor (`ev/types-theme-profile-archive.txt:26-90`, `ev/types-misc-ui.txt:20-40`, `ev/bundle-asset-names.txt`; observed):

- Background kind: a basic color, a blended single color, or a blended gradient.
- Gradient: number of colors, color wheel rule (`complimentary` or `analogous`), saturation, lightness range, and a primary color.
- Texture overlay: `grain`, `sand`, `denim`, or `tweed`, with a noise amount (`noiseFactor`) and strength (`intensityFactor`).
- Translucency: `light`, `dark`, or `auto`; also `isVibrant`.
- Light and dark: every theme value can be one value or a light and dark pair. The editor has an automatic, light, or dark toggle (Lottie files `automatic`, `moon`, `sun`) and a "dark mode bias" that is either a number or a forced appearance.
- Presets: the editor pages through presets (`currentPresetPage`) and offers color pad sets Drab, Greyscale, and Pastel (9 colors each).
- Saved form: colors are extended-sRGB RGBA values (`StorableColor`). The editor keeps an undo stack.

## Not determined

- **Shortcut defaults outside the menu nib.** Defaults for "go to sidebar item 1-9", "go to space N", split-pane jumps, the extensions picker, the Little Arc "Open In" menu, and the global Little Arc hotkey are not in static strings. They need a decompiler or runtime observation. (unknown)
- **Runtime menu changes.** Classes like `SpacesMainMenuProvider` and `WindowMenuProvider`, and the `KeyBindings` layer, probably add, remove, or rebind menu items at launch. The live menu may differ from the nib, for example in how the Shift+Cmd+N collision is resolved. (unknown)
- **Default setting values** (auto-archive threshold, sidebar width, and so on). No defaults plist ships, and the values are code constants. (unknown)
- **Exact on-disk JSON shape.** The field and `CodingKeys` names are observed, but custom encoders (for example `SidebarItemDictionaryCoding` and the legacy keys) mean the real JSON layout can differ. (unknown)
- **The 0.9% of field types** marked `mangled:` in `ev/swift-fields-arc-arm64.tsv`, mostly nested generics. (unknown)
- **Chromium side.** `ArcCore.framework` and its Chromium-level settings (`arc://settings`) were not analyzed. (unknown)
- **Pane placement** of each setting in 4.2 comes from string order, not from layout code. (inferred)

