# Design rationale: Brk on Swift, AppKit and CEF

## Problem

We are rebuilding Arc as a native macOS app: AppKit for the shell, Chromium through CEF for pages, Swift 6 with strict concurrency, SwiftPM at the repo root. The first wave covers the core (sidebar, spaces, Pinned and Today, Favorites, folders, command bar, split view, archive and auto-archive, theme, persistence, shortcuts). Every other feature in anatomy section 3 has to fit later without reshaping that core. Six workers fill in the bodies in parallel, so the shape has to give each of them fixed types to work against and separate files to own.

These constraints from the grounding make the shape non-obvious:

- The only hosting mode that gave a clipped rounded card, native views over the page, focus going and coming back, Arc-style key priority, live split resize and `chrome://extensions` is the Chrome-runtime embed: each page gets its own CEF-owned host window, and Chromium's `ViewsCompositorSuperview` and `WebContentsViewCocoa` are moved into our card (cef-hosting-results.md). It crashed at quit in 5 of 5 runs, it depends on private Chromium classes, and it leaves one empty host window per page that must never become key.
- While a page has focus, AppKit menu key equivalents never fire. CEF's `OnPreKeyEvent` sees the key before the page and `OnKeyEvent` sees it after, if the page did not consume it. So every app shortcut, including Cmd+Q, must go through the CEF key handler, and the same table must still drive the menu for native focus and the command bar's action list.
- Arc's model (anatomy 1.4 to 1.9) is one flat map of sidebar items with parent ids and ordered children; spaces point at Pinned and Today roots; Favorites is one root per profile; a split is an item whose children are its panes; archived items keep a snapshot with a reason and a source. The Electron version ported that model behind one state owner and a pure reducer, and its 77 reducer tests plus the regression scenarios are the behavioral spec. That domain carries over.
- 77 layout numbers are now known from Arc's binary (layout-constants.md), each with a confidence. Pixel faithfulness means one place for them, a source for each, and a way to check the window against them.
- The CefSwift package that the spike used is a one-person project with no human commits since June. The user ruled out building on cra and copying its code.

## Usage (caller's view)

Written first; the types under `Sources/` are derived from these call sites.

### W1, domain

`AppStore` is the reducer's only production caller. It holds an opaque `AppState` and uses three functions from BrkDomain.

```swift
// BrkApp/AppStore.swift: the only writer of state
let t = reduce(state, input, Context(now: clock.now(), newID: { UUID().uuidString }))
guard t.changed else { return t.keyHandled }
state = t.state
snapshot = project(state, ProjectionContext(now: clock.now(), calendar: calendar))
if t.docChanged { stateFile.schedule(StateCodec.encode(state)) }
engine.reconcile(snapshot.pages)
for (id, window) in snapshot.windows { controller(for: id).render(window) }
run(t.effects)
```

Its tests are its other callers. `Driver` builds state only from `StateCodec.restore(nil, ...)` plus commands and reads only what views and the engine read.

```swift
let d = Driver()
let b = d.open("http://127.0.0.1:9/b")             // Cmd+T, type, Enter
d.user(.tab(.togglePin(.focused)))
XCTAssertEqual(d.pinnedIDs, [b])
d.advance(.seconds(13 * 3600)); d.system(.clockTick)
XCTAssertEqual(d.todayIDs, [])                      // the idle start tab was archived; b is pinned
```

```swift
// Key routing is an input like any other
let t = d.key(KeyChord(.command, .t), stage: .beforePage, pressID: 1)
XCTAssertTrue(t.keyHandled)                        // consumed before the page
XCTAssertNotNil(d.view.overlay)                    // the command bar is open
```

### W2, engine and window host

```swift
// Brk/main.swift: CEF must exist before NSApp
let engine = try CEFEngine.bootstrap(.init(cacheDirectory: data.appendingPathComponent("Chromium"), remoteDebuggingPort: nil))
```

```swift
// BrkApp/WindowController.swift: one snapshot -> frames -> views -> pages in cards -> focus
let frames = WindowLayout.compute(snapshot, contentSize: root.bounds.size)
root.render(snapshot, frames: frames, surface: { engine.surface(for: $0) })
if snapshot.focus != lastSnapshot?.focus { applyFocus(snapshot.focus) }   // .page(id) -> engine.focus(id)
```

