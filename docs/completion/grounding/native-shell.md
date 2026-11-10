# Native shell grounding at 6d2d6d5

Brk has a working native browsing shell, a shared domain tree, window projections, atomic persistence, and a tested CEF focus lifecycle. That foundation does not complete the full Arc inventory. This pass owns exactly A001–A035, A056–A082, A089–A092, A113–A118 and A127–A133, totaling 79 rows. The [row proposals](../proposals/native-shell.json) retain each canonical row's original fields and add current acceptance, implementation, checks and gaps.

Starting commit: `6d2d6d50694b17d0c5e4ffcaf5b69bff4a30011d`. Production code, tests, canonical inventory and `.audit/arc-clone.tsv` were read-only. The source baseline and reproducible probes are under [a3966b7375:verify/completion/native-grounding](../../../verify/completion/native-grounding/). This is the exploration input to the parent's explanation and two design sketches. It does not choose or implement new shared APIs.

The highest-impact finding is that two standard windows can select the same logical tab while only one contains its page. Clicking that tab again in the empty window does not restore its surface. Separately, all nine Advanced switches lack runtime consumers, folder collapse belongs to the shared tree, and container archiving destroys structure. The existing tests still pass because their assertions do not cover these requirements.

## Components found

| Component | Location | Responsibility |
|---|---|---|
| `AppStore` | `Sources/BrkApp/AppStore.swift` | Owns opaque state, serializes dispatch and publishes whole snapshots before running effects. |
| `Work`, `reduce`, `normalize` | `Sources/BrkDomain/Reduce.swift`, `Normalize.swift`, `Rules/` | Apply typed commands, maintain references, load visible tabs and stamp activity. |
| `SidebarTree` | `Sources/BrkDomain/SidebarTree.swift` | Owns hierarchy edits, section placement, folder nesting and split cardinality. |
| `Doc`, `WindowDoc`, `Session` | `Sources/BrkDomain/Model.swift` | Separate saved global data, saved window selections and temporary overlays, page state and scratch trees. |
| `project`, `AppSnapshot`, `WindowSnapshot` | `Sources/BrkDomain/Project.swift`, `Snapshot.swift` | Derive rows, page demand, content, enabled actions, focus and settings from state. |
| `WindowLayout`, `SidebarLayout` | `Sources/BrkLayout/` | Compute native frames and drop geometry from snapshots and provenance-tagged metrics. |
| `WindowController`, `WindowRootView`, `CardView` | `Sources/BrkApp/WindowController.swift`, `Sources/BrkContent/` | Compose native chrome, put page surfaces in cards and apply window-specific focus. |
| `SidebarView`, `TablistView`, `FavoritesView`, `DockView` | `Sources/BrkSidebar/` | Render title controls, address, tiles, rows and spaces; dispatch commands for pointer interactions. |
| `DragController` | `Sources/BrkSidebar/DragController.swift` | Handles local pointer drags to list, Favorites and dock destinations. |
| `SpaceDialogHost`, `CommandBarView`, `Suggest` | `Sources/BrkOverlays/` | Hold editing drafts or query state and dispatch selected domain commands. |
| `ThemeBackgroundView`, `ThemeRenderer`, `SpaceTheme` | `Sources/BrkTheme/`, `Sources/BrkDomain/Theme/SpaceTheme.swift` | Resolve a single stored theme and draw a procedural Metal background with crossfades. |
| `SettingsHost`, pane views | `Sources/BrkSettings/` | Mount six panes and send settings commands; UI presence does not establish a runtime consumer. |
| `MainMenu`, `ActionID`, `KeyBindings`, `KeyRouter` | `Sources/BrkApp/MainMenu.swift`, `KeyRouter.swift`, `Sources/BrkDomain/Actions.swift`, `KeyRouting.swift` | Build menus and resolve app, page and page-then-app shortcuts from one action table. |
| `StateCodec`, `StateFile` | `Sources/BrkDomain/Codec.swift`, `Sources/BrkApp/StateFile.swift` | Migrate and validate v2 data, then debounce and atomically replace the state file. |
| `WebEngine`, `CEFEngine`, `EmbeddedSurface` | `Sources/BrkEngine/WebEngine.swift`, `Sources/BrkCEF/` | Maintain one live surface per PageID and explicit per-window focus requests. |

