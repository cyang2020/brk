# Module map

Owners: **W1** domain, **W2** main process, **W3** sidebar UI, **W4** command bar and archive UI, **S** scaffold (phase 3) and integrator (phase 5). "Contract" files are frozen at this skeleton: their types and exported names do not change during parallel work. A worker that needs a change records it as a deviation in its report and the integrator applies it. A contract file's function bodies are still written by the named owner.

## Modules

| Module | Path | Owner | Hides | Exposes | Imported by |
|---|---|---|---|---|---|
| Base types | `src/shared/base.ts` | contract (W1) | nothing | `ItemId`, `SpaceId`, `WindowId`, `ArchiveId`, `Instant`, `Platform`, `Point`, `Size`, `Rect`, their zod schemas | everything |
| Commands | `src/shared/commands.ts` | contract (W1 writes `parseUiCommand`) | validation of untrusted renderer messages | `UiCommandSchema`, `UiCommand`, `SystemCommand` (page/updated, page/open, pane/focused, tab/cycle-recent-commit, window/bounds, clock/tick), `Input`, `PagePatch`, `Destination`, `ItemRef`, `parseUiCommand` | domain, main, preload, renderers, e2e |
| Shortcut table | `src/shared/actions.ts` | contract (W2 writes `paletteActions`) | nothing | `ACTIONS`, `ActionId`, `ActionSpec`, `MENU_ORDER` (a `Record<MenuName, number>`), `paletteActions` | `shared/accelerator`, `main/input`, `overlay/suggest` |
| Accelerators | `src/shared/accelerator.ts` | W2 | accelerator grammar, physical key-code matching, platform rules | `parseAccelerator`, `createKeymap`, `formatAccelerator`, `findConflicts`, `KeyInput` | `main/input`, `main/test-api`, `overlay/suggest` |
| View contract | `src/shared/view.ts` | contract (W1) | nothing | `WindowView` and its parts (`OverlayView` with `openId`, `ArchiveView.anchor`), `LayoutView`, `ArchiveBucket` | `domain/project`, main, renderers, e2e |
| Bridge contract | `src/shared/bridge.ts` | contract (W2) | nothing | `ArcBridge`, `SurfaceKind`, `window.arc` | preload, `renderer/common`, main |
| Theme | `src/shared/theme.ts` | W1 | luminance math, gradient derivation, scheme choice | `SpaceTheme`, `SpaceIcon` (emoji, named, none), `NAMED_ICONS`, `NamedIcon`, schemas, `THEME_PRESETS`, `SIDEBAR_TOKENS`, `ResolvedTheme`, `resolveTheme`, `themeFromPrimary`, `DEFAULT_THEME` | domain, `shared/commands`, `sidebar/SpaceDialog` and `sidebar/Dock` (icons, preview), `renderer/common/theme-vars` |
| Placement rules | `src/shared/placement.ts` | W1 | the v1 rule table | `SECTION_KINDS`, `SectionKind`, `PlaceableKind`, `canPlace` | `domain/tree`, `domain/codec`, `sidebar/dnd` |
| URL policy | `src/shared/url.ts` | W1 | address-vs-search heuristics, allowed schemes | `resolveTypedInput`, `isAllowedUrl`, `displayUrl`, `TypedInput` | `domain/ops/tabs`, `domain/project`, `overlay/suggest` |
| Constants | `src/shared/constants.ts` | contract | nothing (every guess is labeled) | `LAYOUT`, `TIMING`, `CAPS`, `AUTO_ARCHIVE_AFTER`, `AUTO_ARCHIVE_MS`, `DEFAULT_AUTO_ARCHIVE`, `ARCHIVE_REASONS`, `ArchiveReason`, `DEFAULT_WINDOW_SIZE`, `urlPillRect` | everything |
| Copy | `src/shared/copy.ts` | contract (W3 and W4 may append) | nothing | `COPY` | `domain/select` (menu labels), renderers |
| Test ids | `src/shared/testids.ts` | contract (W3 sidebar block, W4 overlay block, append-only) | nothing | `TID` | renderers, e2e |
| Test API contract | `src/shared/test-api.ts` | contract (W2) | nothing | `ArcTestApi`, `NativeWindowFacts`, `NativeLayer`, `LayerCapture`, `TEST_ENV`, `TEST_API_GLOBAL`, the `globalThis.__arc` declaration | `main/test-api`, e2e |
| IPC channels | `src/ipc/channels.ts` | W2 | channel names, surface argument | `CHANNEL`, `SURFACE_ARG_PREFIX` | preload, `main/ipc`, `main/window-host` |
| Domain API | `src/domain/index.ts` | W1 | everything below | `reduce`, `windowIds`, `selectWindow`, `loadedTabIds`, `projectWindow`, `restoreState`, `serializeState`; types `AppState` (opaque), `Effect`, `WebEffect`, `MenuEntry`, `Ctx`, `Transition`, `WindowSelection`, `PaneSelection`, `FocusTarget`, `RestoreDefaults`, `RestoreOutcome` | main only |
| Model | `src/domain/model.ts` | W1 | data structures, opaque-handle casts | (domain-internal) | domain |
| Reducer | `src/domain/reduce.ts` | W1 | handler dispatch, overlay rule, rev, immer | `reduce`, `Handlers`, `HandlerCtx`, `keepsOverlay` | domain index, ops |
| Handlers | `src/domain/ops/{tabs,sidebar,spaces,split,archive,window}.ts` | W1 | per-command policy | handler groups; `openTab`, `focusItem`, `archiveItems`, `restoreEntry` (takes `HandlerCtx`), `sweepAutoArchive`, `openOverlay`, `closeOverlay` | `domain/reduce`, each other |
| Tree | `src/domain/tree.ts` | W1 | `parentId`/`children` consistency, move legality, `pinnedUrl` upkeep | `getItem`, `locate`, `childrenOf`, `tabsUnder`, `sidebarOrder`, `insertItem`, `moveItem`, `removeSubtree`, `repairTree` | ops, normalize, select, project, codec |
| Invariants | `src/domain/normalize.ts` | W1 | every cross-entity rule (repairs only; never fills an absent active item) | `normalize` | reduce, codec |
| Selectors | `src/domain/select.ts` | W1 | what is visible, focus derivation, popup menu models | `windowIds`, `selectWindow`, `loadedTabIds` (public); `focusedTabId`, `visibleTabIds`, `menuFor` (internal) | domain index, ops, project |
| Projection | `src/domain/project.ts` | W1 | turning the tree into rows, titles, statuses, candidates | `projectWindow` | domain index |
| Codec | `src/domain/codec.ts` | W1 | the file format (`StoredDocV1Schema`, `StoreFileSchema`), versions, `migrate`, repair on load | `restoreState`, `serializeState`, `RestoreOutcome` | domain index |
| Fresh profile | `src/domain/initial.ts` | W1 | defaults of a new profile | `createInitialDoc`, `createInitialSession` | codec |
| Effects | `src/domain/effects.ts` | W1 | nothing | `Effect`, `WebEffect`, `MenuEntry` | domain, main (types) |
| Domain tests | `src/domain/reduce.test.ts` | W1 | nothing | the test inventory (`it.todo` until written) and the handler-group disjointness test | vitest |
| Entry | `src/main/index.ts` | W2 | env, paths, startup order | nothing | (Electron) |
| App | `src/main/app.ts` | W2 | the state value, dispatch queue, effect execution, host lifecycle, sweep timer | `startApp`, `App` | `main/index`, `main/test-api` |
| Window host | `src/main/window-host.ts` | W2 | BaseWindow, surfaces, stack order (archive under a peeked sidebar, command bar on top), bounds, radius, focus, view pushes | `createWindowHost`, `WindowHost`, `SurfaceSource` | `main/app` |
| Tab runtime | `src/main/tab-runtime.ts` | W2 | webContents creation, per-view generations, page and focus events, async close, window-open handler, page context menu | `createTabRuntime`, `TabRuntime`, `TabViewEntry` | `main/app`, `main/window-host` |
| Layout | `src/main/layout.ts` (tests: `src/main/layout.test.ts`) | W2 | geometry math, the overlay rect per overlay kind | `computeLayout`, `Layout`, `LayoutInput` | `main/window-host`, `main/app` |
| Input | `src/main/input.ts` | W2 | menu building, before-input-event, the dedupe rule, popup menus | `createKeyRouter`, `KeyRouter`, `installAppMenu`, `popupMenu`, `Dispatch` | `main/app`, `main/window-host`, `main/tab-runtime` |
| IPC | `src/main/ipc.ts` | W2 | `ipcMain`, parsing, sender routing | `installIpc`, `SenderRoute` | `main/app` |
| Store | `src/main/store.ts` | W2 | file IO, debounce, atomic rename, quarantine | `openDocStore`, `DocStore` | `main/index`, `main/app` |
| Clock | `src/main/clock.ts` | W2 | `Date.now()` | `Clock`, `TestClock`, `systemClock`, `createTestClock` | `main/index`, `main/app`, `main/test-api` |
| Test API | `src/main/test-api.ts` | W2 | `sendInputEvent`, captures, global install | `createTestApi`, `installTestApi` | `main/index` |
| Preload | `src/preload/index.ts` | W2 | `ipcRenderer`, channels, surface argument | `window.arc` | (Electron) |
| Renderer common | `src/renderer/common/{bridge,theme-vars}.ts` | W3 | `useSyncExternalStore` wiring, CSS variable names | `useWindowView`, `dispatch`, `currentSurface`, `themeVars` | sidebar, overlay |
| Sidebar UI | `src/renderer/sidebar/*` | W3 | all sidebar rendering, named-icon glyphs, drag and drop | `SidebarApp` (entry) | (sidebar entry only) |
| Drag geometry | `src/renderer/sidebar/dnd.ts` | W3 | hit testing | `dropAt`, `RowGeometry`, `DropPreview` | sidebar |
| Overlay UI | `src/renderer/overlay/*` | W4 | command bar and archive rendering (the archive fills the card-sized overlay view) | `OverlayApp` (entry) | (overlay entry only) |
| Suggestions | `src/renderer/overlay/suggest.ts` | W4 | ranking | `suggest`, `commandFor`, `Suggestion` | overlay |
| Archive buckets | `src/renderer/overlay/archive-groups.ts` | W4 | calendar math | `groupArchive`, `bucketOf`, `ArchiveGroup` | overlay |
| E2E harness | `e2e/fixtures.ts`, `e2e/markdown-reporter.ts`, `e2e/playwright.config.ts`, `e2e/docker-run.sh`, `e2e/site/` | S | Playwright launch, page-to-webContents mapping, compositing, the static fixture server, the report | `test`, `expect`, `Arc` | `e2e/arc.spec.ts` |
| E2E scenarios | `e2e/arc.spec.ts` | S | nothing | the nine done-predicate scenarios plus a launch smoke, `test.skip` until W2 lands | Playwright |
| Build and checks | `package.json`, `tsconfig*.json`, `electron.vite.config.ts`, `vitest.config.ts`, `src/architecture.test.ts` | S | toolchain | scripts `dev`, `build`, `typecheck`, `test`, `e2e`, `e2e:docker` | |