```swift
// BrkApp/KeyRouter.swift: the CEF key path, a thin adapter
func engine(_ e: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: UInt64) -> Bool {
    guard let window = store.window(showing: page) else { return false }   // derived from the snapshot
    return store.dispatchKey(window, KeyInput(press: key, stage: stage, pressID: pressID))
}
```

### W3, sidebar views

```swift
// DockView: a click is a command
dispatch(.space(.focus(item.id)))
```

```swift
// RowView drag end: the same placement rule the reducer applies
if let to = TablistLayout.dropTarget(at: point, rows: frames.rows, space: space, dragging: row.kind) {
    dispatch(.item(.move(row.id, to: to)))
}
```

```swift
// ResizeHandleView: Arc's snapping is a pure state machine
dispatch(.sidebar(.resize(width: drag.update(translation: dx, velocity: speed, time: event.timestamp))))
```

### W4, command bar and archive

```swift
// CommandBarView: ranking is local to the typed query; choosing a result is dispatching its command
let results = Suggest.rank(query: input.stringValue, bar: bar, appName: Product.name)
dispatch(results[highlighted].command)    // .commandBar(.submit(text)), .tab(.focus(id)), or an action's command
```

```swift
// ArchivePageView: groups come from the projection
for group in archive.groups { /* header for group.bucket, rows */ }
dispatch(.archive(.restore(entry.id)))
```

### W5, theme

```swift
// WindowRootView.render: equal themes are a no-op, so this runs on every snapshot
background.show(snapshot.theme, animated: lastTheme != nil)
```

```swift
// BrkDomain/Project.swift: what the views paint with is derived, never stored
theme: resolveTheme(space.theme)
```

```swift
// BrkThemeTests: textures are generated, deterministic, tileable
let denim = TexturePixels.generate(.denim, size: Metrics.Theme.denimTile.value, seed: 7)
```

### W6, harness

```swift
let app = AppUnderTest(app: arguments.app, dataDirectory: directory, site: site)
try app.launch()
try app.press("cmd+t"); try app.type(site.url("page2.html").absoluteString); try app.press("return")
try app.waitUntil("a second Today row") { try app.view().space.today.rows.count == 2 }
let card = try app.native().actual[ViewID.card(0).identifier]!
try expect(card.cornerRadius == Metrics.Content.cornerRadius.value, "card radius \(card.cornerRadius)")
```

## Shape

### Two pure functions: state and geometry

`reduce` decides what the app state is; `WindowLayout.compute` decides where everything is. Both are pure, both live in headless modules (no AppKit), and both are tested without a window. Everything else is a reconciler that makes the outside world match their output and turns the outside world's events back into input:

- `AppStore` (BrkApp) is the only state owner. It runs `reduce`, projects, schedules the write, reconciles the engine and the windows, then runs effects.
- `WindowController` turns a `WindowSnapshot` into frames (`WindowLayout`), hands both to `WindowRootView`, puts page surfaces into cards, and applies keyboard focus when the snapshot's `focus` changes.
- The engine makes its live pages equal `snapshot.pages`.
- The control socket returns exactly the snapshot and the frames, next to the frames AppKit really has, so e2e asserts on the same data the views rendered from and catches drift between "computed" and "on screen".

This is the Electron design's state model (one owner, pure reducer, whole-snapshot projections, injected clock) plus one new decision: geometry is data too. In Electron the CSS engine laid out the sidebar; in AppKit we place every view ourselves, and pixel faithfulness to 77 constants needs one function that can be read, tested and compared with the screen (per boundary-discipline: business logic pure, the shell thin).

### Data structures

The domain is the Electron model in Swift, with Arc's names where they help. `SidebarTree.items: [ItemID: Item]`; `Item` has `parent`, ordered `children`, and `body: ItemBody` (`tab`, `folder`, `split`, `section`). A space points at its Pinned and Today roots; Favorites is one root per profile (`Doc.favorites: [ProfileID: ItemID]`, v1 has only the default profile). A split is an item whose children are its panes, with `widths` keyed by pane id (Arc's `itemWidthFactors`), so removing a pane cannot misalign an array. `Doc` is what is saved; `Session` (overlays, cycles, loaded pages, live page facts, key-routing memory) dies with the process (per separate-before-serializing-shared-state). Inside a tab the page writes `title` and the user writes `customTitle`; the projection merges them.

