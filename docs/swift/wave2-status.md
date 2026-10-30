# Wave 2 integration status

The four interrupted workers continued with Codex. Their Settings, Windows, Command bar, and Library changes are merged with the completed Profiles implementation. The signed application is `dist/Brk.app`.

This snapshot is dated 2026-10-30. It covers the second implementation wave. Full Arc feature coverage and pixel parity remain unfinished.

## Verification

- `scripts/build.sh` passes: 449 tests, three existing skips, zero failures, explicit-import checks, CEF bundling, HTTP/HTTPS URL declarations, and signature verification. See the [build log](../../verify/swift/wave2-integration/evidence/release-build.log).
- The parent ran all 41 scenarios against the merged Swift application and CEF 154.0.34.0 on macOS 26.6.2. All passed, with no skips. See the [native report and captures](../../verify/swift/wave2-integration/native/REPORT.md).
- The three skipped tests cover two later Max features and the native file-export save panel. They are not counted as verified behavior.
- The [source hashes](../../verify/swift/wave2-integration/source-sha256.json) and [application hash](../../verify/swift/wave2-integration/app-sha256.txt) identify the verified files.

The native run used this command after the successful build:

```sh
BRK_E2E_DATA_ROOT=/tmp/brk-resume-20261030/data SKIP_BUILD=1 scripts/e2e.sh --out /tmp/brk-resume-20261030/release-e2e
```

## Implemented behavior

| Area | Behavior | Evidence |
| --- | --- | --- |
| Settings | General, Max, Profiles, Shortcuts, Links, and Advanced panes mount their editors. Native edits, profile creation and rename, close keys, and restart persistence work. Reopening the same pane raises the existing window. | W2-1, W2-1-edit, W2-8; `SettingsHostTests`, `ControlInputRegressionTests` |
| Profiles and incognito | Separate cookie stores, profile reassignment, deferred profile deletion, private scratch tabs, dark private chrome, and private history/download/archive isolation. | W2-2, W2-3, W2-11P; profile, Library, and window tests |
| Windows and links | Shared standard windows, Little Arc, Open In, Shift-click Peek, and configured external-link routing. | W2-4 through W2-7 |
| Command bar and menus | Exact URLs retain their destination. Exact existing-tab matches still switch tabs. Suggestions, site search, menu actions, and remapping work. The tests account for all 189 extracted menu rows; later-feature actions remain disabled. | W2-8 through W2-10a; menu and key-routing tests |
| Library | The 417 pt panel replaces the sidebar. Downloads reach disk with unique names, History is scoped by profile, and Archive restores tabs. Active and completed downloads permit immediate clean shutdown. | 7, R2, W2-11, W2-12, W2-11Q, W2-11A, W2-11P |

## Integration corrections

`AppEffect.showSettings` raises Settings even when its pane state does not change. Control input remembers the last presented or clicked window when macOS supplies no key window. Standard editing actions then use that window's responder chain. Modifier matching preserves Fn, so typing `f` does not invoke Fn+F.

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