## Dependency direction

```
src/shared  <-  src/domain  <-  src/main  ->  src/ipc  <-  src/preload
    ^                                                          |
    +----------------------------------------------------------+
    ^
    +--  src/renderer/common  <-  src/renderer/sidebar
    |                         <-  src/renderer/overlay
    +--  e2e
```

Arrows point from the importer to the imported module.

1. `src/shared` imports only `src/shared` and `zod`. No Electron, DOM or Node APIs: it compiles into all three tsconfig projects.
2. `src/domain` imports only `src/domain`, `src/shared`, `immer` and `zod`. No `electron`, no `node:*`.
3. Code outside `src/domain` imports it only through `src/domain/index.ts`. `AppState` is opaque, so nothing outside can read the tree even structurally.
4. Renderers import only their own bundle directory, `src/renderer/common` and `src/shared`. `sidebar` and `overlay` never import each other.
5. `e2e` imports only `e2e` and `src/shared`.
6. Single writers: only `src/domain/tree.ts` assigns `parentId` or `children`; only `src/main/tab-runtime.ts` and `src/main/window-host.ts` construct `WebContentsView`; only `src/main/clock.ts` calls `Date.now()`; only `src/main/app.ts` calls `reduce`.

Enforcement: the three composite tsconfig projects reject imports of files outside their `include` (TS6307), which covers rules 4 and 5 against node-side code and keeps `src/ipc` out of renderers. `src/architecture.test.ts` scans the import specifiers of every file under `src/` and `e2e/` (comments stripped) for rules 1 to 5 and the single-writer patterns of rule 6, and proves itself with negative cases (for example `src/main` importing `../domain/tree`). Test files may also import `vitest`.