Dominant reads, traced through the structure: render a section walks `children` from its root; "which section is this tab in" (Cmd+D, auto-archive, focus) walks `parent` up at most four steps; "what does the window show" is `WindowDoc.activeBySpace[space]`, a tab or a split whose children are the panes; recent-tab order sorts the space's tabs by `lastActiveAt`, so there is no recent list to keep in sync; auto-archive scans each space's Today children. No read needs an index we would add later.

The projection is `AppSnapshot { rev, now, windows: [WindowID: WindowSnapshot], pages: [PageSpec] }`. A `WindowSnapshot` holds the resolved theme, sidebar state, URL pill, favorites, the space's rows (with status current/visible/idle already derived), the dock, the panes (`PaneContent.page(PageID)`, `.blank`, `.crashed`), the overlay (command bar candidates, archive groups already bucketed), the focus target, and which table actions apply now. It is Sendable, Equatable (views skip unchanged slices) and Codable (the socket).

`WindowFrames` is the layout's output: sidebar column parts (title row, traffic-light origin, URL pill, favorite tiles, tab list rows, dock cells), the floating flag, the reveal strip, the content area, one `CardFrame` per pane, dividers, the command bar box and the archive rect. Top-left origin; every BrkUI container is flipped, so frames are assigned without conversion.

### Invariants encoded in types

- `AppState` has only internal stored properties: outside BrkDomain nothing can read the tree, only `project` and `StateCodec` can (per encode-lessons-in-structure).
- `Item.parent` and `Item.children` are `fileprivate(set)` in `SidebarTree.swift`; `Item`'s initializer is therefore file-private too. Only the tree's own `insert`, `move` and `removeSubtree` change the hierarchy, and `move` is the only place `pinnedURL` is maintained, so Cmd+D, drag and drop and "move to space" cannot disagree. The Electron version needed a scan for this; here the compiler refuses.
- `Work.run` and `ActionID.spec` are exhaustive switches: a command area without rules, or an action without a table row, does not compile. There is no second list to keep in step.
- `Metric(value, source)` cannot be built without a `MetricSource` (`.arc(constant name)`, `.cra(line)`, `.anatomy(section)`, `.guess(reason)`), so an unsourced layout number does not compile. Every number in `Metrics.swift` names its row in layout-constants.md or says it is a guess.
- `PageID` is not `ItemID`: the engine works with pages and cannot reach the sidebar.

### Every input is an input to `reduce`, including keys

`Input` is `.user(WindowID, Command)`, `.key(WindowID, KeyInput)` or `.system(SystemEvent)`. `Command` covers every user intent from every source; its ten area enums (`commandBar`, `archive`, `tab`, `page`, `item`, `space`, `split`, `sidebar`, `app`, `settings`) port the Electron vocabulary one to one, plus the app commands (quit, hide, minimize) that must now go through the router. `SystemEvent` covers page events, clock ticks and window events.

The decision that differs most from the Electron version: key routing is part of the reducer. The CEF key handler must answer "consumed or not" synchronously, and Arc's priorities need memory: `promptAfterConsumedByWebView` means the page gets the first press and the app gets a second press soon after. That memory is session state with exactly one writer, `reduce`. So `OnPreKeyEvent`, `OnKeyEvent` and menu key equivalents are three thin adapters that dispatch `.key(window, KeyInput(press, stage, pressID))` and return `Transition.keyHandled`. `KeyRouting.decide` applies seven ordered rules (key-up ignored; unbound passes; repeats only where the table allows; one press dispatches once; the menu stage always dispatches; before the page `.app` dispatches, `.pageThenApp` records or takes the second press, `.page` passes; after the page dispatches). If it decides to dispatch, the action's command runs in the same transition. All of it is tested through `reduce`, with no CEF and no AppKit.

### One shortcut table

