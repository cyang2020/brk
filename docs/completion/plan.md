# Complete the agreed Arc feature set

The user resumed work on 2026-10-31 and requested completion of the full agreed scope. Continue on Codex. The historical inventory contains 148 feature rows across 22 sections. Its old status counts are not current implementation counts.

## Scope and completion rules

Build Brk from scratch in Swift with native AppKit/SwiftUI views and CEF. Keep the existing domain, layout, privacy, lifecycle, and native-control boundaries unless a proven requirement needs a revised contract. Do not copy the excluded cra implementation.

The user excluded account, membership, referral, and Send to Dia functionality. Sharing uses local file export. AI uses the user's local Claude or Codex command-line tools. Automatic updates remain deferred. Those decisions do not exclude the other unfinished Arc features.

Every inventory row must have an explicit current state, acceptance criteria, an owner, and verification appropriate to its behavior. A persisted toggle, a disabled menu item, a placeholder, or a passing build alone is not completion. `scripts/check-completion.py --require-complete` must pass before the whole project is called complete. Passing the script checks bookkeeping; independent source and runtime review must still validate the evidence.

Reference UI is a separate gate. The cloud Arc currently shows Sign In. The user's own Mac has an authenticated Arc session. Investigate the user's requested local skip-login route using shipped-artifact evidence and isolated experiments. If no route is established, prepare a local reference-capture script. Neither static constants nor Brk screenshots prove visual parity without an actual Arc reference.

This is a multi-batch project with several large feature groups, not a single short patch. Effort for the remaining groups will be estimated after the source and CEF capability audit. No calendar deadline or completion percentage is inferred from the historical table.

## Workflow

1. Integrate the completed native-focus changes and independently rerun the signed build and all existing CEF scenarios. Preserve preexisting dirty verification files.
2. Reconcile all 148 feature rows with current source, disabled actions, settings consumers, tests, and native evidence. Produce an ownership and capability map before adding interfaces.
3. Ground the next engine and native-UI changes with the `how` workflow. Compare two independent type/interface designs through `architect` and `arena`, then obtain an independent judgment. Do not repeat the settled overall application architecture.
4. Freeze interfaces and assign separate checkouts and source ownership for each implementation batch. Start with actual download cancellation and essential page operations, then site/extension support, advanced tab/space tools, import/onboarding, creation tools, media, AI, and local-folder sync. The capability audit may reorder dependencies.
5. Integrate each batch, reproduce review findings, and rerun affected native scenarios plus required build checks. Keep all failed attempts and their disposition. Test private navigation and immediate download shutdown after engine changes.
6. Complete visual comparison against reference Arc states, physical-input and external-link checks, data migration and privacy verification, and an independent final audit. Unresolved evidence or access is recorded as blocked, not verified.

## Execution boundaries

The parent owns main, the canonical inventory, the plan, and `.audit/arc-clone.tsv`. Delegates publish their own findings or implementation branch. They do not edit the canonical inventory or audit while another worker is active. The parent aggregates proposals by feature ID.

Each implementation brief names its exact starting commit, owned paths, caller contracts, acceptance conditions, commands, and evidence destination. GUI verification uses that checkout's app and separate data. No worker kills other application processes or replaces another worker's data.

Browser data import, sync, and UI reference collection are developed and verified with fixtures or explicit user-selected files. Do not move credentials, cookies, or private browser profiles to obtain a reference session. A local UI experiment does not establish authenticated server functionality.

## Inventory use

`features.json` initially marks rows `unreviewed` so stale wave-1 statuses are not promoted to current claims. Reviewers return row proposals in separate files. `historical_status` is provenance only. A `verified` row needs passing, repository-local evidence and every declared verification kind. `excluded` and `deferred` rows require a recorded user decision.

```sh
python3 scripts/check-completion.py
python3 scripts/check-completion.py --require-complete
```

The second command is expected to fail until the agreed feature scope is complete.

## Completed grounding and current batch

- [Platform grounding](grounding/platform.md) assessed 43 rows covering CEF and browser operations.
- [Native-shell grounding](grounding/native-shell.md) assessed 79 rows covering UI, domain, layout, persistence, menus, and settings.
- The parent reviewed the remaining 26 productivity/integration rows in [integration grounding](grounding/integrations.md).

All 148 rows now have a current assessment. The counts are 16 verified, 23 implemented, 48 partial, 55 missing, 3 excluded, 2 deferred, and 1 blocked. These categories describe acceptance and evidence, not effort or a completion percentage. The parent merged the 122 delegated proposals with `scripts/merge-completion-proposals.py`, then recorded subsequent corrections without rewriting the historical reports.

