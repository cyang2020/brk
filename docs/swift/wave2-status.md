# Wave 2 integration status

The four interrupted workers continued with Codex. Their Settings, Windows, Command bar, and Library changes are merged with the completed Profiles implementation. The signed application is `dist/Brk.app`.

Updated on 2026-10-31 after parent integration of the privacy, native-focus, History storage, and window-owned page fixes. All 79 current native scenarios pass on main. Full Arc feature coverage and pixel parity remain unfinished; their ongoing delivery is tracked in the [completion plan](../completion/plan.md) and [148-row inventory](../completion/features.json).

## Verification

- `scripts/build.sh` passes: 537 tests, three existing skips, zero failures, explicit-import checks, CEF bundling, HTTP/HTTPS URL declarations, and signature verification. See the [parent build log](../../verify/completion/find-parent/build-complete.log).
- The parent independently ran the merged CEF application through all 79 scenarios: 79 PASS, 0 FAIL, 0 SKIPPED. See the [current report and captures](../../verify/completion/find-parent/native-complete/REPORT.md). The earlier [43/45 run](../../verify/swift/wave2-privacy-fix/REPORT.md) remains recorded with its focus failures.
- The three skipped tests cover two later Max features and the native file-export save panel. They are not counted as verified behavior.
- The [source hashes](../../verify/completion/find-parent/manifest-complete.json) and [application hash](../../verify/completion/find-parent/manifest-complete.json) identify the current tested files.

The native run used this command after the successful build:

```sh
BRK_LOCK_WAIT=900 python3 verify/completion/find-parent/run.py suite
```

## Implemented behavior

| Area | Behavior | Evidence |
| --- | --- | --- |
| Settings | General, Max, Profiles, Shortcuts, Links, and Advanced panes mount their editors. Native edits, profile creation and rename, close keys, and restart persistence work. Reopening the same pane raises the existing window. | W2-1, W2-1-edit, W2-8; `SettingsHostTests`, `ControlInputRegressionTests` |
| Profiles and incognito | Separate cookie stores, profile reassignment, deferred profile deletion, private scratch tabs, dark private chrome, and tested private history/download/archive isolation. Modifier links and hidden popups retain the source private window. | W2-2, W2-3, W2-11P, W2-P1/P1C/P2/P2C; profile, Library, and window tests |
| Windows and links | Window-owned browsers for shared tabs, independent navigation/restoration, Little Arc, Open In, Shift-click Peek, and configured external-link routing. | W2-4 through W2-7, I1-I6 |
| Command bar and menus | Exact URLs retain their destination. Exact existing-tab matches still switch tabs. Suggestions, site search, menu actions, and remapping work. The tests account for all 189 extracted menu rows; later-feature actions remain disabled. | W2-8 through W2-10a; menu and key-routing tests |
| Find | Native Find, Replace in supported captured fields, Next/Previous, Use Selection and Jump; per-window/private/Peek/split ownership, Unicode input/undo, stale-result handling and narrow controls. | F1-F12; [parent receipt](../../verify/completion/find-parent/REPORT.md) |
| Library | The 417 pt panel replaces the sidebar. Downloads reach disk with unique names, History is scoped by profile, and Archive restores tabs. Active and completed downloads permit immediate clean shutdown. | 7, R2, W2-11, W2-12, W2-11Q, W2-11A, W2-11P |

## Integration corrections

`AppEffect.showSettings` raises Settings even when its pane state does not change. Control input remembers the last presented or clicked window when macOS supplies no key window. Standard editing actions then use that window's responder chain. Modifier matching preserves Fn, so typing `f` does not invoke Fn+F.

Page focus now belongs to its native window. Late AppKit layout can repair a missing page responder without activating a background window or replacing a valid native editor. The [focus handoff](../../verify/swift/focus-integration/REPORT.md) records the traced W2-4 cause and the remaining uncertainty about N1's original invalidation trigger.

Cmd+Shift+J defaults to app priority because Chromium can consume its download accelerator before Brk receives the post-page callback. Explicit user priority overrides still apply. This is a documented CEF adaptation to the extracted Arc default.

Chromium auxiliary download windows close before CEF shutdown. This fixes the reproduced exit crash without a shutdown delay. Download updates and history title changes also stay within their browsing profile.

Clear History now removes Brk visits without scheduling the custom profile's Chromium directory for deletion. The new C-HISTORY case proves that the fixture's localStorage survives the action and a restart. Cookie, cache, and broader site-storage clearing remain unfinished.

The parent preserved failing-before tests, native focus snapshots, and routing logs under [integration evidence](../../verify/swift/wave2-integration/). A temporary screenshot retry was removed after a test identified the unintended fullscreen transition. Final captures use the original strict WindowServer check.

The [parent identity review and corrections](../../verify/completion/identity-parent/REPORT.md) records six additional defects fixed after the initial 50-scenario pass. The current 52-scenario result includes replacement navigation and shared mutations initiated from private windows.

## Remaining work and limits

- Download Cancel now controls the actual transfer. Accepted public downloads retain their browser across Brk tab/window close and reassignment. Mandatory native browser destruction reports a terminal failure/recovery result. The [parent transfer receipt](../../verify/completion/transfers-parent/REPORT.md) records the tested limits, original review findings and corrections.
- Media, Easels and Notes, Boosts, and Spaces have Library placeholders. Their underlying features, extension management, import, and other later-wave features remain in the [feature inventory](feature-ledger.md).
- The native export save panel still needs a runtime check. AI integration uses local Claude or Codex command-line tools; the later Max tasks remain unfinished.
- No authenticated Arc reference captures were available for this integration. The native captures establish Brk behavior, not pixel parity. Little Arc and Peek still include explicitly estimated dimensions.
- The download shutdown fix depends on CEF's private native-window class. The immediate-quit scenarios must run on a CEF upgrade.
- The scenarios use the control socket to inject native events. Physical keyboard layouts and external-app delivery through Launch Services were not verified. The default browser was not changed.

The inventory's old wave-1 status counts are historical. This document and its linked native report describe the current second-wave integration.