## Flow

[Open the flow and ownership diagram](../../../verify/completion/native-grounding/flow.html).

### A native action becomes state, layout and page work

1. A view dispatches a typed `Command`. A menu mouse selection uses `MenuTarget` and `KeyRouter.menuAction`. A key comes through `BrowserWindow` or the CEF delegate with a physical chord, delivery stage and press ID.
2. `AppStore.dispatch` queues reentrant inputs. `reduce` sends each command to its rule module. Most commands commit a pending recent-tab cycle and apply overlay-close policy first. `.later` does nothing.
3. `Work.finish` normalizes cross-references and stamps tabs entering or leaving the union of all window selections. A changing transition increments the revision. Document changes schedule persistence. Effects can run even when state did not change.
4. `project` creates each `WindowSnapshot`. The current item becomes one pane or a split. Page demand comes from `Session.loaded`; each loaded tab becomes `PageSpec(id: PageID(tab), context: ...)` once globally.
5. `AppStore.publish` calls `engine.reconcile` before rendering windows. `WindowLayout.compute` returns frames. `WindowRootView.render` updates background, sidebar, content cards, Library, Peek and overlays.
6. `CardView.host` attaches the engine's existing NSView. `WindowController.applyFocus` calls `engine.focus(page, in: window)` or releases that window's page focus before focusing a native editor. Page callbacks return through `KeyRouter` as system events.

This sequence gives the parent a clear implementation boundary: domain rules own intent and persistence, projection owns display data, layout owns frames, views own interaction mechanics, and the engine owns Chromium lifetime. A feature still needs a complete path through the layers it uses.

### What the sidebar workflows currently do

`openTab` inserts Today tabs at index zero. Close archives Today tabs, but unloads a pinned or Favorite tab while keeping its row. Explicit Archive removes a pinned tab. Reset navigates to `pinnedURL`. Titles from webpages and user-defined titles are separate, so normal page-title events do not overwrite a manual rename.

Folders live in Pinned. Their row toggles a saved `Folder.collapsed` field; rename opens collapsed ancestors. The current `pinnedCollapsed` flag removes the whole Pinned list. Neither flag has a peeked mode. Folder collapse is global, as the probe confirms, rather than per window as A091 requires.

Favorites use a separate root for each profile. Their geometry supports four, two or one columns. `DragController` corrects indices after detaching an item and delegates placement validation to the tree. It accepts rows and Favorites as drag sources, and list, Favorites or dock spaces as targets. It has no content-edge split target and no space-reorder source.

There is a small implemented multi-select interaction that the historical ledger misses. Cmd-click adds tab IDs to `TablistView.multiselection`, and the close button on a selected row closes all those tabs. This selection is view-local. It is not available to menu commands, has no range selection or batch transaction, and does not provide Archive Other, Archive Below or New Folder from Selection.

Recent-tab cycling freezes order and commits activity on Control release. There is no switcher-panel projection or view. Linear cycling, numbered navigation, duplicate, reset-all and folder expand-all remain absent or `.later`. `FocusTarget.sidebar` and `focusList` exist, but no current projection chooses that target for Reveal Current Tab.

### Space and theme editing stops before the full editor

The space form edits a draft and commits once on Save. It supports a name, an emoji or one of 16 named icons, four sets of nine preset swatches, a wheel choice, texture, noise, intensity and appearance. Cancel discards the draft. A new space always receives the default profile. There is no profile card or multi-stage animated creation flow.

`space.move` is a working reducer command with tests, but dock cells do not issue it from a drag. The space popup's Delete command immediately archives contents and deletes the space; it has no confirmation step. Manage Spaces is `.later`, and the Library Spaces page is a placeholder.

`SpaceTheme` stores one set of one to three base colors, one texture, noise, intensity and appearance. The form changes only the primary swatch. It has no free color pad, color-count controls, saturation or lightness controls, dark bias, preset paging or undo. Fixed light and dark UI tokens and a forced appearance are not independently editable light and dark theme values.

The Metal renderer and offscreen crossfade tests are real. Grain, sand, denim and tweed are procedural approximations. The precise gradient layout, noise interpretation, default theme and preset order remain choices or guesses where cached evidence does not establish them.

