# Parallel browser completion batch

The user requested parallel completion of browser foundations, tabs and Spaces, splits, website/extensions, and import/sync on 2026-10-31. This batch has six implementation slices plus the existing Find task. It prioritizes these groups without cancelling the remaining agreed scope.

The common starting commit is `2e9935b54dcee18c7da680c6e3a28fc7a9bb7f15`. The parent commits these instructions before dispatch. Each T3-provided worktree must begin at the dispatch checkpoint or its direct descendant. Record the actual starting SHA before edits.

## Current architecture and evidence

The product is native Swift 6, AppKit/SwiftUI and pinned Chrome-runtime CEF. `AppStore` is the sole runtime state owner. Inputs pass to the pure reducer; projection produces window snapshots and page demand. AppStore executes typed effects, renders native views, and reconciles the engine. Browser events return with browser/document/context identity. Keep this flow; do not introduce a second mutable application store.

`PageID` identifies a window/item pair. `BrowserToken` distinguishes native browser incarnations and `DocumentToken` fences main-document operations. Saved logical tree metadata and window-specific live addresses are different. Explicit blank/empty selection must not silently create demand. Hidden or retired pages must not take focus or act on another window.

Accepted public downloads have operation-owned native resources and may outlive Brk tab closure. Private-session epochs and synchronous context revocation precede final drain. A mandatory native close may terminate a transfer and must report the actual failure/recovery result. Never reconstruct its original request or infer that a writer stopped from a closed browser. Read the current production code and `2e9935b54d:verify/completion/transfers-parent/REPORT.md` before changing these paths.

`StateCodec` v3 saves validated public document state; `StateFile` performs atomic local writes. Scratch/private state remains transient. Sync is a separate explicitly whitelisted protocol, never a copy of `state.json`. The one shortcut/action table drives menu, command bar and key routing. Preserve page-first handling, user remaps and the special documented Downloads priority.

Read `docs/completion/core-design/{README,identity,transfers}.md`, `docs/completion/grounding/{platform,native-shell,integrations}.md`, `docs/design/swift/module-map.md`, and your assigned acceptance rows. Grounding reports describe an older baseline: current identity/transfers reports and current source supersede their obsolete gaps. The original interface candidates and native experiments are evidence, not code to copy blindly. C4 Find is owned by the existing task; C5 output belongs to browser-basic and C6 data removal to sites-extensions.

## Design and implementation

Use the selected domain/engine/native architecture. Do not repeat the overall app design arena. For a genuinely new ownership or stored-format decision, follow architect/arena within the slice: compare two independent sketches, grade them against concrete correctness/privacy/extension/verification criteria, synthesize, then implement without waiting for the user. You may launch at most two bounded, read-only Codex design agents for this purpose. No further implementation fanout. User preference for Codex overrides the global Claude pstack role configuration.

Each implementer owns its entire isolated branch. Prefer dedicated new files for its rules, adapters, panels and scenarios. Shared integration files may receive necessary additive changes in each isolated checkout; record every change to `Actions`, `Command`, `Effect`, `Model`, `Snapshot`, `Project`, `Codec`, `AppStore`, `WebEngine`, CEF callbacks and package/build composition. The parent alone merges them. Do not mutate main, another worker's checkout, another branch, running worker output, or shared canonical reports.

Keep shared `StateCodec` changes backward-readable and default new optional fields for existing v3 files. The parent owns any coordinated format-version bump. If the feature requires a semantic migration, provide a named migration and fixture tests; do not silently reinterpret an existing field. Do not create parallel global callback sinks, page owners or competing keyboard maps. Existing engine callbacks may be extended with scoped operation owners and explicit teardown.

The main branch has 15 inherited dirty verification files under `bf1ea87186:verify/swift`; leave them untouched. The parent owns `docs/completion/features.json`, `docs/completion/plan.md`, this batch manifest and `.audit/arc-clone.tsv`. Slice reports/proposals are independent outputs. Existing frozen type files may be extended only when necessary for the assigned feature; preserve their proven invariants and record the deviation with evidence.

## What counts as complete

Implement the actual menu/control entry points, state/effect execution, native behavior, persistence/migration where appropriate, cancellation/errors, private/context scope and tests. A persisted switch, disabled action, placeholder page, routed command, raw API name or successful build alone is not completion. Do not drop smaller actions listed in acceptance or relabel unsupported behavior as success. Cross-feature rows remain partial until all their prerequisites are implemented.

Use fixture pages, harmless local extensions, explicit temporary sources/credentials and owned temporary sync replicas. Never read actual user browser profiles, cookies, passwords or private keychains for development. Do not change the user's default browser or publish/send anything. Runtime authorization belongs to a real native user flow; fixture authorization is not proof that a real user's OS permission was granted. Missing hardware, external authorization or authenticated Arc pixels are explicit evidence gaps, not an excuse to stop other implementation.

All production code must build in Swift 6 and obey the existing import boundaries. Prefer behavior tests that exercise observable outcomes. Record exact commands, input/source and executable identities, actual file/DOM/network outcomes, screenshots and failed attempts. Inspect real Brk captures for layout/readability; do not claim Arc pixel parity. The native suite currently has 67 passing scenarios. Add a dedicated scenario file per slice and minimally register it; retain existing assertions/skips. Each completed branch runs the signed build and the affected native cases, plus the full native suite before acceptance when it can obtain the shared lock.

## Shared Mac and tool boundaries

T3 creates the isolated checkout; do not create worktrees in the shell. Do not use a CLI to bypass an unavailable delegate provider. A design child uses Codex only. Follow a running delegate's `next` instruction and never poll it. Read a completed task before discussing its result.

Compile in the assigned checkout. A copied scratch project needs a fresh Swift scratch path. Full release builds should serialize through `/tmp/brk-batch-build.lock`; focused unit work can proceed independently. Every GUI/native probe must acquire the existing `/tmp/brk-core-native.lock` using the established Python `fcntl.flock` wrappers, use that checkout's signed bundle and its own short `/tmp` data root, and terminate only its own PIDs. Lock contention is an infrastructure condition, not a product failure: do useful non-GUI work, then perform bounded acquisition. Never run a whole native suite without the lock.

If returning before all assigned features work is unavoidable, retain actual progress, commit it, and return ISSUES/BLOCKED with an exact remaining list and reproduction evidence. Do not claim the slice complete. The parent continues unresolved work and independently reviews integrated behavior.
