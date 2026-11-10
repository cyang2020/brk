# Command bar actions, Little Brk entry points and auto-archive, Live Folders

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish four rows. A068: every remaining menu action, folder destination and installed extension is searchable from the command bar. A085: global shortcut registration and the menu-bar entry for Little Brk (coordinate with the status item from menus-system through its command), real external-app delivery receipts and private-link protection. A086: define idle by actual interaction and activity, protect panels with active media or downloads, and add native active-versus-idle and restart threshold checks. A092: error, loading and freshness states for GitHub Live Folders and a reauthorization flow for authenticated refresh without saving tokens. Owned paths: `Sources/BrkOverlays/Suggest.swift`, `Sources/BrkDomain/Rules/{CommandBar,Windows,Peek,Archive}.swift`, `Sources/BrkApp/{LittleEntryPoints,LittleWindowController,ExternalLinks}.swift`, the Live Folder parts of `Sources/BrkDomain/SidebarTree.swift` and `Sources/BrkSidebar/TablistView.swift`, and your new `LittleScenarios.swift`.

## Owned feature acceptance

### A068 Actions in the bar ("Type Travel")

Search all applicable completed menu actions, spaces, folder destinations and extensions from the command bar.

Current assessment: partial.
- Implement the remaining actions, folder destinations and extensions; W2-8 tests Preferences, not every advertised workflow.

Current behavior: Type travel lists enabled non-later actions, settings panes, focus-space and move-space results.

Existing pointers: `Sources/BrkOverlays/Suggest.swift`, `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/Project.swift`

### A085 Little Arc entry points

External links, global hotkey, Option+Cmd link click and menu-bar entry can open Little Brk, with correct destination profile and private-link protections.

Current assessment: partial.
- Implement global shortcut registration and menu-bar entry.
- Verify real external-app delivery and physical modifier clicks; retain private links in private context.

Current behavior: File-menu shortcut, domain externalURL path and Option+Cmd routing exist. No global hotkey or menu-bar item.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/Rules/Windows.swift`, `Sources/BrkDomain/Rules/Peek.swift`, `Sources/BrkApp/ExternalLinks.swift`

### A086 Little Arc auto-archive

Little Brk auto-archive respects configured thresholds and never closes a panel that is actively used; expired panels archive/close once and can be restored appropriately.

Current assessment: partial.
- Define idle using actual relevant interaction/activity; protect actively used panels and media/download work.
- Add native active-vs-idle and restart/never threshold checks.

Current behavior: Tick sweep compares tab lastActiveAt; no native activity/key-window input refreshes it while a panel remains shown.

Existing pointers: `Sources/BrkDomain/Rules/Archive.swift`, `Sources/BrkDomain/Reduce.swift`, `Sources/BrkApp/WindowController.swift`, `Sources/BrkDomain/SettingsModel.swift`

### A092 Live Folders

Maintain a GitHub pull-request Live Folder with refresh, opening items and useful loading, empty and error states.

Current assessment: partial.
- Explicit repository selection, real fixture HTTP fetch/refresh, PR document opening, empty state and saved config passed in native. Error/loading/freshness and authenticated private-repository refresh requires a reauthorization flow because refresh is currently anonymous; tokens are never saved.

Current behavior: Folder has only a future live-source comment; no fetch event, adapter or UI exists.

Existing pointers: `Sources/BrkDomain/SidebarTree.swift`, `Sources/BrkDomain/Command.swift`, `Sources/BrkSidebar/TablistView.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Little`) and evidence under `verify/completion/batch2-little-arc-folders/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A068, A085, A086, A092), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
