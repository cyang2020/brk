# Brk Swift wave 1 review

Reviewed `d7511149f8e94990ad61d352c651767145624f4b`. All experiments used `/tmp/swift-wave1-review`; the reviewer edited no source checkout or worker worktree. Seven proven findings follow. Scratch tests and logs are retained there.

Reproduce from `/tmp/swift-wave1-review` after `swift test --scratch-path .review-build --list-tests` builds the added tests. Define:

```sh
probe() { swift test --scratch-path .review-build --skip-build --filter "$1"; }
```

**1. A corrupt saved timestamp crashes the next archive sweep. Severity: breaks a feature.** `Sources/BrkBase/IDs.swift:73`, reached through `Sources/BrkDomain/Rules/Archive.swift:42`.
Repro: `probe testCorruptTimestampDoesNotCrashClockTick` → `REVIEW timestamp accepted: restored(repairs: [])`, then `exited with unexpected signal code 5` (exit 1; `timestamp-crash.log`). The test sets an inactive saved tab's `lastActiveAt` to `Int64.min`, restores it, then sends `.clockTick`. Intent: repair or reject unusable saved values without trapping. Fix: validate restored timestamps and make elapsed-time arithmetic safe across the supported range.

**2. Filling a pinned split pane never records its original URL. Severity: breaks a feature.** `Sources/BrkDomain/Rules/CommandBar.swift:29`.
Repro: `probe testPinnedSplitFilledPaneKeepsOriginalURL` → `pinnedURL=nil canReset=Optional(false) resetEffects=0`; the URL remains `https://example.com/away` instead of `/original` (exit 1; `pinned.log`). Steps: pin a tab, add a split pane, submit its first URL, navigate elsewhere, request Reset Tab. Intent: every filled pinned pane retains its saved destination and can reset after navigation. Fix: record the first URL when filling an empty pane in Pinned, preserving an existing saved URL.

**3. Favorites offers Rename but cannot focus any editor. Severity: breaks a feature.** `Sources/BrkSidebar/SidebarView.swift:127`.
Repro: `probe testFavoriteRenameOffersAnEditableField` → `favorite rename focus=renameField(...), editor focused=false` (exit 1; `favorite.log`). The test moves a tab into Favorites, dispatches the context menu's `.beginRename` command, then calls the root's public focus API. The snapshot requests rename, but focus only searches the tab list; Favorite tiles have no editor. Intent: the offered Rename action permits editing the title. Fix: provide a Favorites rename editor and route focus to it.

**4. A finite control-clock argument traps instead of returning failure. Severity: wrong behavior.** `Sources/BrkApp/Control/ControlExecutor.swift:155`.
Repro: `probe testLargeFiniteClockInputReturnsFailure` → `Fatal error: Double value cannot be converted to Int64 because it is either infinite or NaN`, signal 5 (exit 1; `clock-crash.log`). `.advanceClock(seconds: 1e308)` passes `isFinite`, but multiplying by 1000 overflows before the integer conversion. Intent: malformed control input returns `.failed` while the app remains alive. Fix: check conversion bounds and cumulative clock range before converting or adding the offset.

**5. Equal finite split weights produce unequal panes after overflow. Severity: wrong behavior.** `Sources/BrkDomain/Rules/Split.swift:76`.
Repro: `probe testEqualLargeSplitWeightsStayEqual` → `equal weights -> [0.15, 0.85]`, expected `[0.5, 0.5]` (exit 1; `weights.log`). Both weights are `1e308`, which the resize command's finite-positive validation accepts; their sum becomes infinity. Intent: equal relative weights remain equal, independently of scale. Fix: scale weights by their maximum before summing and normalizing.

**6. The metric gate permits a 100-fold Arc timing error. Severity: weak test.** `Tests/ArchitectureTests/MetricInventoryTests.swift:93`; mutated metric at `Sources/BrkBase/Metrics.swift:201`.
Repro: `bash ./repro-metric.sh` → `MUTATION sidebarToggle 0.08 -> 8.0 seconds`; `Executed 301 tests, with 0 failures` (exit 0; `metric-mutation.log`). The script retains the Arc source label and restores the original file afterward. Intent: the claimed fidelity gate catches disagreement with `layout-constants.md`, whose value is 0.08 s. The checker reads row names and confidence but never compares values. Fix: validate metric values against machine-readable grounded values, including supported variants.

**7. Tab-indented imports bypass the architecture scanner. Severity: weak test.** `Tests/ArchitectureTests/ImportRulesTests.swift:113`.
Repro: `probe testTabbedImportCannotBypassScanner` → `tab-indented AppKit import violations=0`, expected 1 (exit 1; `import-scanner.log`). The input is the legal Swift declaration `\timport AppKit` in BrkDomain. Intent: every import is checked against the module allow list. Splitting only on a literal space misses tabs. Fix: tokenize Swift whitespace or parse import declarations, and retain this negative case.

## Unproven suspicions

- Consumed events and key-up callbacks may mispair `PressCorrelator` entries during rapid same-chord input. No CEF counterexample was established; N1 passed.
- Whether restored `data:` or `javascript:` URLs can execute on launch remains unverified. No execution or arbitrary-file-read exploit is claimed.

## Checks run

- Requested `cp -R` and `.cef` symlink: exit 0. Initial plain `swift test`: exit 1 because copied module caches contain absolute source paths. Fresh-cache `swift test --scratch-path .review-build`: exit 0, **301 tests passed** (`baseline.log`).
- `bash ./repro-probes.sh`: six isolated probes each exited 1, as recorded in `probe-exits.log`; timestamp and clock probes terminated XCTest with signal 5. Added tests are `Tests/{BrkDomainTests,BrkAppTests,ArchitectureTests}/Wave1ReviewTests.swift`.
- `bash ./repro-metric.sh`: exit 0, **301 existing tests passed with the bad metric**. Scratch production files were restored; `git diff -- Sources` is empty.
- `swift run --scratch-path .review-build brk-e2e --app dist/Brk.app --site Tests/E2ESite --out /tmp/swift-wave1-review/e2e-review --only N1,N4`: exit 0, **2 PASS**, real CEF 154.0.34.0. This used the copied existing app bundle; no release rebuild or full 24-scenario rerun.