`Actions.swift` is Arc's menu nib as data: per action a title, a menu and group, its key bindings each with its own priority (Arc gives alternates their own binding id and priority: Go Back is `overrideWebView` on Cmd+[ but unset on Cmd+Left, so Cmd+Left still moves the caret in a text field), the argument-free command, an optional command-bar listing (Arc's `arcTypeTravelTriggers` and icon), and whether auto-repeat dispatches again. The menu is built from it (`MainMenu`), `KeyMap` is built from it for routing, and `CommandBarSnapshot.actions` is filtered from it. Matching is by physical key (macOS virtual key code), because CEF's `native_key_code`, an injected `NSEvent` and the menu disagree about characters; Ctrl+Shift+= therefore matches although the page types "+".

### The engine interface

`WebEngine` is six calls: `reconcile(_ pages: [PageSpec])`, `surface(for:) -> PageSurfaceView?`, `perform(_:on:)`, `focus(_:)`, `facts(for:)`, `shutdown() async`, plus a delegate that receives `PageEvent`s and key presses. Behind it `CEFEngine` hides: CEF initialization before `NSApp` exists; one frameless Chrome-runtime browser per page; waiting for its host window's views and moving the compositor and input views into our surface; keeping the host window click-through, frame-synced and never key (by replacing `canBecomeKeyWindow` on CEF's window class once); telling Chromium a page is hidden when its surface leaves a window; re-parenting the host window when a surface moves to another window; ids reused while an old browser is still closing; events from retired browsers dropped; and the shutdown order. The caller never coordinates two calls for one operation: pages appear and disappear by `reconcile`, and a surface is placed like any NSView.

Which pages exist is derived from state, not commanded: the projection lists every loaded tab as a `PageSpec`, and the engine converges to the list. Only one-shot actions (navigate on submit, back, reload, devtools, recover after a crash) are effects. So a page cannot be left alive by a forgotten "close" call, and restarting with lazy restore is just a shorter list (per make-operations-idempotent).

`StubEngine` implements the same interface with placeholder views. With `BRK_ENGINE=stub`, `swift run Brk` opens the whole shell without CEF, so W3, W4 and W5 can run and screenshot their work before anyone downloads Chromium. An Alloy engine for testing or fallback is a third implementation with no caller changes.

### CEF bridge: vendored CefSwift

We vendor CefSwift at `ba6ebff` under `Vendor/CefSwift` and use only its `CefKit` product, only from BrkCEF. Reasons: the spike built Mode B embed on exactly this API (`CefChromeBrowser`, `CefBrowserDelegate.handleKeyEvent(isBeforePage:)`, `browserDidClose`, `decideWindowOpenFor`), so the hosting behavior we rely on is measured on it; it is `@MainActor` end to end and builds in Swift 6 mode, matching strict concurrency; its loader `dlopen`s the framework, so `swift build` and `swift test` need no CEF on disk; its `cef` plugin downloads a SHA-1-pinned stock CEF and assembles the .app with the five helpers, which `scripts/build.sh` reuses. A bridge of our own over the C API would mean writing about 6,000 lines of reference counting and callback structs before the first page shows, with nothing to gain for the first wave. Vendoring (rather than a URL dependency) is because upstream is inactive: we own CEF bumps through its update script, and if it ever falls short, the `WebEngine` interface keeps a replacement bridge local to BrkCEF. One change to its behavior is made from our side: `CEFEngine.bootstrap` removes CefSwift's terminate handler (`CEFApplication.setTerminateHandler(nil)`), because that handler closes browsers while their views are still in our window, which is our best explanation of the spike's crash at quit.

### Shutdown order

Every quit path (Cmd+Q through the reducer as `AppEffect.quit`, the Dock menu, logout, closing the last window) reaches `applicationShouldTerminate`, which returns `.terminateLater` and runs: stop timers and the control server's accept loop; `store.flush()` (state is on disk before anything risky); `await engine.shutdown()`, which (1) returns every borrowed Chromium view to its host window and detaches the host windows from ours, (2) sends `close(force: true)` to every browser and awaits each `OnBeforeClose`, bounded by a timeout, (3) calls `CefRuntime.shared.shutdown()`; then `NSApp.reply(toApplicationShouldTerminate: true)`. CEF's message pump keeps running during `.terminateLater` because CefSwift schedules it in the common run-loop modes. `shutdown()` is idempotent (a second call awaits the same task) and its phases are an enum, so a page call after phase 1 is easy to refuse.

### Views

