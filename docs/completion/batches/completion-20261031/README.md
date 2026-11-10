# Completion batch: every partial and missing row

On 2026-10-31 the user asked for all remaining partial and missing feature rows to be completed in parallel without stopping, using the pstack skills that fit. The reconciled ledger (`ee4e2ec04e:verify/completion/ledger-reconciliation-20261031/REPORT.md`) lists 43 partial and 19 missing rows. This batch assigns 60 of them to twelve implementation slices in two waves and keeps two cross-feature rows (A043 appearance consumers, A081 Library) with the parent. A148 (Arc pixel reference) stays blocked on the user's Arc login and is not part of this batch.

The base commit is recorded in `manifest.json`. The parent commits these instructions before dispatch; each T3-provided worktree starts at that commit or its direct descendant. Record the actual starting SHA before edits. Wave 2 slices start from `main` after the wave 1 branches are integrated, so their base commit is later.

## Roles and models

Implementation runs on Codex (`gpt-6.1-sol`, reasoning effort xhigh), as the user decided on 2026-10-31. A slice may launch at most two bounded, read-only Codex design children when its brief asks for two design sketches; no other fan-out. Independent review of each delivered branch runs on Claude (`claude-fable-5-1` and `claude-opus-5-5`, effort xhigh) as a new delegate per review; a worker never reviews itself. The parent (Claude Fable 5.1) integrates, re-verifies and updates the canonical ledger. `dispatch.json` records which task ran which slice.

## Current architecture and evidence

The product is native Swift 6, AppKit/SwiftUI and the pinned Chrome-runtime CEF 154.0.34.0. `AppStore` is the sole runtime state owner. Inputs pass to the pure reducer; projection produces window snapshots and page demand. AppStore executes typed effects, renders native views and reconciles the engine. Browser events return with browser, document and context identity. Keep this flow; do not introduce a second mutable application store.

`PageID` identifies a window and item pair. `BrowserToken` distinguishes native browser incarnations and `DocumentToken` fences main-document operations. Saved logical tree metadata and window-specific live addresses are different. Explicit blank or empty selection must not silently create demand. Hidden or retired pages must not take focus or act on another window. Accepted public downloads own their native resources and may outlive tab closure; private-session epochs and synchronous context revocation precede the final drain. `StateCodec` v3 saves validated public document state through atomic `StateFile` writes; scratch and private state stay transient; sync is a separate whitelisted protocol. The one shortcut and action table drives the menu, the command bar and key routing; preserve page-first handling, user remaps and the documented Downloads priority. Website policy, site data, extensions, Find, output and transfer adapters each have one owner file in `Sources/BrkCEF`; their contracts are in `docs/completion/core-design/` and the parent receipts under `1b71cb97bd:verify/completion/*-parent/REPORT.md`.

Read `docs/completion/handoff-20261031.md`, `docs/completion/core-design/README.md`, `docs/design/swift/module-map.md`, the parent receipts for the subsystems you touch, and your slice brief. Grounding reports describe an older baseline; current source and the parent receipts supersede them.

## Design and implementation

Use the selected architecture. Do not repeat the overall application design arena. For a genuinely new ownership or stored-format decision your brief names, compare two independent sketches, grade them on correctness, privacy, extension and verification, synthesize one `DESIGN.md` under your evidence directory and implement without waiting for the user.

Each implementer owns its isolated branch. Prefer dedicated new files for rules, adapters, panels and scenarios. Shared integration files (`Actions`, `Command`, `Effect`, `Model`, `Snapshot`, `Project`, `Codec`, `AppStore`, `WebEngine`, CEF callbacks, package and build composition) may receive necessary additive changes; list every such change in your report's `INTEGRATION.md`. Keep `StateCodec` changes backward-readable with defaulted optional fields; the parent owns any format-version bump. Do not create parallel callback sinks, page owners or competing keyboard maps. The paths named as owned by another slice in the briefs belong to that slice; add only additive hooks there and list them.

