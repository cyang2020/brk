# Module map: Brk on Swift, AppKit and CEF

Owners: **W1** domain, **W2** engine and window host, **W3** sidebar views and sidebar layout, **W4** command bar and archive, **W5** theme, **W6** e2e harness and control server. **Contract** files are frozen at this skeleton: their types and public names do not change during parallel work. A worker that needs a contract change writes it down as a deviation in its report, and the integrator applies it. The function bodies inside a contract file are still written by the owner named in the table.

## Modules

Every module is a SwiftPM target. Paths are under `Sources/`.

| Module | Path | Owner | Hides | Exposes | Imported by |
|---|---|---|---|---|---|
| Base vocabulary | `BrkBase/` | contract (W1) | nothing | `ID<Tag>` with `ItemID`, `SpaceID`, `WindowID`, `ArchiveID`, `ProfileID`; `Instant`; `Modifiers`, `Key`, `KeyChord`, `KeyPress`, `KeyStage`; the page vocabulary `PageID`, `PageSpec`, `PageAction`, `PageEvent`, `OpenDisposition`, `PageFacts`; `Metric`, `MetricSource`, `Metrics` (the constants file); `Product`, `LaunchOptions` | every module |
| Domain: model | `BrkDomain/Model.swift`, `SidebarTree.swift` | W1 | every stored field; the hierarchy can only change inside `SidebarTree.swift` (`fileprivate(set)`) | `AppState` (opaque: no readable fields), `SpaceIcon`, `AutoArchiveThreshold`, `ArchiveReason`, `LoadFailure`, `SectionKind`, `ItemKind`, `Placement.canPlace` | (domain only, plus the public types) |
| Domain: commands | `BrkDomain/Command.swift`, `Effect.swift` | contract (W1) | nothing | `Input`, `Command` and its ten area enums, `ItemRef`, `SpaceRef`, `Step`, `Destination`, `SystemEvent`, `WindowEvent`, `Effect`, `MenuModel` | BrkLayout, BrkUI, BrkControl, BrkApp, BrkE2E |
| Domain: reducer | `BrkDomain/Reduce.swift`, `Rules/*.swift`, `Normalize.swift`, `KeyRouting.swift` | W1 (KeyRouting: W2) | handler dispatch, the overlay rule, per-area rules, invariants, key priorities and press-twice memory | `reduce`, `Context`, `Transition`, `KeyInput`, `resolveTypedInput`, `isAllowedURL` | BrkApp (only `AppStore.swift` calls `reduce`) |
| Domain: projection | `BrkDomain/Snapshot.swift`, `Project.swift` | contract types (W1); `archiveBucket` body W4 | how rows, titles, statuses, focus, pages and candidates are derived | `project`, `ProjectionContext`, `AppSnapshot`, `WindowSnapshot` and its parts, `FocusTarget`, `ArchiveBucket`, `archiveBucket` | BrkLayout, BrkTheme, BrkUI, BrkControl, BrkApp, BrkE2E |
| Domain: codec | `BrkDomain/Codec.swift` | W1 | the state file format (`StoredDocV1`, private), versions, migration, repair | `StateCodec.encode`, `StateCodec.restore`, `RestoreSeed`, `Restored`, `RestoreOutcome` | BrkApp |
| Shortcut table | `BrkDomain/Actions.swift` | contract (W2 may add rows) | nothing | `ActionID`, `ActionSpec`, `KeyBinding`, `KeyPriority`, `MenuName`, `CommandBarListing`, `KeyMap` | BrkApp (menu), BrkDomain (routing, command bar), BrkUI (titles) |
| Theme model | `BrkDomain/Theme/SpaceTheme.swift` | W5 | luminance math, gradient derivation | `RGBA`, `Texture`, `AppearanceChoice`, `Scheme`, `SpaceTheme`, `ThemePresets`, `SidebarTokens`, `ResolvedTheme`, `resolveTheme` | domain, BrkTheme, BrkUI |
| Layout | `BrkLayout/WindowFrames.swift` (contract), `WindowLayout.swift`, `SidebarResize.swift` | W2 (window, content, command bar, placement); W3 (`SidebarLayout`, `FavoritesGrid`, `TablistLayout`, `DockLayout`, `SidebarResizeDrag`) | all geometry | `WindowFrames`, `CardFrame`, `SidebarFrames`, `RowFrame`, `ViewID` (accessibility identifiers), `WindowLayout.compute`, the sub-layouts, `SidebarResizeDrag`, `WindowPlacement.fit` | BrkUI, BrkControl, BrkApp, BrkE2E |
| Engine interface | `BrkEngine/WebEngine.swift` (contract), `StubEngine.swift` | W2 | for the stub: placeholder views and fake page events | `WebEngine`, `WebEngineDelegate`, `PageSurfaceView`, `StubEngine` | BrkCEF, BrkApp, `Brk` (main) |
| CEF engine | `BrkCEF/` | W2 | CEF init, the Chrome-runtime browser and host window per page, moving Chromium's views into the card, the key guard on host windows, CEF key translation, page close bookkeeping, shutdown order | `CEFEngine` (`bootstrap`, `Configuration`, the `WebEngine` methods) | `Brk` (main) only |
| Theme renderer | `BrkTheme/` | W5 | Metal pipeline, shader source, procedural textures, display-link crossfade | `ThemeBackgroundView` (`show(_:animated:)`), `TexturePixels` | BrkUI |
| Views | `BrkUI/` | W2 (`WindowRootView`, `Content/`), W3 (`Sidebar/`), W4 (`CommandBar/`, `Archive/`), W5 (`Dialogs/`) | all AppKit drawing, hover, drag preview, typed query, scroll; SwiftUI only inside `NSHostingView` (the space dialog) | `Dispatch`, `WindowRootView` (`render(_:frames:surface:)`), `Palette`, `Copy`, `Suggest`, `Suggestion`, `identify(_:)` | BrkApp |
| Control protocol | `BrkControl/` | W6 | JSON line framing, the client socket | `ControlRequest`, `ControlOp`, `ControlReply`, `ControlResult`, `NativeFacts`, `ActualView`, `AppWindowFact`, `PageLogEntry`, `Hello`, `ControlWire`, `ControlClient` | BrkApp, BrkE2E |
| App | `BrkApp/` | W2 (W6: `Control/`) | the state value, dispatch queue, effect execution, window controllers, traffic-light placement, menu building, key adapters, debounced atomic writes, quarantine, the clocks, launch and quit order, the control server | `Lifecycle`, `AppStore`, `WindowController`, `BrowserWindow`, `StateFile`, `Clock`, `SystemClock`, `OffsetClock` | `Brk` (main) |
| Composition root | `Brk/main.swift` | W2 | which engine runs; CEF before `NSApp` | the executable | (none) |
| E2E runner | `BrkE2E/` | W6 | process launch, fixture server, polling, report writing | `brk-e2e` executable | (none) |
| Vendored CefSwift | `Vendor/CefSwift/` at `ba6ebff` | W2 (bumps only) | the CEF C API, refcounting, the dlopen loader, the message pump | `CefKit` product (`CefRuntime`, `CefChromeBrowser`, `CefBrowser`, `CefBrowserDelegate`, `CefKeyEvent`), the `cef` command plugin, `cef-helper` | BrkCEF only |

