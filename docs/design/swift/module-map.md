# Module map: Brk on Swift, AppKit and CEF

Owners: **W1** domain and layout math, **W2** engine, window host and app store, **W3** sidebar UI, **W4** command bar, archive and dialogs, **W5** theme renderer, **W6** e2e harness and control protocol. Wave 2 adds **F1** settings, **F2** profiles and incognito, **F3** window kinds and external links, **F4** command bar, menu and remapping, **F5** Library; their paths, contracts, tests and scenarios are in `wave2.md`. **Contract** files are frozen at this skeleton: their types and public names do not change during parallel work. A worker that needs a contract change writes it down as a deviation in its report, and the integrator applies it. The function bodies inside a contract file are still written by the owner named in the table.

Every path below is relative to the repository root. Every file has exactly one owner; the owner of a directory owns every file under it unless a row names the file.

## Targets

Every module is a SwiftPM target. Paths are under `Sources/`.

| Module | Path | Owner | Hides | Exposes | Imported by |
|---|---|---|---|---|---|
| Base vocabulary | `BrkBase/` | contract (W1 maintains) | nothing | `ID<Tag>` with `ItemID`, `SpaceID`, `WindowID`, `ArchiveID`, `ProfileID`, `DownloadID`, `LinkRouteID`, `SearchEngineID`, `AIRequestID`; `Instant`; `Modifiers`, `Key` (a `CaseIterable` enum by key code), `KeyChord`, `KeyPress`, `KeyStage`, `PressID`; the page vocabulary `PageID`, `PageSpec` (with `BrowsingContext`), `PageAction`, `PageEvent`, `DownloadEvent`, `DownloadDecision`, `OpenDisposition`, `PageFacts`, `PageLogEntry`, `ShutdownOutcome`; `Metric`, `MetricSource`, `MetricGroup`, `Metrics` (the constants table); `Product`, `LaunchOptions` | every module |
| Domain: model | `BrkDomain/Model.swift`, `SettingsModel.swift`, `SidebarTree.swift` | W1 (`SettingsModel.swift`: F1, with F2/F3/F4 for their types) | every stored field; the hierarchy changes only inside `SidebarTree.swift` (`fileprivate(set)` on parent, body, children, panes, focus) | `AppState` (opaque), `ContainerScope`, `WindowKind`, `CustomIcon`, `NamedIcon`, `SpaceIcon`, `SplitOrientation`, `AutoArchiveThreshold`, `ArchiveReason`, `LoadFailure`, `SectionKind`, `ItemKind`, `Placement.canPlace`; the settings vocabulary `SettingsPane`, `GeneralSettings`, `ProfileSettings`, `LinkSettings`, `LinkRoute`, `LinkDestination`, `MaxSettings`, `AIProviderChoice`, `AIProviderKind`, `AdvancedSettings`, `KeyOverride`, `SearchEngine`, `LibraryPage`, `DownloadState`, `AITask`, `AIOutcome` | (domain only, plus the public types) |
| Domain: commands | `BrkDomain/Command.swift`, `Effect.swift` | contract (W1) | nothing | `Input`, `Command` and its fifteen area enums (`later(LaterFeature)` for greyed-out rows), `ItemRef`, `SpaceRef`, `Step`, `Destination`, `SystemEvent`, `WindowEvent`, `Effect`, `WindowEffect`, `AppEffect`, `MenuModel`, `ExportDocument`, `ExportEntry`, `ExportFormat` | BrkLayout, BrkUIKit, BrkSidebar, BrkOverlays, BrkLibrary, BrkSettings, BrkContent, BrkControl, BrkApp, BrkE2E |
| Domain: reducer | `BrkDomain/Reduce.swift`, `Rules/*.swift` (`Keys.swift` holds `routeKey`; wave 2: `Settings.swift` F1, `Profiles.swift` F2, `Windows.swift` and `Peek.swift` F3, `Library.swift` F5, `Assist.swift` later wave), `KeyRouting.swift`, `Normalize.swift`, `Codec.swift` | W1 | handler dispatch, the overlay rule, per-area rules, invariants, key priorities and press-twice memory, the file format and the export format | `reduce`, `Context`, `Transition`, `KeyInput`, `resolveTypedInput`, `isAllowedURL`, `displayURL`, `StateCodec`, `RestoreSeed`, `Restored`, `RestoreOutcome`, `CodecError`, `ExportCodec` | BrkApp (only `AppStore.swift` calls `reduce`) |
| Domain: projection | `BrkDomain/Snapshot.swift` (contract), `Project.swift` | W1 (`projectSettings` F1; the `library` and `peek` overlay arms F5 and F3) | how rows, titles, statuses, focus, pages, candidates and archive buckets are derived | `project`, `ProjectionContext`, `AppSnapshot` (with `settings`), `WindowSnapshot` and its parts (`kind`, `scratch`, `profileDialog`, `LibrarySnapshot`, `PeekSnapshot`, `ProfileBadge`), `SettingsSnapshot` and its rows, `FocusTarget`, `ArchiveBucket`, `archiveBucket` | BrkLayout, BrkTheme, every UI target, BrkControl, BrkApp, BrkE2E |
| Shortcut table | `BrkDomain/Actions.swift` | contract (W1; F4 edits listings and triggers) | nothing | `ActionID` (every Arc menu row), `ActionSpec` (`row`, `submenu`, `hidden`, `alternate`), `KeyBinding`, `KeyPriority`, `MenuName`, `Submenu`, `CommandBarListing`, `KeyBindingState`, `KeyBindingSource`, `ResolvedBinding`, `KeyBindings.resolve`, `KeyMap(overrides:)` | BrkApp (menu), BrkDomain (routing, command bar, settings), BrkOverlays (titles), BrkSettings |
| Theme model | `BrkDomain/Theme/SpaceTheme.swift` | types contract (W1); `resolveTheme` body W5 | luminance math, gradient derivation | `RGBA`, `Texture`, `ColorWheel`, `AppearanceChoice`, `Scheme`, `SpaceTheme`, `ThemePresets`, `SidebarTokens`, `ResolvedTheme`, `resolveTheme`, `relativeLuminance` | domain, BrkTheme, BrkUIKit |
| Layout | `BrkLayout/WindowFrames.swift` (contract), `WindowLayout.swift` (`LibraryLayout`: F5), `SidebarLayout.swift`, `SidebarResizeDrag.swift` | W1 | all geometry | `WindowFrames` (with `library`, `peek`), `LibraryFrames`, `CardFrame`, `SidebarFrames`, `RowFrame`, `ViewID`, `WindowLayout.compute`, `ContentLayout`, `CommandBarLayout`, `LibraryLayout`, `WindowPlacement.fit`, `SidebarLayout`, `FavoritesGrid`, `TablistLayout`, `DockLayout`, `SidebarResizeDrag` | every UI target, BrkControl, BrkApp, BrkE2E |
| Engine interface | `BrkEngine/WebEngine.swift` (contract), `PageLedger.swift` (contract), `PressCorrelator.swift`, `StubEngine.swift` | W2 | for the stub: placeholder views and synchronous load events | `WebEngine` (plus `forget(_ context:)`), `WebEngineDelegate` (plus `decideDownload`, `shouldNavigateTo`), `PageSurfaceView`, `PageLedger`, `PressCorrelator`, `StubEngine` | BrkCEF, BrkApp, `Brk` (main) |
| CEF engine | `BrkCEF/` | W2 | CEF init, the Chrome-runtime browser and host window per page, moving Chromium's views into the card, the key guard on host windows, CEF key translation, page close bookkeeping, shutdown order | `CEFEngine` (`bootstrap`, `Configuration`, the `WebEngine` methods) | `Brk` (main) only |
| Theme renderer | `BrkTheme/` | W5 | Metal pipeline, shader source, procedural textures, display-link crossfade (today: a gradient layer with a Core Animation crossfade) | `ThemeBackgroundView` (`show(_:animated:)`), `TexturePixels` | BrkContent |
| View contract | `BrkUIKit/Rendering.swift` | contract (W1 maintains) | nothing | `Dispatch`, `identify(_:)`, `Palette`, `Copy` | BrkSidebar, BrkOverlays, BrkContent, BrkApp |
| Sidebar views | `BrkSidebar/` | W3 | all AppKit drawing of the column, hover, drag preview, scroll, the rename field | `SidebarView` (`init(dispatch:)`, `render`, `focusRenameField`, `focusList`) | BrkContent |
| Overlay views | `BrkOverlays/` | W4 / F4 (`ArchivePageView.swift`: F5, moving to BrkLibrary) | the command bar's query, highlight and rows; the archive page; the space dialog form (SwiftUI in `NSHostingView`) | `CommandBarView` (`render`, `focusInput`), `ArchivePageView` (`render`), `SpaceDialogHost` (`render`, `focusForm`), `Suggest`, `Suggestion` | BrkContent, BrkOverlaysTests |
| Library | `BrkLibrary/` | F5 (Easels: R3-3) | the page strip and the pages (downloads, history, media, easels and notes, boosts, spaces; the archive page joins from BrkOverlays); an Easel's board, drawn over the card that shows it, and the drawing it shares with the Easels page's cards and Share's PNG | `LibraryView` (`init(dispatch:)`, `render`), `LibraryCopy`, `EaselBoardView` (`init(dispatch:)`, `render`, `focusBoard`), `EaselDrawing.png` | BrkContent, BrkLibraryTests |
| Settings window | `BrkSettings/` | F1 (F2, F3, F4 write their panes' contents) | the panes as SwiftUI in an `NSHostingView`; every control dispatches a `.settings(...)` command and keeps no state | `SettingsHost` (`init(dispatch:)`, `render(_:)`), `SettingsCopy` | BrkApp, BrkSettingsTests |
| Content and root | `BrkContent/` | W2 (`PeekCardView`: F3) | the card views, dividers, the Peek card, how the root composes the targets above | `WindowRootView` (`render(_:frames:surface:)`, `focus(_:)`), `ContentAreaView`, `PeekCardView`, `EaselExport` (Share's PNG for BrkApp, which may not import BrkLibrary) | BrkApp |
| Control protocol | `BrkControl/` | W6 | JSON line framing, the client socket | `ControlRequest`, `ControlOp` (plus `settings`, `openSettings`, `externalURL`), `ControlReply`, `ControlResult`, `NativeFacts`, `ActualView`, `AppWindowFact`, `Hello`, `ControlWire`, `ControlClient` | BrkApp, BrkE2E |
| App | `BrkApp/` | W2 (`Control/`: W6; `SettingsWindowController.swift`: F1; `ExternalLinks.swift` and the Little Arc host: F3; `MainMenu.swift`, `SuggestionFetcher.swift`: F4; `AIProvider.swift`, `ShareExport.swift`: wave 2 seams) | the state value, dispatch queue, effect execution, window controllers, the settings window, traffic-light placement, menu building, key adapters, download and navigation decisions, debounced atomic writes, quarantine, the clocks, launch and quit order, the control server, the AI tool runner, the export writer, the suggestion fetch, the GetURL handler | `Lifecycle`, `Quit`, `AppStore`, `WindowController`, `BrowserWindow`, `StateFile`, `Clock`, `SystemClock`, `OffsetClock`, `ClockError`, `AIProvider`, `AIProviderSeam`, `CLIProvider`, `AIPrompt`, `ShareExport`, `SuggestionFetcher`, `GetURLHandler`, `DefaultBrowser` | `Brk` (main) |
| Composition root | `Brk/main.swift` | W2 | which engine runs; CEF before `NSApp` | the executable | (none) |
| E2E runner | `BrkE2E/` | W6 | process launch, fixture server, polling, report writing, owned file-panel accessibility verification and system-wide input (`NativePickerInput.swift`: window-server key presses, the status item, a held hot key) | `brk-e2e` executable | (none) |
| Vendored CefSwift | `Vendor/CefSwift/` at `ba6ebff` | W2 (bumps only) | the CEF C API, refcounting, the dlopen loader, the message pump | `CefKit` product, the `cef` command plugin, `cef-helper` | BrkCEF only |

## Workers

| Worker | Owns (paths) | Frozen contracts it writes against | Tests it fills | Stubs left (`fatalError("not implemented")`) |
|---|---|---|---|---|
| W1 domain and layout math | `Sources/BrkBase/`, `Sources/BrkDomain/` (except `resolveTheme`'s body), `Sources/BrkLayout/`, `Sources/BrkUIKit/`, `Tests/BrkDomainTests/`, `Tests/BrkLayoutTests/`, `Tests/ArchitectureTests/` | `Command.swift`, `Effect.swift`, `Snapshot.swift`, `Actions.swift`, `WindowFrames.swift`, `Metrics.swift`, `Keys.swift`, `Page.swift` (types may not change; bodies and rules may) | 137 domain, 15 layout | BrkDomain 16, BrkLayout 1 |
| W2 engine, window host, app store | `Sources/BrkEngine/`, `Sources/BrkCEF/`, `Sources/BrkApp/*.swift`, `Sources/BrkContent/`, `Sources/Brk/`, `Vendor/CefSwift/` (bumps), `scripts/build.sh`, `Tests/BrkAppTests/`, `Tests/BrkEngineTests/` | `WebEngine.swift`, `PageLedger.swift`, `Page.swift`, `Snapshot.swift`, `WindowFrames.swift`, the public surfaces of BrkSidebar and BrkOverlays | 25 app | BrkCEF 7, BrkApp 2 (`WindowFrames.frame(of:)` reports layout-owned frames; view-owned ones come from `actual`) |
| W3 sidebar UI | `Sources/BrkSidebar/` | `Rendering.swift`, `Snapshot.swift`, `WindowFrames.swift`, `Command.swift`; its own public surface (`SidebarView`) | (W3's work shows in the e2e scenarios; unit cases for its layout are W1's) | 0 (first-pass bodies with `TODO(W3)` notes) |
| W4 command bar, archive, dialogs | `Sources/BrkOverlays/`, `Tests/BrkOverlaysTests/` | `Rendering.swift`, `Snapshot.swift`, `WindowFrames.swift`, `Command.swift`, `Actions.swift`; its own public surfaces | 12 suggestion | BrkOverlays 1 (`Suggest.rank`) |
| W5 theme renderer | `Sources/BrkTheme/`, `resolveTheme` in `Sources/BrkDomain/Theme/SpaceTheme.swift`, `Tests/BrkThemeTests/`, the theme cases in `Tests/BrkDomainTests/PolicySpecTests.swift` | `SpaceTheme.swift` types, `ThemeBackgroundView.show` signature | 3 texture, 9 theme | BrkTheme 4 |
| W6 e2e harness and control protocol | `Sources/BrkControl/`, `Sources/BrkApp/Control/`, `Sources/BrkE2E/`, `Tests/BrkControlTests/`, `Tests/E2ESite/`, `scripts/e2e.sh`, `scripts/ctl.sh` | `Protocol.swift` (W6 owns it but it is frozen for everyone else), `Snapshot.swift`, `WindowFrames.swift`, `WebEngine.swift` (`evaluate`, `facts`, `pageLog`) | 3 decode, 24 scenarios | BrkControl 2, BrkE2E 18 |

Totals at this skeleton: 258 XCTest cases, 63 run and pass, 195 `XCTSkip` stubs naming their owner; 51 first-party `fatalError("not implemented")` bodies (BrkDomain 16, BrkE2E 18, BrkCEF 7, BrkTheme 4, BrkApp 2, BrkControl 2, BrkLayout 1, BrkOverlays 1); 24 e2e scenarios registered as `todo`. Everything on the launch-and-idle path (restore, normalize, project, layout, first-pass renders, the stub engine, the store, lifecycle, menu, quit) runs: `BRK_ENGINE=stub swift run Brk` opens the shell.

Wave 2 workers (F1 to F5), their paths, the contracts they write against, their tests and scenarios, and the dependency order are in `wave2.md`. At the wave-2 contract commit: 379 tests run, 30 `XCTSkip` stubs naming their owner, no `fatalError("not implemented")` left (every reducer arm has a total first-pass body), 24 scenarios PASS and W2-1 to W2-12 registered `pending` their owner.

What "first pass" means: the integrator wrote the simplest body that makes the shell open and left `TODO(Wn)` notes where the owner's spec goes further (projection candidates, the space-title counter, favorites drag and drop, rename field, suggestion rows, archive groups, the Metal renderer). Owners replace those bodies; they do not treat them as frozen.

## Dependency rules

```
BrkDomain   -> BrkBase
BrkLayout   -> BrkDomain, BrkBase
BrkEngine   -> BrkBase
BrkCEF      -> BrkEngine, BrkBase, CefKit (vendored)
BrkTheme    -> BrkDomain, BrkBase
BrkUIKit    -> BrkLayout, BrkDomain, BrkBase
BrkSidebar  -> BrkUIKit, BrkLayout, BrkDomain, BrkBase
BrkOverlays -> BrkUIKit, BrkLayout, BrkDomain, BrkBase
BrkLibrary  -> BrkUIKit, BrkLayout, BrkDomain, BrkBase
BrkSettings -> BrkUIKit, BrkLayout, BrkDomain, BrkBase
BrkContent  -> BrkSidebar, BrkOverlays, BrkLibrary, BrkTheme, BrkUIKit, BrkLayout, BrkDomain, BrkBase
BrkControl  -> BrkLayout, BrkDomain, BrkBase
BrkApp      -> BrkContent, BrkSettings, BrkUIKit, BrkControl, BrkEngine, BrkTheme, BrkLayout, BrkDomain, BrkBase
Brk (main)  -> BrkApp, BrkCEF, BrkEngine, BrkBase
BrkE2E      -> BrkControl, BrkLayout, BrkDomain, BrkBase
```

Each line lists the first-party modules a module may import. Apple frameworks are allowed per module as well (AppKit only in BrkEngine, BrkCEF, BrkTheme, the UI targets, BrkApp and main; Metal and QuartzCore only in BrkTheme; SwiftUI only in BrkOverlays and BrkSettings; UniformTypeIdentifiers only in BrkApp; `os` only in BrkEngine, BrkCEF and BrkApp); the exact lists are in `ImportRulesTests.allowedImports`. Browser-basic document output adds PDFKit in BrkCEF for output validation, BrkApp for native printing, and BrkE2E for independent file parsing. BrkApp also uses Carbon for its registered Little Brk global shortcut. Only `BrkE2E/NativePickerInput.swift` may import ApplicationServices to drive the owned remote file panel through accessibility. AppKit remains forbidden in BrkE2E. These system imports add no first-party dependency edge.

1. `BrkBase`, `BrkDomain`, `BrkLayout` and `BrkControl` import only Foundation and CoreGraphics besides each other: no AppKit, so the reducer, the projection, the layout and the wire format are testable headless and cannot touch views.
2. `BrkEngine` imports only BrkBase and AppKit: it knows pages, not tabs.
3. Only `BrkCEF` imports `CefKit`, `CCef` or `CCefAppKit`, and only `Brk/main.swift` imports `BrkCEF`. BrkApp holds `any WebEngine`.
4. `BrkSidebar`, `BrkOverlays` and `BrkLibrary` never import each other, and never import `BrkApp`, `BrkEngine` or `BrkCEF`; `BrkApp` composes the browser window's views only through `BrkContent` and reaches a view's keyboard focus only through `WindowRootView.focus(_:)`. The settings window is its own NSWindow, so `BrkApp` hosts `BrkSettings` directly (`SettingsWindowController`). Views get page surfaces as plain `NSView`s through a closure and send intent through `Dispatch`.
5. `BrkE2E` never imports `BrkApp` or any UI target: model state and commands pass through the control socket. Only `NativePickerInput.swift` observes and operates the owned system file panel through accessibility.
6. Single writers: only `BrkApp/AppStore.swift` calls `reduce`; only `BrkApp/Clock.swift` reads the real time (`Date()`); only `BrkDomain/SidebarTree.swift` changes hierarchy, kinds, panes or split focus (enforced by `fileprivate(set)` and a fileprivate `Item.init`, not by a scan); only `BrkCEF` adds child windows or replaces methods; only `BrkDomain/Codec.swift`, `BrkControl` and the runner create JSON coders; no `cornerRadius = <number>` outside `BrkBase/Metrics.swift`; only `BrkApp/Lifecycle.swift` and `AppStore.swift` ask for a quit, through `Quit.request()`.

How each rule is enforced:

- **Target graph.** `Package.swift` declares exactly the edges above. An import of an undeclared module fails to compile; `scripts/build.sh` builds with `--explicit-target-dependency-import-check error` so a module reachable only transitively fails too.
- **Types.** `AppState` has only internal stored properties, so code outside BrkDomain cannot read the tree. Hierarchy, kind, panes and focus are settable only in `SidebarTree.swift`; `SplitPanes` cannot hold fewer than two or more than `Metrics.content.maxPanes` panes; a `SidebarTree` refuses roots of another `ContainerScope`. A `Metric` cannot be built without a `MetricSource`. `ActionID.spec` is an exhaustive switch, so an action without a table row does not compile, and `Work.run` is an exhaustive switch over `Command`, so an area without rules does not compile. `WindowDoc.container` is an exhaustive switch over `WindowKind`, so a new window kind has to say where its items live. `Key` is `CaseIterable`, so there is no second key list.
- **`ArchitectureTests`.** `ImportRulesTests` scans every `import` (including `@testable` and `@preconcurrency`) under `Sources/` against a per-target allow list, checks the single-writer patterns of rule 6 by file, checks that every target directory is in the rule table, and proves each rule with a negative case (an AppKit import in BrkDomain, `Date()` in a rule file, `reduce(` in the key router, a literal radius in a view, a sibling view-target import, a worker view import from BrkApp). `MetricInventoryTests` walks `Metrics` by reflection and reads `Metrics.swift` for free globals: a bare number anywhere in the table, an `.arc` row the constants document does not have, a confidence the row does not state, or a guess without a reason fails. Both run in `swift test`.
- **`package` access level** is not used. All our targets are in one package, so `package` would mean the same as `public` to every sibling; the boundary is the target graph above. Everything a sibling may call is `public` and listed in the table, and everything else is `internal` by default.

## Frozen contracts, by path

| Contract | Path | What it fixes |
|---|---|---|
| Commands and effects | `Sources/BrkDomain/Command.swift`, `Sources/BrkDomain/Effect.swift` | every input a view, key, socket or page can produce; every one-shot the reducer can ask for |
| Snapshot | `Sources/BrkDomain/Snapshot.swift` | what views render, what layout reads, what the socket returns |
| Frames and view ids | `Sources/BrkLayout/WindowFrames.swift` | `WindowFrames`, `SidebarFrames`, `RowFrame`, `CardFrame`, `ViewID` and its identifier strings |
| Engine protocol | `Sources/BrkEngine/WebEngine.swift`, `Sources/BrkEngine/PageLedger.swift`, `Sources/BrkBase/Page.swift` | the seven calls, the delegate, the page vocabulary, the identity rule for reused ids, `ShutdownOutcome` |
| Control protocol | `Sources/BrkControl/Protocol.swift` | every op, every reply, the wire framing |
| Actions table | `Sources/BrkDomain/Actions.swift` | titles, menus, bindings with priorities, command-bar listings |
| Metrics | `Sources/BrkBase/Metrics.swift` | every layout, motion and theme number with its source |
| Keys and press identity | `Sources/BrkBase/Keys.swift` | `Key`, `KeyChord`, `KeyPress`, `KeyStage`, `PressID` and its correlation rule |
| View contract | `Sources/BrkUIKit/Rendering.swift` plus the public surfaces of `WindowRootView`, `SidebarView`, `CommandBarView`, `ArchivePageView`, `SpaceDialogHost` | `Dispatch`, `identify`, `Palette`, `Copy`; render and focus entry points |
| Container seam | `ContainerScope`, `Session.scratch`, `AppState.tree/withTree/locate`, `WindowDoc.container` in `Sources/BrkDomain/Model.swift`; `SectionRole.scratch` in `SidebarTree.swift` | how ephemeral windows' items enter the reducer and the projection |
| Codec envelope | `StoredFile`, `StoredFileV1` (decode only), `StoredFileV2`, `CodecError`, `StateCodec.migrate`, `StoredDocV2.init(_:)`/`init(v1:)`/`validated(ctx:)` in `Sources/BrkDomain/Codec.swift` | the versioned file and its conversions; v2 is current |
| Settings | `SettingsCommand` and its per-pane enums in `Command.swift`; `SettingsSnapshot` in `Snapshot.swift`; the setting structs in `SettingsModel.swift` | every settings field, how it is changed and how it is read (window and socket) |
| Library and Peek | `LibraryCommand`, `PeekCommand`, `LibrarySnapshot`, `PeekSnapshot`, `LibraryFrames`, `WindowFrames.peek` | the Library host, its pages, the Peek card |
| Windows | `WindowKind`, `WindowCommand`, `WindowSnapshot.kind/scratch`, `SystemEvent.externalURL`, `LinkRoute`/`LinkDestination` | standard, incognito and Little Arc windows; links from other apps |
| Profiles | `ProfileCommand`, `ProfileDialogSnapshot`, `ProfileBadge`, `BrowsingContext`, `WebEngine.forget` | profiles, their contexts, the dialogs |
| Export and AI seams | `ExportDocument`, `ExportCodec`, `Effect.export`; `AITask`, `AIOutcome`, `Effect.ai`, `SystemEvent.aiResult`, `AIProvider` (BrkApp) | share-by-file; the local command-line AI tools |

## Control socket contract

### Launch

- Environment: `BRK_CONTROL_SOCKET=<path>` starts the server (never set in a normal launch); `BRK_DATA_DIR=<dir>` replaces `~/Library/Application Support/Brk` (state.json, quarantined files, the Chromium cache, `shutdown-incomplete.log`); `BRK_TEST_CLOCK=1` makes the clock real time plus an offset that only `advanceClock` moves; `BRK_START_URL=<url>` is the one tab of a fresh profile; `BRK_ENGINE=stub` runs without Chromium; `BRK_REMOTE_DEBUGGING_PORT` opens CEF DevTools.
- The runner launches `dist/Brk.app/Contents/MacOS/Brk` directly (not through `open`), so it owns the process and its exit status. Screen capture of the app's own window works without the screen-recording permission (spike unknown 8) and while the display is locked (`CGWindowListCreateImage` by window id, as the integrator used to verify the stub shell).
- The runner waits for `hello` (up to 10 s: the first launch creates the Chromium profile in 4.3 s, later launches answer in 1.2 s, spike unknown 7).

### Transport

A Unix stream socket. One JSON object per line in each direction: `{"id": n, "op": {...}}` and `{"id": n, "result": {...}}`. Requests on one connection run in order on the main actor. The types are `BrkControl/Protocol.swift`, used by both the server and the runner, so the two cannot disagree. `scripts/ctl.sh <socket> '<json>'` sends one line by hand.

### Operations

Every op maps to a capability the executor can reach through BrkApp's allowed imports: `AppStore` (dispatch, snapshot, flush), `WindowController` (frames, window), `WebEngine` (`surface`, `facts`, `evaluate`, `pageLog`, `perform`), `OffsetClock`, `NSApp.sendEvent`, `CGWindowListCreateImage`, `Quit.request`.

| Op | Does | Reply |
|---|---|---|
| `hello` | readiness probe | pid, engine kind, window ids, data directory |
| `view(window)` | the window's last rendered `WindowSnapshot` | `view` |
| `native(window)` | `WindowLayout.compute` of the last snapshot, every view with an accessibility identifier and its real frame (window coordinates, top-left), hidden flag and layer radius; `PageFacts` of every page in the window; first responder; every app window with its key flag | `native(NativeFacts)` |
| `dispatch(window, command)` | decodes a `Command` and dispatches it as if a view sent it | `dispatched(rev)` |
| `load(window, url)` | scenario setup: opens `url` as a new Today tab with the same two commands Cmd+T, typing and Enter produce | `loaded(tab)` |
| `press(chord)` | in-process key-down and key-up `NSEvent`s into `NSApp.sendEvent` for the key window; with a page focused they reach Chromium and CEF's key handler exactly like real presses (spike unknown 3); with a native view focused they reach the menu | `ok` |
| `hold(modifiers, chord, times)` | modifier down, `times` presses, modifier up (Ctrl+Tab cycling) | `ok` |
| `type(text)` | key events for each character into the first responder | `ok` |
| `click(view or point, modifiers, count)` | in-process mouse down and up at the centre of the live view with that identifier, or at a window point; `modifiers: "cmd"` for Cmd+click on a page link | `ok` |
| `hover(point)` | mouse-moved event (peek the hidden sidebar) | `ok` |
| `screenshot(window, path)` | `CGWindowListCreateImage` of the window, written as PNG | path and pixel size |
| `pixel(window, point)` | one sRGB pixel of a fresh capture at a window point in points | RGBA 0 to 255 |
| `advanceClock(seconds)` | moves the test clock forward and dispatches `.system(.clockTick)`; a negative value is `failed` (the clock refuses it) | `clock(now)` |
| `evaluate(page, script)` | `WebEngine.evaluate`: runs JavaScript in a page, no result (fixtures report through `document.title`) | `ok` |
| `crash(page, renderer or gpu)` | loads `chrome://crash` or `chrome://gpucrash` in the page | `ok` |
| `setWindowFrame(window, frame)` | moves the NSWindow (screen coordinates) | `ok` |
| `pageLog` | `WebEngine.pageLog`: `created`, `closeRequested` and `closed` (OnBeforeClose) entries with page id, generation and browser id, in order | `pageLog` |
| `flush` | writes state.json now (drains pending debounced writes) | `ok` |
| `settle(timeout)` | waits until no page is loading and the main queue is idle | `ok` or `failed` |
| `quit` | `Quit.request()`: the ordered quit; replies before the process exits. Exit status 0 after a clean shutdown, 3 (`Lifecycle.shutdownTimedOutStatus`) when browsers did not close in time, with `shutdown-incomplete.log` in the data directory | `ok` |
| `settings` | `AppSnapshot.settings`: every saved value, the resolved shortcut table, the open pane | `settings(SettingsSnapshot)` |
| `openSettings(pane)` | dispatches `.settings(.openPane(pane))` on the key window, as Preferences… does | `dispatched(rev)` |
| `externalURL(url)` | dispatches `.system(.externalURL(url))`, as the GetURL Apple Event does | `dispatched(rev)` |

`BRK_SUGGEST_URL=<url>` (wave 2) replaces every search engine's suggest endpoint so the fixture server answers W2-10; `click(view:)` finds the view in any app window (the settings window included).

Restart is the runner's job: `quit`, wait for exit, launch again with the same `BRK_DATA_DIR`.

After every scenario the runner checks three things for free: no CEF host window is ever key (`native().appWindows`), the process exits with status 0, and no new crash report appears in `~/Library/Logs/DiagnosticReports`. The spike's Mode B crashed at quit in 5 of 5 runs, so that check is part of every pass; a status of 3 is the engine saying so in words.

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
| 8 | Cmd+W closes the page | open a tab, `press("cmd+w")` | `pageLog` has `closeRequested` then `closed` for its page (OnBeforeClose); `native().pages` no longer has it; the row is gone from Today (archived) |
| 9 | Restart restores everything | new space, two tabs, pin one, open `/fail`, focus page2, `dispatch(.sidebar(.resize(width: 300)))`, `flush`, restart | the same dock, space, pinned and Today ids, URLs and titles, current tab and width 300 before and after; after restart `native().pages` holds only the current tab (lazy restore); the `/fail` tab kept its URL and title |
| R2 | Peek keeps the archive open | `press("cmd+s")`, `dispatch(.archive(.open))`, `hover` the reveal strip | `view().sidebar.peek` true and the overlay is still the archive; `floating-sidebar` is above the archive |
| R3 | Cmd+click opens a background tab that loads | `click(point: link, modifiers: "cmd")` in fixture home | Today has two rows, focus stays on home, the new row becomes loaded and its title is "Fixture Page 2" |
| R5a | Ctrl+Tab after 11 h is not archived an hour later | open B, `advanceClock(11 h)`, `hold("ctrl", "tab", 1)`, `advanceClock(1 h 1 min)` | B is still in Today |
| R5b | Dropped on another space after 13 h is not swept | new space, back to the first, `advanceClock(13 h)`, `dispatch(.item(.move(x, to: .space(work))))`, `advanceClock(1 min)` | x is in Work's Today |
| R6 | Ctrl+Tab twice returns | open B, Cmd+D twice, open C, `hold("ctrl", "tab", 1)` twice | current is B after the first hold, C after the second |
| R7a | `window.close()` leaves no blank card | open `close.html` | within 8 s: `pageLog` closed for it without a `closeRequested` (page-initiated), the row is gone, every card in `native()` has a surface or is the empty-card placeholder that `view()` predicts |
| R7b | A crashed renderer is recovered with no other input | `crash(page, .renderer)` | within 8 s, with no further op: the page's surface has its Chromium views again and the card midpoint is the page's white |
| R8 | A window saved off every display reopens on screen | `setWindowFrame(x: 5000, y: 4000)`, `flush`, restart | the restored window frame intersects a screen's visible frame |
| R9 | Only the current space's surface is attached | new space with `red.html`, `click(.dockSpace(first))` | `native().pages` lists exactly the panes `view()` shows; the card midpoint pixel is white, not red |
| R10 | A GPU crash leaves the native sidebar working | `crash(page, .gpu)` | within 8 s the card midpoint is the page's white again; a click on a dock space still switches space |
| N1 | Key priorities and press identity | open page2, then `keys.html` focused: `press("cmd+t")`, `press("escape")`, `press("cmd+shift+k")`; then `keys.html?swallow=1`: `press("cmd+s")` twice; then two rapid `press("cmd+r")` | Cmd+T opens the bar and the page title never shows `cmd+t`; Cmd+Shift+K (page priority) reaches the page first (title `key:cmd+shift+k:seen`) and then clears page2 from Today; with swallow, the first Cmd+S goes to the page and the sidebar stays, the second within 1 s hides the sidebar; two unconsumed Cmd+R presses reload twice (two after-page ids, no false duplicate) |
| N2 | Focus round trip, host windows never key | `press("cmd+l")`, `type("x")`, `press("escape")`, `type("y")` | the bar input had focus and the page did not get "x"; after Esc the page title shows `key:y:seen`; no host window in `appWindows` was ever key |
| N3 | Pixel layout equals the constants | launch, `native()` | traffic lights at x 13 with 14 pt size centred 24 from the top; `url-pill` height 36, 8 from each sidebar side, radius 12; favorites tiles at least 47 with gap 8; rows 40 tall on a 41 pitch; `dock` height 50; every computed frame equals its `actual` frame |
| N4 | Clean quit with many pages | three tabs, a split, `quit` | exit status 0 within 10 s (3 would mean the engine timed out), no new crash report, `pageLog` has `closed` for every created page |
| W2-1 to W2-12 | Wave 2 (settings, profiles, incognito, new window, Little Arc, Peek, external links, type travel, remapping, suggestions, downloads, history) | see `wave2.md` | registered `pending` their owner (SKIPPED without a launch) until the owner makes them pass |

Scenario 7 asserts the archive page at `computed.library.page` since wave 2 (the Library host fills the content area with a page strip on top); R2 opens `.library(.open(.archive))`.

## Accessibility identifiers

Set by the UI targets from `BrkLayout.ViewID`, never typed by hand. The runner addresses views by the same enum.

| ViewID | Identifier |
|---|---|
| `.sidebar`, `.floatingSidebar`, `.titleRow`, `.urlPill`, `.favoritesTray` | `sidebar`, `floating-sidebar`, `title-row`, `url-pill`, `favorites` |
| `.favorite(id)`, `.section(kind)`, `.row(id)`, `.rowClose(id)` | `favorite-<id>`, `section-favorites` / `section-pinned` / `section-today` / `section-scratch`, `row-<id>`, `row-<id>-close` |
| `.todayNewTab`, `.todayClear`, `.renameField` | `today-new-tab`, `today-clear`, `rename-field` |
| `.dock`, `.dockSpace(id)`, `.dockLibrary`, `.dockPlus` | `dock`, `dock-space-<id>`, `dock-library`, `dock-plus` |
| `.resizeHandle`, `.revealStrip` | `sidebar-resize`, `reveal-strip` |
| `.card(i)`, `.divider(i)` | `card-<i>`, `split-divider-<i>` |
| `.commandBar`, `.commandBarInput`, `.commandBarResult(i)` | `command-bar`, `command-bar-input`, `command-bar-result-<i>` |
| `.archive`, `.archiveGroup(bucket)`, `.archiveEntry(id)`, `.archiveRestore(id)`, `.archiveClear`, `.archiveThreshold` | `archive`, `archive-group-<bucket>`, `archive-entry-<id>`, `archive-restore-<id>`, `archive-clear`, `archive-threshold` |
| `.spaceDialog`, `.themeBackground` | `space-dialog`, `theme-background` |
| `.library`, `.libraryPage(page)`, `.libraryClose`, `.downloadEntry(id)`, `.historyEntry(i)` | `library`, `library-page-<page>`, `library-close`, `download-<id>`, `history-<i>` |
| `.peek`, `.peekClose`, `.peekOpenIn`, `.littleHint` | `peek`, `peek-close`, `peek-open-in`, `little-hint` |
| `.profileBadge`, `.profileDialog` | `profile-badge`, `profile-dialog` |
| `.settingsWindow`, `.settingsPane(pane)`, `.settingsField(name)` | `settings`, `settings-pane-<pane>`, `settings-field-<name>` |

## Build layout

- `swift build` and `swift test` work with no CEF on disk: CefKit loads the framework with `dlopen` at run time. `BRK_ENGINE=stub swift run Brk` opens the full shell with placeholder pages; `BRK_DATA_DIR` points it at a scratch profile (restoring an existing state.json needs W1's `validated(ctx:)` first).
- `scripts/build.sh`: reads the product name from `Package.swift`, builds with the explicit import check, runs the tests, runs the vendored plugin's `cef bundle` (downloads CEF 154.0.34 minimal arm64 once into `.cef/`, SHA-1 checked; builds the product and `cef-helper`; assembles `dist/Brk.app` with `Brk Helper.app`, `Brk Helper (Alerts).app`, `(GPU)`, `(Plugin)`, `(Renderer)`; sets `LSEnvironment MallocNanoZone=0`; signs ad hoc), then verifies the signature. Notarization is out of scope.
- `scripts/e2e.sh`: build (unless `SKIP_BUILD=1`), then `swift run brk-e2e --app dist/Brk.app --site Tests/E2ESite --out verify/swift`, which writes `verify/swift/REPORT.md` (PASS, FAIL or SKIPPED per scenario, with the machine, the CEF version and timings) and `verify/swift/shots/`.
- `scripts/ctl.sh`: one control request by hand.