### Splits and archive preserve less than their models suggest

A split is one shared tree item containing two to four tab IDs, focused pane, fractions, orientation and icon. Adding a pane creates a blank tab and opens the command bar. Closing a Today pane archives it. Closing a pinned pane moves it out and unloads it. A remaining single pane dissolves the split in place. Fractions and vertical geometry work, but no native menu or control invokes `setOrientation`.

The row has clickable pane segments and the content divider dispatches resize. Dedicated Separate, Expand and Separate All workflows do not exist. Moving a pane through a generic tree command is only part of Separate. The content area has no drag-to-split destination, and there are no numbered or next/previous pane shortcuts.

`archiveTabs` flattens folders and splits into independent `ArchivedTab` records. Restore recreates tabs, using their source section if valid and current-space Today otherwise. It cannot restore the original folder, split identity, title, icon, ordering or pane layout as one unit. A080 needs a stored-format decision before a restore control can complete the workflow.

Auto-archive reads per-profile thresholds and excludes all panes selected by any window. A pending Ctrl+Tab cycle is committed before the sweep, preserving the outgoing timestamp fix. The Archive page groups by date and supports filtering, restore, confirmed clearing and threshold selection. Downloads and History have real pages; Media, Easels and Notes, Boosts and Spaces are `LaterPageView` placeholders. A Library navigation button does not complete its destination workflow.

## Window, tab and page ownership

Primary source locations: `AppStore.swift:100` and `:176`, `ContentAreaView.swift:129`, `WindowController.swift:106`, `:129` and `:135`, `CEFEngine.swift:148`, and `Rules/Shared.swift:12`.

The following is established by source and the [reproducible AppKit probe](../../../verify/completion/native-grounding/OwnershipProbe.swift), with [captured output](../../../verify/completion/native-grounding/probe-output.txt).

| Identity or state | Actual owner | Consequence |
|---|---|---|
| Standard tab, URL, title, folder and split structure | Global `Doc.tree` | All standard windows see the same records. |
| Selected item in each space, sidebar width, bounds | `WindowDoc` | Two windows may independently select the same item. |
| Folder collapse, split focused pane, orientation and widths | Shared tree payload | These are not independent per-window view states. |
| Loaded tabs and live page reports | App-wide session sets keyed by ItemID | One tab creates one PageID regardless of selected-window count. |
| Page surface | Engine map keyed by PageID | One NSView can be attached to only one card and window at a time. |
| Page focus request | CEF map keyed by native NSWindow identity | Requests cannot blur or reclaim another window's moved surface. |

The reproduction creates a standard window with one loaded tab, creates a second standard window, and selects the first tab there. Both snapshots then claim the same page, `snapshot.pages` has one entry, and the surface belongs to exactly one window. Selecting that same row again in the empty window changes no domain state or revision. The store therefore does not republish. The become-key and update delegate paths only try to focus a surface already attached to that window; they do not reattach it. The empty card remains empty in this probe.

On a state-changing publish, every window renders. `CardView.host` removes the surface from its current parent before attaching it. The last rendered claimant gets it. `renderWindows` iterates a dictionary and does not establish an active-window ownership policy. Selecting a tab or activating a window therefore does not define a reliable owner for a shared page.

There is also an unresolved event-routing ambiguity. `AppStore.window(showing:)` returns the first snapshot that claims a page, while the surface belongs to one native window. `KeyRouter` uses that lookup for CEF shortcuts and pinned-link Peek routing. `openRequested` independently chooses the first sorted standard window claiming a global opener. The probe's one captured run happened to match the lookup and attached owner; it does not prove a wrong-window shortcut occurred. Source establishes that these selections are not explicitly tied to the actual host.

W2-4 is not proof of same-tab usability. `Wave2Scenarios.newWindow` opens `page2.html` in window 2 before asserting both windows' native focus and restarting. `NativeFocusLifecycleTests.testOldWindowCannotReclaimOrBlurASurfaceMovedToAnotherWindow` manually moves the surface and proves that the old window leaves it alone. It deliberately does not test a shared-tab ownership policy.

