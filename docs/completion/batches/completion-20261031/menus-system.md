# Default browser and incoming links, Help menu, About, menu bar coverage, Dock tile, status item, AppleScript

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish the system-integration rows. A112: accurate default-browser status through Launch Services, the OS confirmation flow (never change the default browser during tests), cold-launch URL ordering and real external delivery with an owned helper app or `open` receipts. A125: resolve the `.later(.help)`, `.later(.restoreData)` and `.later(.troubleshooting)` entries into working local documentation, restore from a backup, trace recording, task manager and diagnostics. A129: Brk credits, packaged version and icon metadata, the actual About panel captured. A130: every in-scope menu row works or carries the explicit updater deferral; dynamic entries validated. A131: Brk-owned Dock tile behavior (badge or progress) across active and inactive states. A132: a menu-bar status item that opens Little Brk. A133: a documented AppleScript dictionary (sdef) for windows, tabs and spaces with correct object identity, exercised through `osascript`, keeping private ownership and the explicit JavaScript permission. Owned paths: `Sources/BrkApp/{MainMenu,Lifecycle,ExternalLinks}.swift`, new Help, Dock, status-item and scripting files in BrkApp, `Sources/BrkDomain/Actions.swift` entries for those groups, and your new `SystemScenarios.swift`.

## Owned feature acceptance

### A112 Default browser and links from other apps

Brk can become the default http/https browser after OS confirmation, reflects actual registration status, and receives/routes real URLs from other applications on cold and warm launch.

Current assessment: partial.
- Verify Launch Services/user confirmation and real external application delivery on this app bundle.
- Wire accurate current default status and error reporting; test cold-launch URL ordering.
- W2-7 injects the control protocol input and does not prove the OS boundary.

Current behavior: Bundle scheme declaration, NSWorkspace registration and GetURL handler exist. isDefault is not reflected in SettingsSnapshot.

Existing pointers: `Sources/BrkApp/ExternalLinks.swift`, `Sources/BrkDomain/Rules/Windows.swift`, `Sources/BrkSettings/SettingsPanes.swift`, `scripts/declare-url-types.sh`, `scripts/build.sh`

### A125 Help menu

Help entries open useful local documentation and working restore, diagnostics and troubleshooting tools instead of disabled placeholders.

Current assessment: partial.
- The menu and shortcut settings entry exist. Restore, tracing, task manager and most help actions remain disabled.

### A129 About window

Open an About Brk panel with correct application identity, version and credits.

Current assessment: partial.
- Add or verify Brk credits and packaged version or icon metadata, then capture the actual About panel.

Current behavior: About dispatches showAbout to the standard AppKit About panel; no custom credits resource was found.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkApp/AppStore.swift`, `Sources/BrkBase/Product.swift`

### A130 Menu bar coverage

Account for all 189 reference menu rows and make every in-scope action work or carry the explicit updater deferral.

Current assessment: partial.
- Implement remaining in-scope later actions, validate actual effects and dynamic entries; accounting and setting writes do not prove feature behavior.

Current behavior: Accounting covers 189 rows: 122 action IDs, 65 non-later and 57 later. Menus include native standard items and authorized dropped rows.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkApp/MainMenu.swift`, `Sources/BrkDomain/Reduce.swift`, `Sources/BrkDomain/Project.swift`

### A131 Dock tile

Implement the intended custom Dock tile behavior for Brk and verify it across active and inactive application states.

Current assessment: missing.
- Establish exact interactions from an authenticated reference, then implement Brk-owned icon or badge behavior; do not add referral features.

Current behavior: No NSDockTile or custom Dock delegate behavior is implemented.

Existing pointers: `Sources/BrkApp/Lifecycle.swift`, `Sources/BrkBase/Product.swift`

### A132 Menu bar status item

Expose a menu-bar status item that opens Little Arc and behaves predictably across app or window states.

Current assessment: missing.
- Add status-item lifecycle, menu and activation behavior, then verify using native system UI.

Current behavior: Little Arc can open through menu commands, but no NSStatusItem exists.

Existing pointers: `Sources/BrkApp/Lifecycle.swift`, `Sources/BrkDomain/Rules/Windows.swift`

### A133 AppleScript

Script windows, tabs and spaces through a documented AppleScript dictionary with correct object identity and context.

Current assessment: missing.
- Implement the agreed scripting subset and actual osascript checks, preserving private ownership and explicit JavaScript permissions.

Current behavior: GetURL Apple Events open external links; there is no scripting dictionary or object-command implementation.

Existing pointers: `Sources/BrkApp/ExternalLinks.swift`, `Sources/BrkApp/Lifecycle.swift`, `Sources/BrkDomain/Command.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `System`) and evidence under `verify/completion/batch2-menus-system/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A112, A125, A129, A130, A131, A132, A133), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