The History review found a destructive coupling between history removal and profile disposal. Commit `ddc2854` removes that coupling and labels the action **Clear History…**. Its [before/after evidence](../../verify/completion/history-safety/REPORT.md) includes a failing native reproduction, 460 build tests with three known skips and zero failures, and 46 passing native scenarios. Full scoped browsing-data clearing remains unfinished.

The reference experiment returned without an Arc-copy launch because its containment probe aborted. The capture helper is delivered at `artifacts/arc-reference-capture.zip`; the parent validated its checks and a genuine cloud welcome-screen capture. Authenticated local browser references and fake-auth runtime behavior remain unresolved. The reference row remains blocked and is not counted as visual parity.

The [architecture overview](grounding/overview.md) combines the grounding reports. Two independent Codex candidates completed the [core batch brief](core-batch-brief.md), and a separate Codex judge recommended A. The parent agreed and adopted the [synthesized design](core-design/README.md), with corrected empty-page, event-origin and restoration rules. The [first implementation unit](core-design/implementation-1.md) integrates window-owned page demand, codec v3, native hosting and input routing under one owner. Later download, find, output and data-removal contracts retain the review's C2-C6 gates. No human approval checkpoint is required for these reversible changes.

## Identity integration and next unit

The first implementation is merged, followed by six parent review corrections. The [parent receipt](../../verify/completion/identity-parent/REPORT.md) records 484 tests with three inherited skips and zero failures, and 52 passing native scenarios. A051 now has verified unit/native acceptance; session restore remains partial because the restore-off setting is not wired. These results do not establish full feature or visual completion.

The next [transfer contract](core-design/transfers.md) and [typed boundary sketch](core-design/Transfers.swift) resolve C2-C3 for actual download cancellation, original browser/context ownership, pending native decisions and disposal. They preserve separate C4-C6 gates for find, output and broad data removal. The implementation must prove real transport/file outcomes and private revoke-before-drain, not only a changed ledger label.

## Transfer integration and page find

The C2-C3 implementation and parent corrections are merged. The [parent receipt](../../verify/completion/transfers-parent/REPORT.md) records 508 tests with three skips, nine raw ownership tests, and 67 native passes. A048 is verified against that contract and its disclosed limits, including explicit failure/recovery for mandatory native browser destruction. Directory deletion remains scheduled for next launch.

The next [Find contract](core-design/find.md) and [typed sketch](core-design/Find.swift) resolve C4: native page find, generated-ID correlation, scoped selection, Jump and supported editable replacement with real undo/input tests. C5 output and C6 broad data removal remain separate, followed by the rest of the full inventory.

## User-prioritized parallel batch

The user requested parallel implementation of browser foundations, tabs/Spaces, split views, website/extensions, and import/sync. The [batch contract](batches/browser-20261031/README.md) partitions these into six isolated implementation branches, with the existing Find task continuing independently. The [manifest](batches/browser-20261031/manifest.json) assigns 105 rows without overlap plus A039 to the existing task. Shared settings/menu rows are integrated by the parent; cross-feature rows remain partial where their other dependencies are outside this batch.

Workers implement complete native flows and publish separate evidence/proposals. Only the parent integrates the branches and updates canonical acceptance. Production shared files are merged sequentially; builds and native GUI tests use the batch locks. Output C5 and data-removal C6 must resolve their earlier design gates in their assigned slices. Creative/media/AI work follows this priority batch. Authenticated Arc visual comparison remains a separate unresolved reference gate.

## Find acceptance and split integration

The parent accepted A039 after the completed implementation, an independent review and parent repairs. The [parent Find receipt](../../verify/completion/find-parent/REPORT.md) records 537 tests with three inherited skips, 14 raw ownership tests, eight focused native passes and 79/79 complete native passes. The 599 actual input hashes and readable native controls are checked. Supported editing and physical-input/Arc-reference limits remain explicit.

The split branch has delivered A071-A077. Independent review proved two regressions: background pane closure changed foreground demand, and unrelated title renders hid valid drag feedback. The parent reproduced and repaired both in an archived source copy; 26 focused component/domain tests pass. [The retained review and repair](../../verify/completion/splits-parent/) precede main integration. Merge must preserve Find's key-intent/focus/document rules, avoid Find/split toolbar overlap, and verify native input after separation in both windows. No split row is promoted from that branch's handoff alone.

The parent accepted all seven split rows after review repairs and combined native verification: 568 tests with three inherited skips,14 ownership tests,14 focused and87 full native passes. Controls, feedback and both-window typing are covered. The tabs branch remains outside main until its isolated fixes are integrated; Chrome audibility and other partial acceptance gates remain.

## Handoff

The parent paused on 2026-10-31 with main at `a485d69`. [The handoff](handoff-20261031.md) records the current build and native results, the five open native failures, the stale ledger counts that still need reconciliation, every remaining feature group, the blocked Arc reference gate, open branches and the exact commands and rules for continuing.