The AppKit probe uses `StubEngine` and actual production controllers and cards. It does not load real CEF, simulate physical activation or prove pixel output. CEF source has the same one-surface contract, but the parent still needs a dedicated real-CEF same-tab scenario. No redesign or fix was made here.

Future interfaces must state whether a logical tab can have more than one live page instance or has an exclusive host, and how activating a claimant window works. They must also identify the origin window for page-driven actions. This decision constrains split focus, page commands, shortcut routing, toolbars, previews and automation. This report does not select an approach.

Preserve the migrated `focus(page, in: window)` contract, pending per-window requests, native-editor protection, hidden/moved-surface guards and page-generation guards. Preserve `ContainerScope.window` for private tabs, incognito request contexts, scratch-owner routing for hidden private popups, suppression of Little Arc promotion for private modifier links, and exclusion of private history, archive, download metadata and windows from saved state. Same-tab work is not permission to merge private and global ownership.

## Settings consumers and menu accounting

Every Advanced and Max setting was searched across `Sources`, then checked at its caller. The complete reference list is in [source-audit.json](../../../verify/completion/native-grounding/source-audit.json). `SettingsSpecTests.test_everySetterPersists` and `SettingsHostTests` prove storage or command dispatch; they do not prove the behavior described by a checkbox.

| Stored setting | Runtime consumer at this commit | What remains |
|---|---|---|
| `advanced.restoreWindowsOnLaunch` | None. `Lifecycle` always calls `StateCodec.restore`, which reconstructs saved standard windows. Probe: false still restores two windows. | Define disabled-restore semantics and consume the value on launch. |
| `advanced.soundEffects` | None. `NSSound.beep()` is an unconditional app effect, not the sound preference. | Add feature sound triggers and honor the switch. |
| `advanced.hapticsOnReorder` | None. Sidebar resize snap calls haptics unconditionally; that is a different interaction. | Add reorder haptics and preference handling. |
| `advanced.showFullURLInToolbar` | None. No toolbar exists. | Implement toolbar and formatting consumer. |
| `advanced.windowDraggingFromPages` | None. The title row permits dragging independently. | Add page-top drag region and interaction policy. |
| `advanced.autoPictureInPicture` | None. | Coordinate engine video state and native PiP behavior. |
| `advanced.themeToCSS` | None. | Specify and apply theme CSS with opt-out cleanup. |
| `advanced.boostsEnabled` | None. | Complete Boost execution and its enable/disable behavior. |
| `advanced.sharedQuotes` | None. Plain Copy URL as Quote is a separate command. | Implement selection-based local quote export under the user's file-sharing decision. |
| `max.provider` | `AppStore.run(.ai)` calls `AIProviderSeam.answer`; discovery finds local `claude` or `codex`, and the projection displays availability. | Verify actual CLI success, failure and cancellation with controlled fixtures; detecting an executable is not authentication proof. |
| `max.renamePinnedTabs` | `tabs(.togglePin)` requests a title when moving Today to Pinned with a URL and no custom title; `aiResult` applies the first trimmed line, capped at 60 characters. | Verify the real CLI and error feedback; review stale-result or manual-rename precedence. Dragging into Pinned does not pass through this trigger. |
| `max.tidyTabs` | None. `AITask.tidyToday` and a prompt exist, but no requester applies a plan; the result branch is empty. | Implement the trigger, plan contract, validation and visible grouping. |

The user's Codex preference controls this research task. The product currently defaults `.auto` to Claude first when detected; the report records that behavior without changing product settings. No API-key integration was introduced.

Additional source locations: `Lifecycle.swift:119`, `Codec.swift:93`, `Rules/Settings.swift:80` and `:86`, `SidebarTree.swift:104`, `Rules/Archive.swift:55`, and `Reduce.swift:109`.

General has two further gaps. `QuitWarning.shouldQuit` is implemented and unit-tested, but no production caller invokes it. `Lifecycle.applicationShouldTerminate` immediately starts ordered shutdown. `general.webAppearance` changes stored data and menu commands but is never applied to webpages. The default-browser notice does have a host consumer. Profile search engine, suggestions, download directory/prompt and auto-archive values have real consumers. Default Document App is absent.