## E2E hook contract

### Launch

- Env: `ARC_E2E=1` installs the test API and the offset test clock; `ARC_USER_DATA=<dir>` sets `userData` before ready; `ARC_START_URL=<url>` is the single tab of a fresh profile.
- Linux adds `--no-sandbox` (the container runs as root). The app is `out/main/index.js` after `electron-vite build`.
- The fixture waits for `globalThis.__arc` and for a `chrome` layer in `native()` before handing the harness to the test.

### Test API on `globalThis.__arc` (reached through `electronApp.evaluate`)

| Method | Returns / does |
|---|---|
| `windowIds()` | ids of open windows |
| `view(windowId?)` | the `WindowView` the window's renderers receive |
| `native(windowId?)` | attached layers bottom to top: role (`chrome`, `pane`, `floating-sidebar`, `overlay`), webContents id, tab id, bounds, radius; content size; background color; focused webContents id. The `overlay` layer is the full window for the command bar and exactly the content card for the archive |
| `dispatch(command, windowId?)` | parses with `UiCommandSchema`, then the normal dispatch path |
| `press(accelerator, windowId?)` | `sendInputEvent` keyDown/keyUp into the window's focused webContents, so before-input-event and menu accelerators run |
| `advanceClock(ms)` | moves the test clock forward, dispatches `clock/tick`, returns the new time |
| `tabWebContentsId(tabId)` | webContents id of a loaded tab, else null |
| `destroyedWebContentsIds()` | tab webContents whose `destroyed` event fired, in order |
| `captureLayers(windowId?)` | `capturePage()` PNG of each attached layer with its layer facts |
| `flush()` | writes state.json now |
| `userDataPath()` | the profile directory |