Tests (`Tests/`): `BrkDomainTests` (reducer spec ported from `electron-v1:src/domain/*.test.ts`, URL, placement, theme and archive-bucket policy, key routing, the shortcut table, vocabulary round trips; `Driver.swift` is the test harness), `BrkLayoutTests` (Electron layout cases and Arc-constant geometry), `BrkUITests` (suggestion ranking), `BrkThemeTests` (texture determinism and tiling), `BrkControlTests` (protocol round trips, boundary decoding), `BrkAppTests` (state file, clocks, key adapters, menu built from the table), `ArchitectureTests` (import and single-writer rules). Today: 213 tests, 22 run and pass, 191 are `XCTSkip` stubs naming their owner.

## Dependency rules

```
BrkDomain   -> BrkBase
BrkLayout   -> BrkDomain, BrkBase
BrkEngine   -> BrkBase
BrkCEF      -> BrkEngine, BrkBase, CefKit (vendored)
BrkTheme    -> BrkDomain, BrkBase
BrkUI       -> BrkTheme, BrkLayout, BrkDomain, BrkBase
BrkControl  -> BrkLayout, BrkDomain, BrkBase
BrkApp      -> BrkUI, BrkControl, BrkEngine, BrkTheme, BrkLayout, BrkDomain, BrkBase
Brk (main)  -> BrkApp, BrkCEF, BrkEngine, BrkBase
BrkE2E      -> BrkControl, BrkLayout, BrkDomain, BrkBase
```