Menu accounting is complete as accounting: 189 reference rows, 122 action IDs, 65 non-`.later` actions and 57 `.later` actions. Remaining rows are menu headers, AppKit standard entries, alternate keys, placeholders or authorized omissions. `ActionsTests` checks the counts and `ArcMenuTree` tests the tree. `enabledActions` removes `.later` entries, and `Work.run` makes them no-ops. Even the 65 count is not a completed-feature count: three appearance actions only store unused settings, and Library actions can open placeholders.

The shortcut editor supports the action table's primary bindings, conflict states, priorities, reset and removal. Fixed alternate bindings and AppKit-standard menu items are not all editable through it. Remapping a `.later` command does not implement that command. W2-8 executes Preferences from the bar; its broad scenario title does not verify every menu action.

App Icon remains in scope. The comment in `SettingsModel.swift` that groups it with excluded Account and referral functionality is stale relative to the user's instruction. App icon selection can be account-free. About currently calls the standard AppKit panel without a credits implementation found in this repository. Custom Dock behavior, a status item and AppleScript scripting are absent. GetURL support alone is not an AppleScript object model.

## Boundaries and persistence

`StateCodec` is the only stored-format authority. Version 1 migrates to version 2. Saved data includes the global tree, profiles and per-profile settings, history, archive, downloads, routes, shortcut overrides and standard-window selection or geometry. Session overlays, live-page status, temporary input state, private or Little Arc trees and nonstandard windows are excluded. On restore, normalization loads selected pages while other saved tabs remain lazy.

`StateFile` accepts bytes, uses a generation-guarded debounce, and writes a synchronized temporary file before replacement. The quit path flushes before engine shutdown. Neither this file nor the view layer should decide migration semantics for structural archives, theme pairs or window-local expansion.

Views dispatch commands but do keep temporary presentation state: space drafts, command-bar text/ranking, archive filters and multiselection. That distinction matters for bulk commands. Menu and command-bar consumers cannot inspect a private view's selected IDs through the existing snapshot. Layout similarly cannot infer a toolbar, manager or hover card without an explicit projection.

The local AI boundary executes the user's CLI. File exports remain local JSON or Netscape bookmark HTML through `ExportDocument` and `ShareExport`; a space manager's Export into Folder still needs its own semantics. Account, membership, referral and Send to Dia remain excluded. Only the updater and its readiness banner are marked deferred here. No unfinished native feature is waived because a CEF capability may exist.

## Reference evidence and its limits

The intended interactions come from the existing `docs/arc-anatomy` reports and cached resources. No Arc process, authenticated profile, REA target or excluded cra checkout was touched.

| Evidence | What it establishes | Limit |
|---|---|---|
| `model-and-shortcuts.md` sections 1.4–1.9, 1.13, 2.3–2.5 and 4 | Cached field and enum names for tab groups, custom icons, per-window expanded items, split tools, settings and menu rows. | A binary field name is evidence of a concept, not an observed interaction sequence. |
| `visual-and-copy.md` theme editor and feature copy | Cached editor controls, preview copy, badge and app-icon vocabulary; preset and named-color values. | Some pane assignments and short labels are inferred. No live screenshot comparison. |
| `layout-constants.md` | Binary-derived widths 164/500, hide threshold 82, snap target 228, and content inset/radius values with original confidence labels. | Default width is marked low-confidence; some values are cached measurements or guesses rather than direct code constants. |
| Existing Brk `Metrics` and geometry tests | The implementation follows its own recorded constants. | N3 compares Brk frames with Brk metrics, not with authenticated Arc pixels. |

The split gap of 10 is recorded as a historical measurement-only value in the cached anatomy, not independently remeasured here. The default theme, texture appearance, noise interpretation and creation animation still need reference validation. App Icon must use Brk-owned assets and omit referral gates. The exact custom Dock interactions and some editor details remain reference questions for the separate reference task.

## Verification and non-obvious limits

`swift test` ran locally with 459 tests, three known skips and zero failures. The skips are AI Today organization, Ask/answer display and the ShareExport save-panel test. The output, with trailing whitespace removed, is [swift-test.log](../../../verify/completion/native-grounding/swift-test.log). This pass did not rebuild or launch the signed CEF application.

