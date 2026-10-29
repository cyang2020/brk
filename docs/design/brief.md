# Architect brief: Arc clone on Electron

You are one runner in a parallel design exploration (pstack `architect`, Phase B, run through `arena`). Produce one candidate design package. Another runner on a different model gets this same brief. Do not hedge toward a safe middle; a sharp, well-argued shape is what the picker needs.

Read in this order before writing anything:

1. `/Users/administrator/.claude/skills/architect/references/runner-prompt.md` (the discipline you work under).
2. `/Users/administrator/.claude/skills/architect/references/rationale-template.md` (the shape of your prose output).
3. `/Users/administrator/.claude/skills/architect/references/design-red-flags.md` (screen your own design against it before you finish).
4. `docs/plan.md` in your worktree: the done predicate, v1 scope, non-goals, stack, and environment limits. Scope is fixed; do not add or drop features.
5. `docs/arc-anatomy/model-and-shortcuts.md` sections 1.3 to 1.11, 1.13, 1.14, 2.4, 2.5, 4.3, 4.4 (Arc's observed data model, menus, shortcuts, settings).
6. `docs/arc-anatomy/visual-and-copy.md` sections "Sidebar and tab colors", "Content area background and corners", "Space theme system", "Space theme preset palette", "Sidebar sections", "Tabs", "Command bar and URL inputter", "Split view", "Layout constants".
7. `/tmp/arc-spike/REPORT.md`: what Electron 45 verifiably does (view stacking, transparency, `setBorderRadius`, Playwright page discovery, `capturePage` compositing, `close()` being asynchronous, `before-input-event` for shortcuts, `setBounds` animation bug).

## The task

Design the module structure, core types, and function signatures for an Arc-style browser on Electron 45 + TypeScript (strict) + React + electron-vite, so that four implementation workers can then fill in bodies in parallel (domain model; main process; sidebar renderer; command bar and archive renderer) without stepping on each other. Fidelity target is Arc's observed model and look, simplified to v1 scope.

Fixed constraints:

- Node 22, Electron 45, one `BaseWindow` per browser window, one full-size chrome `WebContentsView` (sidebar UI, gradient background) at the bottom of the stack, one `WebContentsView` per tab stacked above it, only the active tab (or the split panes) attached.
- Renderers run with `contextIsolation: true`, `sandbox: true`, and a preload that exposes a typed API. No `remote`, no Node in renderers.
- One owner for application state. Say which process owns it, how renderers get a projection of it, and how an edit flows back. IPC is typed end to end; wire shapes never leak past the boundary.
- Persistence: one JSON file under `app.getPath('userData')`, written atomically, versioned, with a parse step at the boundary. Restoring must tolerate a tab whose page fails to load.
- Keyboard shortcuts: `Menu` accelerators plus `before-input-event` on every tab view (the spike showed the accelerator alone loses to pages that handle the key). Shortcuts come from one table that also drives the menu and the command bar's command list.
- Auto-archive uses an injectable clock so e2e can advance time.
- Test hooks: the main process exposes a small, explicit test API (for example on `globalThis` behind an env flag) that Playwright reaches through `electronApp.evaluate`; renderer elements carry stable `data-testid` values. Name the hooks in your sketch.
- Layout numbers Arc compiled into code are unknown. Pick defaults (sidebar default/min/max width, content inset, corner radius, dock height) and mark them as guesses in one constants file.

## What to produce, in your worktree

1. `docs/design/rationale.md` per the rationale template. Write the caller's usage first (what each implementation worker imports and calls, two or three realistic call sites per worker), then derive the types. Fill every section except "Synthesis decision".
2. `docs/design/module-map.md`: one table of modules with path, owner worker (W1 domain, W2 main, W3 sidebar UI, W4 command bar and archive UI), what it hides, what it exposes, and who imports it. Include the dependency direction rules and the e2e hook contract.
3. `src/**`: the skeleton. Real file names, real exported types and signatures, `throw new Error('not implemented')` bodies, pseudocode as `// TODO` comments for tricky logic, doc comments stating intent and invariants. It must typecheck in principle (imports resolve, types agree). Do not install dependencies or write bodies. A `package.json` with the dependency list and scripts (`dev`, `build`, `typecheck`, `test`, `e2e`, `e2e:docker`) is part of the skeleton.
4. `e2e/` skeleton: the Playwright fixture that launches the app, maps Pages to webContents, and takes a composite screenshot, as signatures and comments only, plus one spec file listing the nine scenarios from `docs/plan.md` as `test.skip` stubs.

Keep the whole package readable in one sitting: a reviewer should trace "user presses Cmd+T" and "user clicks a space in the dock" from input to pixels by reading types and signatures alone.

## Rules

- Work only inside your worktree. Commit your package to your branch with one commit (`git add -A && git commit`), message `arena candidate: <one-line summary of the shape>`.
- Do not read the other runner's worktree.
- Finish with a reply under 300 words: the load-bearing decisions, what you rejected, and the single biggest risk in your shape.