Each line lists the first-party modules a module may import. Apple frameworks are allowed per module as well (AppKit only in BrkEngine, BrkCEF, BrkTheme, BrkUI, BrkApp and main; Metal and QuartzCore only in BrkTheme; SwiftUI only in BrkUI); the exact lists are in `ImportRulesTests.allowedImports`.

1. `BrkBase`, `BrkDomain`, `BrkLayout` and `BrkControl` import only Foundation and CoreGraphics besides each other: no AppKit, so the reducer, the projection, the layout and the wire format are testable headless and cannot touch views.
2. `BrkEngine` imports only BrkBase and AppKit: it knows pages, not tabs.
3. Only `BrkCEF` imports `CefKit`, `CCef` or `CCefAppKit`, and only `Brk/main.swift` imports `BrkCEF`. BrkApp holds `any WebEngine`.
4. `BrkUI` never imports `BrkApp`, `BrkEngine` or `BrkCEF`: views get page surfaces as plain `NSView`s through a closure, and send intent through `Dispatch`.
5. `BrkE2E` never imports `BrkApp` or `BrkUI`: the runner sees the app only through the control socket.
6. Single writers: only `BrkApp/AppStore.swift` calls `reduce`; only `BrkApp/Clock.swift` reads the real time (`Date()`); only `BrkDomain/SidebarTree.swift` changes `parent` or `children` (enforced by `fileprivate(set)`, not by a scan); only `BrkCEF` adds child windows or replaces methods; only `BrkDomain/Codec.swift`, `BrkControl` and the runner create JSON coders; no `cornerRadius = <number>` outside `BrkBase/Metrics.swift`.

How each rule is enforced:

- **Target graph.** `Package.swift` declares exactly the edges above. An import of an undeclared module fails to compile; `scripts/build.sh` builds with `--explicit-target-dependency-import-check error` so a module reachable only transitively fails too.
- **Types.** `AppState` has only internal stored properties, so code outside BrkDomain cannot read the tree. `Item.parent` and `Item.children` are `fileprivate(set)` in `SidebarTree.swift`. A `Metric` cannot be built without a `MetricSource`. `ActionID.spec` is an exhaustive switch, so an action without a table row does not compile, and `Work.run` is an exhaustive switch over `Command`, so an area without rules does not compile.
- **`ArchitectureTests/ImportRulesTests.swift`.** Scans every `import` (including `@testable` and `@preconcurrency`) under `Sources/` against a per-target allow list, checks the single-writer patterns of rule 6 by file, checks that every target directory is in the rule table, and proves each rule with a negative case (an AppKit import in BrkDomain, `Date()` in a rule file, `reduce(` in the key router, a literal radius in a view). It runs in `swift test`.
- **`package` access level** is not used. All our targets are in one package, so `package` would mean the same as `public` to every sibling; the boundary is the target graph above. Everything a sibling may call is `public` and listed in the table, and everything else is `internal` by default.

## Control socket contract

### Launch

- Environment: `BRK_CONTROL_SOCKET=<path>` starts the server (never set in a normal launch); `BRK_DATA_DIR=<dir>` replaces `~/Library/Application Support/Brk` (state.json, quarantined files, the Chromium cache); `BRK_TEST_CLOCK=1` makes the clock real time plus an offset that only `advanceClock` moves; `BRK_START_URL=<url>` is the one tab of a fresh profile; `BRK_ENGINE=stub` runs without Chromium; `BRK_REMOTE_DEBUGGING_PORT` opens CEF DevTools.
- The runner launches `dist/Brk.app/Contents/MacOS/Brk` directly (not through `open`), so it owns the process and its exit status. Screen capture of the app's own window works without the screen-recording permission (spike unknown 8).
- The runner waits for `hello` (up to 10 s: the first launch creates the Chromium profile in 4.3 s, later launches answer in 1.2 s, spike unknown 7).

### Transport

A Unix stream socket. One JSON object per line in each direction: `{"id": n, "op": {...}}` and `{"id": n, "result": {...}}`. Requests on one connection run in order on the main actor. The types are `BrkControl/Protocol.swift`, used by both the server and the runner, so the two cannot disagree. `scripts/ctl.sh <socket> '<json>'` sends one line by hand.