The parent's [45-scenario report](../../../verify/swift/focus-parent/native/REPORT.md) is applicable: all 520 entries in its `source-sha256.json` match current files. The report records CEF 154.0.34.0, 45 PASS, zero FAIL and zero SKIPPED. The source comparison does not substitute for a new scenario covering a newly discovered gap. The parent build log is supporting evidence, not a second build claimed by this worker.

Reproduce the additional probes with `python3 a3966b7375:verify/completion/native-grounding/run-probes.py`. It builds the unmodified BrkApp target, links a small probe against its Swift objects, and writes generated files and synthetic state under `.build/native-grounding`. The probe checks same-tab attachment, repeated selection, focus callbacks, restore-off, shared folder collapse and menu counts. It uses StubEngine and AppKit, not Chromium, real web content or physical input. A PASS means the described current limitation was reproduced, not that the feature meets acceptance.

The proposal marks only A004 sidebar toggle and A078 auto-archive as functionally verified. Those have corresponding rule or geometry assertions and real CEF scenarios. Every visual-comparison gate remains separate. Most working workflows are `implemented` because a native control path, edge case or required visual check has not been demonstrated. A static check in a missing row verifies the source audit, not the missing behavior.

Notable test limits include:

- W2-1-edit mounts six panes and persists values. It deliberately turns quit warning back off, and does not test Advanced consumers.
- W2-4 uses distinct pages in the two windows. Focus lifecycle tests protect other windows and native editors; they do not solve shared ownership.
- W2-10 tests fixture suggestions and built-in engine search submission. It does not verify remote search results or arbitrary site search.
- R5b dispatches a move command. It does not prove native dock-drop mechanics.
- Offscreen Metal tests verify Brk's crossfade math. They do not establish Arc texture parity.
- The archive unit tests exercise filtering and confirmation controls directly; scenario 7 covers sweep and restore, not every archive interaction.

## Candidate next implementation units

These are inputs for the parent to sequence with platform and integration work, not a reduced scope or a new architecture decision.

1. Establish shared-tab host and event-origin semantics before broadening page-facing interfaces. Acceptance must select the same tab in two real CEF windows, activate each, type, navigate, open an overlay, switch split focus and close either window. Keep the current focus and incognito regression suite.
2. Define window-local folder expansion, sidebar focus and selection targets. Then implement Reveal, range or bulk actions, duplicate, numbered or linear navigation, reset-all, collapse-all and the recent-tab panel. Complete item icon pickers and tab groups against those commands.
3. Define structural archive records and migration. Preserve folder trees and split metadata as one restorable item before relying on container bulk operations.
4. Complete split controls and content-edge drops using the agreed page ownership. Verify orientation, three and four panes, divider persistence, separate, expand and pane shortcuts.
5. Complete space creation, deletion confirmation, dock reorder and Space manager. Include profile selection and local export. Add swipe only with a tested distinction between sidebar gestures and webpage scrolling.
6. Complete the theme editor and paired theme values, then the toolbar and native polish. Add loading glow, crash UI, toasts, auto-archive education, App Icon, About credits, Dock and status-item behavior. Keep unsupported reference details labeled until measured.
7. Wire settings to behavior through their actual owners. Start with unused restore and quit-warning controls, then coordinate PiP, theme CSS, Boosts, quote export, previews, audio/badges, Live Folders and document-app handling with platform or integration work. Finish the local CLI Max workflows through explicit request and result contracts.
8. Audit all remaining menu and scripting operations end to end. Do not confuse 189-row coverage with working actions. Only updater-related rows retain the explicit deferral.

## Open questions

- Which user-visible same-tab behavior should the parent select: exclusive host transfer or separate live instances? What does authenticated Arc actually do in this case? No answer was inferred from W2-4.
- Which view properties must be independent per window beyond folder expansion, notably split focus and layout? Current storage shares them.
- What migration and restore destinations preserve container archives when the original space or profile no longer exists?
- What exact site search, hover-card, badge and Live Folder provider interactions are in the accepted Arc scope? Cached fields and copy do not establish their complete runtime protocols.
- What are the authenticated Arc measurements for advanced editor controls, Dock behavior, hidden traffic lights and gesture transitions? No pixel-parity claim is possible yet.
- The quit-warning missing call is established statically. A cancel/confirm sequence through the actual app termination path remains to be added. Actual AI CLI failure, authentication and cancellation were not exercised.