Do not mutate `main`, another worker's checkout or branch, running worker output, `docs/completion/features.json`, `docs/completion/plan.md`, this batch's manifest or `.audit/arc-clone.tsv`. The 15 inherited dirty files under `bf1ea87186:verify/swift` stay untouched.

## What counts as complete

Implement the actual entry points, state and effect execution, native behavior, persistence or migration where appropriate, cancellation and errors, private and context scope, and tests. A persisted switch, a disabled action, a placeholder page, a routed command, a raw API name or a successful build alone is not completion. Do not drop smaller actions listed in acceptance or relabel unsupported behavior as success. Cross-feature rows stay partial until their prerequisites are merged.

Use fixture pages, harmless local extensions, explicit temporary sources and credentials, and owned temporary data roots. Never read the user's real browser profiles, cookies, passwords or keychains. Do not change the default browser, do not publish or send anything, do not change OS permissions. Missing hardware, external authorization or authenticated Arc pixels are explicit evidence gaps, stated as such.

All production code builds in Swift 6 and obeys the import boundaries. Prefer behavior tests. Record exact commands, source and executable identities, actual file, DOM and network outcomes, screenshots and failed attempts. Inspect real Brk captures for layout and readability; do not claim Arc pixel parity. Add one scenario file per slice with the brief's name prefix and register it minimally; keep existing assertions and skips. Before delivery run the signed build and your scenarios, and the full native suite when you can obtain the lock.

## Shared Mac, locks and tools

Create the CEF link once in a new checkout: `ln -s /Users/administrator/.cache/arc-spike-swift/.cef .cef`.

Two kinds of build. An iteration build compiles, bundles and signs without the unit-test step and takes only the build lock, so native runs of other slices overlap with it:

```sh
SKIP_TESTS=1 python3 scripts/with-batch-locks.py --lock /tmp/brk-batch-build.lock -- scripts/build.sh
```

The delivery build, run once before the final report, takes both locks and runs the full unit suite:

```sh
python3 scripts/with-batch-locks.py --lock /tmp/brk-core-native.lock --lock /tmp/brk-batch-build.lock -- scripts/build.sh
```

Native runs record source and binary identity and take the native lock:

```sh
python3 scripts/run-native.py <unique-name> --only <scenarios> --run-timeout 600
```

Run only your own scenarios plus the existing ones your change touches. Do not run the full native suite: the parent runs one unified full build and the full regression on the integration branch after each delivery and sends failures back to their owners. Focused `swift test --filter` runs need no lock.

The lock wrapper waits in a fair first-come, first-served queue (`/tmp/brk-lock-queue`), starts your command the moment the locks are free and it is your turn, and prints every 30 seconds your position and who holds the locks. It has no give-up time unless you pass `--timeout`; `python3 scripts/with-batch-locks.py --status` shows the holders and the queue. A wait is never a blocker and never evidence; do not report BLOCKED for lock contention. If your shell tool limits command duration, start the locked command in the background with its output in a log under your evidence directory and read the log; do not edit source while it waits or runs. Never run a native suite without the lock; never change source while your native run is active; terminate only your own PIDs. T3 creates your checkout; do not create worktrees in the shell. Follow a running delegate's `next` instruction and never poll it.

Deliver as soon as your own scenarios pass natively and the delivery build is green. Rows you could not finish stay partial with their exact remaining gate; the parent's unified regression and review decide the rest. If you must return before everything works, commit the real progress and return ISSUES or BLOCKED with the exact remaining list and reproduction evidence.

## Deliverable

Evidence goes under `1b71cb97bd:verify/completion/batch2-<slice>/`: `REPORT.md` (PASS, ISSUES or BLOCKED first; starting and final commits; what works; exact remaining gates per row; commands; identities; retained failures), `proposal.json` with exactly the assigned IDs in the shape of `06656768e1:verify/completion/batch-tabs/proposal.json`, `INTEGRATION.md` listing shared-file edits, and `decisions.tsv` written with `~/.claude/skills/show-me-your-work/scripts/log.sh`. The final reply states PASS, ISSUES or BLOCKED, the starting and final commit, changed files, actual commands and results, limitations and clean-worktree status. No PR or publishing.