### Operations

| Op | Does | Reply |
|---|---|---|
| `hello` | readiness probe | pid, engine kind, window ids, data directory |
| `view(window)` | the window's last rendered `WindowSnapshot` | `view` |
| `native(window)` | `WindowLayout.compute` of the last snapshot, every view with an accessibility identifier and its real frame (window coordinates, top-left), hidden flag and layer radius; `PageFacts` of every page in the window (surface frame, embedded Chromium view classes, browser id, host window number); first responder; every app window with its key flag | `native(NativeFacts)` |
| `dispatch(window, command)` | decodes a `Command` and dispatches it as if a view sent it | `dispatched(rev)` |
| `load(window, url)` | scenario setup: opens `url` as a new Today tab with the same two commands Cmd+T, typing and Enter produce | `loaded(tab)` |
| `press(chord)` | in-process key-down and key-up `NSEvent`s into `NSApp.sendEvent` for the key window. With a page focused they reach Chromium and CEF's key handler exactly like real presses (spike unknown 3); with a native view focused they reach the menu | `ok` |
| `hold(modifiers, chord, times)` | modifier down, `times` presses, modifier up (Ctrl+Tab cycling) | `ok` |
| `type(text)` | key events for each character into the first responder | `ok` |
| `click(view or point, modifiers, count)` | in-process mouse down and up at the centre of the live view with that identifier, or at a window point; `modifiers: "cmd"` for Cmd+click on a page link | `ok` |
| `hover(point)` | mouse-moved event (peek the hidden sidebar) | `ok` |
| `screenshot(window, path)` | `CGWindowListCreateImage` of the window, written as PNG | path and pixel size |
| `pixel(window, point)` | one sRGB pixel of a fresh capture at a window point in points | RGBA 0 to 255 |
| `advanceClock(seconds)` | moves the test clock and dispatches `.system(.clockTick)` | `clock(now)` |
| `evaluate(page, script)` | runs JavaScript in a page, no result (fixtures report through `document.title`) | `ok` |
| `crash(page, renderer or gpu)` | loads `chrome://crash` or `chrome://gpucrash` in the page | `ok` |
| `setWindowFrame(window, frame)` | moves the NSWindow (screen coordinates) | `ok` |
| `pageLog` | pages created and closed (OnBeforeClose) since launch, in order | `pageLog` |
| `flush` | writes state.json now | `ok` |
| `settle(timeout)` | waits until no page is loading and the main queue is idle | `ok` or `failed` |
| `quit` | starts the ordered quit; replies before the process exits | `ok` |

Restart is the runner's job: `quit`, wait for exit, launch again with the same `BRK_DATA_DIR`.

After every scenario the runner checks two things for free: no CEF host window is ever key (`native().appWindows`), and at quit the process exits with status 0 and no new crash report appears in `~/Library/Logs/DiagnosticReports`. The spike's Mode B crashed at quit in 5 of 5 runs, so that check is part of every pass.

### Fixture site

`Tests/E2ESite/` served on 127.0.0.1 by the runner: `index.html` "Fixture Home" (white, a link to `page2.html` at a fixed position for Cmd+click), `page2.html` "Fixture Page 2", `red.html` "Red" (full red), `close.html` "Closer" (calls `window.close()` after 300 ms), `keys.html` (records the last key it saw in its title; `?swallow=1` calls `preventDefault`), and `/fail`, which drops the connection.

## E2E scenarios

Scenarios 0 to 9 are the Electron plan's done predicate. R2 to R10 are `electron-v1:e2e/regression.spec.ts` (finding 1 there was unit-only and is in the reducer spec). N1 to N4 are new checks for what the native design adds. Every scenario launches with a fresh data directory and `BRK_START_URL` = fixture home. Constants are from `Metrics`.