## Files read

Paths below identify source and test files read in full or in relevant excerpts. Broad symbol searches and hash checks covered additional files but are not claimed as full semantic review. Architecture documents with an older focus signature were not used as authority.

- Planning and reference: `docs/completion/plan.md`, `docs/completion/features.json`, `docs/arc-anatomy/model-and-shortcuts.md`, `docs/arc-anatomy/layout-constants.md`, `docs/arc-anatomy/visual-and-copy.md`.
- Build and validation: `Package.swift`, `scripts/build.sh`, `scripts/e2e.sh`, `scripts/check-completion.py`.
- Domain: `Sources/BrkDomain/Model.swift`, `Snapshot.swift`, `Project.swift`, `Command.swift`, `Effect.swift`, `Reduce.swift`, `Normalize.swift`, `SidebarTree.swift`, `Codec.swift`, `SettingsModel.swift`, `Actions.swift`, `KeyRouting.swift`, `Theme/SpaceTheme.swift`.
- Rules: `Sources/BrkDomain/Rules/Sidebar.swift`, `Tabs.swift`, `Split.swift`, `Archive.swift`, `Shared.swift`, `Queries.swift`, `Windows.swift`, `Settings.swift`, `Assist.swift`, `CommandBar.swift`, `Peek.swift`. Profile and privacy consumers were checked at their call sites and through the matched regression evidence.
- Application and engine: `Sources/BrkApp/AppStore.swift`, `WindowController.swift`, `Lifecycle.swift`, `KeyRouter.swift`, `MainMenu.swift`, `StateFile.swift`, `AIProvider.swift`; `Sources/BrkEngine/WebEngine.swift`, `StubEngine.swift`; `Sources/BrkCEF/CEFEngine.swift`, `EmbeddedSurface.swift`; `Sources/BrkBase/IDs.swift`, `Page.swift`, `Metrics.swift`.
- Native content and layout: `Sources/BrkContent/WindowRootView.swift`, `ContentAreaView.swift`; `Sources/BrkLayout/WindowLayout.swift`, `SidebarLayout.swift`, `SidebarResizeDrag.swift`.
- Sidebar and overlays: `Sources/BrkSidebar/SidebarView.swift`, `TablistView.swift`, `FavoritesView.swift`, `DockView.swift`, `DragController.swift`, `Controls.swift`, `Glyphs.swift`; `Sources/BrkOverlays/SpaceDialogHost.swift`, `Suggest.swift`, `CommandBarView.swift`.
- Settings, Library and theme: `Sources/BrkSettings/SettingsHost.swift`, `SettingsPanes.swift`, `SettingsCopy.swift`, `Panes/ShortcutsPane.swift`, `QuitWarning.swift`; `Sources/BrkLibrary/LibraryView.swift`, `LibraryPages.swift`, `ArchivePageView.swift`; `Sources/BrkTheme/ThemeBackgroundView.swift`, `ThemeRenderer.swift`, `TexturePixels.swift`.
- Tests examined beyond their names: `Tests/BrkDomainTests/ActionsTests.swift`, `ReduceSpecTests.swift`, `SettingsSpecTests.swift`, `AssistAndExportSpecTests.swift`; `Tests/BrkAppTests/NativeFocusLifecycleTests.swift`, `F3WindowRegressionTests.swift`, `Wave1ReviewRegressionTests.swift`; `Tests/BrkSettingsTests/SettingsHostTests.swift`; `Tests/BrkOverlaysTests/SpaceDialogTests.swift`; `Tests/BrkLibraryTests/ArchivePageViewTests.swift`; `Tests/BrkThemeTests/ThemeRendererTests.swift`. The complete test-name index was also searched to map requirement coverage.
- Native scenario assertions: `Sources/BrkE2E/Scenarios.swift`, `Wave2Scenarios.swift`, `SettingsEditingScenario.swift`, `PlanScenarios.swift`, `RegressionScenarios.swift`, `NativeScenarios.swift`.
- Existing evidence: `bf1ea87186:verify/swift/focus-parent/source-sha256.json`, `native/REPORT.md`, `evidence/build.log`. The manifest was recomputed against every listed current file. Existing screenshots were not used to claim reference parity.

## Deliverables