### Harness (`Arc` in `e2e/fixtures.ts`)

`surface(kind)`, `tabPage(tabId)`, `pageForWebContentsId(id)`, `view()`, `native()`, `dispatch(command)`, `press(accelerator)`, `advanceClock(ms)`, `waitForDestroyed(webContentsId)`, `compositeScreenshot(name)`, `layerPixel(role, x, y)`, `restart()`. The `siteUrl` fixture serves `e2e/site/` (`index.html` titled "Fixture Home", `page2.html` titled "Fixture Page 2") and drops the socket on `/fail`.

### Page discovery and input

- Never pick Playwright pages by index. The harness maps each Page to its webContents id with CDP `Target.getTargetInfo` and `webContents.fromDevToolsTargetId`, then matches ids from `native()`.
- App shortcuts go through `press()`. Playwright's `page.keyboard` is for typing into inputs (command bar, rename) only.
- A closed tab is gone when its webContents id appears in `destroyedWebContentsIds()`, not when `isDestroyed()` is checked right after closing.

### Stable selectors (`TID` in `src/shared/testids.ts`)

Sidebar: `sidebar`, `floating-sidebar`, `theme-background`, `url-pill`, `section-<kind>`, `section-<kind>-toggle`, `today-new-tab`, `today-clear`, `row-<itemId>` (with `data-status`, `data-kind`), `row-<itemId>-close`, `rename-input`, `dock`, `dock-space-<spaceId>` (with `data-active`), `dock-archive`, `dock-plus`, `sidebar-resize`, `split-divider-<i>`, `peek-zone`, `space-dialog*` (including `space-dialog-icon-<name>`). Overlay: `command-bar`, `command-bar-input`, `command-bar-result-<i>`, `archive`, `archive-group-<bucket>`, `archive-entry-<archiveId>`, `archive-restore-<archiveId>`, `archive-clear`, `archive-threshold`.

### Screenshots and report

`captureLayers()` plus the harness's `compositeScreenshot` (each layer in a rounded clip of its radius, drawn bottom to top on a canvas in the chrome page) produce `verify/shots/<n>-<name>.png`. `e2e/markdown-reporter.ts` writes `verify/REPORT.md` with PASS, FAIL or SKIPPED per scenario and the counts in the header. `npm run e2e:docker` (`e2e/docker-run.sh`) builds and runs the suite on Linux/Xvfb in the Playwright image and copies `933155f61c:verify/` back.

### Scenario to hooks

| # | Scenario | Drives with | Asserts on |
|---|---|---|---|
| 0 | Launch smoke: test API, chrome layer, sidebar DOM | launch | `native()` layer 0, sidebar `TID.sidebar`, `view()` dock and Today |
| 1 | Launch shows sidebar and one tab, card inset and rounded | launch | `native()` layers, pane bounds and radius; composite corner pixel equals chrome pixel |
| 2 | Cmd+T, type URL, Enter adds a Today tab that loads it | `press('CmdOrCtrl+T')`, overlay `command-bar-input` | `view().space.today.rows`, `tabPage(id).url()` and title |
| 3 | Cmd+D to Pinned and back | `press('CmdOrCtrl+D')` twice | `view().space.pinned/today.rows`, sidebar DOM `section-pinned` |
| 4 | Dock click switches space and gradient | `dispatch(space/new)`, click `dock-space-<id>` | `view().space.id`, sidebar rows, `layerPixel('chrome', ...)` distance |
| 5 | Cmd+S hides sidebar, content fills with inset and radius, again restores | `press('CmdOrCtrl+S')` twice | `native()` pane bounds and radius, `view().sidebar.visible` |
| 6 | Ctrl+Shift+= makes two side-by-side tab views | `press('Ctrl+Shift+=')`, fill the command bar | `native()` two `pane` layers left to right, `view().content.splitId` |
| 7 | Clock past threshold archives idle Today tab; archive shows and restores it | `advanceClock(13h)`, click `dock-archive`, `archive-restore-<id>` | `view().space.today.rows` before and after, overlay `archive-group-today`, overlay layer bounds equal `view().content.rect` |
| 8 | Closing a tab destroys its webContents | `press('CmdOrCtrl+W')`, `waitForDestroyed` | `destroyedWebContentsIds()` contains the tab's id; no layer with it |
| 9 | Restart restores spaces, Pinned, Today, current tab, sidebar width | `dispatch(sidebar/resize)`, `restart()` | the same reduction of `view()` before and after; the `/fail` tab survives with its title |
