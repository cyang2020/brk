# Wave 2 integration status

The four interrupted workers continued with Codex. Their Settings, Windows, Command bar, and Library changes are merged with the completed Profiles implementation. The signed application is `dist/Brk.app`.

Updated on 2026-10-31 after parent integration of the privacy and native-focus fixes. All 45 current native scenarios now pass on main. Full Arc feature coverage and pixel parity remain unfinished; their ongoing delivery is tracked in the [completion plan](../completion/plan.md) and [148-row inventory](../completion/features.json).

## Verification

- `scripts/build.sh` passes: 459 tests, three existing skips, zero failures, explicit-import checks, CEF bundling, HTTP/HTTPS URL declarations, and signature verification. See the [parent build log](../../verify/swift/focus-parent/evidence/build.log).
- The parent independently ran the merged CEF application through all 45 scenarios: 45 PASS, 0 FAIL, 0 SKIPPED. See the [current report and captures](../../verify/swift/focus-parent/native/REPORT.md). The earlier [43/45 run](../../verify/swift/wave2-privacy-fix/REPORT.md) remains recorded with its focus failures.
- The three skipped tests cover two later Max features and the native file-export save panel. They are not counted as verified behavior.
- The [source hashes](../../verify/swift/focus-parent/source-sha256.json) and [application hash](../../verify/swift/focus-parent/app-sha256.txt) identify the current tested files.

The native run used this command after the successful build:

```sh
BRK_E2E_DATA_ROOT=/tmp/brk-complete/data SKIP_BUILD=1 scripts/e2e.sh --out /tmp/brk-complete/focus-native
```

## Implemented behavior

| Area | Behavior | Evidence |
| --- | --- | --- |
| Settings | General, Max, Profiles, Shortcuts, Links, and Advanced panes mount their editors. Native edits, profile creation and rename, close keys, and restart persistence work. Reopening the same pane raises the existing window. | W2-1, W2-1-edit, W2-8; `SettingsHostTests`, `ControlInputRegressionTests` |
| Profiles and incognito | Separate cookie stores, profile reassignment, deferred profile deletion, private scratch tabs, dark private chrome, and tested private history/download/archive isolation. Modifier links and hidden popups retain the source private window. | W2-2, W2-3, W2-11P, W2-P1/P1C/P2/P2C; profile, Library, and window tests |
| Windows and links | Shared standard windows, Little Arc, Open In, Shift-click Peek, and configured external-link routing. | W2-4 through W2-7 |
| Command bar and menus | Exact URLs retain their destination. Exact existing-tab matches still switch tabs. Suggestions, site search, menu actions, and remapping work. The tests account for all 189 extracted menu rows; later-feature actions remain disabled. | W2-8 through W2-10a; menu and key-routing tests |
| Library | The 417 pt panel replaces the sidebar. Downloads reach disk with unique names, History is scoped by profile, and Archive restores tabs. Active and completed downloads permit immediate clean shutdown. | 7, R2, W2-11, W2-12, W2-11Q, W2-11A, W2-11P |

## Integration corrections

`AppEffect.showSettings` raises Settings even when its pane state does not change. Control input remembers the last presented or clicked window when macOS supplies no key window. Standard editing actions then use that window's responder chain. Modifier matching preserves Fn, so typing `f` does not invoke Fn+F.

Page focus now belongs to its native window. Late AppKit layout can repair a missing page responder without activating a background window or replacing a valid native editor. The [focus handoff](../../verify/swift/focus-integration/REPORT.md) records the traced W2-4 cause and the remaining uncertainty about N1's original invalidation trigger.

Cmd+Shift+J defaults to app priority because Chromium can consume its download accelerator before Brk receives the post-page callback. Explicit user priority overrides still apply. This is a documented CEF adaptation to the extracted Arc default.

Chromium auxiliary download windows close before CEF shutdown. This fixes the reproduced exit crash without a shutdown delay. Download updates and history title changes also stay within their browsing profile.

The parent preserved failing-before tests, native focus snapshots, and routing logs under [integration evidence](../../verify/swift/wave2-integration/). A temporary screenshot retry was removed after a test identified the unintended fullscreen transition. Final captures use the original strict WindowServer check.

## Remaining work and limits

- Download Cancel updates the ledger but does not stop the network transfer. Downloads therefore remain partially implemented.
- Media, Easels and Notes, Boosts, and Spaces have Library placeholders. Their underlying features, extension management, import, and other later-wave features remain in the [feature inventory](feature-ledger.md).
- The native export save panel still needs a runtime check. AI integration uses local Claude or Codex command-line tools; the later Max tasks remain unfinished.
- No authenticated Arc reference captures were available for this integration. The native captures establish Brk behavior, not pixel parity. Little Arc and Peek still include explicitly estimated dimensions.
- The download shutdown fix depends on CEF's private native-window class. The immediate-quit scenarios must run on a CEF upgrade.
- The scenarios use the control socket to inject native events. Physical keyboard layouts and external-app delivery through Launch Services were not verified. The default browser was not changed.

The inventory's old wave-1 status counts are historical. This document and its linked native report describe the current second-wave integration.
