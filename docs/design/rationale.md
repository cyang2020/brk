# Design rationale: Arc clone on Electron 45 (candidate 2)

## Problem

We are building Arc's core experience on Electron 45 + TypeScript + React: a window whose background is a per-space gradient, a sidebar with Favorites, Pinned, Today, folders and splits, a dock of spaces, a command bar, an archive with auto-archive, and full restore after restart. Four workers fill in the bodies in parallel (W1 domain, W2 main process, W3 sidebar UI, W4 command bar and archive UI). The shape has to let each of them work against fixed types without editing another worker's files.

These constraints from the grounding make the shape non-obvious:

- The window is a stack of native views, not one page. `BaseWindow` cannot paint a gradient (spike section 2), so a full-size chrome view sits at the bottom and tab views sit above it. Anything that must draw over a page needs its own view above the tabs, because the chrome view is underneath them. That covers the command bar, the archive, and the hidden sidebar that floats over content on hover.
- Keys go to whichever webContents has focus. A menu accelerator alone loses to a page that handles the key (spike section 4), so every webContents needs a `before-input-event` hook. The same key press must still run once when both paths fire.
- Renderers are sandboxed with context isolation. The file system, the clock and the other webContents are only reachable from main, so main has to own the state.
- `webContents.close()` is asynchronous, Playwright lists pages in unstable order, and `page.keyboard` does not trigger shortcuts (spike sections 5 and 7). The e2e hooks have to be part of the design.
- Arc's observed model (model-and-shortcuts.md 1.4 to 1.9): one flat dictionary of sidebar items with parent ids and ordered children; spaces point at pinned and unpinned section roots; favorites are a shared root; a split is a sidebar item whose children are its panes; archived items keep a full snapshot with a reason and a source. We keep that model, simplified to v1.
- Arc's layout numbers are compiled into code and unknown, so we guess them, and keep every guess in one file.

## Usage (caller's view)

Written first; the types in `src/` are derived from these call sites.

### W2, main process: the domain's only production caller

Main holds one opaque `AppState` and uses seven functions from `src/domain/index.ts`.

```ts
// src/main/app.ts: the only writer of state
const t = reduce(state, input, { now: clock.now(), newId })
state = t.state
if (t.docChanged) store.save(serializeState(state))
for (const host of hosts) host.render(state, clock.now())
tabs.collect(loadedTabIds(state))
for (const effect of t.effects) run(effect) // web/* -> tabs.perform, clipboard/write, window/fullscreen, menu/popup
```

```ts
// src/main/window-host.ts: render(state, now)
const sel = selectWindow(state, windowId)
const layout = computeLayout({
  contentSize: sel.contentSize,
  sidebar: sel.sidebar,
  fractions: sel.panes.map((p) => p.fraction),
  overlayOpen: sel.overlay !== null,
})
const panes = sel.panes.map((p) => tabs.viewFor(p.tabId, p.url, windowId))
// make the stack [sidebar surface, ...panes, floating?, overlay?]; bounds and radius from `layout`
push(projectWindow(state, windowId, layout, now, platform))
```

```ts
// src/main/input.ts: the hook every webContents gets
const actionId = keymap(input)
if (actionId && (owner.surface !== 'tab' || ACTIONS[actionId].priority === 'app')) {
  event.preventDefault()
  dispatch({ origin: 'ui', windowId: owner.windowId, command: ACTIONS[actionId].command })
}
```

```ts
// src/main/tab-runtime.ts: page events become system commands
wc.on('page-title-updated', (_event, title) =>
  dispatch({ origin: 'system', command: { type: 'page/updated', tabId, patch: { title } } }),
)
```

### W1, domain: its unit tests are its other callers

```ts
const { state: s0 } = restoreState(null, ctx, { startUrl: 'http://127.0.0.1:9/a', contentSize })
const [w] = windowIds(s0)
const t = reduce(s0, { origin: 'ui', windowId: w, command: { type: 'tab/toggle-pin', target: 'focused' } }, ctx)
const view = projectWindow(t.state, w, layout, ctx.now, 'darwin')
expect(view.space.pinned.rows).toHaveLength(1)
expect(view.space.today.rows).toHaveLength(0)
expect(t.docChanged).toBe(true)
```

