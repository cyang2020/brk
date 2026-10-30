# Core browser ownership and operations

Produce a candidate interface design for the next implementation batch. The product is Brk, a native Swift AppKit/SwiftUI browser over CEF. This batch repairs ownership boundaries and adds essential browser operations within the existing architecture. It does not reopen the application's overall framework choice.

Read the `architect` skill and its `references/runner-prompt.md`, `rationale-template.md`, and `design-red-flags.md` under `/Users/administrator/.codex/skills/`. You are one candidate runner. Do the work yourself, without starting other agents. The parent runs the comparison and synthesis. Use Codex as the user requested.

## Starting evidence

Read these documents in full, then inspect the relevant source and tests:

- [Architecture overview](grounding/overview.md) and [historical constraints](grounding/lineage.md).
- [Platform grounding](grounding/platform.md), [native-shell grounding](grounding/native-shell.md), and [integration grounding](grounding/integrations.md).
- [Full completion plan](plan.md) and [feature inventory](features.json).
- The history safety correction and its evidence under `verify/completion/history-safety/`.
- The existing native focus, privacy, profile, and shutdown evidence under `verify/swift/focus-parent/` and the latest parent native run.

The grounding reports describe immutable commit `6d2d6d5`. The starting checkout also contains later history-only clearing and its regression coverage. Cite the exact commit and binary used for every new probe. Historical source matches are not proof that a later experiment is unchanged.

## Required outcomes

1. Define how two standard windows selecting the same logical tab obtain usable content. Resolve activation, background behavior, splits, Peek, closure, restoration, and actual event-origin routing. Compare whole ownership alternatives before recommending one. Reproduce the current same-tab behavior with real CEF. Do not claim Arc's precise behavior without reference evidence. Preserve per-window focus requests, native editors, and hidden private-opener routing.
2. Make download cancellation control the real transfer. Define original context, settings, native parent, callback ownership, updates before the decision callback, save-panel reentrancy, and terminal results. Resolve source-tab closure, profile reassignment/deletion, private-context expiry, and application quit. Do not assume a transfer survives browser destruction. Measure bytes, callback order, and file outcome with a bounded local server. Compare retaining the initiating browser with other viable ownership strategies before freezing the contract.
3. Define typed find requests and results for initial search, next, previous, count/ordinal, and close. Account for query replacement and document changes within one browser incarnation. Include native focus and keyboard routing. Find and Replace in supported editable content, Use Selection to Find, and Jump to Selection remain required; give their implementation boundary and dependencies.
4. Define save-page, print, PDF, and scoped browsing-data removal requests, results, cancellation, and native UI ownership. Use supported CEF capabilities and resolved command identifiers. Probe disputed behavior in the actual hidden-toolbar, reparented host. Separate completed output from opening a native dialog. Separate data removal from profile disposal. Unsupported data classes must be explicit, and operations must complete before dependent reloads.

The package must trace representative calls from menu or view through domain state and engine, then back to visible results. Distinguish logical tab identity, browser incarnation, document identity, operation identity, and native host only where their lifetimes differ. Keep CEF wire values and borrowed callbacks behind the adapter. Derive ownership rather than maintaining inconsistent copies.

## Candidate package

Write your package under `docs/completion/core-candidate/` in your assigned worktree. Start with caller usage and realistic call sites, then derive types, signatures, and module boundaries. Include an executable compile check for the type sketch where practical. Use unimplemented bodies for the final design sketch; a prototype is evidence, not a disguised implementation claim.

Include a short rationale, a structurally different alternative, the red-flag review, and a concrete migration plan. Name old paths to delete, existing callers to migrate, file ownership for implementation workers, and tests that prove each unit. State what is proven, inferred, or still unknown. Any unresolved feasibility question must have a bounded next experiment and must not silently become an assumed contract.

Put reproducible probes and captured results under `verify/completion/core-candidate/`. Experimental changes to this worktree are allowed. Label them and keep them distinct from the proposed final contracts. Use the checkout's bundle, isolated data, and only processes started by your probe. Do not change global browser settings, original Arc data, credentials, OS protections, or other workers' apps. Do not reuse the parent bundle for an experiment with changed source.

Native GUI experiments across candidates share a display. Acquire the common advisory lock `/tmp/brk-core-native.lock` with Python `fcntl.flock` before launching a native experiment and release it afterward. Use nonblocking lock attempts with a bounded wait, continuing source work if another runner owns it. Do not hold the lock during a build. Close your own test windows, then release it. Independent compiler and reducer checks can run concurrently.

Keep the canonical inventory, completion plan, audit log, and existing verification files unchanged. Commit your candidate and evidence on the assigned branch, report the starting/final SHA and exact commands, and leave a clean worktree. No PR and no publishing. Do not read another candidate or the parent's private scoring rubric.

## Scope that remains after this batch

The full inventory remains the delivery contract. Extensions, site permissions, media and casting, advanced tab/space tools, import/onboarding, Notes/Easels/Boosts, local CLI AI, and local-folder sync remain scheduled. Identify dependencies this batch creates for them without building a generic framework for all future features.

Account, membership, referrals, and Send to Dia are excluded. Online sharing uses local file export. Automatic updates are deferred. No other feature is excluded by this brief. Authenticated Arc references still gate final visual parity, while functional work continues.
