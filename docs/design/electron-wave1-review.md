# Wave 1 review

Reviewed `c6ba738..08d6787` for domain, shared, renderers, and Vitest configuration against the requested design, scope, anatomy, and e2e contracts. All experiments ran in `/tmp/wave1-review-copy`; the original workspace and worker worktrees were not modified. Three proven findings follow. No scripted e2e blocker was established; Electron e2e was not run while W2 is pending.

All repro commands below run from `/tmp/wave1-review-copy`. The new test files remain there for reruns. Renderer repros use real React components, schema parsing, reducer, and projection, with jsdom geometry supplied explicitly.

## 1. Ctrl+Tab makes a just-used tab eligible for immediate auto-archive

Severity: **wrong behavior**. File: `src/domain/ops/tabs.ts:221` and `:229`.

Repro: pin A, open Today tab B, leave B visible for 13 hours, Ctrl+Tab to A, release Ctrl, then tick the clock.

```sh
npx vitest run src/domain/wave1-review.test.ts -t 'recent cycling'
```

Trimmed output, exit 1:

```text
cycle: just-left B exists= false archive= [ 'https://example.com/b' ]
AssertionError: expected [ 'review-1', 'review-3', …(2) ] to include 'review-7'
Tests  1 failed (1)
```

Intent: auto-archive measures inactivity. B was on screen until the switch, so its inactivity has just begun. Cycling suppresses screen-change stamps, and commit stamps only the destination, leaving B's timestamp 13 hours old.

Fix: keep the frozen cycling order but stamp outgoing tabs and split panes when they leave the screen. Update the existing test at `src/domain/reduce.test.ts:423`, which currently asserts the incorrect stamps-only-chosen policy.

## 2. Favorites cannot be reordered within their grid

Severity: **wrong behavior**. File: `src/renderer/sidebar/drag.tsx:121`; missing tile geometry in `src/renderer/sidebar/Favorites.tsx:45`.

Repro: create Favorites A and B, then pointer-drag B before A.

```sh
npx vitest run src/wave1-ui-review.test.tsx -t 'favorite tiles'
```

Trimmed output, exit 1:

```text
favorite order after B-before-A drag: [ 'https://example.com/a', 'https://example.com/b' ]
AssertionError: expected [ 'ui-review-6', 'ui-review-7' ] to deeply equal [ 'ui-review-7', 'ui-review-6' ]
Tests  1 failed | 1 skipped (2)
```

Intent: v1 tab drag sorting includes Favorites. Tiles expose no measured drop geometry, and dragging a Favorite filters out the grid's sole placeholder, so no destination remains inside the grid.

Fix: measure individual tiles and use both pointer coordinates to compute an insertion index after detaching the source. Keep the grid append target for drops from other sections.

## 3. Rename Current Item cannot reveal a tab inside a collapsed folder

Severity: **wrong behavior**. File: `src/domain/ops/sidebar.ts:21`; renderer hides the target at `src/renderer/sidebar/Row.tsx:190`.

Repro: pin the current tab, move it into a folder, collapse that folder, then dispatch the Rename Current Item action.

```sh
npx vitest run src/wave1-ui-review.test.tsx -t 'renaming the current'
```

Trimmed output, exit 1:

```text
rename target= ui-review-6 input exists= false
AssertionError: expected null not to be null
Tests  1 failed | 1 skipped (2)
```

Intent: the rename action must expose an editable input for its target. The reducer sets `renamingId` and redirects focus to the sidebar, but the collapsed ancestor prevents the input from mounting.

Fix: expand the target's ancestor folders and Pinned section when beginning rename, then let the existing input focus itself.

## Unproven suspicions

None retained. Native window behavior and the nine Electron scenarios require W2 integration verification.

## Checks run

- `cp -R /Users/administrator/.t3/projects/brk /tmp/wave1-review-copy` — exit 0.
- `npm install` — exit 0.
- Baseline `npm test` — exit 0; 205 passed, 5 TODOs.
- Baseline `npm run typecheck` and `npm run build` — exit 0 each.
- `npm test -- --exclude src/domain/wave1-review.test.ts --exclude src/wave1-ui-review.test.tsx` — exit 0; original 205 tests still pass.
- Three individual repro commands above — exit 1 each, failing on the stated behavior.
- `git diff --exit-code 08d6787..HEAD -- src/domain src/shared src/renderer vitest.config.ts docs/design docs/plan.md docs/arc-anatomy e2e/arc.spec.ts` — exit 0; copied sources match the review target.