| # | Scenario | Drives with | Asserts on |
|---|---|---|---|
| 0 | Launch smoke | launch, `hello` | one window; `view()` has one dock item and one Today row with status current; `native().actual` has `sidebar` and `card-0`; the screenshot is at least the content size |
| 1 | One page in one card, inset and rounded | launch, `settle` | `card-0` frame x = sidebar width + 10, y = 10, width and height inset 10 on the other sides; radius 6; `PageFacts.embeddedViews` lists the two Chromium views; `pixel` 1 pt inside the card corner equals the background sampled just outside the card (the corner is cut); the card midpoint is white |
| 2 | Cmd+T, URL, Enter adds a Today tab that loads | `press("cmd+t")`, `type(page2 URL)`, `press("return")` | `command-bar` visible at `computed.commandBar` (766 wide, centered) while open; then Today has one more row with status current, title "Fixture Page 2"; `command-bar` hidden; `pageLog` shows the page created |
| 3 | Cmd+D to Pinned and back | `press("cmd+d")` twice | the row moves to `space.pinned`, `section-pinned` contains `row-<id>`, `canReset` false; then back in Today |
| 4 | Dock click switches space and background | `dispatch(.space(.create(...)))` with a Drab theme, open a tab, `click(.dockSpace(first))` | `view().space.id` is the first space, its row is visible and the other space's is not; `pixel(4, 200)` differs by more than 24 per channel from the sample taken after the crossfade settled in the second space |
| 5 | Cmd+S hides the sidebar; again restores | `press("cmd+s")` twice | hidden: `card-0` = window inset 10 on every side, radius 6, `sidebar` hidden; shown again: x = sidebar width + 10 |
| 6 | Ctrl+Shift+= makes a split | `press("ctrl+shift+=")`, type URL, return | two cards, same y and height, `card-0.maxX + 10 == card-1.minX`; `view().content.split` set; one split row with two panes; the command bar was open for the empty pane; after Enter the second page's title is "Fixture Page 2" |
| 7 | Auto-archive, archive page, restore | open B (A goes idle), `advanceClock(13 h)`, `click(.dockLibrary)`, `click(.archiveRestore(id))` | A leaves Today, B stays (visible tabs never archive); `archive` frame equals `computed.contentArea`; the entry for A has reason auto and is in `archive-group-today`; after restore A is back in Today |
| 8 | Cmd+W closes the page | open a tab, `press("cmd+w")` | `pageLog` has `closed` for its page (OnBeforeClose); `native().pages` no longer has it; the row is gone from Today (archived) |
| 9 | Restart restores everything | new space, two tabs, pin one, open `/fail`, focus page2, `dispatch(.sidebar(.resize(width: 300)))`, `flush`, restart | the same dock, space, pinned and Today ids, URLs and titles, current tab and width 300 before and after; after restart `native().pages` holds only the current tab (lazy restore); the `/fail` tab kept its URL and title |
| R2 | Peek keeps the archive open | `press("cmd+s")`, `dispatch(.archive(.open))`, `hover` the reveal strip | `view().sidebar.peek` true and the overlay is still the archive; `floating-sidebar` is above the archive |
| R3 | Cmd+click opens a background tab that loads | `click(point: link, modifiers: "cmd")` in fixture home | Today has two rows, focus stays on home, the new row becomes loaded and its title is "Fixture Page 2" |
| R5a | Ctrl+Tab after 11 h is not archived an hour later | open B, `advanceClock(11 h)`, `hold("ctrl", "tab", 1)`, `advanceClock(1 h 1 min)` | B is still in Today |
| R5b | Dropped on another space after 13 h is not swept | new space, back to the first, `advanceClock(13 h)`, `dispatch(.item(.move(x, to: .space(work))))`, `advanceClock(1 min)` | x is in Work's Today |
| R6 | Ctrl+Tab twice returns | open B, Cmd+D twice, open C, `hold("ctrl", "tab", 1)` twice | current is B after the first hold, C after the second |
| R7a | `window.close()` leaves no blank card | open `close.html` | within 8 s: `pageLog` closed for it, the row is gone, every card in `native()` has a surface or is the empty-card placeholder that `view()` predicts |
| R7b | A crashed renderer is recovered with no other input | `crash(page, .renderer)` | within 8 s, with no further op: the page's surface has its Chromium views again and the card midpoint is the page's white |
| R8 | A window saved off every display reopens on screen | `setWindowFrame(x: 5000, y: 4000)`, `flush`, restart | the restored window frame intersects a screen's visible frame |
| R9 | Only the current space's surface is attached | new space with `red.html`, `click(.dockSpace(first))` | `native().pages` lists exactly the panes `view()` shows; the card midpoint pixel is white, not red |
| R10 | A GPU crash leaves the native sidebar working | `crash(page, .gpu)` | within 8 s the card midpoint is the page's white again; a click on a dock space still switches space |
| N1 | Key priorities | open page2, then `keys.html` focused: `press("cmd+t")`, `press("escape")`, `press("cmd+shift+k")`; then `keys.html?swallow=1`: `press("cmd+s")` twice | Cmd+T opens the bar and the page title never shows `cmd+t`; Cmd+Shift+K (page priority) reaches the page first (title `key:cmd+shift+k:seen`) and then clears page2 from Today; with swallow, the first Cmd+S goes to the page and the sidebar stays, the second within 1 s hides the sidebar |
| N2 | Focus round trip, host windows never key | `press("cmd+l")`, `type("x")`, `press("escape")`, `type("y")` | the bar input had focus and the page did not get "x"; after Esc the page title shows `key:y:seen`; no host window in `appWindows` was ever key |
| N3 | Pixel layout equals the constants | launch, `native()` | traffic lights at x 13 with 14 pt size centred 24 from the top; `url-pill` height 36, 8 from each sidebar side, radius 12; favorites tiles at least 47 with gap 8; rows 40 tall on a 41 pitch; `dock` height 50; every computed frame equals its `actual` frame |
| N4 | Clean quit with many pages | three tabs, a split, `quit` | exit status 0 within 10 s, no new crash report, `pageLog` has `closed` for every created page |