BrkUI views follow one contract: `render(slice, frames, palette)` makes the view match and returns early when the slice is unchanged; positions come only from `WindowFrames`; hover, drag preview, typed query and scroll stay in the view; intent goes out through one `Dispatch` closure. Views never see the store, the engine or the window controller. Accessibility identifiers come from `ViewID`, the same enum the runner uses. The sidebar's tab list is not an `NSOutlineView` (Arc's is): rows are plain views placed at `TablistLayout.rows`, because drag hit testing (`TablistLayout.dropTarget`, which calls the same `Placement.canPlace` the reducer uses), row pitch and pixel tests then all read one pure function. Window stacking, bottom to top: Metal background, anchored sidebar, cards with page surfaces, the archive page (inside the content area, so the sidebar and dock stay clickable), the floating sidebar while peeking, the command bar. The spike verified native views above the moved Chromium views draw and take focus. SwiftUI appears only inside an `NSHostingView` for the space dialog and theme editor (and later settings and onboarding), as Arc does; its form fields are local state seeded from the snapshot, and Save dispatches a command.

### Theme

`SpaceTheme` (stored) is 1 to 3 base colors, one texture (grain, sand, denim, tweed), an intensity and an appearance choice. `resolveTheme` derives the scheme from the primary color's luminance unless forced, the gradient stops, the texture opacity (intensity times Arc's per-texture multiplier: 0.8, 0.15, 0.6, 0.4), the wash (white in light, black at 35% in dark, opacity min(0.2 + 0.55 x intensity, 0.5)) and Arc's sidebar tokens for that scheme. `ThemeBackgroundView` draws it with Metal in three passes like Arc's shader library (gradient into a small texture, overlay selection, final composite with the tiled texture multiplied over it) and crossfades both gradient and texture by a `progress` uniform on space switch. Shaders compile from source at launch because SwiftPM does not compile `.metal` files. Textures are generated procedurally at the tile sizes of Arc's assets; Arc's files are not copied.

### Persistence and time

`StateCodec` knows the format (`{ "version": 1, "doc": ... }`, private DTOs, explicit field-by-field construction both ways so a missing field is a compile error); `StateFile` knows bytes and paths (debounced writes off the main actor, temp file, full fsync, rename; quarantine to `state.rejected-<ms>.json` when restore says `.rejected`). Restored tabs keep their saved URL and title; only visible tabs are loaded at launch. `Clock` is injected; `OffsetClock` (BRK_TEST_CLOCK=1) is real time plus an offset only `advanceClock` moves. Only `Clock.swift` reads the real time.

### Validation

Three boundaries parse into domain types: the control socket (JSON into `Command` through Codable), the state file (`StateCodec.restore`), and typed URLs (`resolveTypedInput`, `isAllowedURL`). Inside, types are trusted (per boundary-discipline). The reducer is total over every `Input` value (unknown ids are no-ops, numbers are clamped), so the socket's parse is structural only and needs no second rule set.

### Interface depth

- Domain: `reduce`, `project`, `StateCodec.encode/restore` over an opaque handle. Behind them: the tree, invariants, archive policy, auto-archive, key priorities, popup menu models, theme resolution, the file format.
- Engine: six calls and two delegate callbacks. Behind them: everything Chromium.
- Layout: `WindowLayout.compute`. Behind it: every constant.
- Views: `WindowRootView.render(snapshot, frames:, surface:)`. Behind it: all AppKit drawing and interaction state.
- What stays exposed is the command vocabulary, the snapshot, the frames and the page vocabulary, which are the real contracts between workers.

### What it deliberately does not do

No second state store in views, no Combine or Observation bindings to state (views get whole slices), no patches, no per-feature manager objects, no NSOutlineView, no WKWebView, no Electron, no `package` access level (all targets are one package, where `package` equals `public`), no global hotkeys, no loading of every restored tab at launch, no code from cra.

### Red-flag screen