```ts
// an idle Today tab is archived once the clock passes the threshold
const t2 = reduce(s1, { origin: 'system', command: { type: 'clock/tick' } }, { ...ctx, now: thirteenHoursLater })
expect(projectWindow(t2.state, w, layout, thirteenHoursLater, 'darwin').space.today.rows.map((r) => r.id)).toEqual([visibleTab])
```

### W3, sidebar renderer

```tsx
const view = useWindowView() // WindowView | null
<div data-testid={TID.row(row.id)} data-status={row.status}
     onClick={() => dispatch({ type: 'tab/focus', tabId: row.id })}
     onDoubleClick={() => dispatch({ type: 'item/begin-rename', target: row.id })} />
<button data-testid={TID.dockSpace(s.id)} onClick={() => dispatch({ type: 'space/focus', spaceId: s.id })} />
```

```ts
const drop = dropAt(event.clientY, measuredRows, { id: dragged.id, kind: dragged.kind })
if (drop) dispatch({ type: 'item/move', itemId: dragged.id, to: drop.to })
```

### W4, command bar and archive renderer

```tsx
const bar = view.overlay?.kind === 'command-bar' ? view.overlay : null
const results = suggest(query, bar, view.platform) // query is local React state
onEnter={() => dispatch(commandFor(results[selected]))} // commandBar/submit, tab/focus, or an action's command
onEscape={() => dispatch({ type: 'overlay/close' })}
```

```tsx
const groups = groupArchive(archive.entries, view.now)
<button data-testid={TID.archiveRestore(entry.id)} onClick={() => dispatch({ type: 'archive/restore', entryId: entry.id })} />
```

### e2e

```ts
await arc.press('CmdOrCtrl+T')
const overlay = await arc.surface('overlay')
await overlay.getByTestId(TID.commandBarInput).fill(arc.server.url('/page/two'))
await overlay.keyboard.press('Enter')
await expect.poll(async () => (await arc.view()).space.today.rows.length).toBe(before + 1)
```

## Shape

### State: one owner, one command vocabulary, one interpreter

Main owns all application state as one immutable value inside `src/main/app.ts`. Renderers hold none of it, only transient UI such as the typed query, hover, a drag preview and dialog form fields. The state is split by who writes it and whether it is saved (per separate-before-serializing-shared-state):

- `Doc`, saved: sidebar items, spaces, archive, history, settings, and per window the current space, what each space shows, sidebar width and visibility, and bounds.
- `Session`, not saved: per window the open overlay, peek, rename, dialog, Ctrl+Tab cycle and content size; which tabs are loaded; page-reported loading, back/forward and failure.
- Inside a tab, the page and the user write different fields. The page writes `title` and `faviconUrl`; rename writes `customTitle`; the projection merges them. `url` means "the current location", and the user (submit, reset) and committed navigations both set it in sequence, which is the meaning we want.

Every input is a command. `UiCommand` (42 types) is defined by a zod schema in `src/shared/commands.ts`, and its type is derived from that schema. It covers every user intent from every source: menu, shortcut, sidebar click, command bar, native popup, test API. `SystemCommand` (5 types) covers what main observes: page events, links opening new tabs, Ctrl released, window geometry, clock ticks. `reduce(state, input, ctx) -> { state, effects, docChanged }` is pure and is the only interpreter. Its handler table has a mapped type over all command types, so a schema entry without a handler fails the build (per encode-lessons-in-structure). Handlers are grouped by the knowledge they own (`ops/tabs`, `ops/sidebar`, `ops/spaces`, `ops/split`, `ops/archive`, `ops/window`), not by when they run.

Edits flow back like this: `window.arc.dispatch(cmd)` -> preload -> `src/main/ipc.ts` parses it with `UiCommandSchema` and attaches the sender's window -> `App.dispatch`. Projection goes the other way: after each change every window host computes `projectWindow(...)` and pushes the whole `WindowView` to its surfaces. There are no patches. A surface renders the latest view, so duplicate or late pushes cannot corrupt it (per make-operations-idempotent).

`AppState` is opaque outside the domain: it has no readable fields. Main cannot depend on the tree. It reads through `selectWindow` (what native views need), `projectWindow` (what renderers need), `loadedTabIds` (which tab views should exist) and `serializeState`.

### Domain data structures