## Accessibility identifiers

Set by BrkUI from `BrkLayout.ViewID`, never typed by hand. The runner addresses views by the same enum.

| ViewID | Identifier |
|---|---|
| `.sidebar`, `.floatingSidebar`, `.titleRow`, `.urlPill`, `.favoritesTray` | `sidebar`, `floating-sidebar`, `title-row`, `url-pill`, `favorites` |
| `.favorite(id)`, `.section(kind)`, `.row(id)`, `.rowClose(id)` | `favorite-<id>`, `section-favorites` / `section-pinned` / `section-today`, `row-<id>`, `row-<id>-close` |
| `.todayNewTab`, `.todayClear`, `.renameField` | `today-new-tab`, `today-clear`, `rename-field` |
| `.dock`, `.dockSpace(id)`, `.dockLibrary`, `.dockPlus` | `dock`, `dock-space-<id>`, `dock-library`, `dock-plus` |
| `.resizeHandle`, `.revealStrip` | `sidebar-resize`, `reveal-strip` |
| `.card(i)`, `.divider(i)` | `card-<i>`, `split-divider-<i>` |
| `.commandBar`, `.commandBarInput`, `.commandBarResult(i)` | `command-bar`, `command-bar-input`, `command-bar-result-<i>` |
| `.archive`, `.archiveGroup(bucket)`, `.archiveEntry(id)`, `.archiveRestore(id)`, `.archiveClear`, `.archiveThreshold` | `archive`, `archive-group-<bucket>`, `archive-entry-<id>`, `archive-restore-<id>`, `archive-clear`, `archive-threshold` |
| `.spaceDialog`, `.themeBackground` | `space-dialog`, `theme-background` |

## Build layout

- `swift build` and `swift test` work with no CEF on disk: CefKit loads the framework with `dlopen` at run time. `BRK_ENGINE=stub swift run Brk` opens the full shell with placeholder pages.
- `scripts/build.sh`: reads the product name from `Package.swift`, builds with the explicit import check, runs the tests, runs the vendored plugin's `cef bundle` (downloads CEF 154.0.34 minimal arm64 once into `.cef/`, SHA-1 checked; builds the product and `cef-helper`; assembles `dist/Brk.app` with `Brk Helper.app`, `Brk Helper (Alerts).app`, `(GPU)`, `(Plugin)`, `(Renderer)`; sets `LSEnvironment MallocNanoZone=0`; signs ad hoc), then verifies the signature. Notarization is out of scope.
- `scripts/e2e.sh`: build (unless `SKIP_BUILD=1`), then `swift run brk-e2e --app dist/Brk.app --site Tests/E2ESite --out verify/swift`, which writes `verify/swift/REPORT.md` (PASS, FAIL or SKIPPED per scenario, with the machine, the CEF version and timings) and `verify/swift/shots/`.
- `scripts/ctl.sh`: one control request by hand.