The two primary files are this report and `docs/completion/proposals/native-shell.json`. Owned evidence files are `OwnershipProbe.swift`, `run-probes.py`, `probe-output.txt`, `swift-test.log`, `source-baseline.json`, `source-audit.json`, `validate.py`, `validation.json` and `flow.html`, all under `a3966b7375:verify/completion/native-grounding/`. The validation script checks row shape, exact ownership, evidence paths, source hashes and an in-memory merged inventory without writing the canonical file.

## Row disposition

The following table is generated from the proposal. Its counts describe this assigned set only: 2 verified, 23 implemented, 27 partial, 25 missing and 2 deferred. Full acceptance and evidence limits remain in the JSON.

| ID | Requirement | Proposed state |
|---|---|---|
| A001 | Window shell and title row | implemented |
| A002 | URL pill | implemented |
| A003 | Sidebar width | implemented |
| A004 | Show and hide sidebar | verified |
| A005 | Floating sidebar on hover | implemented |
| A006 | Toolbar mode | missing |
| A007 | Space header | partial |
| A008 | Today section and New Tab row | implemented |
| A009 | Closing a tab archives it | implemented |
| A010 | Pinned tabs | implemented |
| A011 | Reset all pinned tabs in a space | missing |
| A012 | Collapse pinned section | partial |
| A013 | Favorites grid | implemented |
| A014 | Favorite badges and subtitles | missing |
| A015 | Join meeting | missing |
| A016 | Next and previous tab | implemented |
| A017 | Recent-tab switcher | partial |
| A018 | Linear tab cycling | missing |
| A019 | Jump to item 1 to 9 and to space N | missing |
| A020 | Rename an item | implemented |
| A021 | Custom icons | partial |
| A022 | Drag and drop in the sidebar | implemented |
| A023 | Multi-select and bulk actions | partial |
| A024 | Duplicate | missing |
| A025 | Reveal tab and keyboard focus in the sidebar | partial |
| A026 | Clear Today | implemented |
| A027 | Restore last closed tab | implemented |
| A028 | Sidebar context menus | partial |
| A029 | Audio indicator and mute | missing |
| A030 | Page loading glow | partial |
| A031 | Hover cards and link previews | missing |
| A032 | Crashed page | partial |
| A033 | Tidy titles rule list | missing |
| A034 | Toasts | missing |
| A035 | Tab groups | missing |
| A056 | Create a space | partial |
| A057 | Switch spaces | implemented |
| A058 | Swipe between spaces | missing |
| A059 | Rename, icon and theme of a space | implemented |
| A060 | Delete and reorder spaces | partial |
| A061 | Space manager | missing |
| A062 | Theme background | implemented |
| A063 | Theme editor | partial |
| A064 | Light and dark theme values | missing |
| A065 | Theme colors for websites | missing |
| A066 | New-tab bar and address bar | implemented |
| A067 | Suggestions | partial |
| A068 | Actions in the bar ("Type Travel") | partial |
| A069 | Site search | partial |
| A070 | Search engine choice | implemented |
| A071 | Add and close panes | implemented |
| A072 | Resize panes | implemented |
| A073 | Split as one sidebar row | implemented |
| A074 | Horizontal and vertical | partial |
| A075 | Separate, expand, separate all | partial |
| A076 | Drag a tab into the page to split | missing |
| A077 | Jump between panes | missing |
| A078 | Auto-archive | verified |
| A079 | Archive page | implemented |
| A080 | Archive whole folders and splits | partial |
| A081 | Library | partial |
| A082 | Auto-archive education banner | missing |
| A089 | Folders | implemented |
| A090 | Collapse and expand all folders | missing |
| A091 | Folder open state per window | partial |
| A092 | Live Folders | missing |
| A113 | Settings window | partial |
| A114 | General pane | partial |
| A115 | Profiles pane | partial |
| A116 | Shortcuts pane and remapping | partial |
| A117 | Advanced pane | partial |
| A118 | App Icon pane | missing |
| A127 | Software updates | deferred |
| A128 | Update banner | deferred |
| A129 | About window | partial |
| A130 | Menu bar coverage | partial |
| A131 | Dock tile | missing |
| A132 | Menu bar status item | missing |
| A133 | AppleScript | missing |