- Shallow module: none of the public surfaces needs the caller to coordinate several calls for one operation; the largest (`WebEngine`) is six calls in front of all the Chromium-specific code.
- Information leakage: the file format lives only in `Codec.swift`, Chromium only in BrkCEF, geometry only in BrkLayout, the wire format only in BrkControl (shared by both ends), key syntax only in `Keys.swift` and `Actions.swift`.
- Temporal decomposition: the codec keeps parse, migrate, validate and repair together; rules are grouped by what they know (tabs, sidebar, split, archive, command bar), not by when they run.
- Pass-through: `AppCommand.quit` only becomes `AppEffect.quit`, which looks like a detour; it follows from every key going through one router, and it gives the reducer a place to refuse or confirm later ("Warn before quitting" is an Arc setting).
- Split ownership: one state value in `AppStore`; hierarchy writes only in `SidebarTree.swift`; window size enters only as `WindowEvent.geometry`; key memory only in `Session`.
- Two ways to do one task: every focus is `.tab(.focus)`, every relocation is `SidebarTree.move`, every archive is `archiveTabs`, every quit reaches `applicationShouldTerminate`, picking an action in the bar dispatches that action's command.
- Importable internals: AppState's fields are internal; `CEFEngine` is the only public type of BrkCEF and only main imports it; ArchitectureTests rejects imports outside the table.
- Hand-synced lists: the menu, key routing and command-bar actions derive from `ActionID`; accessibility identifiers derive from `ViewID`; the e2e protocol is one set of types for both ends; the product name is written once in `Package.swift` and derived at run time and by the build script.

### Where later features plug in

| Feature | Where it goes, without reshaping the core |
|---|---|
| Little Arc | `WindowKind.little(...)` (reserved in `Model.swift`); its one-tab container is a section kind; a `LittleWindowController` renders the same `WindowSnapshot` subset in an `NSPanel`; `OpenDisposition` gains `.littleArc`; auto-archive gains the Little Arc threshold (Arc: `AutoArchiveType.littleArc`). |
| Peek | `Overlay.peek(PeekState)` (reserved) holding a tab in a scratch section; the page surface is placed in a panel view above the card; `OpenDisposition.peek` from Shift+click and from Pinned/Favorites links (Arc's Links settings). |
| Profiles | `ProfileID` already on spaces, favorites roots and `PageSpec`; the engine maps a profile to a CEF request context (`CefProfile`); a settings pane edits them. |
| Incognito | `WindowKind.incognito`; its tabs live in `Session` only, so the codec never writes them; pages use an off-the-record profile. |
| Extensions | The Chrome runtime already renders `chrome://extensions`; toolbar buttons are a URL-pill accessory fed by an engine capability (`extensionActions(for:)`) added to `WebEngine`; Arc's "pinned extensions picker" is a table action. |
| Boosts | Domain records keyed by host; `PageSpec` gains the user scripts and CSS that apply; the engine injects them at load. |
| Easels, Notes | New `ItemBody` cases and `PaneContent` cases (`.note`, `.easel`) that a card fills with a native editor (SwiftUI in `NSHostingView`) instead of a page surface. |
| Live Folders | `Folder.live: LiveFolderSource?`; a fetcher outside the domain dispatches `SystemEvent.liveFolder(folder, urls)` (reserved). |
| Air Traffic Control | `Doc.linkRoutes`; `SystemEvent.externalURL(url)` (reserved) and `openRequested` consult the routes in the reducer. |
| Picture in picture | A `PageAction` (`.requestPictureInPicture`) and a `PageEvent` for auto-PiP when leaving a video tab; Arc's per-site rules are domain data. |
| Captures | `Effect.capture(region)` run by BrkApp (window capture or ScreenCaptureKit); the result dispatches a system event that adds a Library entry. |
| Site control center | A popover anchored to the URL pill's frame, reading `URLPillSnapshot` plus engine per-site permissions. |
| Settings | `Doc.settings` grows; a SwiftUI settings window dispatches `.settings(...)` commands. |
| Onboarding | `Doc.onboarding`; a fresh profile's seed tabs (Arc's `DefaultSidebarTabType`); a SwiftUI window. |
| Import | An importer reads another browser's bookmarks and dispatches `.item` commands (or one `.importer(.apply(plan))` command) to add items. |
| Shortcut remapping | Arc's `StorableKeyBindings` user overrides become `Doc.keyOverrides`; `KeyMap` is built from table plus overrides, and a conflict becomes a state (Arc: `KeyBinding.State.conflict`). |

### Trace: the user presses Cmd+T while a page has focus

