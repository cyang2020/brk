# Native open/save panel input and the import, export and sync receipts that depend on it

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Resolve the one blocker behind the ImportSync-Import, ImportSync-Export and ImportSync-Sync failures: the macOS open and save panels run in a separate Apple XPC process (`com.apple.appkit.xpc.openAndSavePanelService`) and the fixture's in-process input never reaches them (`timed out after 8.0 s waiting for native sheet contains 1 bookmarks`).

Read the previous bounded attempt first: `/Users/administrator/.t3/worktrees/brk/t3-da37a8f1/verify/completion/native-picker-input/REPORT.md` (branch `t3/native-picker-input`, commit `576dc75`). Its external helper `scripts/native-picker-input.swift` and the opt-in `Sources/BrkE2E/NativePickerInput.swift` are reusable; copy or cherry-pick them with attribution in your report. That report names two corrections that were never run: record the proposed click point and the top window's PID, number and bounds before the hit guard rejects a click; and compare the system-wide accessibility focused application and focused element with the owned tree while refreshing application-state observations through a pumped run loop. Apply both. Then make at most two bounded native attempts, each at most 180 s of actual run under the native lock, to drive the real panel: focus it, type the fixture path through the panel's path field (Cmd+Shift+G) or select the fixture row, confirm, and let the existing scenario assertions prove preview, accept and cancel, saved JSON and HTML bytes, two-root sync convergence and disconnect. Do not change OS permissions, do not assign `panel.url` or invoke a panel completion from inside the product, and do not read any user browser profile.

If both attempts fail, apply the fallback acceptance the parent has decided for this batch: the panel is shown and recorded (window number, bounds, screenshot), the real post-selection production command is exercised with an explicitly selected fixture URL (the pattern extension installation already uses), and the scenario asserts the downstream behavior. Rows accepted that way are proposed `implemented` with an explicit `manual` gap for the physical gesture, never `verified`. Either way the three ImportSync scenarios must stop failing: a step that depends on an unavailable physical gesture ends in SKIPPED with the reason, not FAIL, and the downstream assertions still run through the explicit path. Keep the LocalAuthentication and protected Keychain exercise for A122 as a stated manual gap; credentials stay in the app-specific Keychain collection and website autofill is out of scope. A144's creative-document export waits for the easels-notes slice.

Owned paths: `Sources/BrkE2E/{Harness,NativePickerInput,ImportSyncScenarios}.swift`, `scripts/native-picker-input.swift`, your new `FilePanelScenarios.swift`, and `Sources/BrkApp/{SidebarDataPanels,ExportSheets,SidebarSyncIO,ShareExport}.swift` only for the explicit post-selection command path. BB1 and the output adapters belong to browser-ops.

## Owned feature acceptance

### A122 Import from other browsers

Import user-selected bookmarks, history and supported passwords with explicit OS authorization, accurate counts and unchanged source data.

Current assessment: partial.
- Native bookmark/history file selection and resulting preview/accept/cancel receipts remain unproven: the macOS remote picker did not accept the scoped test input. See the final native failures and panel census.
- Real LocalAuthentication and protected Keychain writes were not exercised with an interactive owned OS identity. Credentials use an app-specific Keychain collection; website autofill is not implemented.

Existing pointers: `Sources/BrkDomain/SidebarImport.swift`, `Sources/BrkApp/SidebarDataPanels.swift`, `Sources/BrkApp/ImportedPasswordVault.swift`, `Sources/BrkApp/AppStore.swift`

### A143 Sidebar sync

Synchronize the agreed sidebar data through a user-selected folder with deterministic conflict/deletion handling and no incognito or credential data.

Current assessment: partial.
- The production reducer, codec, file adapter and two AppStores with separate data roots pass real transport-file convergence, privacy and editor-preservation tests. Native folder choice and the separate real-CEF-process simulation remain gated by remote file-picker input.

Existing pointers: `Sources/BrkDomain/SidebarSync.swift`, `Sources/BrkDomain/Rules/SidebarData.swift`, `Sources/BrkDomain/Rules/SidebarSyncMaterialize.swift`, `Sources/BrkDomain/Codec.swift`, `Sources/BrkApp/SidebarSyncIO.swift`, `Tests/BrkAppTests/ImportSyncIOTests.swift`

### A144 Sharing by link

Export spaces, folders, selected tabs and supported creative documents to user-chosen local files; verify the native save flow.

Current assessment: partial.
- Native destination selection and actual save-panel file receipts remain unproven; JSON/HTML encoding and owner-bound documents pass unit tests.
- Creative document types/editors are outside this batch, so creative-document export remains partial.

Existing pointers: `Sources/BrkApp/ExportSheets.swift`, `Sources/BrkApp/ShareExport.swift`, `Sources/BrkDomain/Rules/Sidebar.swift`, `Sources/BrkSidebar/TablistView.swift`, `Sources/BrkE2E/ImportSyncScenarios.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `FP`) and evidence under `1f7d43f7b0:verify/completion/batch2-file-panels/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A122, A143, A144), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
