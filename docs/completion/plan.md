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

All 148 rows now have a current assessment. The counts are 6 verified, 26 implemented, 52 partial, 58 missing, 3 excluded, 2 deferred, and 1 blocked. These categories describe acceptance and evidence, not effort or a completion percentage. The parent merged the 122 delegated proposals with `scripts/merge-completion-proposals.py`, then recorded subsequent corrections without rewriting the historical reports.

The History review found a destructive coupling between history removal and profile disposal. Commit `ddc2854` removes that coupling and labels the action **Clear History…**. Its [before/after evidence](../../verify/completion/history-safety/REPORT.md) includes a failing native reproduction, 460 build tests with three known skips and zero failures, and 46 passing native scenarios. Full scoped browsing-data clearing remains unfinished.

The reference experiment returned without an Arc-copy launch because its containment probe aborted. The capture helper is delivered at `artifacts/arc-reference-capture.zip`; the parent validated its checks and a genuine cloud welcome-screen capture. Authenticated local browser references and fake-auth runtime behavior remain unresolved. The reference row remains blocked and is not counted as visual parity.

The [architecture overview](grounding/overview.md) combines the grounding reports. The [next batch brief](core-batch-brief.md) asks two independent Codex candidates to resolve same-tab window ownership, real download control, and essential page operations. A separate judge will compare their contracts and runtime evidence before implementation. No human approval checkpoint is required for these reversible changes.