1. `BrkCEF/ChromePage.swift`, `browser(_:handleKeyEvent:isBeforePage: true)`: CEF's `OnPreKeyEvent`. `KeyTranslation.press` gives `KeyPress(cmd+t, .down)`; `CEFEngine.pageKey` forwards to the delegate.
2. `BrkApp/KeyRouter.swift`: finds the window whose snapshot shows the page and calls `store.dispatchKey(window, KeyInput(press, .beforePage, pressID))`.
3. `BrkDomain/Reduce.swift`, `Work.routeKey`: `KeyRouting.decide` finds `ActionID.newTab`, priority `.app`, decides `.dispatch(.newTab)`; `run(.commandBar(.open(.newTab)))`; `Rules/CommandBar.swift` sets `overlay = .commandBar(openID: n, target: .newTab)`. `keyHandled = true` goes back to CEF, which drops the event: the page never sees it.
4. `AppStore`: `project` gives `overlay = .commandBar(CommandBarSnapshot(openID: n, placement: .centered, ...))` and `focus = .commandBarInput`; `engine.reconcile` changes nothing.
5. `WindowController.render`: `WindowLayout.compute` gives `frames.commandBar` (width min(766, area - 160), 338 tall, centered in the content area); `WindowRootView.render` shows `CommandBarView` at that frame, which resets its query for the new `openID` and plays the 0.95 to 1 bounce; focus changed, so `engine.focus(nil)` and the bar's input becomes first responder.
6. The user types and presses Return: `CommandBarView` dispatches `.commandBar(.submit(text))`; the reducer resolves the URL, adds a tab at the top of Today, focuses it, closes the bar. The next snapshot lists a new `PageSpec`; `engine.reconcile` creates the browser and its surface; `render` puts the surface in card 0; the surface embeds Chromium's views when they appear and the pending focus is applied. Page events (`committed`, `titleChanged`) come back through the delegate as `.system(.page(...))` and the row's title fills in.

### Trace: the user clicks a space in the dock

1. `BrkUI/Sidebar/SidebarView.swift`, `DockView`: mouse up on a cell dispatches `.space(.focus(id))` through `Dispatch`, which the window controller bound to `store.dispatch(.user(window, command))`.
2. `Rules/Sidebar.swift`, `spaces`: stamps `lastActiveAt` on tabs leaving the screen, sets `windows[w].space`.
3. `project`: the new space's rows, the dock's active flag, `theme = resolveTheme(space.theme)`, the space's active item as the pane; `pages` includes it (loaded now if it never was).
4. `engine.reconcile` creates the page if needed. `WindowController.render`: frames for the new rows and the card; `ThemeBackgroundView.show(theme, animated: true)` starts the Metal crossfade (Metrics.Motion.themeCrossfade); the tab list slides the old rows out and the new ones in; card 0 swaps surfaces (the old surface leaves the window and its page is told it is hidden); focus moves to the shown page.
5. e2e scenario 4 samples the background pixel before and after; R9 checks that only the current space's surface is in the window.

## Synthesis decision

Filled in by arena.

## Tradeoffs accepted

- We accept running `project` over the whole state after every changing transition, including each page title event and each frame of a sidebar drag, in exchange for no patch protocol and views that cannot fall out of step. Sidebars hold hundreds of rows; views skip unchanged slices.
- We accept that key presses go through the reducer and the store, so typing in a page costs one `reduce` call per key-down, in exchange for one place that owns key priorities and the press-twice memory. The reducer returns the input state untouched (no normalize, no comparison) when routing decides "pass to page" with no memory change.
- We accept writing our own sidebar list instead of `NSOutlineView` (cell reuse, accessibility roles, keyboard navigation are ours to write) in exchange for row geometry, drag targets and pixel tests that all read one pure layout function.
- We accept a vendored, unmaintained dependency (CefSwift, about 4.6 MB with the CEF headers) in exchange for the exact API the spike measured and a build that needs no CEF to compile and test.
- We accept depending on Chromium's private view classes and on replacing two methods of CEF's host window class, because it is the only hosting mode that met all five hosting needs. The e2e harness checks the host-window key rule and the clean quit on every scenario so a CEF upgrade that breaks them fails a scenario.
- We accept one empty CEF host window per page, kept as a click-through child window following the card's screen frame.
- We accept that Cmd+Q, Cmd+H and Cmd+M are table actions that go through the reducer, because the menu does not fire while a page has focus.
- We accept physical-key matching: on non-US layouts a shortcut follows the key position, not the printed character.
- We accept a global folder collapsed state and window-keyed state although v1 opens one window.
- We accept quitting when the only window closes (Arc keeps running with no window).
- We accept procedural textures that will not match Arc's grain, sand, denim and tweed pixel for pixel; only their tile sizes and opacity multipliers are Arc's.