We follow Arc. `items: Record<ItemId, Item>` with `Item = TabItem | FolderItem | SplitItem | SectionItem`. Every non-root item has `parentId`; containers have ordered `children`. A space points at two section roots, and Favorites is one shared root. A split is an item whose children are its 2 to 4 pane tabs, with `widths` keyed by pane id (Arc's `itemWidthFactors`), so removing a pane cannot misalign a parallel array. Archive entries snapshot the tab with a reason and a source.

How the dominant reads go through this structure:

- Render a section: walk `children` from its root.
- Find which section and space a tab is in (Cmd+D, auto-archive, focus across spaces): walk `parentId` up, at most four steps.
- What a window shows: `windows[w].activeBySpace[spaceId]` is a tab or a split, and a split's children are the panes.
- Recent-tab order for Ctrl+Tab: sort the space's tabs by `lastActiveAt`. There is no separate recent list to keep in sync.
- Auto-archive: scan each space's Today children.

Both directions of the hierarchy are stored so these reads are direct. Only `src/domain/tree.ts` writes them (`insertItem`, `moveItem`, `removeSubtree`), and an architecture test checks that. `moveItem` is the only way an item changes place, and it also maintains `pinnedUrl` (set exactly while a tab is in Pinned or Favorites), so Cmd+D, drag and drop and "move to space" cannot disagree about it. Where an item may go is one shared function, `canPlace`. The domain uses it to refuse a move, and the sidebar uses it for drag feedback.

`normalize` runs after every command and after decoding a file. It holds every rule that spans entities: a split left with one pane becomes that tab; visible tabs are loaded; active items exist; overlay and rename targets exist; caps; width clamp. Handlers therefore only do their local change.

### Native views: declared by state, applied in one function

`WindowHost.render(state)` is the only code that adds, removes, orders, sizes, rounds or focuses views. It derives what should be attached from `selectWindow` and the pure `computeLayout` (`src/main/layout.ts`), then makes the native stack match. It is idempotent, so calling it after every dispatch is safe. Tab views are created on first show by `TabRuntime.viewFor` and closed by `collect(loadedTabIds(state))` when the domain stops listing them. The map entry is dropped at once because `close()` is asynchronous. Keyboard focus is derived (`FocusTarget`) and applied only when it changes.

Per window, bottom to top: the sidebar surface (full window: gradient, sidebar, resize handle, split dividers), the tab panes, the floating-sidebar surface (only while peeking), and the overlay surface (only while the command bar or the archive is open). That is three renderer surfaces from two bundles: the sidebar bundle serves both sidebar surfaces, and the overlay bundle serves the command bar and the archive.

### Keys

`ACTIONS` in `src/shared/actions.ts` is the one table: label, keys, menu, group, whether it is listed in the command bar, priority, and the command it dispatches. The menu, the before-input-event matcher and the command bar's action rows are all derived from it. Every webContents is created in one of two places (the tab runtime and the surface factory in the window host), and both call `KeyRouter.attach`, so no view can miss the hook. Priorities follow Arc's nib: `app` actions are intercepted before the page sees the key, `page` actions let the page handle it first. If the menu accelerator also fires for a key press the hook already handled, the router drops the second dispatch. Matching uses the physical key code, so Ctrl+Shift+= matches even though the typed character is `+`.

### Persistence

`src/main/store.ts` knows bytes and paths: one `state.json`, debounced, written to a temp file, fsynced, renamed over the old one. `src/domain/codec.ts` knows the format: `{ version, doc }`, parsed with zod, migrated, decoded, tree-repaired, normalized. A file that cannot be used is moved aside and the app starts fresh. Restored tabs use their saved URL and title. Only visible tabs get a webContents at launch, and a failed load is recorded only in live state, so it never changes the saved tab.

### Time

`Clock` is injected. `ctx.now` feeds the reducer and `view.now` feeds renderers, so only `src/main/clock.ts` reads `Date.now()`. The e2e clock is real time plus an offset that only moves forward. `advanceClock` moves it and dispatches `clock/tick`.

### Validation

Three boundaries parse into domain types: renderer and test-API messages (`parseUiCommand`), the state file (`restoreState`), and typed URLs (`resolveTypedInput` and `isAllowedUrl`, run again in main on submit). Inside those boundaries, types are trusted (per boundary-discipline).

### Interface depth

- Domain: seven functions over an opaque handle. Behind them: the tree, invariants, archive policy, auto-archive, menu models, theme resolution and the file format.
- Bridge: two methods, `subscribe` and `dispatch`. Behind them: channel names, sender routing, parsing and window ids.
- Window host: `render(state)`. Behind it: stacking, lazy surfaces, bounds, radius, focus and projection pushes.
- Tab runtime: `viewFor`, `perform`, `collect`. Behind them: webContents lifecycle and all page-event wiring.

What remains exposed is the command vocabulary and the view shape, which are the actual contract between workers.

### What it deliberately does not do

No state store in renderers, no patches, no optimistic updates in renderers, no per-feature manager classes in main, no `globalShortcut` (it takes keys from other apps, spike section 4), no `<webview>`, no loading of every restored tab at launch.

### Red-flag screen

- Shallow module: the domain is seven functions over an opaque handle; the bridge is two methods; `WindowHost.render` is one call. No operation needs the caller to coordinate several methods.
- Information leakage: the file format lives only in `codec.ts`, channel names only in `src/ipc/channels.ts`, the tree only in `src/domain`, key syntax only in `ACTIONS` and `accelerator.ts`. Layout numbers are shared on purpose, from one file, so the URL pill and the Cmd+L anchor cannot drift.
- Temporal decomposition: the codec keeps parse, migrate, decode and repair together; handlers are grouped by what they know, not by when they run.
- Pass-through: commands that only produce an effect (`nav/history`, `ui/popup`) still add something in the reducer: resolving `'focused'` to a tab, or building the menu entries from state.
- Split ownership: one state value in `App`; `parentId`/`children` have one writer; window size enters only through `window/bounds`; the sidebar width during a drag is written only by main.
- Two ways to do one task: every focus is `tab/focus`, every relocation is `moveItem`, every archive is `archiveItems`, every command bar opening is `commandBar/open`, and picking an action in the bar dispatches that action's own command. The page context menu dispatches `nav/*` too, so even "back" has one path.
- Importable internals: renderers and e2e cannot import node-side files (TS6307 from composite projects); main reaches the domain only through its index (architecture test); `AppState` has no readable fields.
- Hand-synced lists: `UiCommand` is derived from its schema; the handler table is total over command types; menu, key matching and palette derive from `ACTIONS`; the overlay rule derives from command name prefixes; tokens, archive buckets and thresholds are `Record`s over their key unions; encode and decode construct fields explicitly so a missing field is a compile error.

### Trace: the user presses Cmd+T while a page has focus

1. `src/main/input.ts`: before-input-event on the tab's webContents. `keymap` returns `newTab`, priority `app`, so `preventDefault()` and dispatch `{ origin: 'ui', windowId, command: { type: 'commandBar/open', mode: 'new-tab' } }`.
2. `src/main/app.ts` calls `reduce`; `src/domain/ops/window.ts` `commandBar/open` sets `session.windows[w].overlay = { kind: 'command-bar', target: { kind: 'new-tab' } }`.
3. `src/main/window-host.ts` `render`: `selectWindow` reports `overlay: 'command-bar'` and focus on the overlay. `computeLayout` gives an overlay rect. The overlay surface is created the first time, added on top and sized. `projectWindow` sets `view.overlay = { kind: 'command-bar', placement: 'center', anchor: <content rect>, ... }`. The view is pushed and the overlay webContents is focused.
4. `src/renderer/overlay/CommandBar.tsx` draws the bar centered in `anchor`. Typing stays local and `suggest` ranks results. Enter dispatches `{ type: 'commandBar/submit', input }`.
5. `src/main/ipc.ts` parses it; `reduce` runs `src/domain/ops/tabs.ts` `commandBar/submit`: `resolveTypedInput`, `openTab` at the top of Today, focus it, close the overlay.
6. `render`: the new tab is now the pane. `tabs.viewFor` creates its view, attaches the key hook and calls `loadURL`. The stack becomes [sidebar surface, new tab]; the overlay is detached; the page gets focus. The sidebar surface receives a view with one more Today row whose status is `current`.
7. `src/main/tab-runtime.ts`: navigation and title events become `page/updated`, and the row's title and favicon update.

### Trace: the user clicks a space in the dock

1. `src/renderer/sidebar/Dock.tsx`: `dispatch({ type: 'space/focus', spaceId })` through `window.arc`.
2. `src/main/ipc.ts`: parse, route by sender to its window, `App.dispatch`.
3. `src/domain/ops/spaces.ts` `space/focus`: stamp `lastActiveAt` on the tabs leaving the screen, set `windows[w].spaceId`.
4. `render`: `selectWindow` gives the new space's active item as the pane (its view is created if it was never loaded) and the new theme's `windowColor`. The stack swaps the pane view. `projectWindow` gives `theme = resolveTheme(space.theme)`, the space's rows and the dock's active flag.
5. `src/renderer/sidebar/Background.tsx` crossfades to the new gradient and `SidebarApp` renders the new space's sections. The chrome view's pixels change, which e2e scenario 4 reads.

## Synthesis decision

Filled in by arena.

## Tradeoffs accepted

- We accept pushing a whole `WindowView` to up to three surfaces on every change, including every frame of a sidebar resize drag and every page title or loading event, in exchange for no patch protocol and renderers that cannot fall out of step. Pushes are coalesced per tick.
- We accept that back, forward, reload, zoom and devtools go through the reducer and come back as effects, which looks like a detour, in exchange for one input path, one place that resolves "the focused tab", and a test API that drives everything the same way a user does.
- We accept an opaque `AppState`, so W2 must ask W1 for every read it needs, in exchange for main never depending on the tree's shape.
- We accept three renderer surfaces (and their processes) per window in exchange for drawing correctly over web content.
- We accept that focus is re-applied only when the derived target changes. A user click can move focus in between, and that is intended.
- We accept that the archive stores tabs only. Archiving a folder or a split archives each tab, and the grouping is lost.
- We accept lazy loading after restart: background tabs show their saved title and favicon until opened.
- We accept native popup menus (context menus, "+") that do not look like Arc's, in exchange for menus that can extend over web content.
- We accept window-keyed state although v1 opens one window. Commands are window-scoped anyway because they come from a window.
- We accept a global folder collapsed state (Arc keeps it per window).
- We accept that a new split pane is a tab without a URL that the command bar fills. Dismissing the bar leaves an empty pane, which Ctrl+Shift+- closes.
- We accept quitting when the window closes, on every platform. Arc on macOS keeps running.

## Alternatives considered

- **Imperative managers in main** (TabManager, SpaceManager, WindowManager) that mutate their own state and emit fine-grained events. Lost on interface depth: dozens of public methods that hide little, state ownership split across managers, every feature touching several of them in a specific order, and no single place to make an operation idempotent or to test it without Electron.
- **State in the sidebar renderer**, with main driving native views from what the renderer reports. Lost: a shortcut pressed inside a tab view must go main -> renderer -> main; persistence, the clock and auto-archive would depend on a renderer being alive; the overlay and floating surfaces need the same state, which means syncing between renderers. That is two writers.
- **Main owns state but sends the raw domain document**, and renderers derive their views. Lost: the tree's representation leaks into W3 and W4, so changing it needs coordinated edits in three workers' code, and payloads grow with the archive and history.
- **Patch-based sync** (immer patches over IPC). Lost: complexity at both ends for small payloads, and lost or reordered patches become a new failure mode.
- **Command bar and archive drawn in the chrome view**, detaching the tab view while they are open. Lost: the page disappears behind the bar, which is not Arc's look, and focus handling gets harder.

## Open questions and risks

- On macOS, does a menu key equivalent fire in addition to `before-input-event` for the same key press? The router drops a duplicate within 100 ms, but the order is unverified. Without the guard, toggles such as Cmd+S would cancel themselves.
- With the sidebar hidden, should the content keep the inset frame (our choice: inset on every side, radius kept) or go edge to edge? The plan says "占满窗口".
- Is lazy loading of restored background tabs acceptable, or should Pinned tabs load at launch?
- Should the archive be a page in the content area, like Arc's Library, instead of an overlay card?
- Is quit-on-close acceptable on macOS for v1?
- What should a fresh profile's first tab open outside e2e? It is Google now.
- Do transparent WebContentsViews above tab views composite on macOS the way they do on Linux? The spike verified a transparent tab over the chrome view, on Linux only.
- The biggest risk is `WindowHost.render`. It is the one place where native views can differ from state: re-adding views to reorder them, a tab archived and restored before its old webContents finishes closing, and focus changes racing user clicks. If it is wrong, every scenario looks wrong. It is idempotent and e2e reads its result directly through `native()`, but it should be tested first.

## Next implementation step

Write `src/domain/tree.ts`, `reduce`, `normalize`, `selectWindow` and `projectWindow` with unit tests for `tab/toggle-pin`, `space/focus`, `split/add` and `clock/tick`, together with `computeLayout` and `WindowHost.render` behind the phase 3 smoke test, because every other worker's output can only be checked once a real `WindowView` reaches a real view stack.