## Alternatives considered

- **Feature stores with Observation** (`@Observable` objects per feature that views bind to, the way Arc uses one TCA store per window). Lost on ownership: several objects write related state, key routing and auto-archive need to read across them, and the Electron spec cannot be ported as pure tests. It exposes less ceremony to views but hides less policy.
- **Imperative engine calls from the reducer's effects** (`createPage`, `closePage`, `attach(page, card)`). Lost on interface depth and idempotence: every caller must pair create with close and attach with detach, a crash halfway leaves orphan browsers, and restart has to replay calls. Reconciling against `snapshot.pages` and placing surfaces like views hides all of that.
- **Key routing as a separate stateful object in BrkApp** (the Electron `KeyRouter` with its own records). Lost on single ownership: press-twice memory and the duplicate guard would be a second writer of state that the reducer cannot see, and its tests would need CEF-shaped fakes.
- **Views compute their own frames with Auto Layout.** Lost on faithfulness checks: the frames that matter for pixel parity would be implicit in constraints, the control socket could only report what AppKit ended up with, and the drag target math would duplicate the layout.
- **Our own thin bridge over CEF's C API instead of CefSwift.** Lost for now on cost with no gain: the spike already ran on CefKit, and the `WebEngine` interface keeps the swap local to BrkCEF if CefSwift falls short (DevTools protocol calls, print, popups that keep their opener).
- **A shell-script e2e runner over `ctl.sh`** like the spike's tools. Lost on drift: a Swift runner decodes replies into the same `WindowSnapshot`, `WindowFrames` and `ViewID` types the app uses, so a renamed field breaks the build instead of a scenario.

## Open questions and risks

- The biggest risk is the quit crash. Our shutdown order (views back, browsers closed and awaited, then `cef_shutdown`) is a hypothesis built from the spike's crash reports, not yet run. If it still crashes, is a fallback acceptable that skips `cef_shutdown` and exits after state is flushed and browsers are closed (the OS reclaims the helpers)? N4 and the per-scenario crash check will tell within the first W2 day.
- Does `flagsChanged` reach our window while a Chromium view is first responder? The spike only logged key-downs. If it does not, Control release must come from CEF's key-up of the Control key; the reducer input stays the same (`WindowEvent.modifiersChanged`).
- Is a key's `pressID` from `NSApp.currentEvent` good enough? CefKit does not pass CEF's `os_event`. Before-page and menu calls run inside `sendEvent` of that event; after-page may not. Should we patch the vendored CefKit to pass the event timestamp?
- Should Arc's press-twice rule (`pageThenApp`) ship in v1, or should those keys behave as `.app` like the Electron version did? It is about 20 lines in `KeyRouting.decide`, but it changes how Cmd+S and Cmd+D feel on pages that use them.
- Popups that need their opener (OAuth windows) are turned into tabs, which breaks `window.opener`. Is that acceptable for the first wave?
- The default sidebar width (228) and the Library width are low-confidence in layout-constants.md, and several sizes (folder indent, favicon, shadow radius) are guesses. Should the user measure them in a running Arc before W3 starts?
- The prototype's `ModeB/main.swift` credits cra for the view-moving idea. We reimplement it from what the spike measured, without copying; does the user want that recorded in the repo's notices anyway?
- A CEF upgrade can rename `ViewsCompositorSuperview` or `WebContentsViewCocoa`. `EmbeddedSurface` gives up after 10 s and logs the host's view tree; should the app then fall back to an Alloy engine at run time, or refuse to start?

## Next implementation step

Fill `CEFEngine` (reconcile, embed, focus, shutdown) and `WindowController.render` with `WindowLayout.compute` for one card, driven by a hand-written snapshot, and run e2e scenarios 1 and N4 on this Mac, because the clipped card and the clean quit are the two facts every other worker's output depends on.
